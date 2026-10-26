#!/usr/bin/env python3
"""Capture anonymized Glances 5 API responses as test fixtures.

Usage:
    python3 -I Scripts/capture-fixtures.py https://glances.example.com [--user NAME]

The password, if needed, is read from the GLANCES_PASSWORD environment
variable so it never appears in the shell history. Fixtures are written to
Packages/MetriBarKit/Tests/MetriBarKitTests/Fixtures/v5/.

Anonymization replaces host names, container names, IDs and images, IP
addresses, user names, command lines and non-standard mount points with
stable placeholders, including the matching keys in `_levels` objects.
Review the output with `git diff` before committing.
"""

import argparse
import base64
import datetime
import hashlib
import ipaddress
import json
import os
import pathlib
import re
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "Packages/MetriBarKit/Tests/MetriBarKitTests/Fixtures/v5"

# (fixture name, path relative to the server URL)
ENDPOINTS = [
    ("status", "/status"),
    ("pluginslist", "/api/5/pluginslist"),
    ("system", "/api/5/system"),
    ("cpu", "/api/5/cpu"),
    ("cpu-limits", "/api/5/cpu/limits"),
    ("percpu", "/api/5/percpu"),
    ("quicklook", "/api/5/quicklook"),
    ("mem", "/api/5/mem"),
    ("memswap", "/api/5/memswap"),
    ("load", "/api/5/load"),
    ("uptime", "/api/5/uptime"),
    ("processcount", "/api/5/processcount"),
    ("containers", "/api/5/containers"),
    ("fs", "/api/5/fs"),
    ("diskio", "/api/5/diskio"),
    ("network", "/api/5/network"),
    ("sensors", "/api/5/sensors"),
    ("processlist-top", "/api/5/processlist/top/25"),
    ("alert", "/api/5/alert"),
    ("alert-incidents", "/api/5/alert/incidents"),
    ("cpu-history", "/api/5/cpu/history?nb=30"),
    ("mem-history", "/api/5/mem/history?nb=30&field=percent"),
    ("load-history", "/api/5/load/history?nb=30"),
    ("network-history", "/api/5/network/history?nb=30"),
    ("error-unknown-plugin", "/api/5/doesnotexist"),
    ("error-unknown-field", "/api/5/cpu/doesnotexist"),
]

STANDARD_MOUNTS = {"/", "/boot", "/boot/firmware", "/boot/efi", "/home", "/var", "/tmp"}
KEEP_IPS = {"0.0.0.0", "127.0.0.1", "255.255.255.0", "255.255.0.0", "255.0.0.0"}
IPV4 = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")


class Anonymizer:
    def __init__(self):
        self.hostnames = {}
        self.containers = {}
        self.images = {}
        self.users = {}
        self.processes = {}
        self.mounts = {}
        self.ips = {}

    @staticmethod
    def _numbered(table, value, template):
        if value not in table:
            table[value] = template.format(len(table) + 1)
        return table[value]

    def container(self, name):
        return self._numbered(self.containers, name, "container-{:02d}")

    def image(self, image):
        return self._numbered(self.images, image, "example/image-{:02d}:latest")

    def user(self, user):
        if user == "root":
            return user
        return self._numbered(self.users, user, "user{}")

    def process(self, name):
        # Process names reveal which services run on the host.
        return self._numbered(self.processes, name, "process-{:02d}")

    def mount(self, mount):
        if mount in STANDARD_MOUNTS:
            return mount
        return self._numbered(self.mounts, mount, "/mnt/volume-{:02d}")

    def ip(self, match):
        value = match.group(0)
        try:
            address = ipaddress.ip_address(value)
        except ValueError:
            return value
        if value in KEEP_IPS:
            return value
        if value not in self.ips:
            n = len(self.ips) + 1
            # RFC 5737 documentation ranges: private → 192.0.2.x, public → 203.0.113.x
            prefix = "192.0.2" if address.is_private else "203.0.113"
            self.ips[value] = f"{prefix}.{n}"
        return self.ips[value]

    def strings(self, node):
        """Replace IP addresses and known host names in every string."""
        if isinstance(node, dict):
            return {key: self.strings(value) for key, value in node.items()}
        if isinstance(node, list):
            return [self.strings(item) for item in node]
        if isinstance(node, str):
            text = IPV4.sub(self.ip, node)
            for real, fake in self.hostnames.items():
                text = text.replace(real, fake)
            return text
        return node


