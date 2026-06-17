/// A geographic position, validated to lie on the surface of the Earth.
public struct Location: Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double?

    public init(latitude: Double, longitude: Double, altitude: Double? = nil) throws {
        guard (-90.0...90.0).contains(latitude), (-180.0...180.0).contains(longitude) else {
            throw ValidationError.invalidCoordinate(latitude: latitude, longitude: longitude)
        }
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }
}

extension Location: Codable {
    private enum CodingKeys: String, CodingKey { case latitude, longitude, altitude }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            latitude: container.decode(Double.self, forKey: .latitude),
            longitude: container.decode(Double.self, forKey: .longitude),
            altitude: container.decodeIfPresent(Double.self, forKey: .altitude)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encodeIfPresent(altitude, forKey: .altitude)
    }
}
