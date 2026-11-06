import Foundation

enum PuntoLocalization {
    static var language: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "system") ?? .system
    }

    static var bundle: Bundle {
        bundle(for: language)
    }

    static func bundle(for language: AppLanguage) -> Bundle {
        let languageCode = language.languageCode
        // The app packager copies lproj folders into the app resource directory.
        // SwiftPM command-line builds keep them in the generated resource bundle.
        if let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"), let bundle = Bundle(path: path) {
            return bundle
        }
        // Do not evaluate Bundle.module eagerly: a packaged app can contain
        // native lproj resources without SwiftPM's separate resource bundle.
        if let path = Bundle.module.path(forResource: languageCode, ofType: "lproj"), let bundle = Bundle(path: path) {
            return bundle
        }
        return Bundle.main
    }
}

func L(_ key: String, table: String = "Localizable") -> String {
    PuntoLocalization.bundle.localizedString(forKey: key, value: key, table: table)
}

/// Formats localized strings whose arguments are runtime display measurements.
func LF(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), locale: PuntoLocalization.language.locale, arguments: arguments)
}
