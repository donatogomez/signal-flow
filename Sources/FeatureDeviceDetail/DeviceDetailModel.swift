import Foundation
import Observation
import DomainKit

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

    private let deviceID: DeviceID
    private let fetchDeviceDetail: FetchDeviceDetailUseCase
    private let fetchHistory: FetchTelemetryHistoryUseCase
    private let eventsRepository: any EventRepository

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
                        valueText: "\(Self.format(reading.value.magnitude)) \(reading.value.unit.symbol)".trimmingCharacters(in: .whitespaces),
                        recordedAt: reading.recordedAt
                    )
                }
            alerts = detail.activeAlerts.map {
                AlertRow(id: $0.id, message: $0.message, severity: $0.severity, raisedAt: $0.raisedAt, isAcknowledged: $0.isAcknowledged)
            }
            events = try await eventsRepository.recentEvents(forDevice: deviceID, limit: 10).map {
                DeviceEventRow(id: $0.id, kind: $0.kind, occurredAt: $0.occurredAt)
            }
            trends = try await loadTrends()
            phase = .loaded
        } catch {
            phase = .failed(String(describing: error))
        }
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
                points: history.map { TrendPoint(id: $0.id, date: $0.recordedAt, value: $0.value.magnitude) }
            ))
        }
        return series
    }

    private static func format(_ value: Double) -> String { String(format: "%.1f", value) }
}
