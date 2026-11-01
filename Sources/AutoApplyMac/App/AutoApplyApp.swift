import SwiftUI

@main
struct AutoApplyApp: App {
    init() {
        print("AutoApply macOS starting up...")
        let db = DatabaseManager.shared
        MigrationService.shared.runInitialMigrationIfNeeded(db: db)
    }
    
    var body: some Scene {
        WindowGroup {
            MainSplitView()
                .frame(minWidth: 1000, minHeight: 650)
                .navigationTitle("AutoApply Pro — Native macOS Job Automation")
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
