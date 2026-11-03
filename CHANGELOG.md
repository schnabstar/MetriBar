# Changelog

All notable changes to MetriBar are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/). Versions before 1.0 may still change; they require a Glances 5 server.

## [Unreleased]

### Added

- The menu bar can show up to three values next to the status icon: CPU, memory, swap, load (5 minutes), the highest temperature, the fullest disk, network download or upload, and containers with problems (Settings › Display). They come with symbols, words or numbers only; an optional trend line follows the first value; and they can be limited to the times when something is wrong, so the menu bar shows the icon alone otherwise. The setting of 0.11.0 is carried over.
- Your own thresholds (Settings › Thresholds): rules such as CPU above 90 % for 5 minutes, a disk above 85 % or a temperature above 80 °C, for one server or all of them. They cover CPU, memory, swap, load (5 minutes), disks, temperatures and network throughput, with a level (warning or critical) and a hold time. A rule that fires changes the status icon like a warning from Glances and is reported by notifications, whatever their general level and hold time are. A rule ends when the value is back by a small margin, so a value at its limit does not flip. Templates help to start; nothing changes on your servers.
- Notifications, off by default (Settings › Notifications): MetriBar tells you when CPU, memory, load, a container, a temperature or a file system reaches warning or critical, and when a server cannot be reached or is back. A problem has to last (2 minutes by default) before it is reported, the same problem is reported at most every 15 minutes unless it gets worse, quiet hours hold notifications back until they end, and every server has its own switch. Clicking a notification opens the alerts of that server. The file systems are fetched in the background while notifications are on, so a full disk is noticed.
- Optional update check, off by default (Settings › General › Updates). When turned on, MetriBar asks GitHub once a day whether a newer release exists and points it out in the menu bar window and in the settings, with links to the release notes and the download. **Check for Updates…** in the app menu checks once on request. Nothing is installed automatically.

### Changed

- The menu bar shows its values as one image instead of text next to the icon, because the system keeps only one image and one text of a label. The image follows the colors of the menu bar like a symbol.
- The disk image has a new window in the style of Liquid Glass: a light background with glass panes behind MetriBar and Applications, an arrow between them and the app icon as volume icon.

## [0.11.0] - 2026-10-31

First regular release, no longer marked as a preview. Requires a server running Glances 5.

### Added

- The menu bar can show CPU and memory usage side by side.
- Temperatures above their hardware warning or critical threshold change the status icon like other alerts. The sensors feed is now fetched in the background for this.
- Sensors without thresholds, such as `cpu_thermal` on a Raspberry Pi, use the level Glances reports.

### Changed

- The menu bar window closes when you open the dashboard, the web UI, settings or About, instead of staying in front.
- The settings window has the same size for every pane and one sidebar that lists the servers, Display and General, like System Settings.

## [0.1.0-preview.1] - 2026-10-26

First preview. Requires a server running the Glances 5 beta.

### Added

- Menu bar icon with the combined status of all servers, optionally with the CPU or memory usage of one server.
- Popover with server switcher, CPU, memory, load, uptime and containers, and explanations with a matching fix when a server cannot be read.
- Dashboard window with the sections of every server in the sidebar: overview (usage rings, trend, network, sensors, storage, containers, system, alerts), history charts, storage, network, sensors and GPU, processes with an inspector, containers and alerts. Menu commands switch sections (⌘1–⌘8) and refresh (⌘R).
- Design that follows the macOS 26 guidelines: Liquid Glass from the system toolbar, sidebar and menu bar window, edge-to-edge tables, and the standard About window.
- Support for multiple Glances 5 servers, with detection of Glances 4 and other servers.
- Server settings with URL validation, passwords in the Keychain, a warning for passwords over plain HTTP, certificate inspection and pinning for self-signed certificates, and a step-by-step connection test.
- Detection of a missing local network permission, with a shortcut to the privacy settings.
- Polling that fetches only what is visible, backs off on errors, stops after rejected credentials to avoid lockouts, and pauses while the Mac sleeps.
- Demo data for trying MetriBar without a server.
- English and German localization.
