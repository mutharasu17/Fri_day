import Foundation

enum IDEType: String, Codable, CaseIterable {
    case xcode = "Xcode"
    case vscode = "VS Code"
    case windsurf = "Windsurf"
    case antigravity = "Antigravity"
    case cursor = "Cursor"
    case unknown = "Unknown"
}

struct IDEContext: Codable {
    var errorText: String
    var fileName: String
    var selectedCode: String
    var buildLog: String
    var projectPath: String
    var ideType: IDEType
    var terminalOutput: String
}
