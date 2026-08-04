import AppKit
import ApplicationServices
import Foundation

enum WorkspaceSwitcherSide: String, CaseIterable {
    case left
    case right

    var title: String {
        switch self {
        case .left:
            return "左侧（默认）"
        case .right:
            return "右侧"
        }
    }
}

enum WorkspacePreferences {
    private static let switcherSideKey =
        "ToubarReplace.workspace.switcherSide"
    private static let floatingSwitcherKey =
        "ToubarReplace.workspace.floatingSwitcher"
    private static let autoCollapseKey =
        "ToubarReplace.workspace.autoCollapse"
    private static let lastPathKey = "ToubarReplace.workspace.lastPath"
    private static let rootFrameMigratedKey =
        "ToubarReplace.workspace.rootFrameMigrated"
    private static let floatingMirrorFrameMigratedKey =
        "ToubarReplace.workspace.floatingMirrorFrameMigrated"
    private static let terminalAdapterKey =
        "ToubarReplace.workspace.terminalAdapter"

    static var switcherSide: WorkspaceSwitcherSide {
        get {
            guard
                let rawValue = UserDefaults.standard.string(
                    forKey: switcherSideKey
                ),
                let side = WorkspaceSwitcherSide(rawValue: rawValue)
            else {
                return .left
            }
            return side
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: switcherSideKey)
        }
    }

    static var floatingSwitcher: Bool {
        get {
            guard
                UserDefaults.standard.object(forKey: floatingSwitcherKey) != nil
            else {
                return true
            }
            return UserDefaults.standard.bool(forKey: floatingSwitcherKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: floatingSwitcherKey)
        }
    }

    static var autoCollapse: Bool {
        get {
            guard UserDefaults.standard.object(forKey: autoCollapseKey) != nil
            else {
                return true
            }
            return UserDefaults.standard.bool(forKey: autoCollapseKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: autoCollapseKey)
        }
    }

    static var lastPath: URL? {
        get {
            guard
                let path = UserDefaults.standard.string(forKey: lastPathKey),
                WorkspacePathResolver.existingDirectory(
                    at: URL(fileURLWithPath: path)
                ) != nil
            else {
                return nil
            }
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        set {
            UserDefaults.standard.set(newValue?.path, forKey: lastPathKey)
        }
    }

    static var hasMigratedRootFrame: Bool {
        get {
            UserDefaults.standard.bool(forKey: rootFrameMigratedKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: rootFrameMigratedKey)
        }
    }

    static var hasMigratedFloatingMirrorFrame: Bool {
        get {
            UserDefaults.standard.bool(forKey: floatingMirrorFrameMigratedKey)
        }
        set {
            UserDefaults.standard.set(
                newValue,
                forKey: floatingMirrorFrameMigratedKey
            )
        }
    }

    static var terminalAdapterID: TerminalAdapterID {
        get {
            guard
                let rawValue = UserDefaults.standard.string(
                    forKey: terminalAdapterKey
                ),
                let adapterID = TerminalAdapterID(rawValue: rawValue)
            else {
                return .otty
            }
            return adapterID
        }
        set {
            UserDefaults.standard.set(
                newValue.rawValue,
                forKey: terminalAdapterKey
            )
        }
    }
}

struct FrontmostAppContext {
    static let finderBundleIdentifier = "com.apple.finder"

    let bundleIdentifier: String?
    let localizedName: String?
    let processIdentifier: pid_t?
    let capturedAt: Date

    var isFinder: Bool {
        bundleIdentifier == Self.finderBundleIdentifier
    }

    @MainActor
    static func capture() -> FrontmostAppContext {
        let application = NSWorkspace.shared.frontmostApplication
        return FrontmostAppContext(
            bundleIdentifier: application?.bundleIdentifier,
            localizedName: application?.localizedName,
            processIdentifier: application?.processIdentifier,
            capturedAt: Date()
        )
    }
}

