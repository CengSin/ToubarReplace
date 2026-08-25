import AppKit
import ApplicationServices
import Foundation

enum WorkspaceSwitcherDisplayMode: String, CaseIterable {
    case touchBar
    case floating

    var title: String {
        switch self {
        case .touchBar:
            return "物理 Touch Bar"
        case .floating:
            return "独立浮窗"
        }
    }
}

enum WorkspaceStartupScene: String, CaseIterable {
    case workspace
    case mirror

    var title: String {
        switch self {
        case .workspace:
            return "Workspace"
        case .mirror:
            return "镜像"
        }
    }
}

enum WorkspaceStartupScenePolicy {
    static func scene(storedRawValue: String?) -> WorkspaceStartupScene {
        guard
            let storedRawValue,
            let scene = WorkspaceStartupScene(rawValue: storedRawValue)
        else {
            return .workspace
        }
        return scene
    }

    static func defaultAutoCollapse(startupScene: WorkspaceStartupScene) -> Bool {
        startupScene == .mirror
    }
}

enum WorkspacePreferences {
    private static let floatingSwitcherKey =
        "ToubarReplace.workspace.floatingSwitcher"
    private static let switcherDisplayModeKey =
        "ToubarReplace.workspace.switcherDisplayMode"
    private static let startupSceneKey =
        "ToubarReplace.workspace.startupScene"
    private static let autoCollapseKey =
        "ToubarReplace.workspace.autoCollapse"
    private static let lastPathKey = "ToubarReplace.workspace.lastPath"
    private static let recentProjectsKey =
        "ToubarReplace.workspace.recentProjects"
    private static let terminalAdapterKey =
        "ToubarReplace.workspace.terminalAdapter"

    /// Preferred location of the Workspace switcher button.
    /// `.touchBar` shows a real touchable button on the hardware Touch Bar.
    /// `.floating` shows the independent floating window only.
    static var switcherDisplayMode: WorkspaceSwitcherDisplayMode {
        get {
            if let rawValue = UserDefaults.standard.string(
                forKey: switcherDisplayModeKey
            ),
                let mode = WorkspaceSwitcherDisplayMode(rawValue: rawValue)
            {
                return mode
            }
            // Migrate from the older floatingSwitcher bool.
            if UserDefaults.standard.object(forKey: floatingSwitcherKey) != nil {
                return UserDefaults.standard.bool(forKey: floatingSwitcherKey)
                    ? .floating
                    : .touchBar
            }
            return .touchBar
        }
        set {
            UserDefaults.standard.set(
                newValue.rawValue,
                forKey: switcherDisplayModeKey
            )
        }
    }

    /// Convenience: true means floating window mode.
    static var floatingSwitcher: Bool {
        get { switcherDisplayMode == .floating }
        set { switcherDisplayMode = newValue ? .floating : .touchBar }
    }

