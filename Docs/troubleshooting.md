# Troubleshooting

Start with **Test Connection** in MetriBar's server settings. It checks reachability, the Glances version, the login and reading values one after another and explains the first failure. The sections below match its messages.

## Local network access not allowed

macOS blocks MetriBar from connecting to devices on your local network. Requests then time out without a clear error.

1. Open System Settings › Privacy & Security › Local Network (MetriBar's error message has a button for this).
2. Turn on **MetriBar**.
3. Click **Try Again** in MetriBar.

Even after clicking "Allow" in the first prompt, the switch can end up off; check it if a server on your network keeps timing out. Servers reached through a VPN such as Tailscale do not need this permission.

## Connection refused

Nothing answers on the port.

- Is Glances running as a web server? Start it with `glances -s` (see [glances-setup.md](glances-setup.md)).
- Glances 5 listens on `127.0.0.1` by default. Start it with `-B 0.0.0.0` or set `bind_address=0.0.0.0` in the `[outputs]` section.
- Check the port in the URL (Glances uses 61208) and the server's firewall.

## No response / Server not found

- "Server not found": the host name could not be resolved. Check the spelling, try the IP address, and check your VPN if the server is only reachable through it.
- "No response": the server did not answer in time. Check that it is on and reachable (`ping`, `curl http://SERVER:61208/status`). If the server is in your local network, also check the local network permission above.

## Not a Glances server / Glances 4 detected

- `curl http://SERVER:61208/status` must answer with `"version": "5"`.
- "Glances 4 detected": MetriBar requires Glances 5. The stable Glances releases and the Docker tags `latest`/`latest-full` are still Glances 4; see [glances-setup.md](glances-setup.md) for the Glances 5 builds.
- Behind a reverse proxy with a path prefix, enter the full base URL, for example `https://proxy.example.com/glances`.

## Login failed

- Check user name (default `glances`) and password in the server settings. MetriBar stops polling after a rejected password until you change it.
- "Too many attempts": Glances blocks logins after 10 failures per minute. MetriBar waits for the time the server asks for.

## Host name rejected

Glances answers `400 Bad Request` when the host name in the URL is not allowed:

- Add the name or IP address you use in MetriBar to `webui_allowed_hosts` in the `[outputs]` section.
- Glances bound to `127.0.0.1` behind a reverse proxy only accepts `localhost`; see the HTTPS section of [glances-setup.md](glances-setup.md).

## Certificate not trusted / Certificate changed / Secure connection failed

- "Certificate not trusted": the certificate is self-signed, expired or issued for another name. Click **Check Certificate** in the server settings and trust it after comparing the fingerprint, or install your own certificate authority in the macOS keychain.
- "Certificate changed": the server presents a different certificate than the one you trusted. After renewing a self-signed certificate, trust the new one. If you did not change it, someone may be intercepting the connection.
- "Secure connection failed": the TLS handshake failed, often because the URL uses `https://` for a plain HTTP port. Use `http://` or set up HTTPS.

## Containers, file systems or network interfaces are missing

- "The containers plugin is not active": Glances runs without container support. Install it with the `containers` extra or use the `-full` Docker image.
- "No containers found": Glances has no access to the Docker or Podman socket. Mount the socket into the Glances container (see the security note in [glances-setup.md](glances-setup.md)).
- Only the container's own file systems or network interfaces appear: run the Glances container with `network_mode: host`, `pid: host` and `/:/rootfs:ro`.

## Values look stale

Values are greyed out after three failed attempts in a row. MetriBar retries with increasing delays (up to 60 seconds) and immediately after waking from sleep or a network change. Click **Try Again** or the refresh button to retry now.

## Reporting a problem

Click **Copy Details** next to the error (it contains no passwords and hides the host name) and include it in a [GitHub issue](https://github.com/schnabstar/MetriBar/issues).

For more detail, MetriBar writes state changes to the system log:

```sh
/usr/bin/log show --last 1h --predicate 'subsystem == "it.schnabel.MetriBar"'
```

(In zsh, `log` alone is a shell builtin; use the full path.)
