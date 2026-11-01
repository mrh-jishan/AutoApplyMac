import Foundation

public final class MigrationService {
    public static let shared = MigrationService()
    
    private init() {}
    
    public func runInitialMigrationIfNeeded(db: DatabaseManager) {
        let applicationsJsonPath = AppPaths.shared.userDesktopDir().appendingPathComponent("job-applications/applications.json").path
        guard FileManager.default.fileExists(atPath: applicationsJsonPath) else {
            // Non-technical fresh user machine: start fresh
            return
        }
        
        let existingCount = db.fetchApplications().count
        if existingCount > 0 {
            print("SQLite database already populated with \(existingCount) applications. Skipping migration.")
            return
        }
        
        print("Starting initial migration from \(applicationsJsonPath) into SQLite...")
        
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: applicationsJsonPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let appsList = json["applications"] as? [[String: Any]] else {
            print("Failed to parse applications.json")
            return
        }
        
        let isoFormatter = ISO8601DateFormatter()
        var importedCount = 0
        
        for item in appsList {
            let id = item["id"] as? String ?? UUID().uuidString
            let company = item["company"] as? String ?? "Unknown"
            let title = item["title"] as? String ?? "Software Engineer"
            let reqId = item["req_id"] as? String
            let url = item["url"] as? String ?? ""
            let resume = item["resume"] as? String ?? ""
            let status = item["status"] as? String ?? "submitted"
            let evidence = item["evidence"] as? String ?? ""
            
            var submittedDate = Date()
            if let dateStr = item["submitted_at"] as? String, let parsed = isoFormatter.date(from: dateStr) {
                submittedDate = parsed
            } else if let dateStr = item["created_at"] as? String, let parsed = isoFormatter.date(from: dateStr) {
                submittedDate = parsed
            }
            
            let record = ApplicationRecord(
                id: id,
                companyName: company,
                jobTitle: title,
                reqId: reqId,
                url: url,
                resumePath: resume,
                status: status,
                confirmationUrl: url,
                confirmationText: "Imported from verified applications.json ledger",
                reviewScreenshot: nil,
                submittedScreenshot: nil,
                evidence: evidence,
                submittedAt: submittedDate
            )
            
            db.recordApplication(record)
            importedCount += 1
        }
        
        print("Successfully migrated \(importedCount) verified applications into autoapply.sqlite!")
    }
}
