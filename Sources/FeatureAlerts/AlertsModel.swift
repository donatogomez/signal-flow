import Foundation
import Observation
import DomainKit
import DesignSystemKit

/// State for the Alerts screen: the active and resolved alert lists, a tab + severity filter, and the
/// acknowledge action — all driven by `DomainKit` ports.
///
/// Alerts are **deterministic**: they're raised and cleared by `AlertRule` evaluation in the data
/// layer, never by AI. This model only reads them, joins device/asset context, and acknowledges.
@MainActor
@Observable
public final class AlertsModel {
    public enum Phase: Sendable, Equatable {
        case loading
        case loaded
        case failed(String)
    }

    public private(set) var phase: Phase = .loading
    public private(set) var active: [AlertRow] = []
    public private(set) var history: [AlertRow] = []

    public var tab: AlertTab = .active
    public var severityFilter: AlertSeverityFilter = .all

    private let assets: any AssetRepository
    private let devices: any DeviceRepository
    private let alerts: any AlertRepository
    private let alertHistory: any AlertHistoryProviding
    private let now: @Sendable () -> Date

    public init(
        assets: any AssetRepository,
        devices: any DeviceRepository,
        alerts: any AlertRepository,
        alertHistory: any AlertHistoryProviding,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.assets = assets
        self.devices = devices
        self.alerts = alerts
        self.alertHistory = alertHistory
        self.now = now
    }

    /// The rows the view renders for the current tab + filter. Active and acknowledged are both drawn from
    /// the still-firing `active` set, split by acknowledgement; resolved is the cleared `history`.
    public var visibleAlerts: [AlertRow] {
        let base: [AlertRow]
        switch tab {
        case .active: base = active.filter { !$0.isAcknowledged }
        case .acknowledged: base = active.filter { $0.isAcknowledged }
        case .resolved: base = history
        }
        return base.filter { severityFilter.matches($0.severity) }
    }

    public var unacknowledgedActiveCount: Int { active.lazy.filter { !$0.isAcknowledged }.count }

    /// Loads active alerts (fleet-wide, with device/asset context) and the resolved history.
    public func refresh() async {
        do {
            var context: [DeviceID: AssetContext] = [:]
            var activeRows: [AlertRow] = []

            for asset in try await assets.allAssets() {
                for device in try await devices.devices(inAsset: asset.id) {
                    let ctx = AssetContext(deviceName: device.name, assetName: asset.name, kind: asset.kind)
                    context[device.id] = ctx
                    activeRows += try await alerts.activeAlerts(forDevice: device.id).map { row(from: $0, ctx: ctx) }
                }
            }
            active = activeRows.sorted(by: Self.activeOrdering)

            history = try await alertHistory.alertHistory(limit: 100).map { alert in
                row(from: alert, ctx: context[alert.deviceID] ?? .unknown)
            }.sorted { $0.raisedAt > $1.raisedAt }

            phase = .loaded
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Acknowledges an active alert, then refreshes deterministically so the row updates and the
    /// device's health (which ignores acknowledged alerts) reflects the change immediately.
    public func acknowledge(_ id: AlertID) async {
        try? await alerts.acknowledgeAlert(id, at: now())
        await refresh()
    }

    /// Keeps the lists fresh while visible; cancelled with the view via `.task`.
    public func observe(interval: Duration = .seconds(3)) async {
        while !Task.isCancelled {
            await refresh()
            do { try await Task.sleep(for: interval) } catch { break }
        }
    }

    // MARK: - Helpers

    private struct AssetContext {
        let deviceName: String
        let assetName: String
        let kind: AssetKind
        static let unknown = AssetContext(deviceName: loc("Device"), assetName: "—", kind: .warehouse)
    }

    private func row(from alert: Alert, ctx: AssetContext) -> AlertRow {
        AlertRow(
            id: alert.id, deviceID: alert.deviceID,
            deviceName: ctx.deviceName, assetName: ctx.assetName, assetKind: ctx.kind,
            severity: alert.severity,
            metric: alert.metric, valueText: formattedMeasurement(alert.observedValue),
            message: localizedAlertMessage(metric: alert.metric, value: alert.observedValue),
            raisedAt: alert.raisedAt, acknowledgedAt: alert.acknowledgedAt
        )
    }

    /// Unacknowledged first, then most severe, then most recent — surfaces what needs attention.
    private static func activeOrdering(_ a: AlertRow, _ b: AlertRow) -> Bool {
        if a.isAcknowledged != b.isAcknowledged { return !a.isAcknowledged }
        if a.severity != b.severity { return a.severity > b.severity }
        return a.raisedAt > b.raisedAt
    }
}
