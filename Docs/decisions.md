# Decisions and findings

A running log of technical decisions and of what we learned from real Glances 5 servers. Newest entries first.

## 2026-10-26 – Dashboard window

- **Layout:** `NavigationSplitView` with the servers in the sidebar (sharing the selection with the popover) and seven sections switched by a segmented control in the toolbar or ⌘1–⌘7: overview, history, storage, network & sensors, processes, containers, alerts.
- **Each section declares its feeds** (`DashboardSection.feeds`) and keeps them active with `keepActive` while visible, so only the visible data is fetched at the live interval.
- **Tables** (`Table` with `KeyPathComparator`) sort locally; MetriBar never changes the server's sort order. Row types are `nonisolated` structs: with `MainActor` default isolation, key paths to actor-isolated properties are not `Sendable`, which `KeyPathComparator` requires in Swift 6. `Format` is `nonisolated` for the same reason.
- **Process command lines** appear only after clicking "Show Command Line" in the inspector and are hidden again when the selection changes, because arguments can contain secrets.
- **History charts** (Swift Charts) show the history Glances keeps; collection plugins (network) are charted per interface. Percent charts use a fixed 0–100 % scale, others start at zero.
- **Snapshots:** `ScrollView` is AppKit-backed and renders empty with `ImageRenderer`, so overview and history are split into a scroll wrapper and a content view (`OverviewContent`, `HistoryContent`) that the snapshot tool renders.

## 2026-10-26 – Menu bar, popover and settings

- **`AppModel`** (app target) owns the server list (`ConfigStore`, UserDefaults, no secrets), preferences, the `MonitorCenter` and the system event observer. Passwords go to `AppKeychain.store`; a changed password without other config changes reconnects the monitor.
- **Connection problems are classified in MetriBarKit** (`ConnectionProblem`, testable) and explained in the app (`ProblemText.swift`, localized) with a matching action: open the server settings, open the Local Network privacy pane, or try again. Timeouts and refused connections are checked with `LocalNetworkCheck` before blaming the server.
- **Problem banner only when the server is unusable** (offline after three failures, rejected credentials, unsupported version). Single failed attempts only show "Retrying…" in the status line.
- **Connection test** runs against the unsaved editor values with a fail-fast session (`.metriBarConnectionTest`, no waiting for connectivity) and stops at the first failing step.
- **Demo server:** anonymized fixtures ship in MetriBarKit (`Resources/Demo`, ~140 KB) and back `DemoServer`, used for "Try with Demo Data", previews and snapshots; later also for App Store review.
- **Localization:** English source strings in code, `Resources/Localizable.xcstrings` with German translations (informal "du", as macOS uses). Strings are extracted with `xcrun xcstringstool sync` from the `.stringsdata` files of a build. `Resources/InfoPlist.xcstrings` localizes the local network prompt.
- **Resources live outside the synchronized source folder** (`Resources/` as a regular group): XcodeGen does not create a Copy Bundle Resources phase for synchronized folders, so assets and string catalogs were missing from the app bundle.
- **Snapshot tool (DEBUG only):** `-MetriBarSnapshots 1` renders the popover and problem banners with demo data to PNGs in the sandbox container's `tmp/snapshots`. `ImageRenderer` cannot draw AppKit-backed controls (buttons with some styles, progress bars, `Form`), which appear as placeholders; the settings window has to be checked in the running app.

## 2026-10-26 – Security

- **Passwords live in the data protection keychain** (`KeychainCredentialStore`, one generic password per server UUID, service `it.schnabel.MetriBar.server`, accessible after first unlock, this device only). Apple's TN3137 calls the file-based keychain "on the road to deprecation", and switching before the first release avoids a migration later. Access is bound to the keychain access group (team + bundle ID) instead of the exact code signature, so development and release builds share items without prompts.
  - This needs the `keychain-access-groups` entitlement and a provisioning profile. Official builds get both through automatic signing (verified: `com.apple.application-identifier` and `keychain-access-groups` = `MTV73SM3Y8.it.schnabel.MetriBar`, profile embedded, store/read/remove works in the signed app). Release builds will need a Developer ID provisioning profile.
  - Team, bundle ID and entitlements come from `Config/Shared.xcconfig`; contributors override them in `Config/Local.xcconfig` (ignored by git). Whether a free Apple ID can get the keychain entitlement is not documented, so contributors can switch to the file-based keychain with `METRIBAR_FILE_KEYCHAIN` and `Config/MetriBar-FileKeychain.entitlements` (verified with an ad-hoc signed build).
  - Without the entitlement the store reports `CredentialStoreError.missingEntitlement` instead of failing silently.