enum WorkspacePathSource {
    case frontmostDocument(appName: String?)
    case recent
    case manual

    var prefix: String? {
        switch self {
        case let .frontmostDocument(appName):
            return appName
        case .recent:
            return "最近"
        case .manual:
            return nil
        }
    }
}

struct WorkspaceContext {
    let directoryURL: URL
    let source: WorkspacePathSource
    let frontmostApplication: FrontmostAppContext

    var compactTitle: String {
        let directoryName = directoryURL.lastPathComponent
        guard let prefix = source.prefix, !prefix.isEmpty else {
            return directoryName
        }
        return "\(prefix) · \(directoryName)"
    }
}

@MainActor
final class FinderPathResolver {
    func currentDirectoryURL() -> URL? {
        guard let script = NSAppleScript(source: Self.scriptSource) else {
            return nil
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        guard errorInfo == nil, let path = result.stringValue else {
            return nil
        }
        return Self.directoryURL(from: path)
    }

    nonisolated static func directoryURL(from value: String) -> URL? {
        let path = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return WorkspacePathResolver.existingDirectory(
            at: URL(fileURLWithPath: path, isDirectory: true)
        )
    }

    private static let scriptSource = """
    tell application "Finder"
        if (count of Finder windows) is 0 then return ""
        return POSIX path of (target of front Finder window as alias)
    end tell
    """
}

@MainActor
final class WorkspacePathResolver {
    private let fileManager: FileManager
    private let finderPathResolver: FinderPathResolver

    init(
        fileManager: FileManager = .default,
        finderPathResolver: FinderPathResolver = FinderPathResolver()
    ) {
        self.fileManager = fileManager
        self.finderPathResolver = finderPathResolver
    }

    func resolveFrontmostPath(
        from context: FrontmostAppContext
    ) -> WorkspaceContext? {
        if context.isFinder {
            guard let directoryURL = finderPathResolver.currentDirectoryURL()
            else {
                return nil
            }
            return WorkspaceContext(
                directoryURL: directoryURL,
                source: .frontmostDocument(appName: context.localizedName),
                frontmostApplication: context
            )
        }

        guard
            let processIdentifier = context.processIdentifier,
            let documentURL = accessibilityDocumentURL(
                processIdentifier: processIdentifier
            ),
            let directoryURL = projectDirectory(for: documentURL)
        else {
            return nil
        }

        return WorkspaceContext(
            directoryURL: directoryURL,
            source: .frontmostDocument(appName: context.localizedName),
            frontmostApplication: context
        )
    }

    func recentContext(
        frontmostApplication: FrontmostAppContext
    ) -> WorkspaceContext? {
        guard let directoryURL = WorkspacePreferences.lastPath else {
            return nil
        }
        return WorkspaceContext(
            directoryURL: directoryURL,
            source: .recent,
            frontmostApplication: frontmostApplication
        )
    }

    func manualContext(
        directoryURL: URL,
        frontmostApplication: FrontmostAppContext
    ) -> WorkspaceContext? {
        guard let directoryURL = Self.existingDirectory(at: directoryURL) else {
            return nil
        }
        return WorkspaceContext(
            directoryURL: directoryURL,
            source: .manual,
            frontmostApplication: frontmostApplication
        )
    }

    nonisolated static func existingDirectory(at url: URL) -> URL? {
        let standardizedURL = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard
            FileManager.default.fileExists(
                atPath: standardizedURL.path,
                isDirectory: &isDirectory
            ),
            isDirectory.boolValue
        else {
            return nil
        }
        return standardizedURL
    }

    private func accessibilityDocumentURL(
        processIdentifier: pid_t
    ) -> URL? {
        guard AXIsProcessTrusted() else { return nil }

        let application = AXUIElementCreateApplication(processIdentifier)
        var focusedWindowValue: CFTypeRef?
        let focusedWindowResult = AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        )
        guard
            focusedWindowResult == .success,
            let focusedWindowValue,
            CFGetTypeID(focusedWindowValue) == AXUIElementGetTypeID()
        else {
            return nil
        }

