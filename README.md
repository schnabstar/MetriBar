# MetriBar

**Glances 5 in your macOS menu bar.**

MetriBar is a native macOS menu bar app with a dashboard window for servers running [Glances](https://github.com/nicolargo/glances) 5. See status and key metrics at a glance, and open a native dashboard for the details: CPU, memory, load, containers, storage, network, sensors, processes and alerts.

No agent to install, no cloud, no account, no telemetry.

> **Status:** Early development. MetriBar targets the Glances 5 REST API (`/api/5`), which is currently in beta. Glances 4 is not supported.

## Planned features

- Menu bar icon showing the combined status of all your servers
- Compact popover with CPU, memory, load, uptime and containers
- Dashboard window: overview, history charts, storage & disks, network & sensors, processes, containers, alerts
- Multiple Glances servers
- Credentials stored in the macOS Keychain, TLS with optional certificate pinning
- Strictly read-only: MetriBar never changes anything on your server

## Requirements

- macOS 26 or later
- A server running Glances 5 in web server mode (`glances -s`)

## Privacy

MetriBar only talks to the Glances servers you configure. It collects no data and sends nothing anywhere else.

## License

MetriBar is licensed under the [Apache License 2.0](LICENSE).

MetriBar is an independent project and is not affiliated with or endorsed by the Glances project. See [NOTICE](NOTICE).
