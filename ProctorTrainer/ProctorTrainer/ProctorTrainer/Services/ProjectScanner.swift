import Foundation
import Combine

// MARK: - Full Project Scanner
class ProjectScanner: ObservableObject {
    // MARK: - Properties
    @Published var isScanning = false
    @Published var scanProgress: Double = 0.0
    @Published var scannedFiles: [ScannedFile] = []
    @Published var projectStructure: ProjectStructure
    
    // MARK: - Data Models
    struct ScannedFile {
        let path: String
        let name: String
        let type: FileType
        let language: String
        let size: Int64
        let lastModified: Date
        let complexity: FileComplexity
        let functions: [FunctionInfo]
        let classes: [ClassInfo]
        let imports: [String]
        let exports: [String]
        let dependencies: [String]
        
        enum FileType: String, CaseIterable {
            case source = "source"
            case config = "config"
            case resource = "resource"
            case test = "test"
            case documentation = "documentation"
            case build = "build"
            case dependency = "dependency"
            case unknown = "unknown"
            
            var displayName: String {
                switch self {
                case .source: return "Source File"
                case .config: return "Config File"
                case .resource: return "Resource"
                case .test: return "Test File"
                case .documentation: return "Documentation"
                case .build: return "Build File"
                case .dependency: return "Dependency"
                case .unknown: return "Unknown"
                }
            }
        }
        
        enum FileComplexity: String, CaseIterable {
            case simple = "simple"
            case moderate = "moderate"
            case complex = "complex"
            case veryComplex = "very_complex"
            
            var displayName: String {
                switch self {
                case .simple: return "Simple"
                case .moderate: return "Moderate"
                case .complex: return "Complex"
                case .veryComplex: return "Very Complex"
                }
            }
        }
        
        struct FunctionInfo {
            let name: String
            let line: Int
            let parameters: [String]
            let returnType: String
            let visibility: String
            let complexity: Int
        }
        
        struct ClassInfo {
            let name: String
            let line: Int
            let type: String
            let inherits: [String]
            let properties: [String]
            let methods: [String]
            let visibility: String
        }
    }
    
    struct ProjectStructure {
        let name: String
        let path: String
        let type: ProjectType
        let technologies: [String]
        let architecture: ArchitecturePattern
        let totalFiles: Int
        let sourceFiles: Int
        let testFiles: Int
        let configFiles: Int
        let dependencies: [String]
        let buildSystem: BuildSystem
        let complexity: ProjectComplexity
        
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
        
        enum ArchitecturePattern: String, CaseIterable {
            case mvc = "mvc"
            case mvvm = "mvvm"
            case mvp = "mvp"
            case clean = "clean"
            case modular = "modular"
            case microservices = "microservices"
            case monolith = "monolith"
            case component = "component"
            case layered = "layered"
            case unknown = "unknown"
            
            var displayName: String {
                switch self {
                case .mvc: return "MVC"
                case .mvvm: return "MVVM"
                case .mvp: return "MVP"
                case .clean: return "Clean Architecture"
                case .modular: return "Modular"
                case .microservices: return "Microservices"
                case .monolith: return "Monolith"
                case .component: return "Component-Based"
                case .layered: return "Layered"
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
                case .unknown: return "Unknown"
                }
            }
        }
        
        enum ProjectComplexity: String, CaseIterable {
            case simple = "simple"
            case moderate = "moderate"
            case complex = "complex"
            case veryComplex = "very_complex"
            case enterprise = "enterprise"
            
            var displayName: String {
                switch self {
                case .simple: return "Simple"
                case .moderate: return "Moderate"
                case .complex: return "Complex"
                case .veryComplex: return "Very Complex"
                case .enterprise: return "Enterprise"
                }
            }
        }
    }
    
    // MARK: - Initialization
    init() {
        self.projectStructure = ProjectStructure(
            name: "",
            path: "",
            type: .unknown,
            technologies: [],
            architecture: .unknown,
            totalFiles: 0,
            sourceFiles: 0,
            testFiles: 0,
            configFiles: 0,
            dependencies: [],
            buildSystem: .unknown,
            complexity: .simple
        )
    }
    
    // MARK: - Full Project Scanning
    
