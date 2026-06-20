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
        #expect(spanish("On-device AI") == "IA en el dispositivo")
        #expect(spanish("Power lost") == "Sin alimentación")
        #expect(spanish("Concern") == "Atención")
    }

    @Test("Every catalog key has a complete Spanish translation")
    func noMissingSpanish() {
        for (key, entry) in Self.catalog.strings {
            let value = entry.localizations?["es"]?.stringUnit.value
            #expect(value != nil && !(value ?? "").isEmpty, "missing es translation for \"\(key)\"")
        }
    }
}
