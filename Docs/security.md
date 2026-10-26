# Security

MetriBar is a read-only client for Glances. This page describes what MetriBar does to protect you and what the operator of a Glances server is responsible for.

## What MetriBar does

**Least privilege**

- Runs in the App Sandbox with a single network entitlement: outgoing connections (`com.apple.security.network.client`). No helpers, no root privileges, no SSH, no Docker socket.
- Sends only `GET` requests. MetriBar never changes anything on a server: no container or process actions and no changes to the server's sort order or settings.

**Credentials**

- Passwords are stored in the macOS data protection keychain, one item per server, available after the first unlock and never synced to other devices.
- Passwords never appear in settings files, logs, exports or diagnostic reports. URLs with embedded credentials (`https://user:pass@host`) are rejected.
- After the server rejects a password, MetriBar stops polling until you change it, so it cannot trigger Glances' login rate limit.

**Encryption**

- TLS certificates are validated by macOS as usual.
- For self-signed certificates you can pin the SHA-256 fingerprint of exactly one certificate per server. MetriBar shows the fingerprint before you trust it and reads it without sending any request. With a pin, any other certificate is rejected with a "Certificate changed" error.
- Plain HTTP is allowed because many home servers have no certificate, but MetriBar marks such connections as unencrypted and warns before you save a password for them.

**Server responses**

- Responses are decoded strictly by type; unexpected values are ignored instead of interpreted. Text is never rendered as HTML or Markdown, and MetriBar never opens URLs from server data.
- Process command lines can contain secrets such as tokens passed as arguments. MetriBar shows them only after you click "Show Command Line" and never logs or stores them.

**Privacy**

- No telemetry, analytics, update checks or third-party SDKs. MetriBar only connects to the servers you add.
- Log messages contain server IDs; host names and errors are marked private in the system log.
- "Copy Details" creates a diagnostic report without passwords, user names, command lines or monitored values, and replaces the host name with `<host>`.

**Local network privacy**

macOS asks whether MetriBar may connect to devices on your local network. If the permission is denied, connections time out; MetriBar detects this and links to System Settings › Privacy & Security › Local Network.

## What the operator of the Glances server should do

MetriBar cannot protect a Glances server that is exposed carelessly. Glances 5 serves its API without authentication unless configured otherwise.

- **Keep Glances in your local network** or behind a VPN (WireGuard, Tailscale). Do not forward port 61208 to the internet.
- **Set a password** (`glances --set-password`, then `[outputs] password`).
- **Use HTTPS**, through a reverse proxy or Glances' `ssl_keyfile`/`ssl_certfile`, especially when a password is set.
- **Restrict host names** with `[outputs] webui_allowed_hosts` to protect against DNS rebinding.
- **Turn off the API documentation** (`[outputs] api_doc=false`) on servers reachable by others; it describes every route.
- **Use a firewall** to limit who can reach port 61208.
- **Understand the Docker socket risk:** mounting `/var/run/docker.sock` into the Glances container, even read-only, gives that container control over the Docker daemon.
- **Keep Glances up to date.** Glances 5 is in beta; security fixes land frequently.

## Reporting vulnerabilities

See [SECURITY.md](../SECURITY.md).
