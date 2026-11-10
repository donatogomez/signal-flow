import Testing
import Foundation
import DomainKit
@testable import DesignSystemKit

/// Localization tests are written to be **deterministic and toolchain-independent**:
///
/// - *Mapping* correctness (does `.label` use the right catalog key?) is asserted by comparing the public
///   mapping to the resolver for the expected key in the **same** locale — equality holds whatever
///   language the machine runs in.
/// - *Translation* correctness is asserted by reading the shipped **`.xcstrings` catalog content**.
///   (Xcode compiles `.xcstrings` → `.lproj` for the real app, verified by the iOS `xcodebuild` build;
///   the SwiftPM CLI only copies the raw catalog, so we validate the catalog's values directly rather
///   than depending on runtime `es` resolution being compiled in CI.)
@Suite("Localization")
struct LocalizationTests {

    // MARK: - Catalog decoding

    private struct Catalog: Decodable {
        let sourceLanguage: String
        let strings: [String: Entry]
        struct Entry: Decodable { let localizations: [String: Localization]? }
        struct Localization: Decodable { let stringUnit: Unit }
        struct Unit: Decodable { let value: String }
    }

    private static let catalog: Catalog = {
        let url = try! #require(DSKLocalization.catalogURL)
        return try! JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }()

    private func spanish(_ key: String) -> String? {
        Self.catalog.strings[key]?.localizations?["es"]?.stringUnit.value
    }

    // MARK: - Presentation mapping (locale-independent equality)

    @Test("Status labels map to the right catalog keys")
    func deviceStatusMapping() {
        #expect(DeviceStatus.nominal.label == DSKLocalization.string("Nominal"))
        #expect(DeviceStatus.warning.label == DSKLocalization.string("Warning"))
        #expect(DeviceStatus.critical.label == DSKLocalization.string("Critical"))
        #expect(DeviceStatus.offline.label == DSKLocalization.string("Offline"))
    }

    @Test("Severity labels map to the right catalog keys")
    func severityMapping() {
        #expect(AlertSeverity.info.label == DSKLocalization.string("Info"))
        #expect(AlertSeverity.warning.label == DSKLocalization.string("Warning"))
        #expect(AlertSeverity.critical.label == DSKLocalization.string("Critical"))
    }

    @Test("Connectivity, insight, asset, and metric labels map to the right keys")
    func otherMappings() {
        #expect(ConnectivityStatus.State.online.label == DSKLocalization.string("Online"))
        #expect(ConnectivityStatus.State.degraded.label == DSKLocalization.string("Degraded"))
        #expect(InsightSeverity.concern.label == DSKLocalization.string("Concern"))
        #expect(InsightSource.foundationModel.label == DSKLocalization.string("On-device AI"))
        #expect(AssetKind.refrigeratedTruck.localizedName == DSKLocalization.string("Refrigerated truck"))
        #expect(MetricKind.temperature.localizedName == DSKLocalization.string("Temperature"))
    }

    @Test("Known custom metric `pressure` maps to the catalog key; unknown customs still prettify")
    func customMetricNames() {
        #expect(MetricKind.custom("pressure").localizedName == DSKLocalization.string("Pressure"))
        // Unknown custom metric keys fall back to a safe prettified label.
        #expect(MetricKind.custom("soil_moisture").localizedName == "Soil Moisture")
    }

    // MARK: - Spanish catalog content

    @Test("Source language is English")
    func sourceLanguage() {
        #expect(Self.catalog.sourceLanguage == "en")
    }

    @Test("Status labels are translated to Spanish")
    func spanishStatusLabels() {
        #expect(spanish("Nominal") == "Nominal")
        #expect(spanish("Warning") == "Advertencia")
        #expect(spanish("Critical") == "Crítico")
        #expect(spanish("Offline") == "Sin conexión")
    }

    @Test("Severity and connectivity labels are translated to Spanish")
    func spanishSeverityAndConnectivity() {
        #expect(spanish("Info") == "Información")
        #expect(spanish("Online") == "En línea")
        #expect(spanish("Degraded") == "Degradada")
    }

    @Test("Domain-concept labels are translated to Spanish")
    func spanishDomainConcepts() {
        #expect(spanish("Refrigerated truck") == "Camión refrigerado")
        #expect(spanish("Temperature") == "Temperatura")
        #expect(spanish("Pressure") == "Presión")
        #expect(spanish("On-device AI") == "IA en el dispositivo")
        #expect(spanish("Power lost") == "Sin alimentación")
        #expect(spanish("Concern") == "Atención")
    }

