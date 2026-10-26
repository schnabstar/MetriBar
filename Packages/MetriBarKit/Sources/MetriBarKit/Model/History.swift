import Foundation

/// `/api/5/<plugin>/history`: values Glances keeps in memory, by default the
/// last 1200 collection cycles.
///
/// Plugins with a single set of fields (cpu, mem, load) send one list of
/// values per field. Plugins with items (network, fs, containers) send one
/// list per field and item, even when the request names a single item.
public struct History: Decodable, Sendable, Equatable {
    /// Unix timestamps, one per collection cycle.
    public var timestamps: [Double]
    /// Values per field, aligned with `timestamps`. `nil` marks a gap.
    public var series: [String: [Double?]]
    /// Values per field and item key, aligned with `timestamps`.
    public var itemSeries: [String: [String: [Double?]]]

    public init(
        timestamps: [Double], series: [String: [Double?]] = [:], itemSeries: [String: [String: [Double?]]] = [:]
    ) {
        self.timestamps = timestamps
        self.series = series
        self.itemSeries = itemSeries
    }

    private enum CodingKeys: String, CodingKey {
        case timestamps, series
    }

    private enum Values: Decodable {
        case plain([Double?])
        case perItem([String: [Double?]])
        case unknown

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let values = try? container.decode([Double?].self) {
                self = .plain(values)
            } else if let values = try? container.decode([String: [Double?]].self) {
                self = .perItem(values)
            } else {
                self = .unknown
            }
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamps = (try? container.decodeIfPresent([Double].self, forKey: .timestamps)) ?? []
        series = [:]
        itemSeries = [:]
        let raw = (try? container.decodeIfPresent([String: Values].self, forKey: .series)) ?? [:]
        for (field, values) in raw {
            switch values {
            case .plain(let values): series[field] = values
            case .perItem(let values): itemSeries[field] = values
            case .unknown: continue
            }
        }
    }

    public struct Point: Sendable, Equatable {
        public var date: Date
        public var value: Double
    }

    /// Points of one field, or of one field of one item, without gaps.
    /// Values beyond the end of `timestamps` are ignored.
    public func points(_ field: String, item: String? = nil) -> [Point] {
        let values = item.map { itemSeries[field]?[$0] } ?? series[field]
        guard let values else { return [] }
        return zip(timestamps, values).compactMap { timestamp, value in
            value.map { Point(date: Date(timeIntervalSince1970: timestamp), value: $0) }
        }
    }

    /// Item keys that have values for `field`, sorted.
    public func items(for field: String) -> [String] {
        itemSeries[field]?.keys.sorted() ?? []
    }
}
