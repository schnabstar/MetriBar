import Foundation

/// One item of `/api/5/alert`: a level transition of one field.
///
/// The structure comes from `glances/alerts.py` on the Glances `develop`
/// branch; no real event was available when this was written.
public struct AlertEvent: Decodable, Sendable, Equatable {
    /// ISO 8601 timestamp in UTC.
    @Lenient public var ts: String?
    @Lenient public var plugin: String?
    /// Item key for collection plugins, for example a mount point.
    @Lenient public var key: String?
    @Lenient public var field: String?
    @Lenient public var level: Level?
    @Lenient public var previousLevel: Level?
    @Lenient public var value: Double?
    @Lenient public var prominent: Bool?
    @Lenient public var isInitial: Bool?

    enum CodingKeys: String, CodingKey {
        case ts, plugin, key, field, level
        case previousLevel = "previous_level"
        case value, prominent
        case isInitial = "is_initial"
    }

    public var date: Date? {
        ts.flatMap(GlancesDate.parse)
    }
}

/// `/api/5/alert/incidents`: the alert history collapsed into incidents.
public struct AlertIncidents: Decodable, Sendable, Equatable {
    @Lenient public var incidents: [AlertIncident]?
    @Lenient public var isInitializing: Bool?

    enum CodingKeys: String, CodingKey {
        case incidents
        case isInitializing = "is_initializing"
    }
}

/// An incident opens when a field leaves `ok` and closes when it returns.
public struct AlertIncident: Decodable, Sendable, Equatable {
    @Lenient public var plugin: String?
    @Lenient public var key: String?
    @Lenient public var field: String?
    /// Highest level reached during the incident.
    @Lenient public var level: Level?
    @Lenient public var begin: String?
    @Lenient public var end: String?
    @Lenient public var ongoing: Bool?
    /// `true` when the start of the incident is no longer in the history.
    @Lenient public var partial: Bool?
    @Lenient public var prominent: Bool?
    /// Names of the top processes at the time of the alert.
    @Lenient public var top: [String]?

    public var beginDate: Date? {
        begin.flatMap(GlancesDate.parse)
    }

    public var endDate: Date? {
        end.flatMap(GlancesDate.parse)
    }
}

enum GlancesDate {
    /// Parses Python `datetime.isoformat()` output, with or without
    /// fractional seconds.
    static func parse(_ string: String) -> Date? {
        let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return (try? withFraction.parse(string)) ?? (try? Date.ISO8601FormatStyle().parse(string))
    }
}
