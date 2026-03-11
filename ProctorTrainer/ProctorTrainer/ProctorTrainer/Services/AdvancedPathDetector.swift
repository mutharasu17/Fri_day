#if os(macOS)
import Foundation
import AppKit
import Combine

// MARK: - Advanced Path Detection System
class AdvancedPathDetector: ObservableObject {
    // MARK: - Properties
    @Published var currentProjectPath: String = ""
    @Published var detectedIDEs: [IDEDetection] = []
    @Published var workspaceInfo: WorkspaceInfo
    
    // MARK: - Data Models
    struct IDEDetection {
        let bundleIdentifier: String
        let name: String
        let path: String?
        let isActive: Bool
        let version: String?
        let pid: pid_t?
        
        enum IDEType: String, CaseIterable {
            case xcode = "com.apple.dt.Xcode"
            case vscode = "com.microsoft.VSCode"
            case windsurf = "com.blackstone.Windsurf"
            case antigravity = "com.antigravity.Antigravity"
            case cursor = "com.cursor.Cursor"
            case sublime = "com.sublimetext.3"
            case atom = "com.github.atom"
            case intellij = "com.jetbrains.intellij"
            case pycharm = "com.jetbrains.pycharm"
            case webstorm = "com.jetbrains.webstorm"
            case androidstudio = "com.google.android.studio"
            
            var displayName: String {
                switch self {
                case .xcode: return "Xcode"
                case .vscode: return "Visual Studio Code"
                case .windsurf: return "Windsurf"
                case .antigravity: return "Antigravity"
                case .cursor: return "Cursor"
                case .sublime: return "Sublime Text"
                case .atom: return "Atom"
                case .intellij: return "IntelliJ IDEA"
                case .pycharm: return "PyCharm"
                case .webstorm: return "WebStorm"
                case .androidstudio: return "Android Studio"
                }
            }
        }
    }
    
    struct WorkspaceInfo {
        let name: String
        let path: String
        let type: WorkspaceType
        let projects: [ProjectInfo]
        let activeProject: ProjectInfo?
        let lastModified: Date
        
        enum WorkspaceType: String, CaseIterable {
            case xcodeWorkspace = "xcode_workspace"
            case vscodeWorkspace = "vscode_workspace"
            case folder = "folder"
            case gitRepository = "git_repository"
            case unknown = "unknown"
            
            var displayName: String {
                switch self {
                case .xcodeWorkspace: return "Xcode Workspace"
                case .vscodeWorkspace: return "VS Code Workspace"
                case .folder: return "Folder"
                case .gitRepository: return "Git Repository"
                case .unknown: return "Unknown"
                }
            }
        }
    }
    
    struct ProjectInfo {
        let name: String
        let path: String
        let type: ProjectType
        let buildSystem: BuildSystem
        let technologies: [String]
        let lastModified: Date
        let isActive: Bool
        
        enum ProjectType: String, CaseIterable {
            case ios = "ios"
            case macos = "macos"
            case web = "web"
            case mobile = "mobile"
            case desktop = "desktop"
            case server = "server"
            case library = "library"
            case framework = "framework"
            case unknown = "unknown"
            
            var displayName: String {
                switch self {
                case .ios: return "iOS App"
                case .macos: return "macOS App"
                case .web: return "Web App"
                case .mobile: return "Mobile App"
                case .desktop: return "Desktop App"
                case .server: return "Server App"
                case .library: return "Library"
                case .framework: return "Framework"
                case .unknown: return "Unknown"
                }
            }
        }
        
        enum BuildSystem: String, CaseIterable {
            case xcodebuild = "xcodebuild"
            case swiftPackageManager = "swift_package_manager"
            case carthage = "carthage"
            case cocoapods = "cocoapods"
            case npm = "npm"
            case yarn = "yarn"
            case webpack = "webpack"
            case vite = "vite"
            case gradle = "gradle"
            case maven = "maven"
            case make = "make"
            case cmake = "cmake"
            case cargo = "cargo"
            case pip = "pip"
            case poetry = "poetry"
            case unknown = "unknown"
            
            var displayName: String {
                switch self {
                case .xcodebuild: return "Xcode Build"
                case .swiftPackageManager: return "Swift Package Manager"
                case .carthage: return "Carthage"
                case .cocoapods: return "CocoaPods"
                case .npm: return "npm"
                case .yarn: return "Yarn"
                case .webpack: return "Webpack"
                case .vite: return "Vite"
                case .gradle: return "Gradle"
                case .maven: return "Maven"
                case .make: return "Make"
                case .cmake: return "CMake"
                case .cargo: return "Cargo"
                case .pip: return "pip"
                case .poetry: return "Poetry"
                case .unknown: return "Unknown"
                }
            }
        }
    }
    
