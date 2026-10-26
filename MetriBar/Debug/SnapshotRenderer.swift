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

            let empty = makeModel()
            let demo = makeModel()
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
            logger.notice("snapshots written to \(directory.path, privacy: .public)")
            NSApplication.shared.terminate(nil)
        }

        private static func makeModel() -> AppModel {
            let suite = "MetriBarSnapshots.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            return AppModel(
                configStore: ConfigStore(defaults: defaults), credentials: InMemoryCredentialStore(),
                defaults: defaults, observeSystemEvents: false)
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
