# Setting up Glances 5 for MetriBar

MetriBar reads the REST API of **Glances 5** (`/api/5`). Glances 4 is not supported.

> **Glances 5 is in beta.** Until Glances 5.0 is released, use the development builds shown below: the Docker tag `dev` or an install from the `develop` branch. The stable Glances releases (4.x) and the Docker tags `latest` and `latest-full` are still Glances 4.

Glances runs on the machine you want to monitor (a Raspberry Pi, NAS, server or Docker host). MetriBar connects to it over HTTP or HTTPS; nothing else is installed on the server.

## Option A: Docker (recommended on Docker hosts)

`docker-compose.yml`:

```yaml
services:
  glances:
    image: nicolargo/glances:dev   # Glances 5 beta; switch to a 5.x tag once released
    restart: always
    pid: host                      # host processes instead of the container's
    network_mode: host             # host network interfaces; Glances listens on port 61208
    read_only: true
    volumes:
      - /:/rootfs:ro                                  # host file systems
      - /var/run/docker.sock:/var/run/docker.sock:ro  # containers (see the security note)
      - ./glances.conf:/glances/conf/glances.conf:ro
    tmpfs:
      - /tmp
    environment:
      - GLANCES_OPT=-C /glances/conf/glances.conf -s
      - TZ=Europe/Berlin
```

`glances.conf` next to it (only the relevant part):

```ini
[outputs]
# Listen on all interfaces so MetriBar can connect from your Mac.
bind_address=0.0.0.0
# Protect the API with a password (see "Password" below).
#password=pbkdf2_sha256$600000$...
# Only answer requests for these host names (DNS rebinding protection).
#webui_allowed_hosts=nas.local,192.168.1.10
```

Start it with `docker compose up -d`.

What the options do for MetriBar:

| Option | Without it |
|---|---|
| `pid: host` | Only the processes inside the Glances container are shown. |
| `network_mode: host` | Only the container's network interfaces are shown. |
| `/:/rootfs:ro` | Only the container's file systems are shown, many of them bind mounts. |
| `/var/run/docker.sock` | No containers are shown. |

**Security note:** mounting the Docker socket read-only (`:ro`) protects the file, not the Docker API. A process in the Glances container can still control the Docker daemon. Only do this on hosts where you accept that risk. For Podman, mount the Podman socket instead.

## Option B: pipx (Linux, macOS)

```sh
pipx install "glances[web,containers,sensors] @ git+https://github.com/nicolargo/glances.git@develop"
glances -s -B 0.0.0.0
```

`-s` starts the REST API and web UI on port 61208. Add `--disable-webui` to serve only the API. Glances 5 listens on `127.0.0.1` by default; `-B 0.0.0.0` (or `bind_address=0.0.0.0` in `[outputs]`) makes it reachable from your Mac.

To keep it running, create a systemd service, for example `/etc/systemd/system/glances.service`:

```ini
[Unit]
Description=Glances
After=network-online.target

[Service]
ExecStart=/home/pi/.local/bin/glances -s -C /etc/glances/glances.conf
Restart=on-failure
User=pi

[Install]
WantedBy=multi-user.target
```

Then `sudo systemctl enable --now glances`.

## Password

Glances 5 serves the API without authentication unless you set a password:

```sh
glances --set-password
```

Paste the printed hash into the `password` key of the `[outputs]` section of `glances.conf` and restart Glances. The default user name is `glances` (`[outputs] username` changes it). In MetriBar, turn on "Server requires a password" and enter user name and password; the password is stored in the macOS Keychain.

After 10 failed logins per minute, Glances blocks further attempts for a while. MetriBar stops polling after a rejected password, so a wrong password cannot lock you out.

## HTTPS

Use HTTPS whenever you set a password, otherwise it travels unencrypted.

**Reverse proxy (recommended).** For example with Caddy:

```
glances.example.lan {
    reverse_proxy 127.0.0.1:61208
}
```

When Glances listens on `127.0.0.1` behind a proxy on the same host, Glances 5 only accepts the host names `localhost`, `127.0.0.1` and `[::1]`. Add the proxy's host name to `webui_allowed_hosts` (or let the proxy send `Host: localhost`).

**Glances itself.** Set `ssl_keyfile` and `ssl_certfile` in `[outputs]`.

**Self-signed certificates.** Either install your own certificate authority in the macOS keychain (then MetriBar trusts it like any other certificate), or click "Check Certificate" in MetriBar's server settings, compare the SHA-256 fingerprint with the server's

```sh
openssl x509 -in cert.pem -noout -fingerprint -sha256
```

and click "Trust This Certificate". MetriBar then accepts exactly this certificate and rejects any other.

## Check that it works

From your Mac:

```sh
curl http://SERVER:61208/status
```

The answer must contain `"version": "5"`. If you see `404`, the server runs Glances 4 or something else answers on that port.

Then add the server in MetriBar (menu bar icon › Add Server…) and click **Test Connection**. If something fails, see [troubleshooting.md](troubleshooting.md).

## Exposing Glances safely

Glances is meant for your local network. Do not expose it to the internet without HTTPS, a password and a firewall; use a VPN such as WireGuard or Tailscale to reach it from outside. See [security.md](security.md).
