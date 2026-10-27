# Release process

Releases are Developer ID signed, notarized by Apple and published on GitHub. Versions before 1.0 are previews (`0.x.y-preview.n`) that require the Glances 5 beta.

## One-time setup

1. A **Developer ID Application** certificate in the login keychain (Xcode › Settings › Accounts › Manage Certificates; only the team's Account Holder can create it).
2. Notarization credentials in the keychain, with an app-specific password from account.apple.com:

   ```sh
   xcrun notarytool store-credentials metribar --team-id MTV73SM3Y8
   ```

3. Xcode signed in with the team account, so `-allowProvisioningUpdates` can create the Developer ID provisioning profile (needed for the keychain access group).

## Steps

1. Set `MARKETING_VERSION` (and increase `CURRENT_PROJECT_VERSION`) in `project.yml`, run `xcodegen generate`.
2. In `CHANGELOG.md`, rename `Unreleased` to the version with today's date and add a new empty `Unreleased` section.
3. Commit and push; wait for CI to pass.
4. Build, sign and notarize:

   ```sh
   Scripts/release.sh 0.1.0-preview.1
   ```

   The script archives the app, exports it with Developer ID, notarizes and staples the app, builds a signed and notarized disk image, checks both with Gatekeeper and writes the DMG, a ZIP and SHA-256 checksums to `dist/`. It does not publish anything.

5. Install the DMG on a Mac and check that it opens without warnings.
6. Tag and publish:

   ```sh
   git tag -a v0.1.0-preview.1 -m "MetriBar 0.1.0 preview 1"
   git push origin v0.1.0-preview.1
   gh release create v0.1.0-preview.1 --prerelease --title "MetriBar 0.1.0 Preview 1" \
     --notes-file <notes> dist/MetriBar-0.1.0-preview.1.{dmg,zip,sha256}
   ```

   Use the changelog section of the version as notes and mention that Glances 5 is required.

## Notes

- The App Sandbox, hardened runtime and the absence of `get-task-allow` are checked by the script.
- Updates are not installed automatically; users download new versions from the releases page. Homebrew distribution is planned for 1.0.

## Screenshots and social preview

`Docs/images/` holds the README screenshots and the social preview (`social-preview.png`, 1280×640, set by hand under Settings › General › Social preview). Make the screenshots from a Debug build with demo data and an English interface, so no real server data appears:

```sh
open -n <Debug MetriBar.app> --args -AppleLanguages "(en)" -AppleLocale en_US \
  -MetriBarDemo 1 -MetriBarOpen dashboard -MetriBarSection overview
screencapture -o -l <window id> Docs/images/dashboard-overview.png
```

Capture the window only (`-l`), never the whole screen.

