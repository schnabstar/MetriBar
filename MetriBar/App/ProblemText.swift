import Foundation
import MetriBarKit

/// User-facing explanation of a connection problem.
extension ConnectionProblem {
    var title: String {
        switch self {
        case .hostNotFound: String(localized: "Server not found")
        case .connectionRefused: String(localized: "Connection refused")
        case .timedOut: String(localized: "No response")
        case .localNetworkDenied: String(localized: "Local network access not allowed")
        case .offline: String(localized: "No network connection")
        case .tlsHandshakeFailed: String(localized: "Secure connection failed")
        case .untrustedCertificate: String(localized: "Certificate not trusted")
        case .certificateMismatch: String(localized: "Certificate changed")
        case .insecureConnectionBlocked: String(localized: "Unencrypted connection blocked")
        case .hostRejected: String(localized: "Host name rejected")
        case .unauthorized: String(localized: "Login failed")
        case .rateLimited: String(localized: "Too many attempts")
        case .notGlances: String(localized: "Not a Glances server")
        case .glances4: String(localized: "Glances 4 detected")
        case .unsupportedVersion: String(localized: "Unsupported Glances version")
        case .serverError: String(localized: "Server error")
        case .invalidResponse: String(localized: "Unexpected response")
        case .other: String(localized: "Connection problem")
        }
    }

    func advice(hasCredentials: Bool) -> String {
        switch self {
        case .hostNotFound:
            String(
                localized: "The host name could not be resolved. Check the URL and, if you use one, the VPN connection."
            )
        case .connectionRefused:
            String(
                localized:
                    "Nothing answers on this port. Is Glances running as a web server (glances -s)? Glances 5 only listens on 127.0.0.1 by default: start it with -B 0.0.0.0 or set bind_address."
            )
        case .timedOut:
            String(
                localized: "The server did not answer in time. Check that it is running and reachable from this Mac.")
        case .localNetworkDenied:
            String(
                localized:
                    "macOS does not allow MetriBar to connect to devices on your local network. Turn on MetriBar in System Settings › Privacy & Security › Local Network."
            )
        case .offline:
            String(localized: "This Mac is not connected to a network.")
        case .tlsHandshakeFailed:
            String(
                localized:
                    "The encrypted connection could not be established. Does the server use HTTPS on this port? For plain HTTP, start the URL with http://."
            )
        case .untrustedCertificate:
            String(
                localized:
                    "The certificate is self-signed, expired or issued for another name. You can check it and trust it in the server settings."
            )
        case .certificateMismatch:
            String(
                localized:
                    "The server presented a different certificate than the one you trusted. If you renewed it, trust the new certificate in the server settings. Otherwise someone may be intercepting the connection."
            )
        case .insecureConnectionBlocked:
            String(localized: "macOS blocked the unencrypted connection. Use HTTPS if the server supports it.")
        case .hostRejected:
            String(
                localized:
                    "Glances only accepts the host names listed in webui_allowed_hosts. Add the name or address you use in MetriBar to that setting."
            )
        case .unauthorized:
            hasCredentials
                ? String(
                    localized:
                        "The server rejected the user name or password. MetriBar stops trying until you change them, so you are not locked out."
                )
                : String(
                    localized: "This server requires a password. Add the user name and password in the server settings."
                )
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter?.components.seconds {
                String(localized: "Glances blocks further logins for now. MetriBar tries again in \(seconds) seconds.")
            } else {
                String(localized: "Glances blocks further logins for now. MetriBar tries again later.")
            }
        case .notGlances:
            String(
                localized:
                    "Something answers at this URL, but it is not Glances 5. Check the address and port; Glances uses port 61208 by default."
            )
        case .glances4:
            String(localized: "MetriBar requires Glances 5. Update Glances on the server.")
        case .unsupportedVersion(let version):
            String(localized: "The server runs Glances \(version). This version of MetriBar supports Glances 5.")
        case .serverError(let status):
            String(localized: "The server answered with HTTP status \(status).")
        case .invalidResponse:
            String(
                localized:
                    "The answer could not be read. Glances 5 is still in beta; please report this together with the diagnostic details."
            )
        case .other(let description):
            description
        }
    }

    /// Whether changing the server settings can fix the problem.
    var isFixedInSettings: Bool {
        switch self {
        case .unauthorized, .untrustedCertificate, .certificateMismatch, .hostRejected, .notGlances, .hostNotFound:
            true
        default:
            false
        }
    }
}