    /// Scan entire project recursively
    func scanFullProject(at path: String) async -> ProjectStructure {
        await MainActor.run {
            isScanning = true
            scanProgress = 0.0
            scannedFiles.removeAll()
        }
        
        defer {
            Task { @MainActor in
                isScanning = false
                scanProgress = 1.0
            }
        }
        
        let projectURL = URL(fileURLWithPath: path)
        var allFiles: [ScannedFile] = []
        var fileCount = 0
        
        // Recursively scan all files
        if let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            let files = enumerator.compactMap { $0 as? URL }
            for fileURL in files {
                let file = await scanSingleFile(at: fileURL, projectPath: path)
                allFiles.append(file)
                fileCount += 1
                
                // Update progress
                await MainActor.run {
                    scanProgress = Double(fileCount) / 1000.0 // Estimate total
                    scannedFiles = Array(allFiles.prefix(100)) // Show recent scans
                }
            }
        }
        
        // Analyze project structure
        let structure = analyzeProjectStructure(files: allFiles, projectPath: path)
        
        await MainActor.run {
            scannedFiles = allFiles
            projectStructure = structure
        }
        
        return structure
    }
    
    /// Scan single file with detailed analysis
    private func scanSingleFile(at fileURL: URL, projectPath: String) async -> ScannedFile {
        let path = fileURL.path
        let name = fileURL.lastPathComponent
        let relativePath = path.replacingOccurrences(of: projectPath, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Get file properties
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let size = attributes?[.size] as? Int64 ?? 0
        let lastModified = attributes?[.modificationDate] as? Date ?? Date()
        
        // Determine file type and language
        let fileType = determineFileType(fileName: name, relativePath: relativePath)
        let language = determineLanguage(fileName: name)
        
        // Scan content if it's a source file
        if fileType == .source {
            do {
                let content = try String(contentsOfFile: path)
                let complexity = analyzeFileComplexity(content: content, language: language)
                let functions = extractFunctions(from: content, language: language)
                let classes = extractClasses(from: content, language: language)
                let imports = extractImports(from: content, language: language)
                let exports = extractExports(from: content, language: language)
                let dependencies = extractDependencies(from: content, language: language)
                
                return ScannedFile(
                    path: relativePath,
                    name: name,
                    type: fileType,
                    language: language,
                    size: size,
                    lastModified: lastModified,
                    complexity: complexity,
                    functions: functions,
                    classes: classes,
                    imports: imports,
                    exports: exports,
                    dependencies: dependencies
                )
            } catch {
                print("[Scanner] Failed to read file \(path): \(error)")
                return ScannedFile(
                    path: relativePath,
                    name: name,
                    type: fileType,
                    language: language,
                    size: size,
                    lastModified: lastModified,
                    complexity: .simple,
                    functions: [],
                    classes: [],
                    imports: [],
                    exports: [],
                    dependencies: []
                )
            }
        } else {
            return ScannedFile(
                path: relativePath,
                name: name,
                type: fileType,
                language: language,
                size: size,
                lastModified: lastModified,
                complexity: .simple,
                functions: [],
                classes: [],
                imports: [],
                exports: [],
                dependencies: []
            )
        }
    }
    
    // MARK: - Analysis Methods
    
    /// Analyze overall project structure
    private func analyzeProjectStructure(files: [ScannedFile], projectPath: String) -> ProjectStructure {
        let sourceFiles = files.filter { $0.type == .source }
        let testFiles = files.filter { $0.type == .test }
        let configFiles = files.filter { $0.type == .config }
        
        // Detect project type
        let projectType = detectProjectType(files: files, projectPath: projectPath)
        
        // Detect technologies
        let technologies = detectTechnologies(files: files)
        
        // Detect architecture
        let architecture = detectArchitecture(files: sourceFiles)
        
        // Detect build system
        let buildSystem = detectBuildSystem(files: files, projectPath: projectPath)
        
        // Calculate complexity
        let complexity = calculateProjectComplexity(files: files)
        
        // Get project name
        let projectName = URL(fileURLWithPath: projectPath).lastPathComponent
        
        return ProjectStructure(
            name: projectName,
            path: projectPath,
            type: projectType,
            technologies: technologies,
            architecture: architecture,
            totalFiles: files.count,
            sourceFiles: sourceFiles.count,
            testFiles: testFiles.count,
            configFiles: configFiles.count,
            dependencies: extractAllDependencies(files: sourceFiles),
            buildSystem: buildSystem,
            complexity: complexity
        )
    }
    
    /// Determine file type based on name and path
    private func determineFileType(fileName: String, relativePath: String) -> ScannedFile.FileType {
        let lowerFileName = fileName.lowercased()
        let lowerPath = relativePath.lowercased()
        
        // Source files
        if lowerFileName.hasSuffix(".swift") || lowerFileName.hasSuffix(".m") || 
           lowerFileName.hasSuffix(".h") || lowerFileName.hasSuffix(".cpp") ||
           lowerFileName.hasSuffix(".c") || lowerFileName.hasSuffix(".java") ||
           lowerFileName.hasSuffix(".py") || lowerFileName.hasSuffix(".js") ||
           lowerFileName.hasSuffix(".ts") || lowerFileName.hasSuffix(".jsx") ||
           lowerFileName.hasSuffix(".tsx") || lowerFileName.hasSuffix(".go") ||
           lowerFileName.hasSuffix(".rs") || lowerFileName.hasSuffix(".kt") {
            return .source
        }
        
        // Test files
        if lowerFileName.contains("test") || lowerFileName.contains("spec") ||
           lowerPath.contains("/test/") || lowerPath.contains("/tests/") ||
           lowerPath.contains("__tests__/") {
            return .test
        }
        
        // Config files
        if lowerFileName.hasSuffix(".json") || lowerFileName.hasSuffix(".yaml") ||
           lowerFileName.hasSuffix(".yml") || lowerFileName.hasSuffix(".toml") ||
           lowerFileName.hasSuffix(".ini") || lowerFileName.hasSuffix(".plist") ||
           lowerFileName.hasSuffix(".xcconfig") || lowerFileName.hasSuffix(".env") {
            return .config
        }
        
        // Documentation
        if lowerFileName.hasSuffix(".md") || lowerFileName.hasSuffix(".txt") ||
           lowerFileName.hasSuffix(".rst") || lowerFileName.hasSuffix(".adoc") ||
           lowerFileName.contains("readme") || lowerFileName.contains("doc") {
            return .documentation
        }
        
        // Build files
        if lowerFileName.hasSuffix(".build") || lowerPath.contains("/build/") ||
           lowerPath.contains("/target/") || lowerPath.contains("/out/") ||
           lowerPath.contains("/dist/") {
            return .build
        }
        
        // Dependencies
        if lowerFileName.hasSuffix(".framework") || lowerFileName.hasSuffix(".a") ||
           lowerFileName.hasSuffix(".so") || lowerFileName.hasSuffix(".dll") ||
           lowerFileName.hasSuffix(".dylib") {
            return .dependency
        }
        
        // Resources
        if lowerFileName.hasSuffix(".png") || lowerFileName.hasSuffix(".jpg") ||
           lowerFileName.hasSuffix(".jpeg") || lowerFileName.hasSuffix(".gif") ||
           lowerFileName.hasSuffix(".svg") || lowerFileName.hasSuffix(".icns") ||
           lowerFileName.hasSuffix(".mp3") || lowerFileName.hasSuffix(".wav") ||
           lowerFileName.hasSuffix(".mp4") || lowerFileName.hasSuffix(".mov") {
            return .resource
        }
        
        return .unknown
    }
    
    /// Determine programming language
    private func determineLanguage(fileName: String) -> String {
        let lowerFileName = fileName.lowercased()
        
        if lowerFileName.hasSuffix(".swift") { return "Swift" }
        if lowerFileName.hasSuffix(".m") || lowerFileName.hasSuffix(".h") { return "Objective-C" }
        if lowerFileName.hasSuffix(".ts") { return "TypeScript" }
        if lowerFileName.hasSuffix(".tsx") { return "TypeScript React" }
        if lowerFileName.hasSuffix(".js") { return "JavaScript" }
        if lowerFileName.hasSuffix(".jsx") { return "JavaScript React" }
        if lowerFileName.hasSuffix(".py") { return "Python" }
        if lowerFileName.hasSuffix(".java") { return "Java" }
        if lowerFileName.hasSuffix(".cpp") || lowerFileName.hasSuffix(".c") { return "C++" }
        if lowerFileName.hasSuffix(".go") { return "Go" }
        if lowerFileName.hasSuffix(".rs") { return "Rust" }
        if lowerFileName.hasSuffix(".kt") { return "Kotlin" }
        if lowerFileName.hasSuffix(".php") { return "PHP" }
        if lowerFileName.hasSuffix(".rb") { return "Ruby" }
        if lowerFileName.hasSuffix(".cs") { return "C#" }
        if lowerFileName.hasSuffix(".vb") { return "VB.NET" }
        if lowerFileName.hasSuffix(".swift") { return "Swift" }
        
        return "Unknown"
    }
    
    /// Detect project type from files and structure
    private func detectProjectType(files: [ScannedFile], projectPath: String) -> ProjectStructure.ProjectType {
        let fileNames = files.map { $0.name.lowercased() }
        let filePaths = files.map { $0.path.lowercased() }
        
        // iOS/macOS projects
        if fileNames.contains(where: { $0.hasSuffix(".xcodeproj") }) ||
           fileNames.contains(where: { $0.hasSuffix(".xcworkspace") }) ||
           filePaths.contains("/sources/") {
            return filePaths.contains("ios/") ? .ios : .macos
        }
        
        // Web projects
        if fileNames.contains("package.json") || fileNames.contains("webpack.config.js") ||
           fileNames.contains("vite.config.js") || fileNames.contains("tsconfig.json") {
            return .web
        }
        
        // Mobile projects
        if filePaths.contains("/android/") || fileNames.contains("build.gradle") ||
           fileNames.contains("AndroidManifest.xml") {
            return .mobile
        }
        
        // Server projects
        if fileNames.contains("server.js") || fileNames.contains("app.py") ||
           fileNames.contains("main.go") || fileNames.contains("Dockerfile") {
            return .server
        }
        
        // Libraries/Frameworks
        if fileNames.contains("Package.swift") || fileNames.contains("module.modulemap") ||
           filePaths.contains("/sources/") && filePaths.contains("/include/") {
            return .library
        }
        
        return .unknown
    }
    
    /// Detect technologies used
    private func detectTechnologies(files: [ScannedFile]) -> [String] {
        var technologies: Set<String> = []
        
        for file in files {
            // From file extensions
            if file.language == "Swift" { technologies.insert("Swift") }
            if file.language == "TypeScript" { technologies.insert("TypeScript") }
            if file.language == "JavaScript" { technologies.insert("JavaScript") }
            if file.language == "Python" { technologies.insert("Python") }
            
            // From imports and dependencies
            for importStatement in file.imports {
                if importStatement.contains("SwiftUI") { technologies.insert("SwiftUI") }
                if importStatement.contains("Combine") { technologies.insert("Combine") }
                if importStatement.contains("Foundation") { technologies.insert("Foundation") }
                if importStatement.contains("React") { technologies.insert("React") }
                if importStatement.contains("Vue") { technologies.insert("Vue") }
                if importStatement.contains("Angular") { technologies.insert("Angular") }
                if importStatement.contains("Express") { technologies.insert("Express.js") }
                if importStatement.contains("Django") { technologies.insert("Django") }
                if importStatement.contains("Flask") { technologies.insert("Flask") }
                if importStatement.contains("FastAPI") { technologies.insert("FastAPI") }
            }
        }
        
        return Array(technologies)
    }
    
    /// Detect architecture pattern
    private func detectArchitecture(files: [ScannedFile]) -> ProjectStructure.ArchitecturePattern {
        let fileNames = files.map { $0.name.lowercased() }
        let filePaths = files.map { $0.path.lowercased() }
        
        // MVVM pattern
        if fileNames.contains(where: { $0.contains("viewmodel") }) ||
           filePaths.contains("/viewmodels/") || filePaths.contains("/viewmodel/") {
            return .mvvm
        }
        
        // MVC pattern
        if fileNames.contains(where: { $0.contains("viewcontroller") }) ||
           filePaths.contains("/views/") || filePaths.contains("/controllers/") {
            return .mvc
        }
        
        // Clean architecture
        if filePaths.contains("/domain/") || filePaths.contains("/usecases/") ||
           filePaths.contains("/entities/") || filePaths.contains("/gateways/") {
            return .clean
        }
        
        // Modular architecture
        if filePaths.contains("/modules/") || filePaths.contains("/components/") ||
           filePaths.contains("/packages/") {
            return .modular
        }
        
        // Component-based
        if filePaths.contains("/components/") && fileNames.contains(where: { $0.contains("component") }) {
            return .component
        }
        
        // Layered architecture
        if filePaths.contains("/layers/") || filePaths.contains("/tiers/") ||
           (filePaths.contains("/presentation/") && filePaths.contains("/business/") && filePaths.contains("/data/")) {
            return .layered
        }
        
        return .unknown
    }
    
    /// Detect build system
    private func detectBuildSystem(files: [ScannedFile], projectPath: String) -> ProjectStructure.BuildSystem {
        let fileNames = files.map { $0.name.lowercased() }
        
        // Xcode build systems
        if fileNames.contains(where: { $0.hasSuffix(".xcodeproj") }) ||
           fileNames.contains(where: { $0.hasSuffix(".xcworkspace") }) {
            return .xcodebuild
        }
        
        // Swift Package Manager
        if fileNames.contains("Package.swift") {
            return .swiftPackageManager
        }
        
        // CocoaPods
        if fileNames.contains("podfile") || fileNames.contains("podfile.lock") {
            return .cocoapods
        }
        
        // Carthage
        if fileNames.contains("cartfile") || fileNames.contains("cartfile.resolved") {
            return .carthage
        }
        
        // npm/yarn
        if fileNames.contains("package.json") {
            if fileNames.contains("yarn.lock") {
                return .yarn
            } else {
                return .npm
            }
        }
        
        // Webpack/Vite
        if fileNames.contains("webpack.config.js") || fileNames.contains("webpack.config.ts") {
            return .webpack
        }
        
        if fileNames.contains("vite.config.js") || fileNames.contains("vite.config.ts") {
            return .vite
        }
        
        // Gradle
        if fileNames.contains("build.gradle") || fileNames.contains("settings.gradle") {
            return .gradle
        }
        
        // Maven
        if fileNames.contains("pom.xml") {
            return .maven
        }
        
        // Make/CMake
        if fileNames.contains("makefile") {
            return .make
        }
        
        if fileNames.contains("cmakelists.txt") || fileNames.contains("cmakecache.txt") {
            return .cmake
        }
        
        return .unknown
    }
    
    /// Calculate project complexity
    private func calculateProjectComplexity(files: [ScannedFile]) -> ProjectStructure.ProjectComplexity {
        let sourceFiles = files.filter { $0.type == .source }
        let totalComplexity = sourceFiles.map { file in
            switch file.complexity {
            case .simple: return 1
            case .moderate: return 2
            case .complex: return 3
            case .veryComplex: return 4
            }
        }.reduce(0, +)
        
        let averageComplexity = Double(totalComplexity) / Double(max(sourceFiles.count, 1))
        
        switch averageComplexity {
        case 0...1.5: return .simple
        case 1.6...2.5: return .moderate
        case 2.6...3.5: return .complex
        default: return .veryComplex
        }
    }
    
    // MARK: - Content Analysis Methods
    
    /// Analyze file complexity
    private func analyzeFileComplexity(content: String, language: String) -> ScannedFile.FileComplexity {
        let lines = content.components(separatedBy: .newlines)
        let lineCount = lines.count
        
        // Count complexity indicators
        let nestedLoops = lines.filter { $0.contains("for") && $0.contains("for") }.count
        let conditionals = lines.filter { $0.contains("if") || $0.contains("switch") }.count
        let functions = lines.filter { $0.contains("func") || $0.contains("function") }.count
        let classes = lines.filter { $0.contains("class") || $0.contains("struct") }.count
        
        let complexityScore = Double(lineCount) / 50.0 + 
                          Double(nestedLoops) * 2.0 + 
                          Double(conditionals) * 1.5 + 
                          Double(functions) * 1.0 + 
                          Double(classes) * 2.0
        
        switch complexityScore {
        case 0...5: return .simple
        case 6...15: return .moderate
        case 16...30: return .complex
        default: return .veryComplex
        }
    }
    
    /// Extract functions from source code
    private func extractFunctions(from content: String, language: String) -> [ScannedFile.FunctionInfo] {
        let lines = content.components(separatedBy: .newlines)
        var functions: [ScannedFile.FunctionInfo] = []
        
        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1
            
            if language == "Swift" {
                if line.contains("func ") {
                    let functionInfo = extractSwiftFunction(from: line, lineNumber: lineNumber)
                    functions.append(functionInfo)
                }
            } else if language == "TypeScript" || language == "JavaScript" {
                if line.contains("function ") || line.contains("=>") {
                    let functionInfo = extractJSFunction(from: line, lineNumber: lineNumber)
                    functions.append(functionInfo)
                }
            } else if language == "Python" {
                if line.contains("def ") {
                    let functionInfo = extractPythonFunction(from: line, lineNumber: lineNumber)
                    functions.append(functionInfo)
                }
            }
        }
        
        return functions
    }
    
    /// Extract classes from source code
    private func extractClasses(from content: String, language: String) -> [ScannedFile.ClassInfo] {
        let lines = content.components(separatedBy: .newlines)
        var classes: [ScannedFile.ClassInfo] = []
        
        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1
            
            if language == "Swift" {
                if line.contains("class ") || line.contains("struct ") {
                    let classInfo = extractSwiftClass(from: line, lineNumber: lineNumber)
                    classes.append(classInfo)
                }
            } else if language == "TypeScript" || language == "JavaScript" {
                if line.contains("class ") {
                    let classInfo = extractJSClass(from: line, lineNumber: lineNumber)
                    classes.append(classInfo)
                }
            } else if language == "Python" {
                if line.contains("class ") {
                    let classInfo = extractPythonClass(from: line, lineNumber: lineNumber)
                    classes.append(classInfo)
                }
            }
        }
        
        return classes
    }
    
    /// Extract imports from source code
    private func extractImports(from content: String, language: String) -> [String] {
        let lines = content.components(separatedBy: .newlines)
        var imports: [String] = []
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if language == "Swift" {
                if trimmedLine.hasPrefix("import ") {
                    let importStatement = trimmedLine.replacingOccurrences(of: "import ", with: "")
                    imports.append(importStatement)
                }
            } else if language == "TypeScript" || language == "JavaScript" {
                if trimmedLine.hasPrefix("import ") || trimmedLine.hasPrefix("const ") {
                    // Extract from import statements
                    if let importRange = trimmedLine.range(of: "from ") {
                        let importStatement = String(trimmedLine[importRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        imports.append(importStatement)
                    }
                }
            } else if language == "Python" {
                if trimmedLine.hasPrefix("import ") || trimmedLine.hasPrefix("from ") {
                    let importStatement = trimmedLine.replacingOccurrences(of: "import ", with: "").replacingOccurrences(of: "from ", with: "")
                    imports.append(importStatement)
                }
            }
        }
        
        return imports
    }
    
    /// Extract exports from source code
    private func extractExports(from content: String, language: String) -> [String] {
        let lines = content.components(separatedBy: .newlines)
        var exports: [String] = []
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if language == "TypeScript" || language == "JavaScript" {
                if trimmedLine.hasPrefix("export ") {
                    let exportStatement = trimmedLine.replacingOccurrences(of: "export ", with: "")
                    exports.append(exportStatement)
                }
            } else if language == "Python" {
                // Python doesn't have explicit exports, but we can track __all__
                if trimmedLine.contains("__all__") {
                    exports.append(trimmedLine)
                }
            }
        }
        
        return exports
    }
    
    /// Extract all dependencies from source files
    private func extractAllDependencies(files: [ScannedFile]) -> [String] {
        var allDependencies: Set<String> = []
        
        for file in files {
            allDependencies.formUnion(file.dependencies)
        }
        
        return Array(allDependencies)
    }
    
    // MARK: - Language-Specific Extraction Methods
    
    private func extractSwiftFunction(from line: String, lineNumber: Int) -> ScannedFile.FunctionInfo {
        let components = line.components(separatedBy: .whitespacesAndNewlines)
        guard let funcIndex = components.firstIndex(where: { $0 == "func" }) else {
            return ScannedFile.FunctionInfo(name: "unknown", line: lineNumber, parameters: [], returnType: "Void", visibility: "internal", complexity: 1)
        }
        
        let functionName = funcIndex + 1 < components.count ? components[funcIndex + 1] : "unknown"
        let cleanName = functionName.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? functionName
        
        return ScannedFile.FunctionInfo(
            name: cleanName,
            line: lineNumber,
            parameters: [],
            returnType: "Void",
            visibility: "internal",
            complexity: 1
        )
    }
    
    private func extractJSFunction(from line: String, lineNumber: Int) -> ScannedFile.FunctionInfo {
        // Simplified JS function extraction
        let components = line.components(separatedBy: .whitespacesAndNewlines)
        guard let funcIndex = components.firstIndex(where: { $0 == "function" }) else {
            return ScannedFile.FunctionInfo(name: "unknown", line: lineNumber, parameters: [], returnType: "any", visibility: "export", complexity: 1)
        }
        
        let functionName = funcIndex + 1 < components.count ? components[funcIndex + 1] : "unknown"
        let cleanName = functionName.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? functionName
        
        return ScannedFile.FunctionInfo(
            name: cleanName,
            line: lineNumber,
            parameters: [],
            returnType: "any",
            visibility: "export",
            complexity: 1
        )
    }
    
    private func extractPythonFunction(from line: String, lineNumber: Int) -> ScannedFile.FunctionInfo {
        let components = line.components(separatedBy: .whitespacesAndNewlines)
        guard let defIndex = components.firstIndex(where: { $0 == "def" }) else {
            return ScannedFile.FunctionInfo(name: "unknown", line: lineNumber, parameters: [], returnType: "Any", visibility: "public", complexity: 1)
        }
        
        let functionName = defIndex + 1 < components.count ? components[defIndex + 1] : "unknown"
        let cleanName = functionName.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? functionName
        
        return ScannedFile.FunctionInfo(
            name: cleanName,
            line: lineNumber,
            parameters: [],
            returnType: "Any",
            visibility: "public",
            complexity: 1
        )
    }
    
    private func extractSwiftClass(from line: String, lineNumber: Int) -> ScannedFile.ClassInfo {
        let components = line.components(separatedBy: .whitespacesAndNewlines)
        guard let classIndex = components.firstIndex(where: { $0 == "class" || $0 == "struct" }) else {
            return ScannedFile.ClassInfo(name: "unknown", line: lineNumber, type: "class", inherits: [], properties: [], methods: [], visibility: "internal")
        }
        
        let className = classIndex + 1 < components.count ? components[classIndex + 1] : "unknown"
        let cleanName = className.components(separatedBy: ":").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? className
        let classType = components[classIndex]
        
        return ScannedFile.ClassInfo(
            name: cleanName,
            line: lineNumber,
            type: classType,
            inherits: [],
            properties: [],
            methods: [],
            visibility: "internal"
        )
    }
    
    private func extractJSClass(from line: String, lineNumber: Int) -> ScannedFile.ClassInfo {
        let components = line.components(separatedBy: .whitespacesAndNewlines)
        guard let classIndex = components.firstIndex(where: { $0 == "class" }) else {
            return ScannedFile.ClassInfo(name: "unknown", line: lineNumber, type: "class", inherits: [], properties: [], methods: [], visibility: "export")
        }
        
        let className = classIndex + 1 < components.count ? components[classIndex + 1] : "unknown"
        let cleanName = className.components(separatedBy: "{").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? className
        
        return ScannedFile.ClassInfo(
            name: cleanName,
            line: lineNumber,
            type: "class",
            inherits: [],
            properties: [],
            methods: [],
            visibility: "export"
        )
    }
    
    private func extractPythonClass(from line: String, lineNumber: Int) -> ScannedFile.ClassInfo {
        let components = line.components(separatedBy: .whitespacesAndNewlines)
        guard let classIndex = components.firstIndex(where: { $0 == "class" }) else {
            return ScannedFile.ClassInfo(name: "unknown", line: lineNumber, type: "class", inherits: [], properties: [], methods: [], visibility: "public")
        }
        
        let className = classIndex + 1 < components.count ? components[classIndex + 1] : "unknown"
        let cleanName = className.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? className
        
        return ScannedFile.ClassInfo(
            name: cleanName,
            line: lineNumber,
            type: "class",
            inherits: [],
            properties: [],
            methods: [],
            visibility: "public"
        )
    }
    
    /// Extract dependencies from source code
    private func extractDependencies(from content: String, language: String) -> [String] {
        // Simplified dependency extraction logic
        var dependencies: [String] = []
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if language == "Swift" && trimmed.hasPrefix("import ") {
                dependencies.append(trimmed.replacingOccurrences(of: "import ", with: ""))
            } else if (language == "TypeScript" || language == "JavaScript") && (trimmed.contains("require(") || trimmed.contains("from '")) {
                dependencies.append(trimmed)
            }
        }
        
        return dependencies
    }
}