    static var startupScene: WorkspaceStartupScene {
        get {
            WorkspaceStartupScenePolicy.scene(
                storedRawValue: UserDefaults.standard.string(
                    forKey: startupSceneKey
                )
            )
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: startupSceneKey)
        }
    }

    static var autoCollapse: Bool {
        get {
            guard UserDefaults.standard.object(forKey: autoCollapseKey) != nil
            else {
                return WorkspaceStartupScenePolicy.defaultAutoCollapse(
                    startupScene: startupScene
                )
            }
            return UserDefaults.standard.bool(forKey: autoCollapseKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: autoCollapseKey)
        }
    }

    static var recentProjects: [WorkspaceRecentProject] {
        get {
            if let data = UserDefaults.standard.data(forKey: recentProjectsKey),
                let decoded = try? JSONDecoder().decode(
                    [WorkspaceRecentProject].self,
                    from: data
                )
            {
                return WorkspaceRecentProjectList.normalized(decoded)
            }
            if let legacy = lastPathFromLegacyKey {
                return [
                    WorkspaceRecentProject(path: legacy.path, lastUsedAt: .distantPast)
                ]
            }
            return []
        }
        set {
            let normalized = WorkspaceRecentProjectList.normalized(newValue)
            if let data = try? JSONEncoder().encode(normalized) {
                UserDefaults.standard.set(data, forKey: recentProjectsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: recentProjectsKey)
            }
            UserDefaults.standard.set(
                normalized.first?.path,
                forKey: lastPathKey
            )
        }
    }

    static var lastPath: URL? {
        get {
            for project in recentProjects {
                if let directory = WorkspacePathResolver.existingDirectory(
                    at: project.url
                ) {
                    return directory
                }
            }
            return lastPathFromLegacyKey
        }
        set {
            if let url = newValue {
                recentProjects = WorkspaceRecentProjectList.recording(
                    url,
                    in: recentProjects
                )
            }
        }
    }

    private static var lastPathFromLegacyKey: URL? {
        guard
            let path = UserDefaults.standard.string(forKey: lastPathKey),
            let directory = WorkspacePathResolver.existingDirectory(
                at: URL(fileURLWithPath: path)
            )
        else {
            return nil
        }
        return directory
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

    private static let customAppsKey = "ToubarReplace.workspace.customApps"

    /// Pinned favorites in slot order (index 0…maxCount-1). Cap via
    /// ``CustomWorkspaceAppList.normalized``.
    static var customApps: [CustomWorkspaceApp] {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: customAppsKey),
                let decoded = try? JSONDecoder().decode(
                    [CustomWorkspaceApp].self,
                    from: data
                )
            else {
                return []
            }
            return CustomWorkspaceAppList.normalized(decoded)
        }
        set {
            let normalized = CustomWorkspaceAppList.normalized(newValue)
            if let data = try? JSONEncoder().encode(normalized) {
                UserDefaults.standard.set(data, forKey: customAppsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: customAppsKey)
            }
        }
    }
}

/// User-pinned app for the Workspace custom zone (open only; no project path).
struct CustomWorkspaceApp: Codable, Equatable {
    /// Bundle identifier when known; used for dedupe and relaunch fallback.
    var bundleIdentifier: String?
    /// Absolute path to the `.app` bundle when selected.
    var applicationPath: String
    /// Display name captured at add time.
    var displayName: String

    var applicationURL: URL {
        URL(fileURLWithPath: applicationPath, isDirectory: true)
    }

    static func make(fromApplicationURL url: URL) -> CustomWorkspaceApp? {
        let standardized = url.standardizedFileURL
        guard standardized.pathExtension == "app" else { return nil }
        let bundle = Bundle(url: standardized)
        let bundleIdentifier = bundle?.bundleIdentifier
        let displayName =
            bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? standardized.deletingPathExtension().lastPathComponent
        return CustomWorkspaceApp(
            bundleIdentifier: bundleIdentifier,
            applicationPath: standardized.path,
            displayName: displayName
        )
    }
}

enum CustomWorkspaceAppList {
    static let maxCount = 3

    /// Dedupe (last wins) and keep at most ``maxCount`` in list order.
    /// Does not silently evict by FIFO when adding — callers use ``adding`` /
    /// ``replacing`` for explicit pin management.
    static func normalized(_ apps: [CustomWorkspaceApp]) -> [CustomWorkspaceApp] {
        var result: [CustomWorkspaceApp] = []
        for app in apps {
            result.removeAll { Self.isSameApp($0, app) }
            result.append(app)
        }
        if result.count > maxCount {
            result = Array(result.prefix(maxCount))
        }
        return result
    }

    /// Append when under capacity. If already pinned, refreshes that slot.
    /// Returns `nil` when full and `app` is not already in the list.
    static func adding(
        _ app: CustomWorkspaceApp,
        to apps: [CustomWorkspaceApp]
    ) -> [CustomWorkspaceApp]? {
        var result = normalized(apps)
        if let existingIndex = result.firstIndex(where: { isSameApp($0, app) }) {
            result[existingIndex] = app
            return result
        }
        guard result.count < maxCount else { return nil }
        result.append(app)
        return result
    }

