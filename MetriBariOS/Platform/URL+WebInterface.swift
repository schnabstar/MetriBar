import Foundation

extension URL {
    var webURL: URL? {
        guard scheme == "http" || scheme == "https" else { return nil }
        return self
    }
}
