import Foundation
import Testing

@testable import MetriBarKit

struct CredentialStoreTests {
    @Test func inMemoryStoreRoundTrip() throws {
        let store = InMemoryCredentialStore()
        let id = UUID()
        #expect(try store.password(for: id) == nil)
        try store.setPassword("first", for: id)
        try store.setPassword("second", for: id)
        #expect(try store.password(for: id) == "second")
        try store.removePassword(for: id)
        #expect(try store.password(for: id) == nil)
        try store.removePassword(for: id)  // removing twice is fine
    }

    /// Writes to the login keychain, so it only runs on request:
    /// `METRIBAR_KEYCHAIN_TESTS=1 swift test`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["METRIBAR_KEYCHAIN_TESTS"] == "1"))
    func keychainStoreRoundTrip() throws {
        let store = KeychainCredentialStore(service: "it.schnabel.MetriBar.tests")
        let id = UUID()
        defer { try? store.removePassword(for: id) }

        #expect(try store.password(for: id) == nil)
        try store.setPassword("pässwört 🔑", for: id)
        #expect(try store.password(for: id) == "pässwört 🔑")
        try store.setPassword("changed", for: id)
        #expect(try store.password(for: id) == "changed")
        try store.removePassword(for: id)
        #expect(try store.password(for: id) == nil)
    }
}

struct CertificateFingerprintTests {
    private let hex = String(repeating: "ab", count: 32)

    @Test func parsesCommonNotations() throws {
        let plain = try #require(CertificateFingerprint(hex))
        let colons = try #require(CertificateFingerprint(plain.description))
        let lowercaseColons = try #require(CertificateFingerprint(plain.description.lowercased()))
        let spaces = try #require(CertificateFingerprint(plain.description.replacingOccurrences(of: ":", with: " ")))
        #expect(plain == colons)
        #expect(plain == lowercaseColons)
        #expect(plain == spaces)
        #expect(plain.description.hasPrefix("AB:AB:"))
        #expect(plain.description.count == 32 * 3 - 1)
    }

    @Test(arguments: [
        "", "abcd", String(repeating: "zz", count: 32), String(repeating: "ab", count: 33),
        "+1" + String(repeating: "ab", count: 31),
    ])
    func rejectsInvalidInput(_ input: String) {
        #expect(CertificateFingerprint(input) == nil)
    }

    @Test func serverConfigCodableRoundTrip() throws {
        let config = ServerConfig(
            name: "NAS", url: URL(string: "https://nas.local")!, username: "glances",
            pinnedCertificate: CertificateFingerprint(hex))
        let data = try JSONEncoder().encode(config)
        #expect(!String(decoding: data, as: UTF8.self).contains("password"))
        #expect(try JSONDecoder().decode(ServerConfig.self, from: data) == config)
    }

    @Test func decodesConfigsWithoutPin() throws {
        let json =
            #"{"id": "6F1C3A3E-4E3B-4C55-9C8A-1D2E3F4A5B6C", "name": "", "url": "http://pi.local:61208", "isEnabled": true}"#
        let config = try JSONDecoder().decode(ServerConfig.self, from: Data(json.utf8))
        #expect(config.pinnedCertificate == nil)
        #expect(config.username == nil)
    }

    @Test func clientReportsPinMismatch() async throws {
        let presented = try #require(CertificateFingerprint(hex))
        let transport = StubTransport { _ in throw CertificatePinningError.mismatch(presented: presented) }
        let client = GlancesClient(baseURL: URL(string: "https://nas.local")!, transport: transport)
        do {
            _ = try await client.get(.cpu)
            Issue.record("Expected a pin mismatch")
        } catch {
            #expect(error == .certificateMismatch(presented: presented))
        }
    }
}

struct TransportSecurityTests {
    @Test(arguments: [
        ("https://glances.example.com", TransportSecurity.encrypted),
        ("HTTPS://192.168.1.10", .encrypted),
        ("http://192.168.1.20:61208", .unencrypted(localNetwork: true)),
        ("http://10.0.0.5", .unencrypted(localNetwork: true)),
        ("http://172.20.1.1", .unencrypted(localNetwork: true)),
        ("http://172.32.1.1", .unencrypted(localNetwork: false)),
        ("http://100.101.102.103", .unencrypted(localNetwork: true)),
        ("http://127.0.0.1:61208", .unencrypted(localNetwork: true)),
        ("http://[::1]:61208", .unencrypted(localNetwork: true)),
        ("http://[fd12:3456::1]", .unencrypted(localNetwork: true)),
        ("http://[2001:db8::1]", .unencrypted(localNetwork: false)),
        ("http://raspberrypi.local:61208", .unencrypted(localNetwork: true)),
        ("http://nas", .unencrypted(localNetwork: true)),
        ("http://nas.fritz.box", .unencrypted(localNetwork: true)),
        ("http://server.home.arpa", .unencrypted(localNetwork: true)),
        ("http://203.0.113.7", .unencrypted(localNetwork: false)),
        ("http://glances.example.com", .unencrypted(localNetwork: false)),
    ])
    func classifiesURLs(url: String, expected: TransportSecurity) throws {
        #expect(TransportSecurity(url: try #require(URL(string: url))) == expected)
    }

    @Test func warnsOnlyWhenAPasswordWouldTravelUnencrypted() {
        let http = URL(string: "http://pi.local:61208")!
        let https = URL(string: "https://pi.local")!
        #expect(ServerConfig(url: http, username: "glances").sendsPasswordUnencrypted)
        #expect(!ServerConfig(url: http).sendsPasswordUnencrypted)
        #expect(!ServerConfig(url: https, username: "glances").sendsPasswordUnencrypted)
    }
}