        let focusedWindow = unsafeDowncast(
            focusedWindowValue,
            to: AXUIElement.self
        )
        for attribute in [kAXDocumentAttribute, kAXURLAttribute] {
            var value: CFTypeRef?
            guard
                AXUIElementCopyAttributeValue(
                    focusedWindow,
                    attribute as CFString,
                    &value
                ) == .success,
                let string = value as? String,
                let url = fileURL(from: string)
            else {
                continue
            }
            return url
        }
        return nil
    }

    private func fileURL(from value: String) -> URL? {
        if let url = URL(string: value), url.isFileURL {
            return url.standardizedFileURL
        }
        guard value.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: value).standardizedFileURL
    }

    private func projectDirectory(for documentURL: URL) -> URL? {
        let resourceValues = try? documentURL.resourceValues(
            forKeys: [.isDirectoryKey]
        )
        var directoryURL = resourceValues?.isDirectory == true
            ? documentURL
            : documentURL.deletingLastPathComponent()
        guard Self.existingDirectory(at: directoryURL) != nil else {
            return nil
        }

        let fallbackDirectory = directoryURL.standardizedFileURL
        while directoryURL.path != "/" {
            if containsProjectMarker(directoryURL) {
                return directoryURL.standardizedFileURL
            }
            let parent = directoryURL.deletingLastPathComponent()
            guard parent != directoryURL else { break }
            directoryURL = parent
        }
        return fallbackDirectory
    }

    private func containsProjectMarker(_ directoryURL: URL) -> Bool {
        for marker in [".git", "Package.swift", "package.json", "Cargo.toml", "go.mod"] {
            if fileManager.fileExists(
                atPath: directoryURL.appendingPathComponent(marker).path
            ) {
                return true
            }
        }
        guard
            let contents = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        else {
            return false
        }
        return contents.contains { url in
            url.pathExtension == "xcodeproj" || url.pathExtension == "xcworkspace"
        }
    }
}

enum AgentID: String, CaseIterable {
    case codex
    case claudeCode
    case cursor
    case grokBuild
}

enum AgentLaunchCommand {
    static let cursorLeadingArguments = ["--new-window"]
}

enum AgentProcess {
    static func make(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        inheritedEnvironment: [String: String] =
            ProcessInfo.processInfo.environment
    ) -> Process {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory.standardizedFileURL

        var environment = inheritedEnvironment
        let executableDirectory = executableURL
            .deletingLastPathComponent().path
        let inheritedPath = environment["PATH"]
            ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = "\(executableDirectory):\(inheritedPath)"
        process.environment = environment
        return process
    }
}

enum TerminalAdapterID: String, CaseIterable {
    case otty
    case terminal
}

enum TerminalAdapterLaunchStrategy {
    case otty(commandLineURL: URL)
    case terminalAppleScript
}

struct TerminalAdapter {
    let id: TerminalAdapterID
    let displayName: String
    let launchStrategy: TerminalAdapterLaunchStrategy
}

@MainActor
final class TerminalAdapterRegistry {
    private let workspace: NSWorkspace
    private let fileManager: FileManager

    init(
        workspace: NSWorkspace = .shared,
        fileManager: FileManager = .default
    ) {
        self.workspace = workspace
        self.fileManager = fileManager
    }

    func discover() -> [TerminalAdapter] {
        var adapters: [TerminalAdapter] = []
        if let ottyApplicationURL = workspace.urlForApplication(
            withBundleIdentifier: "io.appmakes.otty"
        ) ?? installedApplication(named: "Otty") {
            let commandLineURL = ottyApplicationURL.appendingPathComponent(
                "Contents/MacOS/otty-cli"
            )
            if fileManager.isExecutableFile(atPath: commandLineURL.path) {
                adapters.append(
                    TerminalAdapter(
                        id: .otty,
                        displayName: "Otty",
                        launchStrategy: .otty(commandLineURL: commandLineURL)
                    )
                )
            }
        }

        let terminalApplicationURL = URL(
            fileURLWithPath: "/System/Applications/Utilities/Terminal.app",
            isDirectory: true
        )
        if fileManager.fileExists(atPath: terminalApplicationURL.path) {
            adapters.append(
                TerminalAdapter(
                    id: .terminal,
                    displayName: "终端 Terminal.app",
                    launchStrategy: .terminalAppleScript
                )
            )
        }
        return adapters
    }

