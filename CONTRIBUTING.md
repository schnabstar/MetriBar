# Contributing to MetriBar

Thanks for your interest in MetriBar! Bug reports, ideas, translations and pull requests are welcome.

Please read the [Code of Conduct](CODE_OF_CONDUCT.md). To report a security issue, follow [SECURITY.md](SECURITY.md) instead of opening a public issue.

## What MetriBar is (and is not)

Keep these principles in mind when proposing changes:

- **Glances 5 only.** MetriBar talks to the Glances 5 REST API (`/api/5`). Glances 4 is not supported.
- **Read-only.** MetriBar only sends `GET` requests and never changes anything on a server: no container actions, no process actions, no changes to the server's sort order.
- **No telemetry, no cloud, no account.** Network traffic goes only to the servers the user adds.
- **No external dependencies.** Only Apple frameworks. Discuss a new dependency in an issue first.
- **Small and native.** A menu bar app with a dashboard window, not a replacement for the Glances web UI.

## Development setup

Requirements: macOS 26 and Xcode 26 or later.

```sh
git clone https://github.com/schnabstar/MetriBar.git
cd MetriBar
cp Config/Local.xcconfig.example Config/Local.xcconfig   # then enter your team ID and bundle ID
open MetriBar.xcodeproj
```

- `Config/Local.xcconfig` is ignored by git. It overrides the maintainer's team, the bundle identifier and, if your account cannot create a provisioning profile, switches your builds to the file-based keychain (see the comments in the example file).
- `MetriBar.xcodeproj` is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). Source folders are synchronized, so adding or removing Swift files needs no regeneration. Run `xcodegen generate` only after changing targets or build settings, and commit both `project.yml` and the generated project.

## Project layout

| Path | Contents |
|---|---|
| `MetriBar/` | The app: menu bar, popover, dashboard, settings (SwiftUI) |
| `Packages/MetriBarKit/` | API client, models, polling, security and diagnosis logic, with tests |
| `Resources/` | Asset catalog and string catalogs (English, German) |
| `Config/` | Info.plist, entitlements, xcconfig files |
| `Docs/` | Setup, security, troubleshooting and the decision log (`decisions.md`) |
| `Scripts/` | Fixture capture |

Most logic lives in MetriBarKit so it can be tested without the app.

## Tests

```sh
swift test --package-path Packages/MetriBarKit
```

Optional tests that need real systems:

| Environment variable | What it runs |
|---|---|
| `METRIBAR_LIVE_URL=https://glances.example.com` (plus `METRIBAR_LIVE_USER`, `METRIBAR_LIVE_PASSWORD`) | Every endpoint and the full monitor against a real Glances 5 server |
| `METRIBAR_KEYCHAIN_TESTS=1` | File-based keychain round trip in your login keychain (cleaned up afterwards) |
| `METRIBAR_TLS_URL=https://127.0.0.1:8443 METRIBAR_TLS_SHA256=AB:CD:…` | Certificate inspection and pinning against a server with a self-signed certificate |

Please add tests for new logic in MetriBarKit. Test against values, not only against successful decoding: lenient decoding turns unexpected data into `nil` silently.

## Test fixtures

Fixtures are real Glances 5 responses, anonymized:

```sh
python3 -I Scripts/capture-fixtures.py https://glances.example.com
```

The script replaces host names, container names and images, IP addresses, user names, process names, command lines and mount points. **Review the diff before committing** and never commit unanonymized data. Do not copy examples from the Glances documentation into the repository; Glances is LGPL-licensed, so we capture our own.

## Formatting

The project uses Apple's `swift-format` from the Xcode toolchain:

```sh
xcrun swift-format format --in-place --recursive MetriBar Packages
xcrun swift-format lint --strict --recursive MetriBar Packages
```

CI fails on lint errors.

## Localization

User-facing strings are written in English in the code and translated in `Resources/Localizable.xcstrings`. After adding strings, build the app once and sync the catalog:

```sh
find build/DerivedData/Build/Intermediates.noindex -path "*MetriBar.build*" -name "*.stringsdata" -print0 \
  | xargs -0 xcrun xcstringstool sync Resources/Localizable.xcstrings --stringsdata
```

Add a German translation if you can; otherwise the maintainer will. New languages are welcome.

## Pull requests

- Keep pull requests focused on one change.
- Describe what changes for users and how you tested it.
- Add an entry to the `Unreleased` section of [CHANGELOG.md](CHANGELOG.md) for user-visible changes.
- Make sure `swift test` and the lint pass.
- Do not include secrets, real host names or unanonymized server data in code, fixtures, screenshots or logs.

## License

MetriBar is licensed under the [Apache License 2.0](LICENSE). By submitting a contribution you agree that it is licensed under the same terms (section 5 of the license); no separate contributor agreement is needed.
