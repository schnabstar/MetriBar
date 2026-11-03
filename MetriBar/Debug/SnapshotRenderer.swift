#if DEBUG
    import AppKit
    import MetriBarKit
    import OSLog
    import SwiftUI

    /// Development tool: launch with `-MetriBarSnapshots 1` to render key
    /// views with demo data as PNG files into the app's temporary directory
    /// (inside the sandbox container), then quit. Useful for checking layouts
    /// and for README screenshots. Views built on AppKit controls, such as
    /// `Form`, render empty with `ImageRenderer` and are not included.
    @MainActor
    enum SnapshotRenderer {
        static func runIfRequested() {
            guard UserDefaults.standard.bool(forKey: "MetriBarSnapshots") else { return }
            Task { await render() }
        }

        private static func render() async {
            let logger = Logger(subsystem: "it.schnabel.MetriBar", category: "snapshots")
            let directory = FileManager.default.temporaryDirectory.appending(path: "snapshots")
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let empty = makeModel(suite: "MetriBarSnapshots.empty")
            let demo = makeModel(suite: "MetriBarSnapshots.demo")
            demo.addDemoServer()
            for _ in 0..<100 where demo.selectedMonitor?.snapshot.containers == nil {
                try? await Task.sleep(for: .milliseconds(50))
            }

            write(PopoverView().environment(empty), name: "popover-empty", to: directory)
            write(PopoverView().environment(demo), name: "popover-demo", to: directory)
            if let monitor = demo.selectedMonitor {
                for (name, problem) in [
                    ("problem-refused", ConnectionProblem.connectionRefused),
                    ("problem-local-network", .localNetworkDenied),
                    ("problem-login", .unauthorized),
                ] {
                    write(
                        ProblemBanner(problem: problem, monitor: monitor, onShowSettings: {})
                            .padding(14).frame(width: 360).environment(demo),
                        name: name, to: directory)
                }
            }
            if let monitor = demo.selectedMonitor {
                let feeds = Task { await monitor.keepActive(Set(Feed.allCases)) }
                for _ in 0..<100 where monitor.snapshot.updated.count < Feed.allCases.count {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                write(
                    OverviewContent(monitor: monitor).environment(demo).frame(width: 860), name: "dashboard-overview",
                    to: directory)
                write(
                    HistoryContent(monitor: monitor).environment(demo).frame(width: 760), name: "dashboard-history",
                    to: directory)
                feeds.cancel()
            }
            writeMenuBarImages(demo: demo, to: directory)
            logger.notice("snapshots written to \(directory.path, privacy: .public)")
            NSApplication.shared.terminate(nil)
        }

        /// The menu bar image in every style, with and without a trend line,
        /// on a gray background, because the real menu bar may be too full to
        /// show a wide item.
        private static func writeMenuBarImages(demo: AppModel, to directory: URL) {
            guard let snapshot = demo.selectedMonitor?.snapshot else { return }
            let items: [MenuBarMetric] = [.cpu, .memory, .networkDown]
            let segments = MenuBarText.segments(items, from: snapshot)
            let trend = TrendLine(
                values: [10, 12, 30, 28, 45, nil, nil, 62, 35, 20, nil, 33, 31], range: 0...100)
            for style in MenuBarStyle.allCases {
                for (name, line) in [("", TrendLine?.none), ("-trend", trend)] {
                    let content = MenuBarContent(health: .ok, segments: segments, style: style, trend: line)
                        .padding(8)
                        .background(Color(white: 0.8))
                    write(content, name: "menubar-\(style.rawValue)\(name)", to: directory)
                }
            }
            let warning = MenuBarContent(health: .warning, segments: segments, style: .symbols).padding(8)
                .background(Color(white: 0.8))
            write(warning, name: "menubar-warning", to: directory)
        }

        /// A model with its own defaults, emptied first, so runs start alike
        /// and leave one preferences file per suite behind.
        static func makeModel(suite: String, deliversNotifications: Bool = false) -> AppModel {
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            return AppModel(
                configStore: ConfigStore(defaults: defaults), ruleStore: RuleStore(defaults: defaults),
                credentials: InMemoryCredentialStore(),
                defaults: defaults, observeSystemEvents: false,
                deliversNotifications: deliversNotifications)
        }

        private static func write(_ view: some View, name: String, to directory: URL) {
            let renderer = ImageRenderer(content: view.background(Color(nsColor: .windowBackgroundColor)))
            renderer.scale = 2
            guard let tiff = renderer.nsImage?.tiffRepresentation,
                let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { return }
            try? png.write(to: directory.appending(path: "\(name).png"))
        }
    }
#endif