    func selectedAdapter() -> TerminalAdapter? {
        let adapters = discover()
        return adapters.first {
            $0.id == WorkspacePreferences.terminalAdapterID
        } ?? adapters.first
    }

    private func installedApplication(named name: String) -> URL? {
        let candidates = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
                "Applications",
                isDirectory: true
            ),
        ].map {
            $0.appendingPathComponent("\(name).app", isDirectory: true)
        }
        return candidates.first {
            fileManager.fileExists(atPath: $0.path)
        }
    }
}

enum AgentLaunchStrategy {
    case openApplication(applicationURL: URL)
    case process(executableURL: URL, leadingArguments: [String])
    case terminal(executableURL: URL)
}

struct AvailableAgent {
    let id: AgentID
    let displayName: String
    let iconApplicationURL: URL?
    let launchStrategy: AgentLaunchStrategy
}

@MainActor
final class AgentRegistry {
    private let workspace: NSWorkspace
    private let fileManager: FileManager

    init(
        workspace: NSWorkspace = .shared,
        fileManager: FileManager = .default
    ) {
        self.workspace = workspace
        self.fileManager = fileManager
    }

    func discover() -> [AvailableAgent] {
        [
            discoverCodex(),
            discoverClaudeCode(),
            discoverCursor(),
            discoverGrokBuild(),
        ].compactMap { $0 }
    }

    private func discoverCodex() -> AvailableAgent? {
        let applicationURL = findApplication(
            names: ["Codex"],
            bundleIdentifiers: ["com.openai.codex"]
        )
        let executableURL = findExecutable(named: "codex")
        let strategy: AgentLaunchStrategy?
        if let executableURL {
            strategy = .process(
                executableURL: executableURL,
                leadingArguments: ["app"]
            )
        } else if let applicationURL {
            strategy = .openApplication(applicationURL: applicationURL)
        } else {
            strategy = nil
        }
        guard let strategy else { return nil }
        return AvailableAgent(
            id: .codex,
            displayName: "Codex",
            iconApplicationURL: applicationURL,
            launchStrategy: strategy
        )
    }

    private func discoverCursor() -> AvailableAgent? {
        let applicationURL = findApplication(
            names: ["Cursor"],
            bundleIdentifiers: ["com.todesktop.230313mzl4w4u92"]
        )
        let strategy: AgentLaunchStrategy?
        let embeddedExecutableURL = applicationURL?.appendingPathComponent(
            "Contents/Resources/app/bin/cursor"
        )
        if let embeddedExecutableURL,
            fileManager.isExecutableFile(atPath: embeddedExecutableURL.path)
        {
            strategy = .process(
                executableURL: embeddedExecutableURL,
                leadingArguments: AgentLaunchCommand.cursorLeadingArguments
            )
        } else if let executableURL = findExecutable(named: "cursor") {
            strategy = .process(
                executableURL: executableURL,
                leadingArguments: AgentLaunchCommand.cursorLeadingArguments
            )
        } else if let applicationURL {
            strategy = .openApplication(applicationURL: applicationURL)
        } else {
            strategy = nil
        }
        guard let strategy else { return nil }
        return AvailableAgent(
            id: .cursor,
            displayName: "Cursor",
            iconApplicationURL: applicationURL,
            launchStrategy: strategy
        )
    }

