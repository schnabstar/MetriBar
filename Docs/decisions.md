# Decisions and findings

A running log of technical decisions and of what we learned from real Glances 5 servers. Newest entries first.

## 2026-11-05 – Custom thresholds

Rules are the user's own limits (`ThresholdRule`: metric, above/below, limit, hold time, warning/critical, one server or all). They only change what MetriBar shows and reports; MetriBar stays read-only towards Glances.

- **One place decides, the monitor.** `ServerMonitor` owns a `RuleEvaluator` and publishes `ruleConditions`; `dataHealth` takes the maximum of Glances' `worstLevel` and the rule levels. So the icon, the dashboard and the notifications agree, and rules work with notifications off. The rule fires after the hold time and ends with a hysteresis (3 points for percent, 2 °C, 0.2 load, 5 % of the limit for MB/s), and both are part of `RuleEvaluator`, a pure struct that takes `now` like `AlertEvaluator`.
- **Rules bypass the global notification settings.** A rule has its own level and hold time, so `AlertEvaluator` reports a `rule` condition from `warning` up and without a second wait, also when the general setting is "critical only, after 10 minutes". The cooldown (15 min), quiet hours, the per-server switch and the recovery option still apply.
- **Per value, not per rule.** A disk rule without a mount point and a temperature rule without a sensor apply to every file system or sensor; each has its own timer and state (`RuleEvaluator` keys: rule and item). Network throughput is the sum of all interfaces that are up without loopback, in MB/s (Glances reports bytes per second).
- **Feeds:** `RuleMetric.Kind.feed` maps a metric to its feed; `ThresholdRule.requiredFeeds` are fetched in the background beyond the usual ones, merged with the storage feed that notifications need (`AppModel.refreshBackgroundFeeds`). Swap comes from the storage feed.
- **Failed feeds keep the state.** Like for notifications, values of a feed with an error are not used: no timer runs, a firing rule keeps firing, and the start of a pending rule is forgotten, so an old start time cannot fire right after an outage. (A test caught that the pending start was not reset at first.)
- **An interrupted observation resets the waiting rules (found by the Codex review of the pull request).** A rule counts the time the value stayed beyond the limit, so it needs continuous observations. `RuleEvaluator.suspend()` forgets the start of every rule that is still waiting; `ServerMonitor` calls it when a poll fails (`recordFailure`, where the core feed failing does not set a feed error, so the old time stamp would have stayed "fresh"), on `pause()` (sleep) and on `stop()`. A firing rule keeps firing. `ServerMonitor` takes the wall clock as a parameter (`now`, default `Date()`) so tests can move time without waiting.
- **State belongs to what is measured, not only to the rule's id (also from the review).** The key of a state is the rule id, the metric, the comparison and the item. Editing a firing CPU rule to memory therefore starts from scratch, with its hold time, instead of inheriting "firing"; the same for above/below and for a changed mount point or sensor. A changed limit or hold time keeps the state. The condition key the alerts see contains the metric kind for the same reason.
- **Storage:** `RuleStore` (UserDefaults, `{"version": 1, "rules": [...]}`) loads each rule on its own, so a metric from a later version drops only that rule. Decoding is tolerant: only the metric and the limit are required. Deleting a server deletes its rules.
- **Not done:** rules per container, rule hits as their own table in the alerts section of the dashboard (the status of a firing rule is visible as the health of the server), and a rule on the history of a value ("average over 5 minutes"). The hold time is "the value stayed beyond the limit", not an average.
- **Checking in the app (DEBUG only):** `-MetriBarFakeRule 1` adds a rule that fires on the demo server.

## 2026-11-04 – Notifications

Notifications are local (`UNUserNotificationCenter`, no entitlement in the sandbox), off by default, and the permission is requested when the user turns them on, not at launch.

