import Testing
import Foundation
import DomainKit
import SnapshotKit
import WatchConnectivityKit
@testable import WatchWidgetSupportKit

@Suite("watchOS complications & Smart Stack")
struct WatchComplicationTests {

    // MARK: - Builders

    private func alert(_ severity: AlertSeverity, device: String, raisedAt: TimeInterval) -> WidgetAlert {
        WidgetAlert(id: AlertID(), deviceName: device, severity: severity, metric: .temperature, message: "m", raisedAt: Date(timeIntervalSince1970: raisedAt))
    }

    private func snapshot(
        online: Int = 8, warning: Int = 0, critical: Int = 0, offline: Int = 0,
        lastReading: Date? = nil,
        criticalAlerts: [WidgetAlert] = [],
        syncedAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> WatchSyncSnapshot {
        WatchSyncSnapshot(
            fleet: FleetSummary(online: online, warning: warning, critical: critical, offline: offline, lastUpdated: lastReading),
            devices: [],
            criticalAlerts: criticalAlerts,
            lastUpdated: syncedAt
        )
    }

    // MARK: - Fleet summary projection

    @Test("Entry projects the synced fleet counts")
    func fleetProjection() {
        let now = Date(timeIntervalSince1970: 2_000)
        let entry = WatchComplicationModel.entry(from: snapshot(online: 8, warning: 1, critical: 1, offline: 0, lastReading: now), now: now)
        #expect(entry.online == 8)
        #expect(entry.warning == 1)
        #expect(entry.critical == 1)
        #expect(entry.total == 10)
        #expect(entry.hasData)
    }

    @Test("An empty snapshot projects a no-data entry")
    func noDataEntry() {
        let entry = WatchComplicationModel.entry(from: .empty, now: .now)
        #expect(entry.freshness == .noData)
        #expect(entry.hasData == false)
        #expect(entry.relevanceScore == 0)
        #expect(WatchComplicationViewModel(entry).statusLine == "No data")
    }

    // MARK: - Stale vs fresh

    @Test("Freshness flips at the stale threshold; stale still carries last-known data")
    func freshVsStale() {
        let reading = Date(timeIntervalSince1970: 10_000)

        let fresh = WatchComplicationModel.entry(
            from: snapshot(online: 9, warning: 1, lastReading: reading),
            now: reading.addingTimeInterval(WatchComplicationModel.staleThreshold - 1)
        )
        #expect(fresh.freshness == .fresh)
        #expect(fresh.isStale == false)

        let stale = WatchComplicationModel.entry(
            from: snapshot(online: 9, warning: 1, lastReading: reading),
            now: reading.addingTimeInterval(WatchComplicationModel.staleThreshold + 1)
        )
        #expect(stale.freshness == .stale)
        #expect(stale.isStale)
        #expect(stale.total == 10) // last-known data preserved
        #expect(stale.warning == 1)
    }

    @Test("Freshness falls back to the sync time when there are no readings")
    func freshnessFallsBackToSyncTime() {
        let syncedAt = Date(timeIntervalSince1970: 5_000)
        let entry = WatchComplicationModel.entry(
            from: snapshot(online: 5, lastReading: nil, syncedAt: syncedAt),
            now: syncedAt.addingTimeInterval(60)
        )
        #expect(entry.referenceDate == syncedAt)
        #expect(entry.freshness == .fresh)
    }

    // MARK: - Relevance scoring (Smart Stack)

    @Test("Relevance rises with severity and is damped when stale")
    func relevanceScoring() {
        func entry(critical: Int, warning: Int, freshness: WatchSnapshotFreshness) -> WatchComplicationEntry {
            WatchComplicationEntry(date: .now, online: 5, warning: warning, critical: critical, offline: 0,
                                   topAlert: nil, referenceDate: .now, freshness: freshness)
        }
        let allNominal = entry(critical: 0, warning: 0, freshness: .fresh)
        let warnings = entry(critical: 0, warning: 2, freshness: .fresh)
        let criticals = entry(critical: 2, warning: 0, freshness: .fresh)
        let criticalsStale = entry(critical: 2, warning: 0, freshness: .stale)

        #expect(criticals.relevanceScore > warnings.relevanceScore)
        #expect(warnings.relevanceScore > allNominal.relevanceScore)
        #expect(allNominal.relevanceScore > 0)                     // surfaced, but low
        #expect(criticalsStale.relevanceScore < criticals.relevanceScore) // stale damped
    }

    // MARK: - Top alert selection

    @Test("Top alert is the most recent critical")
    func topAlertSelection() {
        let now = Date(timeIntervalSince1970: 10_000)
        let entry = WatchComplicationModel.entry(
            from: snapshot(
                online: 6, critical: 2, lastReading: now,
                criticalAlerts: [
                    alert(.critical, device: "Old", raisedAt: 100),
                    alert(.critical, device: "Newest", raisedAt: 900),
                    alert(.critical, device: "Mid", raisedAt: 500),
                ]
            ),
            now: now
        )
        #expect(entry.topAlert?.deviceName == "Newest")
        #expect(WatchComplicationViewModel(entry).topAlertDeviceName == "Newest")
    }

    // MARK: - Composed status line (English on the test host)

    @Test("Status line is severity-first and concise")
    func statusLine() {
        let now = Date(timeIntervalSince1970: 2_000)
        func line(critical: Int, warning: Int, online: Int, total: Int) -> String {
            let s = snapshot(online: online, warning: warning, critical: critical, offline: total - online - warning - critical, lastReading: now)
            return WatchComplicationViewModel(WatchComplicationModel.entry(from: s, now: now)).statusLine
        }
        #expect(line(critical: 2, warning: 0, online: 8, total: 10) == "2 critical · 8/10 online")
        #expect(line(critical: 0, warning: 2, online: 8, total: 10) == "2 warning") // "2 warnings" in the compiled app
        #expect(line(critical: 0, warning: 0, online: 10, total: 10) == "All nominal")
    }

    @Test("Compact count is the worst count, with glyphs for the small families")
    func compactCount() {
        let now = Date(timeIntervalSince1970: 2_000)
        func compact(critical: Int, warning: Int, online: Int, total: Int) -> String {
            let s = snapshot(online: online, warning: warning, critical: critical, offline: total - online - warning - critical, lastReading: now)
            return WatchComplicationViewModel(WatchComplicationModel.entry(from: s, now: now)).compactCount
        }
        #expect(compact(critical: 3, warning: 1, online: 6, total: 10) == "3")
        #expect(compact(critical: 0, warning: 2, online: 8, total: 10) == "2")
        #expect(compact(critical: 0, warning: 0, online: 10, total: 10) == "10")
        #expect(WatchComplicationViewModel(WatchComplicationModel.entry(from: .empty, now: now)).compactCount == "—")
    }

    // MARK: - Localization catalog coverage

    @Test("The widget string catalog carries the expected Spanish strings")
    func spanishCatalog() throws {
        let cat = try Catalog()
        #expect(cat.unit("Fleet Health", "es") == "Estado de la flota")
        #expect(cat.unit("Critical and warning counts at a glance.", "es") == "Recuentos de críticos y advertencias de un vistazo.")
        #expect(cat.unit("All nominal", "es") == "Todo en orden")
        #expect(cat.unit("No data", "es") == "Sin datos")
        #expect(cat.unit("Stale", "es") == "Desactualizado")
        #expect(cat.unit("Updated", "es") == "Actualizado")
        #expect(cat.unit("%lld/%lld online", "es") == "%lld/%lld en línea")
    }

    @Test("The count keys are pluralized in Spanish (and English)")
    func spanishCatalogPlurals() throws {
        let cat = try Catalog()
        #expect(cat.plural("%lld warning", "es", "one") == "%lld advertencia")
        #expect(cat.plural("%lld warning", "es", "other") == "%lld advertencias")
        #expect(cat.plural("%lld critical", "es", "one") == "%lld crítico")
        #expect(cat.plural("%lld critical", "es", "other") == "%lld críticos")
        #expect(cat.plural("%lld warning", "en", "other") == "%lld warnings")
    }
}

/// Reads the shipped `Localizable.xcstrings` straight from the WatchWidgetSupportKit resource bundle —
/// SwiftPM copies it in uncompiled, so this asserts the translations at their source, independent of the
/// macOS test host's process language and of plural compilation.
private struct Catalog {
    private let strings: [String: Any]

    init() throws {
        let url = try #require(watchWidgetSupportResourceBundle.url(forResource: "Localizable", withExtension: "xcstrings"))
        let json = try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        strings = (json?["strings"] as? [String: Any]) ?? [:]
    }

    private func localization(_ key: String, _ language: String) -> [String: Any]? {
        let entry = strings[key] as? [String: Any]
        let localizations = entry?["localizations"] as? [String: Any]
        return localizations?[language] as? [String: Any]
    }

    func unit(_ key: String, _ language: String) -> String? {
        (localization(key, language)?["stringUnit"] as? [String: Any])?["value"] as? String
    }

    func plural(_ key: String, _ language: String, _ category: String) -> String? {
        let variations = (localization(key, language)?["variations"] as? [String: Any])?["plural"] as? [String: Any]
        let unit = (variations?[category] as? [String: Any])?["stringUnit"] as? [String: Any]
        return unit?["value"] as? String
    }
}
