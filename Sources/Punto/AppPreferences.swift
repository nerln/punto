import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case italian = "it"

    var id: String { rawValue }

    var languageCode: String {
        switch self {
        case .english: return "en"
        case .italian: return "it"
        case .system:
            return Locale.preferredLanguages.first.map { $0.lowercased().hasPrefix("it") ? "it" : "en" } ?? "en"
        }
    }

    var locale: Locale { Locale(identifier: languageCode) }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct SettingsView: View {
    @AppStorage("appLanguage") private var language = AppLanguage.system.rawValue
    @AppStorage("appAppearance") private var appearance = AppAppearance.system.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Lingua", selection: $language) {
                    Text("Come il sistema").tag(AppLanguage.system.rawValue)
                    Text(verbatim: "English").tag(AppLanguage.english.rawValue)
                    Text(verbatim: "Italiano").tag(AppLanguage.italian.rawValue)
                }
                Picker("Aspetto", selection: $appearance) {
                    Text("Come il sistema").tag(AppAppearance.system.rawValue)
                    Text("Chiaro").tag(AppAppearance.light.rawValue)
                    Text("Scuro").tag(AppAppearance.dark.rawValue)
                }
            } header: {
                Text("Preferenze di Punto")
            } footer: {
                Text("Lingua e aspetto si aggiornano subito. Queste preferenze non modificano le impostazioni del monitor.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 250)
        .environment(\.locale, (AppLanguage(rawValue: language) ?? .system).locale)
        .preferredColorScheme((AppAppearance(rawValue: appearance) ?? .system).colorScheme)
    }
}