- **A pure evaluator decides, a timer drives it.** `AlertEvaluator` (MetriBarKit) is a state machine without clock or side effects: it gets a `ServerObservation` and `now` and returns `AlertNotice`s. `AlertCenter` calls it every 15 s for all monitors. It works from a timer instead of hooks into `ServerMonitor`, because time has to pass also when a server stopped answering or polling was halted (rejected credentials); a hook at the end of each poll would never fire then.
- **Rules:** a condition has to stay at or above the chosen level (warning or critical) for the hold time (default 2 min) before it is reported. The same condition is reported at most once per 15 min (cooldown), so a value at its threshold does not produce a stream. A reported problem that gets worse is reported at once (warning to critical), one that gets better is not. Recovery is reported only if asked for; a server that was reported offline is always reported back. A container or sensor that disappears is dropped without a recovery notice.
- **Quiet hours hold back, they do not drop.** During quiet hours nothing is reported and the state is not marked as reported, so a problem that lasts beyond them is reported when they end. Recovery notices during quiet hours are dropped.
- **Sleep and network changes:** after wake or a network change, offline servers are ignored for 60 s and problems that were waiting start counting anew; without that, a critical value from before the sleep would be reported at once from an hour-old start time.
- **Sources are the ones of the menu bar icon** (`ServerSnapshot.conditions`: CPU, memory, load, containers including unhealthy ones, temperatures), plus file systems. File systems come from the storage feed, which is not a background feed for everyone: `MonitorCenter.setExtraBackgroundFeeds` adds it only while notifications are on (three more requests per interval: fs, diskio, swap). They do not change the icon, because `worstLevel` would otherwise depend on whether the storage view was opened before.
- **Outdated values are not reported (found by the Codex review of the pull request).** When an optional feed fails (file systems, containers, sensors) while `core` works, `ServerMonitor` keeps the old snapshot and only records `feedErrors[feed]`; the old values would have satisfied the hold time and raised an alert without a fresh reading. `ServerMonitor.watchedConditions(now:)` leaves out the kinds whose feed has an error or was not fetched for 5 minutes, and `AlertEvaluator` treats those kinds as unknown: no timer runs, nothing counts as recovered, and what was reported stays reported, so the problem is not announced twice when fresh values return. The hold time then starts anew.
- **A monitor is not restarted for a setting that does not concern the connection.** `ServerConfig.notificationsEnabled` is a new field; `ServerMonitor.update(config:client:)` keeps the connection when only that field changed (but not when the config is unchanged, which is how `reconnect` swaps the client; a test caught that mistake).
- **`ServerConfig` decodes tolerantly now** (only `id` and `url` required), like `Preferences`, so saved servers of 0.11.0 stay readable. A test loads the old format through `ConfigStore`.
- **Notices replace each other:** the request identifier is the condition (server, kind, item), so a worse level replaces the older banner instead of stacking. Banners are also shown while MetriBar's own windows are in front. Sound only for critical and offline. No "Time Sensitive" level, which needs an extra capability.
- **Clicks:** the delegate sets the server and the alerts section and bumps `AppModel.dashboardRequest`; `MenuBarLabel` observes it and opens the window, because only a view has `openWindow`.
- **Not done:** per-condition mute, notification actions (mute for an hour), a history of what was reported. Custom thresholds come next and will feed the same evaluator.
- **Checking in the app (DEBUG only):** `-MetriBarFakeNotification 1` asks for permission and posts a critical CPU notice for the demo server. The system prompt has to be answered by hand.

## 2026-11-03 – Update check (opt-in)

MetriBar can tell the user about a newer release, but never installs one. Distribution stays a notarized DMG from GitHub, and the next step (Homebrew for 1.0) is a package manager's job, so Sparkle would only add a dependency, XPC services and sandbox entitlements.

- **Opt-in, off by default.** The privacy promise ("contacts only your servers") held until now, so the check had to be a conscious choice. `Preferences.checksForUpdates` is false, there is no prompt at first launch, and nothing leaves the Mac while it is off. The footer, `PRIVACY.md` and the README say what is sent: one anonymous `GET api.github.com/repos/schnabstar/MetriBar/releases/latest` with a generic `User-Agent: MetriBar/<version>`; GitHub sees the IP address. Anonymous requests are limited to 60 per hour per IP, far above one per day; a 403/429 is reported as "GitHub is limiting requests" and counts as a check, so it is not repeated at once.
- **`releases/latest` skips drafts and pre-releases,** so previews are never offered. A running pre-release is still offered the final release (the plan said it would not check at all; offering the final release is the more useful behavior).
- **Links are validated.** `ReleaseInfo` only exposes the release page and the DMG if they are `https://github.com/schnabstar/MetriBar/…` (no user info, no port, no look-alike hosts, and no `.` or `..` path segment, also not percent-encoded or hidden in an encoded `/`: a prefix check alone let `…/MetriBar/../../other/` through, which resolves to another repository; found by the Codex review of the pull request); `AvailableUpdate` is built only from such a release. A manipulated answer cannot make the app open another site. Release notes are not rendered at all, only linked.
- **Schedule:** a task started when the setting is on waits 5 s after launch, then looks at the clock every hour and checks if the last check is a day old (`UpdatePolicy.isDue`, also when the clock was set back). The hourly look also covers wake from sleep without extra event handling. User actions ("Check Now", the app menu command) ignore the setting and the schedule.
- **State:** `UpdateModel` stores the time of the last check, the found release (`AvailableUpdate`, Codable) and the skipped version in UserDefaults, outside `Preferences`, so a check does not look like a settings change. A found update survives a restart until it is installed (`known.appVersion > current`). A failed automatic check keeps an update found earlier. "Skip This Version" only hides the banner in the menu bar window; the settings still show it, and a manual check brings it back.
- **`Preferences` moved into MetriBarKit** to be tested (the app target has no tests). Its `init(from:)` uses `decodeIfPresent`: the synthesized decoder would fail on data written by 0.11.0, and `AppModel` would silently reset all settings. The same applies to every later addition to `Preferences` and `ServerConfig`.
- **Not done:** detecting a Homebrew installation (no cask yet), verifying the SHA-256 of a download (the app downloads nothing), and a check on wake or when opening the settings (the hourly look is enough).
- **Checking in the app (DEBUG only):** `-MetriBarFakeUpdate 1` shows a fake release 99.0.0 without contacting GitHub. For the real path, a copy of the app with `CFBundleShortVersionString` set to a lower version (`plutil -replace`, then `codesign --force --sign -`) finds the real release.