    private func discoverClaudeCode() -> AvailableAgent? {
        guard let executableURL = findExecutable(named: "claude") else {
            return nil
        }
        let applicationURL = findApplication(
            names: ["Claude"],
            bundleIdentifiers: ["com.anthropic.claudefordesktop"]
        )
        return AvailableAgent(
            id: .claudeCode,
            displayName: "Claude Code",
            iconApplicationURL: applicationURL,
            launchStrategy: .terminal(executableURL: executableURL)
        )
    }

    private func discoverGrokBuild() -> AvailableAgent? {
        guard let executableURL = findExecutable(named: "grok") else {
            return nil
        }
        let applicationURL = findApplication(
            names: ["Grok"],
            bundleIdentifiers: []
        )
        return AvailableAgent(
            id: .grokBuild,
            displayName: "Grok Build",
            iconApplicationURL: applicationURL,
            launchStrategy: .terminal(executableURL: executableURL)
        )
    }

    private func findApplication(
        names: [String],
        bundleIdentifiers: [String]
    ) -> URL? {
        for bundleIdentifier in bundleIdentifiers {
            if let url = workspace.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            ) {
                return url.standardizedFileURL
            }
        }

        for application in workspace.runningApplications {
            guard let applicationURL = application.bundleURL else { continue }
            if bundleIdentifiers.contains(application.bundleIdentifier ?? "")
                || names.contains(application.localizedName ?? "")
            {
                return applicationURL.standardizedFileURL
            }
        }

        let homeApplications = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        for directory in [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeApplications,
        ] {
            for name in names {
                let candidate = directory.appendingPathComponent(
                    "\(name).app",
                    isDirectory: true
                )
                if fileManager.fileExists(atPath: candidate.path) {
                    return candidate.standardizedFileURL
                }
            }
        }
        return nil
    }

    private func findExecutable(named name: String) -> URL? {
        var candidates: [URL] = []
        let environmentPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        candidates.append(contentsOf: environmentPath.split(separator: ":").map {
            URL(fileURLWithPath: String($0), isDirectory: true)
                .appendingPathComponent(name)
        })

        for directory in ["/opt/homebrew/bin", "/usr/local/bin"] {
            candidates.append(
                URL(fileURLWithPath: directory, isDirectory: true)
                    .appendingPathComponent(name)
            )
        }

        let home = fileManager.homeDirectoryForCurrentUser
        for directory in [".local/bin", ".grok/bin", "bin"] {
            candidates.append(
                home.appendingPathComponent(directory, isDirectory: true)
                    .appendingPathComponent(name)
            )
        }

        let nodeVersions = home.appendingPathComponent(
            ".nvm/versions/node",
            isDirectory: true
        )
        if let versions = try? fileManager.contentsOfDirectory(
            at: nodeVersions,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            candidates.append(contentsOf: versions.sorted {
                $0.lastPathComponent > $1.lastPathComponent
            }.map {
                $0.appendingPathComponent("bin", isDirectory: true)
                    .appendingPathComponent(name)
            })
        }

        var visited = Set<String>()
        for candidate in candidates {
            let path = candidate.standardizedFileURL.path
            guard visited.insert(path).inserted else { continue }
            if fileManager.isExecutableFile(atPath: path) {
                // Keep the launcher path instead of resolving a Node shim to
                // its JavaScript target. The launcher's bin directory is
                // prepended to PATH so `/usr/bin/env node` can find the
                // matching runtime even when ToubarReplace starts from Finder.
                return candidate.standardizedFileURL
            }
        }
        return nil
    }

}

enum AgentLaunchError: LocalizedError {
    case projectDirectoryUnavailable
    case terminalAdapterUnavailable
    case processFailed(agentName: String, status: Int32)

    var errorDescription: String? {
        switch self {
        case .projectDirectoryUnavailable:
            return "项目目录已不可用，请重新选择"
        case .terminalAdapterUnavailable:
            return "没有找到可用的终端应用，请在设置中选择"
        case let .processFailed(agentName, status):
            return "\(agentName) 启动失败（状态码 \(status)）"
        }
    }
}

