import Foundation

/// Result of the "Test Connection" button in the server settings.
public struct ConnectionTestReport: Sendable, Equatable {
    public enum Step: Sendable, Equatable {
        case pending
        case passed
        case failed(ConnectionProblem)
        case skipped
    }

    /// Server reachable and running Glances 5.
    public var server: Step = .pending
    /// Credentials accepted (or none needed).
    public var authentication: Step = .pending
    /// Values can be read and decoded.
    public var data: Step = .pending

    public var glancesVersion: String?
    public var hostname: String?
    public var plugins: Set<String> = []

    public init() {}

    public var succeeded: Bool {
        server == .passed && authentication == .passed && data == .passed
    }

    /// The first failure, if any.
    public var problem: ConnectionProblem? {
        for step in [server, authentication, data] {
            if case .failed(let problem) = step { return problem }
        }
        return nil
    }
}

public enum ConnectionTest {
    /// Runs the checks one after another and stops at the first failure.
    /// - Parameter localNetworkCheck: Tells whether macOS blocks the
    ///   connection; replaceable in tests.
    public static func run(
        client: GlancesClient,
        localNetworkCheck: @Sendable (URL) async -> Bool? = { await LocalNetworkCheck.isDenied(for: $0) }
    ) async -> ConnectionTestReport {
        var report = ConnectionTestReport()

        do throws(GlancesError) {
            let status = try await client.checkServer()
            report.glancesVersion = status.glancesVersion
            report.server = .passed
        } catch {
            var problem = ConnectionProblem(error)
            // URLSession only reports a timeout when macOS blocks the connection.
            if problem.mayBeLocalNetworkPermission, await localNetworkCheck(client.baseURL) == true {
                problem = .localNetworkDenied
            }
            report.server = .failed(problem)
            report.authentication = .skipped
            report.data = .skipped
            return report
        }

        do throws(GlancesError) {
            report.plugins = Set(try await client.get(.pluginsList))
            report.hostname = try await client.get(.system).value.hostname
            report.authentication = .passed
        } catch {
            report.authentication = .failed(ConnectionProblem(error))
            report.data = .skipped
            return report
        }

        do throws(GlancesError) {
            _ = try await client.get(.cpu)
            _ = try await client.get(.memory)
            report.data = .passed
        } catch {
            report.data = .failed(ConnectionProblem(error))
        }
        return report
    }
}

extension URLSessionConfiguration {
    /// Like `.metriBar`, but fails fast instead of waiting for connectivity,
    /// so the connection test answers within seconds.
    public static var metriBarConnectionTest: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.metriBar
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        return configuration
    }
}