    // MARK: - Threshold / alert text is never raw English

    @Test("Custom device-event titles map to localized catalog keys, not the raw English key")
    func customEventTitles() {
        #expect(DeviceEvent.Kind.custom("threshold_exceeded").title == DSKLocalization.string("Threshold exceeded"))
        #expect(DeviceEvent.Kind.custom("battery_low").title == DSKLocalization.string("Battery low"))
        // Unknown keys still fall back to a prettified form.
        #expect(DeviceEvent.Kind.custom("foo_bar").title == "Foo Bar")
    }

    @Test("Threshold/battery event titles have Spanish translations (no raw English)")
    func spanishEventTitles() {
        #expect(spanish("Threshold exceeded") == "Umbral superado")
        #expect(spanish("Battery low") == "Batería baja")
    }

    @Test("The localized alert message uses the catalog template, never the domain English")
    func alertMessageIsLocalizedNotRaw() throws {
        let value = try MeasuredValue(magnitude: 12, unit: .celsius)
        let message = localizedAlertMessage(metric: .temperature, value: value)

        // Never the threshold-event wording, and never the domain's "(threshold)" diagnostic phrasing.
        #expect(!message.contains("Threshold exceeded"))
        #expect(!message.contains("acceptable range ("))
        // The Spanish template is present in the catalog.
        #expect(spanish("%@ %@ is outside the acceptable range") == "%1$@ %2$@ está fuera del rango aceptable")
    }

    @Test("Every translatable catalog key has a complete Spanish translation")
    func noMissingSpanish() {
        for (key, entry) in Self.catalog.strings {
            // Skip pure format/symbol placeholders auto-extracted by Xcode (e.g. "%lld%%", "%lld %@", "—"):
            // strip format specifiers first, then a key with no remaining letters is locale-neutral.
            let withoutFormat = key.replacing(/%(?:\d+\$)?\d*[@a-zA-Z]+|%%/, with: "")
            guard withoutFormat.contains(where: \.isLetter) else { continue }
            let value = entry.localizations?["es"]?.stringUnit.value
            #expect(value != nil && !(value ?? "").isEmpty, "missing es translation for \"\(key)\"")
        }
    }

    /// Any catalog's entries, including plural variations, which have no single `stringUnit`.
    private struct AnyCatalog: Decodable {
        let strings: [String: Entry]
        struct Entry: Decodable { let localizations: [String: Localization]? }
        struct Localization: Decodable { let stringUnit: Unit?; let variations: Variations? }
        struct Unit: Decodable { let value: String }
        struct Variations: Decodable {}
    }

    /// Keys that are not translated on purpose: the brand, Swift Charts plottable labels (identifiers,
    /// not prose), and the widget gallery description, which resolves from the widget extension's own
    /// catalog (docs/28, "App Intents & App Extensions"). `AppIntentsKit`'s catalog is skipped for the
    /// same reason: intent metadata resolves from the app's catalog, which is checked here instead.
    private static let untranslatedOnPurpose: Set<String> = ["SignalFlow", "i", "v", "Shows persisted fleet status and alerts."]

    @Test("Every user-facing key in every module and app catalog has a Spanish translation")
    func noMissingSpanishInAnyCatalog() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../..").standardized
        let modules = try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "Sources").path)
            .filter { $0 != "AppIntentsKit" }
            .map { root.appending(path: "Sources/\($0)/Resources/Localizable.xcstrings") }
        let apps = ["SignalFlow", "SignalFlowWidgets"].map { root.appending(path: "App/\($0)/Localizable.xcstrings") }
        let catalogs = (modules + apps).filter { FileManager.default.fileExists(atPath: $0.path) }
        #expect(catalogs.count >= 15)
        for url in catalogs {
            let catalog = try JSONDecoder().decode(AnyCatalog.self, from: Data(contentsOf: url))
            for (key, entry) in catalog.strings where !Self.untranslatedOnPurpose.contains(key) {
                guard key.replacing(/%(?:\d+\$)?\d*[@a-zA-Z]+|%%/, with: "").contains(where: \.isLetter) else { continue }
                let spanish = entry.localizations?["es"]
                #expect(spanish?.variations != nil || spanish?.stringUnit?.value.isEmpty == false, "missing es translation for \"\(key)\" in \(url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent)")
            }
        }
    }
}
