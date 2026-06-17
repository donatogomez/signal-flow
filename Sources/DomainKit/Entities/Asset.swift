/// A monitored physical asset (a greenhouse, refrigerated truck, warehouse, …) that owns one or more
/// ``Device``s.
public struct Asset: Identifiable, Hashable, Sendable, Codable {
    public let id: AssetID
    public let name: String
    public let kind: AssetKind
    public let deviceIDs: [DeviceID]
    public let location: Location?

    public init(
        id: AssetID = AssetID(),
        name: String,
        kind: AssetKind,
        deviceIDs: [DeviceID] = [],
        location: Location? = nil
    ) throws {
        self.id = id
        self.name = try DomainText.validatedName(name, context: "Asset")
        self.kind = kind
        self.deviceIDs = deviceIDs
        self.location = location
    }
}
