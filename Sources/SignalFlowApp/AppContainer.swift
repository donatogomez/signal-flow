import Foundation
import Observation
import DomainKit
import DataKit
import IntelligenceKit
import PersistenceKit
import LiveActivityKit
import WatchConnectivityKit

/// The dependency composition root.
///
/// This is the one and only place that assembles concrete implementations: it owns the `DataKit`
/// `SimulatedDataSource` and exposes it solely as `DomainKit` ports. Features receive those ports and
/// never learn what's behind them — swapping the simulated source for a persisted/live one later is a
/// change *here*, nowhere else.
///
/// `@MainActor` because it drives app lifecycle from the UI; `@Observable` so the app/root view can
/// hold it as `@State`.
@MainActor
@Observable
public final class AppContainer {
    private let source: SimulatedDataSource
    private var didBootstrap = false

    /// Drives the critical-alert Live Activity. ActivityKit work happens inside the service (guarded for
    /// iOS); on other platforms it's a no-op, so the composition root calls it unconditionally.
    private let liveActivities = CriticalAlertActivityService()

    /// Sends compact fleet snapshots to the paired Apple Watch over WatchConnectivity (iOS-only inside the
    /// service; a no-op stub elsewhere). Composition root is the only place that knows about it.
    private let watchSync = PhoneSnapshotSync()

    // Domain ports — the entire surface features depend on.
    public var assets: any AssetRepository { source.assets }
    public var devices: any DeviceRepository { source.devices }
    public var telemetry: any TelemetryRepository { source.telemetry }
    public var alerts: any AlertRepository { source.alerts }
    public var alertHistory: any AlertHistoryProviding { source.alertHistory }
    public var events: any EventRepository { source.events }
    public var insights: any InsightsProviding { source.insights }

    public init(source: SimulatedDataSource) {
        self.source = source
    }

    /// The real app configuration: a real-time simulated source playing telemetry at 600× wall speed.
    ///
    /// The composition root decides the insight provider here: if Apple's on-device model is
    /// available, use the Foundation Models provider (with the deterministic one as its runtime
    /// fallback); otherwise use the deterministic provider directly. Either way features see only the
    /// `InsightsProviding` port.
    public static func live() -> AppContainer {
        let deterministic = DeterministicInsightsProvider()
        let insights: any InsightsProviding = FoundationModelsInsightProvider.systemModelAvailable
            ? FoundationModelsInsightProvider(fallback: deterministic)
            : deterministic
        // On-disk SwiftData persistence in the shared App Group container, so the SignalFlowWidgets
        // extension reads the exact same store. If the container can't be created, the app degrades to
        // in-memory only rather than failing to launch.
        let persistence = (try? PersistenceController.makeSharedContainer()).map(PersistenceStore.init(modelContainer:))
        return AppContainer(source: .live(seed: 42, timeScale: 600, insights: insights, persistence: persistence))
    }

    /// A deterministic configuration for previews and tests.
    public static func preview() -> AppContainer {
        AppContainer(source: .deterministic(seed: 42, maxTicks: 80))
    }

    /// Boots the data layer (once) and starts ingestion. Idempotent and safe to call again after
    /// `stop()`.
    public func start() async {
        if !didBootstrap {
            try? await source.bootstrap()
            didBootstrap = true
        }
        await source.start()
    }

    /// Halts ingestion. `stop()` awaits the ingestion loop to completion, so teardown is clean and
    /// cancellation-safe (see DataKit §16.5).
    public func stop() async {
        await source.stop()
    }

    // MARK: - Live Activities

    /// Reconciles the critical-alert Live Activity on a steady cadence while on screen.
    ///
    /// Critical-alert detection is **deterministic and data-driven**: it reads alerts/devices/assets
    /// straight from the `DomainKit` ports — the same state the app and widgets show — and never
    /// consults Foundation Models. Cancellation-safe; tied to a view's `.task`.
    public func observeCriticalAlertActivity(pollInterval: Duration = .seconds(4)) async {
        while !Task.isCancelled {
            await liveActivities.reconcile(currentAlertContexts())
            do { try await Task.sleep(for: pollInterval) } catch { break }
        }
    }

    /// Builds the alert contexts (alert + device/asset names) from the domain ports.
    private func currentAlertContexts() async -> [AlertContext] {
        var contexts: [AlertContext] = []
        guard let allAssets = try? await assets.allAssets() else { return [] }
        for asset in allAssets {
            guard let assetDevices = try? await devices.devices(inAsset: asset.id) else { continue }
            for device in assetDevices {
                guard let active = try? await alerts.activeAlerts(forDevice: device.id) else { continue }
                for alert in active {
                    contexts.append(AlertContext(alert: alert, deviceName: device.name, assetName: asset.name))
                }
            }
        }
        return contexts
    }

    // MARK: - Watch sync

    /// Sends a compact fleet snapshot to the paired Watch on app start and whenever fleet/alert state
    /// changes, on a steady cadence. WatchConnectivity coalesces to the latest application context, so a
    /// simple periodic push is the most reliable strategy. Cancellation-safe; tied to a view's `.task`.
    public func observeWatchSync(pollInterval: Duration = .seconds(5)) async {
        watchSync.start()
        while !Task.isCancelled {
            if let snapshot = await currentWatchSnapshot() {
                watchSync.send(snapshot)
            }
            do { try await Task.sleep(for: pollInterval) } catch { break }
        }
    }

    /// Assembles the watch snapshot from the same domain ports the app renders — never the data engine
    /// internals. Returns `nil` until the catalog is available.
    private func currentWatchSnapshot() async -> WatchSyncSnapshot? {
        guard let allAssets = try? await assets.allAssets() else { return nil }
        var deviceList: [Device] = []
        var alertList: [Alert] = []
        for asset in allAssets {
            guard let assetDevices = try? await devices.devices(inAsset: asset.id) else { continue }
            deviceList += assetDevices
            for device in assetDevices {
                alertList += (try? await alerts.activeAlerts(forDevice: device.id)) ?? []
            }
        }
        let persisted = PersistedSnapshot(
            assets: allAssets, devices: deviceList, latestReadings: [],
            events: [], alerts: alertList, insights: []
        )
        return WatchSnapshotBuilder.build(from: persisted, now: Date())
    }
}
