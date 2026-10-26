# Changelog

All notable changes to MetriBar are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/). Versions before 1.0 are previews that require the Glances 5 beta.

## [Unreleased]

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