    // MARK: - Initialization
    init() {
        self.workspaceInfo = WorkspaceInfo(
            name: "",
            path: "",
            type: .unknown,
            projects: [],
            activeProject: nil,
            lastModified: Date()
        )
    }
    
    // MARK: - Advanced Path Detection
    
    /// Get comprehensive project path using multiple methods
    func getProjectPath(using fallback: String = "") -> String {
        // Method 1: Active IDE detection
        if let idePath = getActiveIDEProjectPath() {
            return idePath
        }
        
        // Method 2: Workspace detection
        if let workspacePath = getWorkspaceProjectPath() {
            return workspacePath
        }
        
        // Method 3: Git repository detection
        if let gitPath = getGitRepositoryPath() {
            return gitPath
        }
        
        // Method 4: Project file search
        if let projectPath = searchForProjectFiles(startingFrom: fallback) {
            return projectPath
        }
        
        // Method 5: Environment variables
        if let envPath = getEnvironmentProjectPath() {
            return envPath
        }
        
        // Method 6: Current working directory
        return getCurrentWorkingDirectory()
    }
    
    /// Detect all running IDEs
    func detectAllIDEs() -> [IDEDetection] {
        var detectedIDEs: [IDEDetection] = []
        
        // Get all running applications
        let runningApps = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            if let bundleId = app.bundleIdentifier,
               let ideType = IDEDetection.IDEType(rawValue: bundleId) {
                
                let ideInfo = IDEDetection(
                    bundleIdentifier: bundleId,
                    name: ideType.displayName,
                    path: getIDEPath(for: bundleId),
                    isActive: app.isActive,
                    version: getIDEVersion(for: bundleId),
                    pid: app.processIdentifier
                )
                
                detectedIDEs.append(ideInfo)
            }
        }
        