struct ServerURLTests {
    @Test(arguments: [
        ("raspberrypi.local:61208", "http://raspberrypi.local:61208"),
        ("  https://Glances.Example.com/  ", "https://glances.example.com"),
        ("http://192.168.1.10:61208/api/5", "http://192.168.1.10:61208"),
        ("http://192.168.1.10:61208/api/5/", "http://192.168.1.10:61208"),
        ("https://proxy.example.com/glances/", "https://proxy.example.com/glances"),
        ("https://proxy.example.com/glances/status", "https://proxy.example.com/glances"),
        ("https://glances.example.com/?refresh=5#cpu", "https://glances.example.com"),
        ("http://[::1]:61208", "http://[::1]:61208"),
    ])
    func normalizesInput(input: String, expected: String) throws {
        #expect(try ServerURL.parse(input).absoluteString == expected)
    }

    @Test(arguments: [
        ("", ServerURLError.empty),
        ("   ", .empty),
        ("ftp://nas.local", .unsupportedScheme("ftp")),
        ("https://glances:secret@nas.local", .containsCredentials),
        ("https://user@nas.local", .containsCredentials),
        ("https://", .missingHost),
    ])
    func rejectsInvalidInput(input: String, expected: ServerURLError) {
        #expect(throws: expected) { try ServerURL.parse(input) }
    }
}

@MainActor
struct DiagnosticReportTests {
    @Test func containsNoSecretsAndHidesTheHost() async {
        let server = FixtureServer(pathPrefix: "/glances")
        server.override("/api/5/cpu", with: .json(#"{"detail": "Invalid host header nas.example.com"}"#, status: 400))
        let config = ServerConfig(url: URL(string: "https://nas.example.com/glances")!, username: "admin-thomas")
        let monitor = ServerMonitor(
            config: config,
            client: GlancesClient(
                baseURL: config.url, credentials: Credentials(username: "admin-thomas", password: "s3cret"),
                transport: server.transport),
            clock: ManualClock())
        monitor.start()
        defer { monitor.stop() }
        await waitUntil { monitor.consecutiveFailures == 1 }

        let hidden = DiagnosticReport.make(for: monitor, includeHost: false, appVersion: "0.1.0 (1)")
        #expect(!hidden.contains("s3cret"))
        #expect(!hidden.contains("admin-thomas"))
        #expect(!hidden.contains("nas.example.com"))
        #expect(hidden.contains("https://<host>/glances"))
        #expect(hidden.contains("Authentication: yes"))
        #expect(hidden.contains("Glances: 5.0.0b1"))
        #expect(hidden.contains("badRequest"))

        let shown = DiagnosticReport.make(for: monitor, includeHost: true, appVersion: "0.1.0 (1)")
        #expect(shown.contains("https://nas.example.com/glances"))
        #expect(!shown.contains("s3cret"))
        #expect(!shown.contains("admin-thomas"))
    }

    @Test func redactsCredentialsQueryAndFragment() {
        let url = URL(string: "https://user:pass@nas.local:8443/glances?token=abc#x")!
        #expect(DiagnosticReport.redacted(url, includeHost: true) == "https://nas.local:8443/glances")
        #expect(DiagnosticReport.redacted(url, includeHost: false) == "https://<host>:8443/glances")
    }
}

/// Runs against an HTTPS server with a self-signed certificate:
/// `METRIBAR_TLS_URL=https://127.0.0.1:8443 METRIBAR_TLS_SHA256=AB:CD:… swift test`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["METRIBAR_TLS_URL"] != nil, "Set METRIBAR_TLS_URL to run"))
struct SelfSignedCertificateTests {
    private let url = URL(string: ProcessInfo.processInfo.environment["METRIBAR_TLS_URL"] ?? "https://127.0.0.1")!
    private let fingerprint = CertificateFingerprint(ProcessInfo.processInfo.environment["METRIBAR_TLS_SHA256"] ?? "")

    @Test func inspectorReadsTheCertificateWithoutTrustingIt() async throws {
        let info = try await CertificateInspector.inspect(url)
        #expect(info.fingerprint == fingerprint)
        #expect(!info.isTrustedBySystem)
        #expect(info.subject != nil)
    }

    @Test func untrustedCertificateFailsWithoutPin() async {
        let client = GlancesClient(baseURL: url, transport: URLSessionTransport())
        do {
            _ = try await client.get(.status)
            Issue.record("Expected a TLS error")
        } catch {
            guard case .transport(let code) = error else {
                Issue.record("Unexpected error \(error)")
                return
            }
            #expect(code.rawValue <= URLError.Code.secureConnectionFailed.rawValue)
        }
    }

    @Test func pinnedCertificateIsAccepted() async throws {
        let pin = try #require(fingerprint)
        let client = GlancesClient(baseURL: url, transport: URLSessionTransport(pinnedCertificate: pin))
        let status = try await client.get(.status)
        #expect(status.version == "5")
    }

    @Test func otherPinIsRejected() async throws {
        let wrong = try #require(CertificateFingerprint(String(repeating: "00", count: 32)))
        let client = GlancesClient(baseURL: url, transport: URLSessionTransport(pinnedCertificate: wrong))
        do {
            _ = try await client.get(.status)
            Issue.record("Expected a pin mismatch")
        } catch {
            #expect(error == .certificateMismatch(presented: try #require(fingerprint)))
        }
    }
}