## 2026-10-26 – Liquid Glass and HIG pass

An audit of every view against the macOS 26 Human Interface Guidelines and the macOS 27 SDK. Guiding rule: Liquid Glass belongs to the navigation and control layer (toolbar, sidebar, inspector, sheets, menu bar window), never to content. MetriBar gets it from system components instead of custom `glassEffect`; the only custom glass is the hover read-out floating over the history charts.

- **Dashboard navigation moved into the sidebar.** One collapsible section per server (health badge and name in the header) with the eight sections as rows, like accounts and mailboxes in Mail. This replaces the custom capsule tab bar in the content. A prototype showed that the sections do not fit into the toolbar: with title, subtitle and German labels, even the new `.pickerStyle(.tabs)` of macOS 27 moved completely into the overflow menu at 1080 pt. "Network & Sensors" became two sections, so there are eight (⌘1–⌘8).
- The sidebar visibility is stored under a new scene storage key (`showsSidebar`), so it starts visible also for users who had hidden the server-only sidebar.
- **Toolbar instead of a content header:** server name as title, a per-section subtitle (system and uptime, or the process, container or history summary that used to be a caption), refresh as a toolbar button. Processes add an inspector toggle (⌥⌘I), containers a "Running Only" filter toggle; search stays in the toolbar. Content scrolls under the toolbar; tables use the hard scroll edge effect for their pinned headers.
- **Menu commands:** the sections and Refresh (⌘R) are in the View menu, enabled through a focused scene value of the dashboard window, instead of hidden buttons. The app menu opens the standard About window; the Help menu links to the source code and issues.
- **Standard About window** with app icon, version and copyright from the Info.plist and credits for links and the privacy note. It replaces the About tab in the settings.
- **Tables are edge to edge** without padding; number columns use `TableColumn.alignment(.numeric)`, so header and values align. Storage and alerts show two tables each in a `VSplitView`; alert events became a sortable table.
- **Cards** keep a plain fill (no glass), lose the border unless Increase Contrast is on, and use one corner radius. `CardGrid` lays them out in rows of equal height, so a short card no longer leaves a gap. The card title opens the matching section (chevron instead of a "Show All" link).
- **Color is never the only signal, and no yellow text:** levels show a colored symbol with secondary text (`LevelLabel`), warnings use multicolor symbols with primary text.
- **Menu bar window:** menu-like rows at the bottom (dashboard, web UI, settings, About, quit) as in Control Center modules; the server switcher is a menu with an inline picker, which shows a native check mark and keeps the health symbols. `.menuStyle(.borderlessButton)` is deprecated in the macOS 27 SDK. The problem banner uses a `ConcentricRectangle`.
- **Meter rows** measure their labels (`MeterGroup`) instead of using a fixed 64 pt column. A `Grid` did not work: it gave the flexible bar column no extra width.
- **Settings:** each tab has its own size; the add-server sheet uses `.presentationSizing(.form)` fitted to the form and puts Cancel and Add Server at the bottom trailing edge through `cancellationAction`/`confirmationAction`; the server list supports the Delete key and a context menu; the login item hint opens System Settings.
- Changing numbers roll with `.numericText` content transitions; rings and bars animate. Both respect Reduce Motion.
- **No macOS 27-only API is used.** CI builds with Xcode 26; anything from the macOS 27 SDK would need `#if compiler(>=6.4)` in addition to `if #available(macOS 27, *)`.
- **Checking windows in the running app (DEBUG only):** `-MetriBarDemo 1` uses a throwaway model with the demo server; `-MetriBarOpen dashboard,settings,add-server`, `-MetriBarSection <section>` and `-MetriBarSettingsTab <tab>` open and select windows, so they can be captured with `screencapture -l`.

## 2026-10-26 – CI and repository setup

- **CI** (`.github/workflows/ci.yml`) runs on `macos-26` with the newest installed **Xcode 26** (26.6 at setup), deliberately not the Xcode 27 used locally, so the code keeps building with the oldest supported toolchain. Steps: `swift-format lint --strict`, `swift test` for MetriBarKit, `xcodebuild build` without code signing. First run: green in under two minutes.
- **Integration** (`integration.yml`, nightly and manual) installs Glances 5 from the `develop` branch with pipx on the runner and runs the live tests against it, to notice API changes in the beta early. Containers are not available there; they are covered by the fixtures.
- Actions are pinned by commit SHA; Dependabot updates them weekly.
- `main` requires the "Build and test" check; admins can still push directly. Pull requests are squash-merged.
- Security reports go through GitHub's private vulnerability reporting or to info@schnabel.it. The feature could not be enabled while the repository was private (the API answered 404 and the settings page had no switch); it is on since the repository became public.
- Secret scanning with push protection, Dependabot alerts and security updates, and CodeQL default setup (Swift, Actions) are enabled.

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