- **Certificate pinning per server**: `ServerConfig.pinnedCertificate` holds the SHA-256 fingerprint of the leaf certificate (as browsers and `openssl x509 -fingerprint -sha256` show it). With a pin, exactly that certificate is accepted, also when self-signed or expired; any other certificate fails with `GlancesError.certificateMismatch(presented:)`. Without a pin the system validates as usual. The check runs in a per-task `URLSessionTaskDelegate`; a test against a local HTTPS server with a self-signed certificate confirmed that server-trust challenges reach it.
- **`CertificateInspector`** reads the certificate a server presents and aborts the TLS handshake before any HTTP request, so no credentials are sent while the user decides whether to trust it.
- **`TransportSecurity`** classifies a URL as HTTPS, HTTP on a (likely) local network or HTTP. `ServerConfig.sendsPasswordUnencrypted` drives the warning before a password is saved for a plain HTTP server.
- **`ServerURL.parse`** rejects URLs with embedded credentials (they belong in the Keychain), adds `http://` when missing, and strips query, fragment and pasted API paths such as `/api/5`, keeping reverse-proxy prefixes.
- **`DiagnosticReport`** produces copyable text without passwords, user names, process command lines or monitored values; the host is replaced by `<host>` unless the user includes it, also inside server error messages.
- **Logging:** state changes are logged with the server UUID public and everything else private (OSLog default).

## 2026-10-26 – Polling (ServerMonitor, MonitorCenter)

- **One `ServerMonitor` per server**, owned by `MonitorCenter`, which also computes the menu bar health (worst of all enabled servers).
- **Feeds** group endpoints: `core` and `containers` run in the background every 10 s; views keep further feeds (`overview`, `storage`, `network`, `sensors`, `processes`, `alerts`, `history`) active with `keepActive(_:)` from a `.task` modifier. While any view is subscribed, all active feeds are fetched every 2 s. Subscriptions are reference-counted, so the popover and the dashboard can overlap.
- **History is downloaded completely every 30 s** while visible instead of merging increments. The payload (a few hundred KB on a LAN) is cheaper than the merging logic for gaps, restarts and per-item series.
- **Failures:** backoff doubles from the current interval up to 60 s; `Retry-After` wins if longer. After three failures in a row the values are marked stale and the server counts as offline; single failures keep the last health so the menu bar does not flicker.
- **401 and unsupported versions halt polling** until the configuration changes or the user refreshes, so a wrong password cannot trigger Glances' failed-login rate limit (10 per minute).
- **A failing optional feed** (for example sensors) is recorded in `feedErrors` and does not affect the connection state. A failing `core` feed or a 401 from any feed is a connection failure.
- **Sleep, wake and network changes:** `SystemEventObserver` reports them; the center pauses all monitors before sleep and polls immediately after wake or a network change.
- **Testing:** the monitor takes a clock; tests use a manual clock and a fake server built from the fixtures, so intervals, backoff and halting are verified exactly without waiting.

## 2026-10-26 – API layer and first connections from the sandboxed app

- **History of collection plugins is nested per item.** `/api/5/network/history` returns `{"series": {"bytes_recv": {"eth0": [...], "lo": [...]}}}`, also when `item=eth0` is given. Plugins with a single set of fields (cpu, mem, load) return `{"series": {"user": [...]}}`. `History` decodes both shapes (`series` and `itemSeries`).
- **Lenient decoding everywhere.** Every model field uses `@Lenient`: a missing key, `null` or an unexpected type becomes `nil` instead of failing the whole payload. Collections drop items that fail to decode. The history bug above was found because a test checked that the decoded series was not empty — tests must assert content, not only that decoding succeeds.
- **JSON5 decoding** is enabled so that `NaN` and `Infinity` from Python's `json` module do not fail a payload.
- **ATS:** plain HTTP to `127.0.0.1` and `localhost` works from the sandboxed app with `NSAllowsArbitraryLoads`.
- **Local network privacy (macOS 27.0.1):** the first HTTPS request to a LAN host (`192.168.x.x`) waited for the permission prompt and failed with `URLError.timedOut` after the 20 s resource timeout. Although the user clicked "Allow" in the prompt, the switch in System Settings › Privacy & Security › Local Network was off afterwards, and every request timed out. The network log shows the cause: `path: unsatisfied (Local network prohibited)`. After switching it on, the request succeeded within a second — also with the app outside `/Applications` (Apple Development signature).
  - Consequences for the app: a timeout to a private address is not enough to explain the problem. The connection test checks the path with Network.framework (`NWPath.UnsatisfiedReason.localNetworkDenied`) and, when access is denied, offers a button that opens `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocalNetwork`. The first connection shows a hint while the system prompt is pending and retries automatically.
  - Developer note: in zsh, `log` is a shell builtin. Use `/usr/bin/log show …` to read the unified log.

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
- Opening settings and the dashboard from the popover: window ordering and focus.
- ATS for plain HTTP to a `.local` name and a qualified LAN host name (only `127.0.0.1` and `localhost` were testable; the test server has no plain HTTP port).