        return detectedIDEs.sorted { $0.isActive && !$1.isActive }
    }
    
    /// Get workspace information
    func getWorkspaceInfo() -> WorkspaceInfo {
        // Detect workspace type and projects
        let workspacePath = detectWorkspacePath()
        let projects = detectProjectsInWorkspace(at: workspacePath)
        let activeProject = getActiveProject(from: projects)
        
        return WorkspaceInfo(
            name: URL(fileURLWithPath: workspacePath).lastPathComponent,
            path: workspacePath,
            type: detectWorkspaceType(at: workspacePath),
            projects: projects,
            activeProject: activeProject,
            lastModified: Date()
        )
    }
    
    // MARK: - IDE-Specific Path Detection
    
    /// Get Xcode project path
    func getXcodeProjectPath() -> String? {
        // Method 1: AppleScript to get current Xcode project
        let script = """
        tell application "Xcode"
            try
                if exists workspace document then
                    set workspacePath to path of workspace document
                else if exists project document then
                    set projectPath to path of project document
                else
                    return "No project open"
                end if
                
                if workspacePath is not "No project open" then
                    return POSIX path of workspacePath
                else if projectPath is not "No project open" then
                    return POSIX path of projectPath
                else
                    return "No project open"
                end if
            on error
                return "Error: " & (error number as string) & " - " & error message
            end try
        end tell
        """
        
        return runAppleScript(script)
    }
    
    /// Get VS Code workspace path
    func getVSCodeWorkspacePath() -> String? {
        // Method 1: AppleScript to get VS Code workspace
        let script = """
        tell application "Visual Studio Code"
            try
                set workspaceFolders to workspace folders of active workspace
                if length of workspaceFolders > 0 then
                    set workspacePath to POSIX path of (item 1 of workspaceFolders)
                    return workspacePath
                else
                    return "No workspace open"
                end if
            on error
                return "Error: " & (error number as string) & " - " & error message
            end try
        end tell
        """
        
        let result = runAppleScript(script)
        return result.contains("Error") ? nil : result
    }
    
    /// Get Windsurf project path
    func getWindsurfProjectPath() -> String? {
        let script = """
        tell application "Windsurf"
            try
                if exists workspace document then
                    set workspacePath to path of workspace document
                    return POSIX path of workspacePath
                else if exists project document then
                    set projectPath to path of project document
                    return POSIX path of projectPath
                else
                    return "No project open"
                end if
            on error
                return "Error: " & (error number as string) & " - " & error message
            end try
        end tell
        """
        
        let result = runAppleScript(script)
        return result.contains("Error") ? nil : result
    }
    
    // MARK: - Helper Methods
    
    /// Get active IDE project path
    private func getActiveIDEProjectPath() -> String? {
        let activeIDEs = detectAllIDEs().filter { $0.isActive }
        
        for ide in activeIDEs {
            switch ide.bundleIdentifier {
            case IDEDetection.IDEType.xcode.rawValue:
                return getXcodeProjectPath()
            case IDEDetection.IDEType.vscode.rawValue:
                return getVSCodeWorkspacePath()
            case IDEDetection.IDEType.windsurf.rawValue:
                return getWindsurfProjectPath()
            default:
                continue
            }
        }
        
        return nil
    }
    
    /// Get workspace project path
    private func getWorkspaceProjectPath() -> String? {
        let workspaceInfo = getWorkspaceInfo()
        return workspaceInfo.activeProject?.path
    }
    
    /// Get Git repository path
    private func getGitRepositoryPath() -> String? {
        let currentPath = getCurrentWorkingDirectory()
        var path = currentPath
        
        // Traverse up to find .git directory
        while path != "/" {
            let gitPath = path + "/.git"
            if FileManager.default.fileExists(atPath: gitPath) {
                return path
            }
            path = (path as NSString).deletingLastPathComponent
        }
        
        return nil
    }
    
    /// Search for project files
    private func searchForProjectFiles(startingFrom path: String) -> String? {
        let searchPaths = [
            path,
            FileManager.default.homeDirectoryForCurrentUser.path + "/Documents",
            FileManager.default.homeDirectoryForCurrentUser.path + "/Desktop",
            FileManager.default.homeDirectoryForCurrentUser.path + "/Projects"
        ]
        
        for searchPath in searchPaths {
            if let projectPath = findProjectInDirectory(at: searchPath) {
                return projectPath
            }
        }
        
        return nil
    }
    
    /// Find project in directory
    private func findProjectInDirectory(at directoryPath: String) -> String? {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directoryPath) else {
            return nil
        }
        
        for item in contents {
            let fullPath = directoryPath + "/" + item
            
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory), isDirectory.boolValue {
                // Check for project indicators
                if isProjectDirectory(at: fullPath) {
                    return fullPath
                }
                
                // Recursively search subdirectories
                if let projectPath = findProjectInDirectory(at: fullPath) {
                    return projectPath
                }
            }
        }
        
        return nil
    }
    
    /// Check if directory is a project directory
    private func isProjectDirectory(at path: String) -> Bool {
        let fileName = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        
        // Check for project files
        let projectIndicators = [
            ".xcodeproj",
            ".xcworkspace",
            "package.json",
            "pom.xml",
            "build.gradle",
            "settings.gradle",
            "Cargo.toml",
            "requirements.txt",
            "pyproject.toml",
            "composer.json",
            "Gemfile",
            "Rakefile",
            "Makefile",
            "CMakeLists.txt"
        ]
        
        // Check if current directory is a project
        for indicator in projectIndicators {
            if fileName.contains(indicator) {
                return true
            }
        }
        
        // Check if directory contains project files
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: path) {
            for item in contents {
                let lowerItem = item.lowercased()
                for indicator in projectIndicators {
                    if lowerItem.contains(indicator) {
                        return true
                    }
                }
            }
        }
        
        return false
    }
    
    /// Get environment project path
    private func getEnvironmentProjectPath() -> String? {
        let envVars = [
            "PROJECT_ROOT",
            "WORKSPACE",
            "PWD",
            "PROJECT_PATH",
            "WORKSPACE_PATH"
        ]
        
        for envVar in envVars {
            if let path = ProcessInfo.processInfo.environment[envVar] {
                return path
            }
        }
        
        return nil
    }
    
    /// Get current working directory
    private func getCurrentWorkingDirectory() -> String {
        return FileManager.default.currentDirectoryPath
    }
    
    /// Detect workspace path
    private func detectWorkspacePath() -> String {
        // Try multiple methods to find workspace
        let methods = [
            getActiveIDEProjectPath,
            getWorkspaceProjectPath,
            getGitRepositoryPath,
            { self.searchForProjectFiles(startingFrom: "") }
        ]
        
        for method in methods {
            if let path = method() {
                return path
            }
        }
        
        return getCurrentWorkingDirectory()
    }
    
    /// Detect projects in workspace
    private func detectProjectsInWorkspace(at workspacePath: String) -> [ProjectInfo] {
        var projects: [ProjectInfo] = []
        
        guard let contents = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: workspacePath), 
                                                               includingPropertiesForKeys: nil,
                                                               options: [.skipsHiddenFiles]) else {
            return projects
        }
        
        for item in contents {
            let fullPath = item.path
            var isDirectory: ObjCBool = false
            
            if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory), isDirectory.boolValue {
                if let projectInfo = analyzeProject(at: fullPath) {
                    projects.append(projectInfo)
                }
            }
        }
        
        return projects
    }
    
    /// Analyze project at path
    private func analyzeProject(at path: String) -> ProjectInfo? {
        let fileName = URL(fileURLWithPath: path).lastPathComponent
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let lastModified = attributes?[.modificationDate] as? Date ?? Date()
        
        // Detect project type and build system
        let projectType = detectProjectType(at: path)
        let buildSystem = detectBuildSystem(at: path)
        let technologies = detectTechnologies(at: path)
        
        return ProjectInfo(
            name: fileName,
            path: path,
            type: projectType,
            buildSystem: buildSystem,
            technologies: technologies,
            lastModified: lastModified,
            isActive: false
        )
    }
    
    /// Detect project type
    private func detectProjectType(at path: String) -> ProjectInfo.ProjectType {
        let fileName = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        
        if fileName.contains(".xcodeproj") || fileName.contains(".xcworkspace") {
            return path.contains("ios/") ? .ios : .macos
        }
        
        if fileName.contains("package.json") {
            return .web
        }
        
        if fileName.contains("build.gradle") || fileName.contains("settings.gradle") {
            return .mobile
        }
        
        if fileName.contains("pom.xml") {
            return .server
        }
        
        if fileName.contains("Cargo.toml") {
            return .library
        }
        
        return .unknown
    }
    
    /// Detect build system
    private func detectBuildSystem(at path: String) -> ProjectInfo.BuildSystem {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return .unknown
        }
        
        let fileNames = contents.map { $0.lowercased() }
        
        if fileNames.contains("package.swift") {
            return .swiftPackageManager
        }
        
        if fileNames.contains("podfile") {
            return .cocoapods
        }
        
        if fileNames.contains("cartfile") {
            return .carthage
        }
        
        if fileNames.contains("package.json") {
            if fileNames.contains("yarn.lock") {
                return .yarn
            } else {
                return .npm
            }
        }
        
        if fileNames.contains("webpack.config") {
            return .webpack
        }
        
        if fileNames.contains("vite.config") {
            return .vite
        }
        
        if fileNames.contains("build.gradle") {
            return .gradle
        }
        
        if fileNames.contains("pom.xml") {
            return .maven
        }
        
        if fileNames.contains("Cargo.toml") {
            return .cargo
        }
        
        if fileNames.contains("requirements.txt") {
            return .pip
        }
        
        if fileNames.contains("pyproject.toml") {
            return .poetry
        }
        
        return .unknown
    }
    
    /// Detect technologies
    private func detectTechnologies(at path: String) -> [String] {
        var technologies: Set<String> = []
        
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return []
        }
        
        let fileNames = contents.map { $0.lowercased() }
        
        // Detect from file names
        if fileNames.contains(where: { $0.hasSuffix(".swift") }) {
            technologies.insert("Swift")
        }
        
        if fileNames.contains("package.json") {
            technologies.insert("Node.js")
            
            // Read package.json for more specific technologies
            if let packageJsonPath = contents.first(where: { $0.lowercased() == "package.json" }) {
                let packageJsonPath = path + "/" + packageJsonPath
                if let data = try? Data(contentsOf: URL(fileURLWithPath: packageJsonPath)),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    
                    if let dependencies = json["dependencies"] as? [String: Any] {
                        for (dep, _) in dependencies {
                            if dep.contains("react") { technologies.insert("React") }
                            if dep.contains("vue") { technologies.insert("Vue") }
                            if dep.contains("angular") { technologies.insert("Angular") }
                            if dep.contains("express") { technologies.insert("Express.js") }
                            if dep.contains("next") { technologies.insert("Next.js") }
                        }
                    }
                    
                    if let devDependencies = json["devDependencies"] as? [String: Any] {
                        for (dep, _) in devDependencies {
                            if dep.contains("typescript") { technologies.insert("TypeScript") }
                            if dep.contains("webpack") { technologies.insert("Webpack") }
                            if dep.contains("vite") { technologies.insert("Vite") }
                        }
                    }
                }
            }
        }
        
        return Array(technologies)
    }
    
    /// Detect workspace type
    private func detectWorkspaceType(at path: String) -> WorkspaceInfo.WorkspaceType {
        if path.contains(".xcodeproj") || path.contains(".xcworkspace") {
            return .xcodeWorkspace
        }
        
        if path.contains(".vscode") {
            return .vscodeWorkspace
        }
        
        if path.contains(".git") {
            return .gitRepository
        }
        
        return .folder
    }
    
    /// Get active project
    private func getActiveProject(from projects: [ProjectInfo]) -> ProjectInfo? {
        // For now, return the most recently modified project
        return projects.sorted { $0.lastModified > $1.lastModified }.first
    }
    
    /// Get IDE path
    private func getIDEPath(for bundleIdentifier: String) -> String? {
        // Use NSWorkspace to get application path
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return appURL.path
        }
        return nil
    }
    
    /// Get IDE version
    private func getIDEVersion(for bundleIdentifier: String) -> String? {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
           let bundle = Bundle(url: appURL) {
            return bundle.infoDictionary?["CFBundleShortVersionString"] as? String
        }
        return nil
    }
    
    /// Run AppleScript
    private func runAppleScript(_ script: String) -> String {
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
#endif // os(macOS)
