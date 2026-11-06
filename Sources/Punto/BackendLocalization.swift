import Foundation

func B(_ key: String, _ arguments: CVarArg...) -> String {
    let format = L(key, table: "Backend")
    return arguments.isEmpty ? format : String(format: format, arguments: arguments)
}