    /// Replace the pin at `index`. Other slots that match the same app are
    /// removed. Returns `nil` if `index` is out of range.
    static func replacing(
        at index: Int,
        with app: CustomWorkspaceApp,
        in apps: [CustomWorkspaceApp]
    ) -> [CustomWorkspaceApp]? {
        var result = normalized(apps)
        guard result.indices.contains(index) else { return nil }
        result[index] = app
        var kept: [CustomWorkspaceApp] = []
        for (i, item) in result.enumerated() {
            if i != index, isSameApp(item, app) { continue }
            kept.append(item)
        }
        return normalized(kept)
    }

    static func removing(
        at index: Int,
        from apps: [CustomWorkspaceApp]
    ) -> [CustomWorkspaceApp]? {
        var result = normalized(apps)
        guard result.indices.contains(index) else { return nil }
        result.remove(at: index)
        return result
    }

    static func isSameApp(_ lhs: CustomWorkspaceApp, _ rhs: CustomWorkspaceApp)
        -> Bool
    {
        if let leftID = lhs.bundleIdentifier,
            let rightID = rhs.bundleIdentifier,
            !leftID.isEmpty,
            leftID == rightID
        {
            return true
        }
        return lhs.applicationPath == rhs.applicationPath
    }
}

struct WorkspaceRecentProject: Codable, Equatable {
    var path: String
    var lastUsedAt: Date

    var url: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }
}

enum WorkspaceRecentProjectList {
    static let maxCount = 5

    static func normalized(
        _ projects: [WorkspaceRecentProject]
    ) -> [WorkspaceRecentProject] {
        var result: [WorkspaceRecentProject] = []
        for project in projects.sorted(by: { $0.lastUsedAt > $1.lastUsedAt }) {
            let path = URL(fileURLWithPath: project.path).standardizedFileURL.path
            result.removeAll { $0.path == path }
            result.append(
                WorkspaceRecentProject(path: path, lastUsedAt: project.lastUsedAt)
            )
        }
        if result.count > maxCount {
            result = Array(result.prefix(maxCount))
        }
        return result
    }

    static func recording(
        _ url: URL,
        at date: Date = Date(),
        in existing: [WorkspaceRecentProject]
    ) -> [WorkspaceRecentProject] {
        var result = normalized(existing)
        let path = url.standardizedFileURL.path
        result.removeAll { $0.path == path }
        result.insert(
            WorkspaceRecentProject(path: path, lastUsedAt: date),
            at: 0
        )
        return Array(result.prefix(maxCount))
    }

    static func removing(
        path: String,
        from existing: [WorkspaceRecentProject]
    ) -> [WorkspaceRecentProject] {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        return normalized(existing).filter { $0.path != standardized }
    }

    static func displayURLs(
        stored: [WorkspaceRecentProject],
        homeDirectory: URL,
        existingDirectory: (URL) -> URL?
    ) -> [URL] {
        let homePath = homeDirectory.standardizedFileURL.path
        var result: [URL] = []
        for project in normalized(stored) {
            guard let directory = existingDirectory(project.url) else { continue }
            let path = directory.path
            guard path != homePath else { continue }
            guard !result.contains(where: { $0.path == path }) else { continue }
            result.append(directory)
            if result.count == maxCount { break }
        }
        return result
    }
}

enum CustomWorkspaceAppLauncher {
    @MainActor
    static func open(
        _ app: CustomWorkspaceApp,
        workspace: NSWorkspace = .shared,
        fileManager: FileManager = .default
    ) async throws {
        try await open(
            app,
            fileManager: fileManager,
            resolveBundleIdentifier: { bundleIdentifier in
                workspace.urlForApplication(
                    withBundleIdentifier: bundleIdentifier
                )
            },
            openApplication: { url in
                try await openApplication(at: url, workspace: workspace)
            }
        )
    }

