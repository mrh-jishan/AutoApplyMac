import Foundation

public final class AppPaths {
    public static let shared = AppPaths()
    
    public let appSupportDir: URL
    public let databaseDir: URL
    public let resumesDir: URL
    public let screenshotsDir: URL
    public let logsDir: URL
    
    public var databaseFilePath: String {
        return databaseDir.appendingPathComponent("autoapply.sqlite").path
    }
    
    public var hasCompletedSetup: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "hasCompletedSetup")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "hasCompletedSetup")
        }
    }
    
    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.appSupportDir = appSupport.appendingPathComponent("AutoApplyPro", isDirectory: true)
        self.databaseDir = appSupportDir.appendingPathComponent("database", isDirectory: true)
        self.resumesDir = appSupportDir.appendingPathComponent("resumes", isDirectory: true)
        self.screenshotsDir = appSupportDir.appendingPathComponent("screenshots", isDirectory: true)
        self.logsDir = appSupportDir.appendingPathComponent("logs", isDirectory: true)
        
        // Ensure all sandbox directories exist
        try? fileManager.createDirectory(at: databaseDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: resumesDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: screenshotsDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)
    }
    
    public func userHomeDir() -> URL {
        return FileManager.default.homeDirectoryForCurrentUser
    }
    
    public func userDesktopDir() -> URL {
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? userHomeDir().appendingPathComponent("Desktop")
    }
}
