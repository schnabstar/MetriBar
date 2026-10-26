# Decisions and findings

A running log of technical decisions and of what we learned from real Glances 5 servers. Newest entries first.

## 2026-10-26 – Findings from a real Glances 5.0.0b1 server

Captured with `Scripts/capture-fixtures.py` (anonymized fixtures in `Packages/MetriBarKit/Tests/MetriBarKitTests/Fixtures/v5`).

- **Version detection works as documented.** `GET /status` returns `{"status": "ok", "version": "5", "glances_version": "5.0.0b1"}` without authentication. `GET /api/4/status` returns 404 on a Glances 5 server.
- **Container `image` is a list of tags**, not a string as the API documentation states. The decoder must accept both.
- **There is no separate health field.** For containers with a health check, `status` is `"healthy"` (and presumably `"unhealthy"` / `"starting"`) instead of `"running"`. MetriBar must treat these as running states.
- **`network_rx` / `network_tx` can be `null`** (for example on the first collection cycle). All numeric fields are decoded as optionals.
- **`engine_url` can be `null`.**
- **Missing plugin:** `GET /api/5/gpu` on a host without GPU returns `404 {"detail": "Plugin 'gpu' not found"}`. Unknown field: `404 {"detail": "Field 'doesnotexist' not found"}`. MetriBar checks `/api/5/pluginslist` first and treats a 404 for a listed plugin as an error.
- **History:** `GET /api/5/<plugin>/history?nb=N` returns `{"timestamps": [...], "series": {"<field>": [...]}}`. Without `field`, CPU returns `system` and `user`, network returns `bytes_recv` and `bytes_sent`.
- **Alerts:** the alert list and incidents were empty during capture. The event structure (`ts`, `plugin`, `key`, `field`, `level`, `previous_level`, `value`, `prominent`, `is_initial`, `hostname`) is taken from `glances/alerts.py` on the `develop` branch and still needs a real sample.
- **Glances running inside Docker** sees the container's view: bind mounts instead of host file systems and only the container's network interfaces. `Docs/glances-setup.md` must explain the Docker options that give Glances the host view.

## 2026-10-26 – Project setup

- XcodeGen (`project.yml`) generates `MetriBar.xcodeproj`, which is committed. Source folders are synchronized folders, so adding files does not require regenerating the project.
- macOS 26 deployment target, Swift 6 language mode, `MainActor` default isolation in the app target, no external dependencies.
- App Sandbox with `com.apple.security.network.client` only; hardened runtime; `LSUIElement`.
- `NSAllowsArbitraryLoads` is enabled because homelab servers are often reached over plain HTTP by host names such as `nas.fritz.box`, which `NSAllowsLocalNetworking` does not cover. The app warns about unencrypted connections itself.
- The dashboard window switches the activation policy to `.regular` while it is open, so it appears in the Dock and the app switcher.

## Open spikes

- Menu bar label with a number: does `MenuBarExtra` respect `monospacedDigit()`?
- Local network privacy prompt on first connection to a LAN host (macOS 26/27).
- ATS behaviour for HTTP to an IP address, a `.local` name and a qualified LAN host name.
- Opening settings and the dashboard from the popover: window ordering and focus.