def rename_collection(payload, field, rename):
    """Rename the primary key `field` in `data` items and in `_levels`."""
    if not isinstance(payload, dict):
        return payload
    for item in payload.get("data", []):
        if isinstance(item, dict) and isinstance(item.get(field), str):
            item[field] = rename(item[field])
    levels = payload.get("_levels")
    if isinstance(levels, dict):
        payload["_levels"] = {rename(key): value for key, value in levels.items()}
    return payload


def anonymize(name, payload, anon):
    if name == "system" and isinstance(payload, dict) and payload.get("hostname"):
        anon.hostnames[payload["hostname"]] = "glances-host"
    if name == "containers":
        rename_collection(payload, "name", anon.container)
        for item in payload.get("data", []):
            if item.get("id"):
                item["id"] = hashlib.sha256(item["name"].encode()).hexdigest()
            # Glances 5 sends the image tags as a list, not as a string.
            image = item.get("image")
            if isinstance(image, list):
                item["image"] = [anon.image(tag) for tag in image]
            elif image:
                item["image"] = anon.image(image)
            if item.get("command"):
                item["command"] = "[command]"
            url = item.get("engine_url")
            if isinstance(url, str) and not url.startswith("unix://"):
                item["engine_url"] = "tcp://docker-host:2375"
    if name == "fs":
        rename_collection(payload, "mnt_point", anon.mount)
    if name == "processlist-top" and isinstance(payload, list):
        for item in payload:
            if item.get("username"):
                item["username"] = anon.user(item["username"])
            if item.get("name"):
                item["name"] = anon.process(item["name"])
            if item.get("cmdline"):
                item["cmdline"] = [item.get("name") or "[process]"]
    if name == "alert" and isinstance(payload, list):
        for event in payload:
            if event.get("hostname"):
                event["hostname"] = "glances-host"
    return anon.strings(payload)


def fetch(base, path, auth):
    request = urllib.request.Request(base.rstrip("/") + path, headers={"Accept": "application/json"})
    if auth:
        request.add_header("Authorization", auth)
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.load(error)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("url", help="Glances server base URL, e.g. https://glances.example.com")
    parser.add_argument("--user", default="glances", help="user name for HTTP Basic auth")
    args = parser.parse_args()

    auth = None
    password = os.environ.get("GLANCES_PASSWORD")
    if password:
        token = base64.b64encode(f"{args.user}:{password}".encode()).decode()
        auth = f"Basic {token}"

    anon = Anonymizer()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    statuses = {}
    glances_version = None
    for name, path in ENDPOINTS:
        status, payload = fetch(args.url, path, auth)
        statuses[name] = status
        if name == "status":
            glances_version = payload.get("glances_version")
            if payload.get("version") != "5":
                sys.exit(f"Not a Glances 5 server: {payload}")
        payload = anonymize(name, payload, anon)
        (OUT_DIR / f"{name}.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
        print(f"{status}  {name}")

    meta = {
        "glances_version": glances_version,
        "captured_on": datetime.date.today().isoformat(),
        "anonymized": True,
        "http_status": statuses,
        "endpoints": dict(ENDPOINTS),
    }
    (OUT_DIR / "META.json").write_text(json.dumps(meta, indent=2, sort_keys=True) + "\n")
    print(f"Wrote {len(ENDPOINTS)} fixtures to {OUT_DIR.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