@MainActor
final class AgentLauncher {
    private let terminalAdapterRegistry: TerminalAdapterRegistry

    init(terminalAdapterRegistry: TerminalAdapterRegistry) {
        self.terminalAdapterRegistry = terminalAdapterRegistry
    }

    func launch(
        _ agent: AvailableAgent,
        at projectDirectory: URL
    ) async throws {
        guard WorkspacePathResolver.existingDirectory(at: projectDirectory) != nil
        else {
            throw AgentLaunchError.projectDirectoryUnavailable
        }

        switch agent.launchStrategy {
        case let .openApplication(applicationURL):
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.promptsUserIfNeeded = true
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                NSWorkspace.shared.open(
                    [projectDirectory],
                    withApplicationAt: applicationURL,
                    configuration: configuration
                ) { _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }

        case let .process(executableURL, leadingArguments):
            try await runProcess(
                executableURL: executableURL,
                arguments: leadingArguments + [projectDirectory.path],
                workingDirectory: projectDirectory,
                agentName: agent.displayName
            )

        case let .terminal(executableURL):
            guard let adapter = terminalAdapterRegistry.selectedAdapter() else {
                throw AgentLaunchError.terminalAdapterUnavailable
            }
            try await launchInTerminal(
                adapter,
                toolURL: executableURL,
                projectDirectory: projectDirectory,
                agentName: agent.displayName
            )
        }
    }

    private func launchInTerminal(
        _ adapter: TerminalAdapter,
        toolURL: URL,
        projectDirectory: URL,
        agentName: String
    ) async throws {
        switch adapter.launchStrategy {
        case let .otty(commandLineURL):
            try await runProcess(
                executableURL: commandLineURL,
                arguments: TerminalLaunchCommand.ottyArguments(
                    toolURL: toolURL,
                    projectDirectory: projectDirectory
                ),
                workingDirectory: projectDirectory,
                agentName: agentName
            )
        case .terminalAppleScript:
            try await runProcess(
                executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
                arguments: TerminalLaunchCommand.terminalAppleScriptArguments(
                    toolURL: toolURL,
                    projectDirectory: projectDirectory
                ),
                workingDirectory: projectDirectory,
                agentName: agentName
            )
        }
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        agentName: String
    ) async throws {
        let process = AgentProcess.make(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectory: workingDirectory
        )
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        while process.isRunning {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard process.terminationStatus == 0 else {
            throw AgentLaunchError.processFailed(
                agentName: agentName,
                status: process.terminationStatus
            )
        }
    }
}

enum TerminalLaunchCommand {
    static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    static func command(toolURL: URL) -> String {
        let toolDirectory = toolURL.deletingLastPathComponent().path
        return "export PATH=\(shellQuote(toolDirectory)):$PATH; exec \(shellQuote(toolURL.path))"
    }

    static func ottyArguments(
        toolURL: URL,
        projectDirectory: URL
    ) -> [String] {
        [
            "open",
            "--command",
            command(toolURL: toolURL),
            projectDirectory.path,
        ]
    }

    static func terminalAppleScriptArguments(
        toolURL: URL,
        projectDirectory: URL
    ) -> [String] {
        let script = """
        on run argv
            set commandText to item 1 of argv
            set projectPath to item 2 of argv
            set shellCommand to "cd " & quoted form of projectPath & "; " & commandText
            set terminalWasRunning to application "Terminal" is running
            tell application "Terminal"
                if terminalWasRunning then
                    do script shellCommand
                else
                    launch
                    repeat 40 times
                        if (count of windows) > 0 then exit repeat
                        delay 0.05
                    end repeat
                    if (count of windows) > 0 then
                        do script shellCommand in front window
                    else
                        do script shellCommand
                    end if
                end if
                activate
            end tell
        end run
        """
        return [
            "-e",
            script,
            command(toolURL: toolURL),
            projectDirectory.path,
        ]
    }
}
