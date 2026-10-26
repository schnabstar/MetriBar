/// One item of `/api/5/network`.
public struct NetworkInterface: Decodable, Sendable, Equatable {
    @Lenient public var interfaceName: String?
    /// Bytes per second.
    @Lenient public var bytesRecv: Double?
    @Lenient public var bytesSent: Double?
    /// Bytes since the interface came up.
    @Lenient public var bytesRecvCumul: Double?
    @Lenient public var bytesSentCumul: Double?
    /// Link capacity per direction in bytes per second, 0 when unknown.
    @Lenient public var linkSpeed: Double?
    @Lenient public var isUp: Bool?
    @Lenient public var hidden: Bool?
    @Lenient public var errorsIn: Double?
    @Lenient public var errorsOut: Double?
    @Lenient public var droppedIn: Double?
    @Lenient public var droppedOut: Double?

    enum CodingKeys: String, CodingKey {
        case interfaceName = "interface_name"
        case bytesRecv = "bytes_recv"
        case bytesSent = "bytes_sent"
        case bytesRecvCumul = "bytes_recv_cumul"
        case bytesSentCumul = "bytes_sent_cumul"
        case linkSpeed = "bytes_speed_rate_per_sec"
        case isUp = "is_up"
        case hidden
        case errorsIn = "errors_in"
        case errorsOut = "errors_out"
        case droppedIn = "dropped_in"
        case droppedOut = "dropped_out"
    }
}
