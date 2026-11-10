import Foundation
import Observation
import DomainKit
import DesignSystemKit

/// The device detail screen's state: current telemetry, trend series for charts, active alerts, and
/// recent events — all derived from `DomainKit` ports for a single device.
@MainActor
@Observable
public final class DeviceDetailModel {
    public enum Phase: Sendable, Equatable {
        case loading
        case loaded
        case failed(String)
    }

    public private(set) var phase: Phase = .loading
    public private(set) var deviceName: String = ""
    public private(set) var status: DeviceStatus = .offline
    public private(set) var connectivity: ConnectivityStatus.State = .offline
    public private(set) var battery: BatteryStatus?
    public private(set) var readings: [ReadingRow] = []
    public private(set) var trends: [TrendSeries] = []
    public private(set) var alerts: [AlertRow] = []
    public private(set) var events: [DeviceEventRow] = []

    /// Metrics charted on the detail screen, in display order.
    private static let chartedMetrics: [MetricKind] = [.temperature, .humidity, .batteryLevel]
    /// Buckets per chart: at most `2 * chartBuckets + 2` points, a few per point of a phone-width chart.
    static let chartBuckets = 120

    private let deviceID: DeviceID
    private let fetchDeviceDetail: FetchDeviceDetailUseCase
    private let fetchHistory: FetchTelemetryHistoryUseCase
    private let eventsRepository: any EventRepository

    // Alerts/events carry simulated-clock timestamps (a first breach can be sim-years old), so "X ago" vs
    // wall time reads "hace 3 años". Age them instead by when they were first seen this session.
    private var alertFirstSeen: [AlertID: Date] = [:]
    private var eventFirstSeen: [EventID: Date] = [:]

    public init(
        deviceID: DeviceID,
        devices: any DeviceRepository,
        telemetry: any TelemetryRepository,
        alerts: any AlertRepository,
        events: any EventRepository
    ) {
        self.deviceID = deviceID
        self.fetchDeviceDetail = FetchDeviceDetailUseCase(devices: devices, telemetry: telemetry, alerts: alerts)
        self.fetchHistory = FetchTelemetryHistoryUseCase(telemetry: telemetry)
        self.eventsRepository = events
    }

    public func refresh() async {
        do {
            let detail = try await fetchDeviceDetail(deviceID: deviceID)
            deviceName = detail.device.name
            status = detail.status
            connectivity = detail.device.connectivity.state
            battery = detail.device.battery
            readings = detail.latestReadings
                .sorted { $0.metric.displayName < $1.metric.displayName }
                .map { reading in
                    ReadingRow(
                        id: reading.metric.displayName,
                        metric: reading.metric,
                        valueText: formattedMeasurement(reading.value),
                        recordedAt: reading.recordedAt
                    )
                }
            alerts = detail.activeAlerts.map {
                AlertRow(id: $0.id, message: localizedAlertMessage(metric: $0.metric, value: $0.observedValue), severity: $0.severity, raisedAt: $0.raisedAt, isAcknowledged: $0.isAcknowledged)
            }
            events = try await eventsRepository.recentEvents(forDevice: deviceID, limit: 10).map {
                DeviceEventRow(id: $0.id, kind: $0.kind, occurredAt: $0.occurredAt)
            }
            trends = try await loadTrends()
            reconcileFirstSeen()
            phase = .loaded
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// When the alert/event first appeared this session — the anchor for its real-time "hace X" age.
    public func firstSeen(alert id: AlertID) -> Date { alertFirstSeen[id] ?? Date() }
    public func firstSeen(event id: EventID) -> Date { eventFirstSeen[id] ?? Date() }

    private func reconcileFirstSeen(now: Date = Date()) {
        let alertIDs = Set(alerts.map(\.id))
        alertFirstSeen = alertFirstSeen.filter { alertIDs.contains($0.key) }
        for id in alertIDs where alertFirstSeen[id] == nil { alertFirstSeen[id] = now }

        let eventIDs = Set(events.map(\.id))
        eventFirstSeen = eventFirstSeen.filter { eventIDs.contains($0.key) }
        for id in eventIDs where eventFirstSeen[id] == nil { eventFirstSeen[id] = now }
    }

    public func observe(interval: Duration = .seconds(3)) async {
        while !Task.isCancelled {
            await refresh()
            do { try await Task.sleep(for: interval) } catch { break }
        }
    }

    private func loadTrends() async throws -> [TrendSeries] {
        let fullRange = try TimeRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 4_000_000_000))
        var series: [TrendSeries] = []
        for metric in Self.chartedMetrics {
            let history = try await fetchHistory(deviceID: deviceID, metric: metric, range: fullRange)
            guard history.count >= 2 else { continue }
            series.append(TrendSeries(
                metric: metric,
                unitSymbol: history.first?.value.unit.symbol ?? metric.canonicalUnit.symbol,
                points: ChartDownsampling.extremes(of: history, buckets: Self.chartBuckets) { $0.value.magnitude }
                    .map { TrendPoint(id: $0.id, date: $0.recordedAt, value: $0.value.magnitude) }
            ))
        }
        return series
    }
}

/// Thins a long series for a chart without hiding what matters on it. The chart is a few hundred points
/// wide, so thousands of samples add rendering work, not detail.
enum ChartDownsampling {
    /// Keeps the first and last samples and, from each of `buckets` equal-count runs in between, its
    /// lowest and highest samples, in their original order. Spikes, the value range and the time span
    /// therefore survive; at most `2 * buckets + 2` samples are returned. A series already that short
    /// is returned unchanged.
    static func extremes<Sample>(of samples: [Sample], buckets: Int, value: (Sample) -> Double) -> [Sample] {
        guard buckets > 0, samples.count > 2 * buckets + 2 else { return samples }
        let interior = 1..<(samples.count - 1)
        var kept = [samples[0]]
        kept.reserveCapacity(2 * buckets + 2)
        for bucket in 0..<buckets {
            let run = (interior.lowerBound + interior.count * bucket / buckets)..<(interior.lowerBound + interior.count * (bucket + 1) / buckets)
            guard let low = run.min(by: { value(samples[$0]) < value(samples[$1]) }),
                  let high = run.max(by: { value(samples[$0]) < value(samples[$1]) }) else { continue }
            if low != high { kept.append(samples[min(low, high)]) }
            kept.append(samples[max(low, high)])
        }
        kept.append(samples[samples.count - 1])
        return kept
    }
}