    @MainActor
    static func open(
        _ app: CustomWorkspaceApp,
        fileManager: FileManager,
        resolveBundleIdentifier: (String) -> URL?,
        openApplication: (URL) async throws -> Void
    ) async throws {
        if fileManager.fileExists(atPath: app.applicationPath) {
            try await openApplication(app.applicationURL)
            return
        }
        if let bundleIdentifier = app.bundleIdentifier,
            let url = resolveBundleIdentifier(bundleIdentifier)
        {
            try await openApplication(url)
            return
        }
        throw CustomWorkspaceAppLaunchError.applicationMissing(app.displayName)
    }

    @MainActor
    static func openApplication(
        at url: URL,
        workspace: NSWorkspace = .shared
    ) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            workspace.openApplication(
                at: url,
                configuration: configuration
            ) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

enum CustomWorkspaceAppLaunchError: LocalizedError {
    case applicationMissing(String)

    var errorDescription: String? {
        switch self {
        case let .applicationMissing(name):
            return "找不到应用「\(name)」"
        }
    }
}

struct FrontmostAppContext {
    static let finderBundleIdentifier = "com.apple.finder"
    static let ottyBundleIdentifier = "io.appmakes.otty"

    let bundleIdentifier: String?
    let localizedName: String?
    let processIdentifier: pid_t?
    let capturedAt: Date

    var isFinder: Bool {
        bundleIdentifier == Self.finderBundleIdentifier
    }

    var isOtty: Bool {
        bundleIdentifier == Self.ottyBundleIdentifier
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

enum WorkspacePathSource: Equatable {
    case frontmostDocument(appName: String?)
    case otty
    case recent
    case manual

    var prefix: String? {
        switch self {
        case let .frontmostDocument(appName):
            return appName
        case .otty:
            return "Otty"
        case .recent:
            return "最近"
        case .manual:
            return nil
        }
    }
}

struct WorkspacePathProbe {
    var frontmost: FrontmostAppContext
    var finderDirectory: URL?
    var ottyDirectory: URL?
    var accessibilityDirectory: URL?
}

struct WorkspaceResolvedPath: Equatable {
    let directoryURL: URL
    let source: WorkspacePathSource
}

enum WorkspacePathResolutionPolicy {
    static func resolve(_ probe: WorkspacePathProbe) -> WorkspaceResolvedPath? {
        if probe.frontmost.isFinder, let directory = probe.finderDirectory {
            return WorkspaceResolvedPath(
                directoryURL: directory,
                source: .frontmostDocument(appName: probe.frontmost.localizedName)
            )
        }
        if probe.frontmost.isOtty, let directory = probe.ottyDirectory {
            return WorkspaceResolvedPath(
                directoryURL: directory,
                source: .otty
            )
        }
        if let directory = probe.accessibilityDirectory {
            return WorkspaceResolvedPath(
                directoryURL: directory,
                source: .frontmostDocument(appName: probe.frontmost.localizedName)
            )
        }
        return nil
    }
}

enum OttyDirectoryParser {
    static func focusedDirectory(fromJSON data: Data) -> URL? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data),
            let object = root as? [String: Any]
        else {
            return nil
        }
        let panes: [[String: Any]]
        if let dataObject = object["data"] as? [[String: Any]] {
            panes = dataObject
        } else if let dataObject = object["data"] as? [String: Any],
            let nested = dataObject["panes"] as? [[String: Any]]
        {
            panes = nested
        } else {
            return nil
        }
        let focused = panes.first { ($0["active"] as? Bool) == true } ?? panes.first
        guard let path = focused?["cwd"] as? String, !path.isEmpty else {
            return nil
        }
        return WorkspacePathResolver.existingDirectory(
            at: URL(fileURLWithPath: path, isDirectory: true)
        ) ?? URL(fileURLWithPath: path, isDirectory: true)
    }

