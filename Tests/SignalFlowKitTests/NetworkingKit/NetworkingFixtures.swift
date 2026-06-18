import Foundation

/// Canned JSON payloads + ids for NetworkingKit tests — deterministic, no backend.
enum NetFixtures {
    static let assetID = "11111111-1111-1111-1111-111111111111"
    static let deviceID = "22222222-2222-2222-2222-222222222222"
    static let readingID = "33333333-3333-3333-3333-333333333333"
    static let eventID = "44444444-4444-4444-4444-444444444444"
    static let alertID = "55555555-5555-5555-5555-555555555555"
    static let ruleID = "66666666-6666-6666-6666-666666666666"
    static let timestamp = "2023-11-14T22:13:20Z"

    static func data(_ string: String) -> Data { Data(string.utf8) }
    static let baseURL = URL(string: "https://api.signalflow.test/v1")!

    static let assetsJSON = data("""
    [{"id":"\(assetID)","name":"Greenhouse A","kind":"greenhouse","deviceIds":["\(deviceID)"],"location":{"latitude":41.4,"longitude":2.1,"altitude":12}}]
    """)

    static let deviceJSON = data("""
    {"id":"\(deviceID)","assetId":"\(assetID)","name":"Reefer 12","connectivity":"online","signal":{"magnitude":-72,"unit":"decibelMilliwatts"},"lastSeenAt":"\(timestamp)","location":null}
    """)

    static let devicesJSON = data("""
    [{"id":"\(deviceID)","assetId":"\(assetID)","name":"Reefer 12","connectivity":"online","signal":{"magnitude":-72,"unit":"decibelMilliwatts"},"lastSeenAt":"\(timestamp)","location":null}]
    """)

    static let telemetryJSON = data("""
    [{"id":"\(readingID)","deviceId":"\(deviceID)","metric":"temperature","value":{"magnitude":3.5,"unit":"celsius"},"recordedAt":"\(timestamp)"}]
    """)

    static let eventsJSON = data("""
    [{"id":"\(eventID)","deviceId":"\(deviceID)","kind":"doorOpened","detail":"left open","occurredAt":"\(timestamp)"}]
    """)

    static let alertsJSON = data("""
    [{"id":"\(alertID)","deviceId":"\(deviceID)","ruleId":"\(ruleID)","metric":"temperature","severity":"critical","message":"Too hot","observedValue":{"magnitude":12,"unit":"celsius"},"raisedAt":"\(timestamp)","acknowledgedAt":null}]
    """)
}
