import XCTest
import SwiftUI
@testable import Punto

final class LocalizationTests: XCTestCase {
    private func strings(_ language: AppLanguage) throws -> [String: String] {
        let bundle = PuntoLocalization.bundle(for: language)
        let path = try XCTUnwrap(bundle.path(forResource: "Localizable", ofType: "strings"))
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    }

    func testUIStringTablesHaveMatchingNonemptyKeysAndValues() throws {
        let english = try strings(.english)
        let italian = try strings(.italian)
        XCTAssertGreaterThanOrEqual(english.count, 90)
        XCTAssertEqual(Set(english.keys), Set(italian.keys))
        for key in english.keys {
            XCTAssertFalse(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(try XCTUnwrap(english[key]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, key)
            XCTAssertFalse(try XCTUnwrap(italian[key]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, key)
        }
    }

    func testExplicitLanguageBundlesResolveUserFacingTranslations() {
        let english = PuntoLocalization.bundle(for: .english)
        let italian = PuntoLocalization.bundle(for: .italian)
        for (key, translation) in [
            ("Impostazioni", "Settings"),
            ("Lingua", "Language"),
            ("HiDPI 2× attivo", "HiDPI 2× active"),
            ("Nativo 1× attivo", "Native 1× active")
        ] {
            XCTAssertEqual(english.localizedString(forKey: key, value: nil, table: "Localizable"), translation)
            XCTAssertEqual(italian.localizedString(forKey: key, value: nil, table: "Localizable"), key)
        }
    }

    func testLocalizedMeasurementsPreserveFormatArguments() throws {
        let english = try strings(.english)
        let italian = try strings(.italian)
        let pattern = #"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:ll|l|h)?[@diuoxXfFeEgGaAcCsSp]"#
        let regex = try NSRegularExpression(pattern: pattern)
        func formats(_ string: String) -> [String] {
            let range = NSRange(string.startIndex..., in: string)
            return regex.matches(in: string, range: range).map { (string as NSString).substring(with: $0.range) }
        }
        for (key, value) in english {
            XCTAssertEqual(formats(value), formats(try XCTUnwrap(italian[key])), key)
        }
    }

    func testAppearanceIncludesAutomaticAndExplicitThemes() {
        XCTAssertNil(AppAppearance.system.colorScheme)
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
        XCTAssertEqual(AppAppearance(rawValue: "system"), .system)
        XCTAssertEqual(AppAppearance(rawValue: "light"), .light)
        XCTAssertEqual(AppAppearance(rawValue: "dark"), .dark)
    }

    func testExplicitLanguagesHaveMatchingLocaleIdentifiers() {
        XCTAssertEqual(AppLanguage.english.languageCode, "en")
        XCTAssertEqual(AppLanguage.english.locale.identifier, "en")
        XCTAssertEqual(AppLanguage.italian.languageCode, "it")
        XCTAssertEqual(AppLanguage.italian.locale.identifier, "it")
        XCTAssertTrue(["en", "it"].contains(AppLanguage.system.languageCode))
    }
}