    static func recentDirectories(fromJSON data: Data, limit: Int) -> [URL] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data),
            let object = root as? [String: Any]
        else {
            return []
        }
        let entries: [[String: Any]]
        if let dataObject = object["data"] as? [String: Any],
            let listed = dataObject["entries"] as? [[String: Any]]
        {
            entries = listed
        } else if let listed = object["entries"] as? [[String: Any]] {
            entries = listed
        } else {
            return []
        }
        var result: [URL] = []
        for entry in entries {
            guard let path = entry["path"] as? String, !path.isEmpty else {
                continue
            }
            let url = URL(fileURLWithPath: path, isDirectory: true)
                .standardizedFileURL
            if !result.contains(where: { $0.path == url.path }) {
                result.append(url)
            }
            if result.count == limit {
                break
            }
        }
        return result
    }
}

struct OttyDirectoryReader {
    var commandLineURL: URL?
    var runJSON: (URL, [String]) -> Data?

    func focusedDirectory() -> URL? {
        guard
            let commandLineURL,
            let data = runJSON(commandLineURL, ["--json", "pane", "list"])
        else {
            return nil
        }
        return OttyDirectoryParser.focusedDirectory(fromJSON: data)
    }

    func recentDirectories(limit: Int = WorkspaceRecentProjectList.maxCount)
        -> [URL]
    {
        guard
            let commandLineURL,
            let data = runJSON(
                commandLineURL,
                ["--json", "jump:ls", String(limit)]
            )
        else {
            return []
        }
        return OttyDirectoryParser.recentDirectories(fromJSON: data, limit: limit)
    }

    static func makeDefault(
        fileManager: FileManager = .default,
        workspace: NSWorkspace = .shared
    ) -> OttyDirectoryReader {
        OttyDirectoryReader(
            commandLineURL: Self.commandLineURL(
                fileManager: fileManager,
                workspace: workspace
            ),
            runJSON: Self.runJSON(executableURL:arguments:)
        )
    }

    static func commandLineURL(
        fileManager: FileManager = .default,
        workspace: NSWorkspace = .shared
    ) -> URL? {
        let applicationURL = workspace.urlForApplication(
            withBundleIdentifier: FrontmostAppContext.ottyBundleIdentifier
        ) ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Otty.app", isDirectory: true)
        let candidates = [
            applicationURL,
            URL(fileURLWithPath: "/Applications/Otty.app", isDirectory: true),
        ].compactMap { $0 }
        for applicationURL in candidates {
            let commandLineURL = applicationURL.appendingPathComponent(
                "Contents/MacOS/otty-cli"
            )
            if fileManager.isExecutableFile(atPath: commandLineURL.path) {
                return commandLineURL
            }
        }
        return nil
    }

