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
    let source: SimulatedDataSource // internal only so lifecycle tests can observe ingestion
    private var didBootstrap = false

    /// The outcome of the data layer's startup, for the root view (see ``StartupState``).
    public private(set) var startupState: StartupState = .notStarted

    /// Whether the composition root had to run without the on-disk store.
    private let persistenceUnavailable: Bool

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

    public convenience init(source: SimulatedDataSource) {
        self.init(source: source, persistenceUnavailable: false)
    }

    init(source: SimulatedDataSource, persistenceUnavailable: Bool) {
        self.source = source
        self.persistenceUnavailable = persistenceUnavailable
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
        // extension reads the exact same store. If the container can't be created, the app runs in
        // memory only rather than failing to launch, and reports that as a degraded startup.
        let persistence: PersistenceStore?
        do {
            persistence = PersistenceStore(modelContainer: try PersistenceController.makeSharedContainer())
        } catch {
            Log.persistence.error("Persistent store unavailable; running in memory only: \(String(describing: error), privacy: .private)")
            persistence = nil
        }
        return AppContainer(
            source: .live(seed: 42, timeScale: 600, insights: insights, persistence: persistence),
            persistenceUnavailable: persistence == nil
        )
    }

    /// A deterministic configuration for previews and tests.
    public static func preview() -> AppContainer {
        AppContainer(source: .deterministic(seed: 42, maxTicks: 80))
    }

    /// Boots the data layer (once) and starts ingestion. Idempotent and safe to call again after
    /// `stop()`. Ordered with every other lifecycle request; see ``requestStart()``.
    public func start() async {
        await requestStart().value
    }

    /// Halts ingestion. `stop()` awaits the ingestion loop to completion, so teardown is clean and
    /// cancellation-safe (see DataKit §16.5). Ordered with every other lifecycle request.
    public func stop() async {
        await requestStop().value
    }

    /// Records a start request **synchronously** and returns the operation that applies it.
    ///
    /// Lifecycle requests arrive from several places (the scene-phase handler, `RootView`). The order
    /// that matters is the order they were *made*, so a request takes its place in the chain at this
    /// call, before any suspension. Each operation waits for the previous one to finish, so operations
    /// apply strictly in request order, whenever their tasks happen to be scheduled. Callers must call
    /// this directly on the main actor rather than from a `Task {}` they create: a task's body can run
    /// later than a request made after it, and Swift doesn't promise otherwise.
    ///
    /// Awaiting the returned task waits for the transition. Cancelling it doesn't withdraw the request:
    /// nothing in the transition checks for cancellation, so it still applies in order. (If the
    /// bootstrap itself reports cancellation, the start is abandoned without being recorded as done or
    /// failed, and the next start bootstraps again.)
    ///
    /// If the bootstrap fails, the start doesn't begin ingestion and ``startupState`` becomes
    /// ``StartupState/failed``. A start request made *after* that tries again, in its place in the
    /// chain; requests that were already queued when it failed don't, so a failure never turns into
    /// back-to-back automatic attempts.
    @discardableResult
    public func requestStart() -> Task<Void, Never> {
        enqueue(.start)
    }

    /// Records a stop request synchronously; see ``requestStart()``.
    @discardableResult
    public func requestStop() -> Task<Void, Never> {
        enqueue(.stop)
    }

    private enum LifecycleRequest { case start, stop }

    /// The most recently requested lifecycle operation; the next one runs after it.
    private var lifecycle: Task<Void, Never>?

    /// Lifecycle requests made so far. Each operation knows its position, i.e. which requests came
    /// before it.
    private var requestCount = 0

    /// `requestCount` when the last bootstrap failure was recorded. Start requests up to that position
    /// were made before the failure was known, so they don't repeat the attempt.
    private var failureRecordedAt: Int?

    /// Appends an operation to the chain. Runs synchronously on the main actor, so the chain order is
    /// the order of the calls. Because overlapping operations can't exist, `didBootstrap` is never read
    /// by two starts at once and a successful bootstrap runs exactly once.
    private func enqueue(_ request: LifecycleRequest) -> Task<Void, Never> {
        requestCount += 1
        let position = requestCount
        let previous = lifecycle
        let next = Task {
            await previous?.value
            await perform(request, position: position)
        }
        lifecycle = next
        return next
    }

    private func perform(_ request: LifecycleRequest, position: Int) async {
        switch request {
        case .start:
            if !didBootstrap {
                if let failureRecordedAt, position <= failureRecordedAt { return }
                guard await bootstrap() else { return }
            }
            await source.start()
        case .stop:
            await source.stop()
        }
    }

    /// Bootstraps the data layer and records the outcome. Returns whether ingestion may start.
    private func bootstrap() async -> Bool {
        let previous = startupState
        startupState = .starting
        do {
            let restore = try await source.bootstrap()
            didBootstrap = true
            let degradation: StartupState.Degradation? = persistenceUnavailable ? .persistenceUnavailable
                : restore == .failed ? .restoreFailed : nil
            if let degradation {
                startupState = .degraded(degradation)
                Log.lifecycle.notice("Startup finished degraded: \(String(describing: degradation), privacy: .public)")
            } else {
                startupState = .ready
                Log.lifecycle.info("Startup finished")
            }
            return true
        } catch is CancellationError {
            startupState = previous
            Log.lifecycle.debug("Bootstrap cancelled; not recorded as done or failed")
            return false
        } catch {
            failureRecordedAt = requestCount
            startupState = .failed
            Log.lifecycle.fault("Bootstrap failed; ingestion not started: \(String(describing: error), privacy: .private)")
            return false
        }
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
    ///
    /// As well as the fleet/alert rollup, it sends each device's **latest primary-metric reading** plus a
    /// short **recent history** of that metric, so the watch's Device Detail can show a live value and a
    /// mini-trend sparkline. Telemetry is read through the `TelemetryRepository` port like every other
    /// surface — no data-engine internals.
    private func currentWatchSnapshot() async -> WatchSyncSnapshot? {
        guard let allAssets = try? await assets.allAssets() else { return nil }
        var deviceList: [Device] = []
        var alertList: [Alert] = []
        var latestReadings: [TelemetryReading] = []
        var historyByDevice: [DeviceID: [TelemetryReading]] = [:]

        for asset in allAssets {
            guard let assetDevices = try? await devices.devices(inAsset: asset.id) else { continue }
            deviceList += assetDevices
            for device in assetDevices {
                alertList += (try? await alerts.activeAlerts(forDevice: device.id)) ?? []

                let latest = (try? await telemetry.latestReadings(forDevice: device.id)) ?? []
                // Show the device's primary metric and, when present, humidity — each as its own paged
                // metric screen on the watch, with its own recent history for a sparkline.
                var metricsToSync: [MetricKind] = []
                if let primary = WatchSnapshotBuilder.primaryMetric(of: latest) { metricsToSync.append(primary) }
                if latest.contains(where: { $0.metric == .humidity }), !metricsToSync.contains(.humidity) {
                    metricsToSync.append(.humidity)
                }

                var deviceHistory: [TelemetryReading] = []
                for metric in metricsToSync {
                    if let reading = latest.first(where: { $0.metric == metric }) { latestReadings.append(reading) }
                    deviceHistory += await recentHistory(deviceID: device.id, metric: metric)
                }
                if !deviceHistory.isEmpty { historyByDevice[device.id] = deviceHistory }
            }
        }

        let persisted = PersistedSnapshot(
            assets: allAssets, devices: deviceList, latestReadings: latestReadings,
            events: [], alerts: alertList, insights: []
        )
        return WatchSnapshotBuilder.build(from: persisted, now: Date(), history: historyByDevice)
    }

    /// The newest readings of one metric, oldest-first, for the watch sparkline: only as many as the
    /// builder draws, so the snapshot never reads a device's whole history.
    private func recentHistory(deviceID: DeviceID, metric: MetricKind) async -> [TelemetryReading] {
        (try? await telemetry.recentReadings(forDevice: deviceID, metric: metric, limit: WatchSnapshotBuilder.trendPointCount)) ?? []
    }
}
