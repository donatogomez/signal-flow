import Foundation
import Testing
import DomainKit
import DataKit

/// Retention behaviour of `InMemoryTelemetryStore`'s bounded history, checked against a reference
/// model: each series keeps its newest `historyLimit` readings in arrival order.
@Suite("Telemetry history retention")
struct TelemetryHistoryTests {
    static let limit = 5
    static let metrics: [MetricKind] = [.temperature, .humidity]

    /// Readings go round-robin over two devices × two metrics, one minute apart, so every series
    /// receives `perSeries` readings interleaved with the others. The counts cover an empty history,
    /// a first insertion, below capacity, exactly at capacity, one over (oldest evicted) and far over.
    @Test("Each series keeps its newest readings, oldest first", arguments: [0, 1, 4, 5, 6, 12])
    func matchesReferenceModel(perSeries: Int) async throws {
        let store = InMemoryTelemetryStore(historyLimit: Self.limit)
        let devices = [DeviceID(), DeviceID()]
        await store.register(devices.map { DataKitFixtures.entry(DataKitFixtures.descriptor(id: $0)) })

        var model: [DeviceID: [MetricKind: [TelemetryReading]]] = [:]
        let total = perSeries * devices.count * Self.metrics.count
        for index in 0..<total {
            let reading = try DataKitFixtures.reading(
                deviceID: devices[index % 2], Self.metrics[(index / 2) % 2], Double(index), at: Double(index) * 60
            )
            await store.ingest(.reading(reading))
            model[reading.deviceID, default: [:]][reading.metric, default: []].append(reading)
        }

        let everything = try DataKitFixtures.wideRange()
        // The middle third of the timeline: once readings are evicted it starts before the retained ones.
        let window = try TimeRange(
            start: DataKitFixtures.origin.addingTimeInterval(Double(total / 3) * 60),
            end: DataKitFixtures.origin.addingTimeInterval(Double(2 * total / 3) * 60)
        )
        var retained = 0
        for device in devices {
            for metric in Self.metrics {
                let expected = Array((model[device]?[metric] ?? []).suffix(Self.limit))
                retained += expected.count
                #expect(try await store.readings(forDevice: device, metric: metric, in: everything) == expected)
                #expect(try await store.readings(forDevice: device, metric: metric, in: window)
                        == expected.filter { window.contains($0.recordedAt) })
            }
            let latest = try await store.latestReadings(forDevice: device)
            #expect(Set(latest) == Set(Self.metrics.compactMap { model[device]?[$0]?.last }))
        }
        #expect(await store.ingestedReadingCount() == retained)
    }

    @Test("Device events keep the newest ones when readings are interleaved")
    func eventsStayBounded() async throws {
        let store = InMemoryTelemetryStore(eventLimit: 3)
        let id = DeviceID()
        await store.register([DataKitFixtures.entry(DataKitFixtures.descriptor(id: id))])

        var events: [DeviceEvent] = []
        for index in 0..<5 {
            let event = DataKitFixtures.event(deviceID: id, index.isMultiple(of: 2) ? .doorOpened : .doorClosed, at: Double(index) * 60)
            events.append(event)
            await store.ingest(.event(event))
            await store.ingest(.reading(try DataKitFixtures.reading(deviceID: id, .temperature, 4, at: Double(index) * 60 + 30)))
        }

        #expect(try await store.recentEvents(forDevice: id, limit: 10) == events.suffix(3).reversed())
        #expect(try await store.readings(forDevice: id, metric: .temperature, in: DataKitFixtures.wideRange()).count == 5)
    }

    @Test("Concurrent ingestion keeps every series bounded and intact")
    func concurrentIngestion() async throws {
        let limit = 50
        let store = InMemoryTelemetryStore(historyLimit: limit)
        let id = DeviceID()
        await store.register([DataKitFixtures.entry(DataKitFixtures.descriptor(id: id))])

        let readings = try (0..<400).map { index in
            try DataKitFixtures.reading(deviceID: id, Self.metrics[index % 2], Double(index), at: Double(index) * 60)
        }
        await withTaskGroup(of: Void.self) { group in
            for reading in readings { group.addTask { await store.ingest(.reading(reading)) } }
        }

        // Arrival order is up to the scheduler, so which readings survive isn't fixed — but each
        // series must hold exactly `limit` distinct readings, all of them ones that were ingested.
        for metric in Self.metrics {
            let history = try await store.readings(forDevice: id, metric: metric, in: DataKitFixtures.wideRange())
            #expect(history.count == limit)
            #expect(Set(history.map(\.id)).count == limit)
            #expect(Set(history).isSubset(of: readings.filter { $0.metric == metric }))
        }
        #expect(await store.ingestedReadingCount() == 2 * limit)
    }
}