    static func runJSON(executableURL: URL, arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let deadline = Date().addingTimeInterval(1.2)
        while process.isRunning, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        return pipe.fileHandleForReading.readDataToEndOfFile()
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
    private let ottyDirectoryProvider: () -> URL?

    init(
        fileManager: FileManager = .default,
        finderPathResolver: FinderPathResolver = FinderPathResolver(),
        ottyDirectoryProvider: @escaping () -> URL? = {
            OttyDirectoryReader.makeDefault().focusedDirectory()
        }
    ) {
        self.fileManager = fileManager
        self.finderPathResolver = finderPathResolver
        self.ottyDirectoryProvider = ottyDirectoryProvider
    }

    func resolveFrontmostPath(
        from context: FrontmostAppContext
    ) -> WorkspaceContext? {
        let finderDirectory = context.isFinder
            ? finderPathResolver.currentDirectoryURL()
            : nil
        let ottyDirectory = context.isOtty ? ottyDirectoryProvider() : nil
        let accessibilityDirectory: URL?
        if !context.isFinder, !context.isOtty,
            let processIdentifier = context.processIdentifier,
            let documentURL = accessibilityDocumentURL(
                processIdentifier: processIdentifier
            )
        {
            accessibilityDirectory = projectDirectory(for: documentURL)
        } else {
            accessibilityDirectory = nil
        }

        let probe = WorkspacePathProbe(
            frontmost: context,
            finderDirectory: finderDirectory,
            ottyDirectory: ottyDirectory,
            accessibilityDirectory: accessibilityDirectory
        )
        guard let resolved = WorkspacePathResolutionPolicy.resolve(probe) else {
            return nil
        }
        return WorkspaceContext(
            directoryURL: resolved.directoryURL,
            source: resolved.source,
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
    case otty(applicationURL: URL, commandLineURL: URL)
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
                        launchStrategy: .otty(
                            applicationURL: ottyApplicationURL,
                            commandLineURL: commandLineURL
                        )
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

enum AgentProcessCompletionMode: Sendable {
    case launchGrace(Duration)
    case waitForTermination
}

enum AgentProcessRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        agentName: String,
        completionMode: AgentProcessCompletionMode
    ) async throws {
        let process = AgentProcess.make(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectory: workingDirectory
        )
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        switch completionMode {
        case let .launchGrace(duration):
            try process.run()
            try await Task.sleep(for: duration)
            guard !process.isRunning else { return }
            try validateTermination(process, agentName: agentName)

        case .waitForTermination:
            try Task.checkCancellation()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Void, Error>) in
                    process.terminationHandler = { completedProcess in
                        do {
                            try validateTermination(
                                completedProcess,
                                agentName: agentName
                            )
                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                    do {
                        try process.run()
                        if Task.isCancelled, process.isRunning {
                            process.terminate()
                        }
                    } catch {
                        process.terminationHandler = nil
                        continuation.resume(throwing: error)
                    }
                }
                try Task.checkCancellation()
            } onCancel: {
                if process.isRunning {
                    process.terminate()
                }
            }
        }
    }

    private static func validateTermination(
        _ process: Process,
        agentName: String
    ) throws {
        guard process.terminationStatus == 0 else {
            throw AgentLaunchError.processFailed(
                agentName: agentName,
                status: process.terminationStatus
            )
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
            try await AgentProcessRunner.run(
                executableURL: executableURL,
                arguments: leadingArguments + [projectDirectory.path],
                workingDirectory: projectDirectory,
                agentName: agent.displayName,
                completionMode: .launchGrace(.milliseconds(300))
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
        case let .otty(applicationURL, commandLineURL):
            let isRunning = !NSRunningApplication.runningApplications(
                withBundleIdentifier: "io.appmakes.otty"
            ).isEmpty
            if isRunning {
                try await CustomWorkspaceAppLauncher.openApplication(
                    at: applicationURL
                )
            }
            try await AgentProcessRunner.run(
                executableURL: commandLineURL,
                arguments: TerminalLaunchCommand.ottyArguments(
                    toolURL: toolURL,
                    projectDirectory: projectDirectory,
                    isRunning: isRunning
                ),
                workingDirectory: projectDirectory,
                agentName: agentName,
                completionMode: .waitForTermination
            )
        case .terminalAppleScript:
            try await AgentProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
                arguments: TerminalLaunchCommand.terminalAppleScriptArguments(
                    toolURL: toolURL,
                    projectDirectory: projectDirectory
                ),
                workingDirectory: projectDirectory,
                agentName: agentName,
                completionMode: .waitForTermination
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
        projectDirectory: URL,
        isRunning: Bool
    ) -> [String] {
        guard isRunning else {
            return [
                "open",
                "--command",
                command(toolURL: toolURL),
                projectDirectory.path,
            ]
        }
        return [
            "tab",
            "new",
            "--cwd",
            projectDirectory.path,
            "--command",
            command(toolURL: toolURL),
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
                    if (count of windows) > 0 then
                        set targetTab to make new tab at end of tabs of front window
                        do script shellCommand in targetTab
                    else
                        do script shellCommand
                    end if
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
