import Foundation
import SQLite3

public final class DatabaseManager {
    public static let shared = DatabaseManager()
    
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.autoapply.database", qos: .userInitiated)
    
    public let dbPath: String
    
    private init() {
        self.dbPath = AppPaths.shared.databaseFilePath
        openDatabase()
        createTables()
    }
    
    private func openDatabase() {
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            print("Error opening database at \(dbPath): \(String(cString: sqlite3_errmsg(db)))")
        } else {
            print("Successfully connected to SQLite database at \(dbPath)")
        }
    }
    
    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }
    
    private func createTables() {
        let schema = """
        PRAGMA journal_mode = WAL;
        
        CREATE TABLE IF NOT EXISTS companies (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL UNIQUE COLLATE NOCASE,
            domain TEXT,
            careers_portal TEXT,
            application_count INTEGER DEFAULT 0,
            max_allowed INTEGER DEFAULT 2,
            is_blocked INTEGER DEFAULT 0,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS job_postings (
            id TEXT PRIMARY KEY,
            portal_source TEXT NOT NULL,
            external_job_id TEXT,
            company_name TEXT NOT NULL,
            title TEXT NOT NULL,
            url TEXT NOT NULL UNIQUE,
            location_raw TEXT,
            is_remote INTEGER DEFAULT 1,
            salary_min REAL,
            salary_max REAL,
            description_text TEXT,
            matched_resume TEXT,
            status TEXT DEFAULT 'discovered',
            discard_reason TEXT,
            discovered_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS applications (
            id TEXT PRIMARY KEY,
            company_name TEXT NOT NULL,
            job_title TEXT NOT NULL,
            req_id TEXT,
            url TEXT NOT NULL,
            resume_path TEXT NOT NULL,
            status TEXT NOT NULL,
            confirmation_url TEXT,
            confirmation_text TEXT,
            review_screenshot TEXT,
            submitted_screenshot TEXT,
            evidence TEXT,
            submitted_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS outreach_campaigns (
            id TEXT PRIMARY KEY,
            company_name TEXT NOT NULL,
            recruiter_name TEXT NOT NULL,
            recruiter_title TEXT,
            recruiter_email TEXT,
            linkedin_url TEXT,
            role_targeted TEXT,
            resume_attached TEXT NOT NULL,
            email_status TEXT DEFAULT 'pending',
            linkedin_status TEXT DEFAULT 'pending',
            sent_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS candidate_profile (
            id TEXT PRIMARY KEY,
            full_name TEXT NOT NULL,
            email TEXT NOT NULL,
            phone TEXT NOT NULL,
            address TEXT,
            city TEXT,
            state TEXT,
            postal_code TEXT,
            country TEXT DEFAULT 'United States',
            is_us_citizen INTEGER DEFAULT 1,
            requires_sponsorship INTEGER DEFAULT 0,
            linkedin_url TEXT,
            github_url TEXT,
            portfolio_url TEXT,
            profession TEXT,
            target_titles TEXT,
            only_remote INTEGER DEFAULT 1,
            require_approval INTEGER DEFAULT 1,
            resumes_json TEXT,
            eeoc_gender TEXT,
            eeoc_race TEXT,
            eeoc_veteran TEXT,
            eeoc_disability TEXT,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );

        CREATE INDEX IF NOT EXISTS idx_postings_status ON job_postings(status);
        CREATE INDEX IF NOT EXISTS idx_postings_portal ON job_postings(portal_source);
        CREATE INDEX IF NOT EXISTS idx_applications_company ON applications(company_name);
        """
        
        queue.sync {
            var errMsg: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, schema, nil, nil, &errMsg) != SQLITE_OK {
                if let err = errMsg {
                    print("Error creating tables: \(String(cString: err))")
                    sqlite3_free(errMsg)
                }
            }
        }
    }
    
    // MARK: - Companies & Saturation Guard
    
    public func isCompanySaturated(_ companyName: String) -> Bool {
        return queue.sync {
            let sql = "SELECT application_count, max_allowed, is_blocked FROM companies WHERE name = ? COLLATE NOCASE;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (companyName as NSString).utf8String, -1, nil)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    let count = Int(sqlite3_column_int(stmt, 0))
                    let maxAllowed = Int(sqlite3_column_int(stmt, 1))
                    let isBlocked = sqlite3_column_int(stmt, 2) != 0
                    sqlite3_finalize(stmt)
                    return isBlocked || count >= maxAllowed
                }
            }
            sqlite3_finalize(stmt)
            return false
        }
    }
    
    public func incrementCompanyApplicationCount(_ companyName: String) {
        queue.sync {
            let sql = """
            INSERT INTO companies (id, name, application_count) 
            VALUES (?, ?, 1)
            ON CONFLICT(name) DO UPDATE SET 
                application_count = application_count + 1,
                updated_at = CURRENT_TIMESTAMP;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                let id = UUID().uuidString
                sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (companyName as NSString).utf8String, -1, nil)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }
    
    // MARK: - Job Postings
    
    public func insertJobPosting(_ job: JobPosting) -> Bool {
        return queue.sync {
            let sql = """
            INSERT OR IGNORE INTO job_postings 
            (id, portal_source, external_job_id, company_name, title, url, location_raw, is_remote, salary_min, salary_max, description_text, matched_resume, status, discard_reason)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            var success = false
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (job.id as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (job.portalSource.rawValue as NSString).utf8String, -1, nil)
                if let ext = job.externalJobId { sqlite3_bind_text(stmt, 3, (ext as NSString).utf8String, -1, nil) }
                sqlite3_bind_text(stmt, 4, (job.companyName as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 5, (job.title as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 6, (job.url as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 7, (job.locationRaw as NSString).utf8String, -1, nil)
                sqlite3_bind_int(stmt, 8, job.isRemote ? 1 : 0)
                if let min = job.salaryMin { sqlite3_bind_double(stmt, 9, min) }
                if let max = job.salaryMax { sqlite3_bind_double(stmt, 10, max) }
                sqlite3_bind_text(stmt, 11, (job.descriptionText as NSString).utf8String, -1, nil)
                if let resume = job.matchedResume { sqlite3_bind_text(stmt, 12, (resume as NSString).utf8String, -1, nil) }
                sqlite3_bind_text(stmt, 13, (job.status.rawValue as NSString).utf8String, -1, nil)
                if let r = job.discardReason { sqlite3_bind_text(stmt, 14, (r as NSString).utf8String, -1, nil) }
                
                if sqlite3_step(stmt) == SQLITE_DONE {
                    success = true
                }
            }
            sqlite3_finalize(stmt)
            return success
        }
    }
    
    public func fetchQueuedJobs(portal: PortalSource? = nil) -> [JobPosting] {
        return queue.sync {
            var sql = "SELECT id, portal_source, external_job_id, company_name, title, url, location_raw, is_remote, salary_min, salary_max, description_text, matched_resume, status, discard_reason FROM job_postings WHERE status IN ('discovered', 'queued')"
            if let portal = portal {
                sql += " AND portal_source = '\(portal.rawValue)'"
            }
            sql += " ORDER BY discovered_at DESC;"
            
            var list: [JobPosting] = []
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = String(cString: sqlite3_column_text(stmt, 0))
                    let portalRaw = String(cString: sqlite3_column_text(stmt, 1))
                    let extId = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
                    let company = String(cString: sqlite3_column_text(stmt, 3))
                    let title = String(cString: sqlite3_column_text(stmt, 4))
                    let url = String(cString: sqlite3_column_text(stmt, 5))
                    let location = String(cString: sqlite3_column_text(stmt, 6))
                    let isRemote = sqlite3_column_int(stmt, 7) != 0
                    let desc = sqlite3_column_text(stmt, 10).map { String(cString: $0) } ?? ""
                    let resume = sqlite3_column_text(stmt, 11).map { String(cString: $0) }
                    let statusRaw = String(cString: sqlite3_column_text(stmt, 12))
                    
                    let posting = JobPosting(
                        id: id,
                        portalSource: PortalSource(rawValue: portalRaw) ?? .direct,
                        externalJobId: extId,
                        companyName: company,
                        title: title,
                        url: url,
                        locationRaw: location,
                        isRemote: isRemote,
                        descriptionText: desc,
                        matchedResume: resume,
                        status: JobStatus(rawValue: statusRaw) ?? .discovered
                    )
                    list.append(posting)
                }
            }
            sqlite3_finalize(stmt)
            return list
        }
    }
    
    public func fetchPortalCounts() -> [PortalSource: Int] {
        return queue.sync {
            var counts: [PortalSource: Int] = [:]
            for p in PortalSource.allCases { counts[p] = 0 }
            
            let sql = "SELECT portal_source, COUNT(*) FROM job_postings WHERE status IN ('discovered', 'queued') GROUP BY portal_source;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let raw = String(cString: sqlite3_column_text(stmt, 0))
                    let cnt = Int(sqlite3_column_int(stmt, 1))
                    if let source = PortalSource(rawValue: raw) {
                        counts[source] = cnt
                    }
                }
            }
            sqlite3_finalize(stmt)
            return counts
        }
    }
    
    // MARK: - Applications
    
    public func recordApplication(_ app: ApplicationRecord) {
        queue.sync {
            let sql = """
            INSERT OR REPLACE INTO applications 
            (id, company_name, job_title, req_id, url, resume_path, status, confirmation_url, confirmation_text, review_screenshot, submitted_screenshot, evidence, submitted_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (app.id as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (app.companyName as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 3, (app.jobTitle as NSString).utf8String, -1, nil)
                if let req = app.reqId { sqlite3_bind_text(stmt, 4, (req as NSString).utf8String, -1, nil) }
                sqlite3_bind_text(stmt, 5, (app.url as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 6, (app.resumePath as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 7, (app.status as NSString).utf8String, -1, nil)
                if let cUrl = app.confirmationUrl { sqlite3_bind_text(stmt, 8, (cUrl as NSString).utf8String, -1, nil) }
                if let cText = app.confirmationText { sqlite3_bind_text(stmt, 9, (cText as NSString).utf8String, -1, nil) }
                if let rev = app.reviewScreenshot { sqlite3_bind_text(stmt, 10, (rev as NSString).utf8String, -1, nil) }
                if let sub = app.submittedScreenshot { sqlite3_bind_text(stmt, 11, (sub as NSString).utf8String, -1, nil) }
                sqlite3_bind_text(stmt, 12, (app.evidence as NSString).utf8String, -1, nil)
                
                let isoFormatter = ISO8601DateFormatter()
                let dateStr = isoFormatter.string(from: app.submittedAt)
                sqlite3_bind_text(stmt, 13, (dateStr as NSString).utf8String, -1, nil)
                
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
        incrementCompanyApplicationCount(app.companyName)
    }
    
    public func fetchApplications() -> [ApplicationRecord] {
        return queue.sync {
            let sql = "SELECT id, company_name, job_title, req_id, url, resume_path, status, confirmation_url, confirmation_text, review_screenshot, submitted_screenshot, evidence, submitted_at FROM applications ORDER BY submitted_at DESC;"
            var list: [ApplicationRecord] = []
            var stmt: OpaquePointer?
            let isoFormatter = ISO8601DateFormatter()
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = String(cString: sqlite3_column_text(stmt, 0))
                    let company = String(cString: sqlite3_column_text(stmt, 1))
                    let title = String(cString: sqlite3_column_text(stmt, 2))
                    let reqId = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
                    let url = String(cString: sqlite3_column_text(stmt, 4))
                    let resume = String(cString: sqlite3_column_text(stmt, 5))
                    let status = String(cString: sqlite3_column_text(stmt, 6))
                    let cUrl = sqlite3_column_text(stmt, 7).map { String(cString: $0) }
                    let cText = sqlite3_column_text(stmt, 8).map { String(cString: $0) }
                    let rev = sqlite3_column_text(stmt, 9).map { String(cString: $0) }
                    let sub = sqlite3_column_text(stmt, 10).map { String(cString: $0) }
                    let ev = sqlite3_column_text(stmt, 11).map { String(cString: $0) } ?? ""
                    let dateStr = String(cString: sqlite3_column_text(stmt, 12))
                    let date = isoFormatter.date(from: dateStr) ?? Date()
                    
                    list.append(ApplicationRecord(
                        id: id,
                        companyName: company,
                        jobTitle: title,
                        reqId: reqId,
                        url: url,
                        resumePath: resume,
                        status: status,
                        confirmationUrl: cUrl,
                        confirmationText: cText,
                        reviewScreenshot: rev,
                        submittedScreenshot: sub,
                        evidence: ev,
                        submittedAt: date
                    ))
                }
            }
            sqlite3_finalize(stmt)
            return list
        }
    }
    
    // MARK: - Outreach
    
    public func recordOutreach(_ o: OutreachRecord) {
        queue.sync {
            let sql = """
            INSERT OR REPLACE INTO outreach_campaigns
            (id, company_name, recruiter_name, recruiter_title, recruiter_email, linkedin_url, role_targeted, resume_attached, email_status, linkedin_status, sent_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (o.id as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (o.companyName as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 3, (o.recruiterName as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 4, (o.recruiterTitle as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 5, (o.recruiterEmail as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 6, (o.linkedinUrl as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 7, (o.roleTargeted as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 8, (o.resumeAttached as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 9, (o.emailStatus as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 10, (o.linkedinStatus as NSString).utf8String, -1, nil)
                
                let isoFormatter = ISO8601DateFormatter()
                let dateStr = isoFormatter.string(from: o.sentAt)
                sqlite3_bind_text(stmt, 11, (dateStr as NSString).utf8String, -1, nil)
                
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }
    
    public func fetchOutreachRecords() -> [OutreachRecord] {
        return queue.sync {
            let sql = "SELECT id, company_name, recruiter_name, recruiter_title, recruiter_email, linkedin_url, role_targeted, resume_attached, email_status, linkedin_status, sent_at FROM outreach_campaigns ORDER BY sent_at DESC;"
            var list: [OutreachRecord] = []
            var stmt: OpaquePointer?
            let isoFormatter = ISO8601DateFormatter()
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = String(cString: sqlite3_column_text(stmt, 0))
                    let company = String(cString: sqlite3_column_text(stmt, 1))
                    let name = String(cString: sqlite3_column_text(stmt, 2))
                    let title = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
                    let email = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
                    let lUrl = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? ""
                    let role = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? ""
                    let resume = String(cString: sqlite3_column_text(stmt, 7))
                    let eStatus = String(cString: sqlite3_column_text(stmt, 8))
                    let lStatus = String(cString: sqlite3_column_text(stmt, 9))
                    let dateStr = String(cString: sqlite3_column_text(stmt, 10))
                    let date = isoFormatter.date(from: dateStr) ?? Date()
                    
                    list.append(OutreachRecord(
                        id: id,
                        companyName: company,
                        recruiterName: name,
                        recruiterTitle: title,
                        recruiterEmail: email,
                        linkedinUrl: lUrl,
                        resumeAttached: resume,
                        roleTargeted: role,
                        emailStatus: eStatus,
                        linkedinStatus: lStatus,
                        sentAt: date
                    ))
                }
            }
            sqlite3_finalize(stmt)
            return list
        }
    }
    
    // MARK: - Candidate Profile
    
    public func saveProfile(_ p: CandidateProfile) {
        queue.sync {
            let sql = """
            INSERT OR REPLACE INTO candidate_profile 
            (id, full_name, email, phone, address, city, state, postal_code, country, is_us_citizen, requires_sponsorship, linkedin_url, github_url, portfolio_url, profession, target_titles, only_remote, require_approval, resumes_json, eeoc_gender, eeoc_race, eeoc_veteran, eeoc_disability, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP);
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (p.id as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (p.fullName as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 3, (p.email as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 4, (p.phone as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 5, (p.address as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 6, (p.city as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 7, (p.state as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 8, (p.postalCode as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 9, (p.country as NSString).utf8String, -1, nil)
                sqlite3_bind_int(stmt, 10, p.isUSCitizen ? 1 : 0)
                sqlite3_bind_int(stmt, 11, p.requiresSponsorship ? 1 : 0)
                sqlite3_bind_text(stmt, 12, (p.linkedinURL as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 13, (p.githubURL as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 14, (p.portfolioURL as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 15, (p.profession as NSString).utf8String, -1, nil)
                
                let titlesStr = p.targetJobTitles.joined(separator: "|")
                sqlite3_bind_text(stmt, 16, (titlesStr as NSString).utf8String, -1, nil)
                sqlite3_bind_int(stmt, 17, p.only100PercentRemote ? 1 : 0)
                sqlite3_bind_int(stmt, 18, p.requireApprovalBeforeSubmit ? 1 : 0)
                
                let resumesData = (try? JSONEncoder().encode(p.resumes)) ?? Data()
                let resumesJson = String(data: resumesData, encoding: .utf8) ?? "[]"
                sqlite3_bind_text(stmt, 19, (resumesJson as NSString).utf8String, -1, nil)
                
                sqlite3_bind_text(stmt, 20, (p.eeocGender as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 21, (p.eeocRace as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 22, (p.eeocVeteran as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 23, (p.eeocDisability as NSString).utf8String, -1, nil)
                
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }
    
    public func fetchProfile() -> CandidateProfile? {
        return queue.sync {
            let sql = "SELECT id, full_name, email, phone, address, city, state, postal_code, country, is_us_citizen, requires_sponsorship, linkedin_url, github_url, portfolio_url, profession, target_titles, only_remote, require_approval, resumes_json, eeoc_gender, eeoc_race, eeoc_veteran, eeoc_disability FROM candidate_profile LIMIT 1;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    var p = CandidateProfile()
                    p.id = String(cString: sqlite3_column_text(stmt, 0))
                    p.fullName = String(cString: sqlite3_column_text(stmt, 1))
                    p.email = String(cString: sqlite3_column_text(stmt, 2))
                    p.phone = String(cString: sqlite3_column_text(stmt, 3))
                    p.address = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
                    p.city = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? ""
                    p.state = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? ""
                    p.postalCode = sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? ""
                    p.country = sqlite3_column_text(stmt, 8).map { String(cString: $0) } ?? "United States"
                    p.isUSCitizen = sqlite3_column_int(stmt, 9) != 0
                    p.requiresSponsorship = sqlite3_column_int(stmt, 10) != 0
                    p.linkedinURL = sqlite3_column_text(stmt, 11).map { String(cString: $0) } ?? ""
                    p.githubURL = sqlite3_column_text(stmt, 12).map { String(cString: $0) } ?? ""
                    p.portfolioURL = sqlite3_column_text(stmt, 13).map { String(cString: $0) } ?? ""
                    p.profession = sqlite3_column_text(stmt, 14).map { String(cString: $0) } ?? "General"
                    
                    if let titlesRaw = sqlite3_column_text(stmt, 15) {
                        p.targetJobTitles = String(cString: titlesRaw).components(separatedBy: "|").filter { !$0.isEmpty }
                    }
                    p.only100PercentRemote = sqlite3_column_int(stmt, 16) != 0
                    p.requireApprovalBeforeSubmit = sqlite3_column_int(stmt, 17) != 0
                    
                    if let resumesRaw = sqlite3_column_text(stmt, 18),
                       let data = String(cString: resumesRaw).data(using: .utf8),
                       let resumesList = try? JSONDecoder().decode([UserResume].self, from: data) {
                        p.resumes = resumesList
                    }
                    
                    p.eeocGender = sqlite3_column_text(stmt, 19).map { String(cString: $0) } ?? "Male"
                    p.eeocRace = sqlite3_column_text(stmt, 20).map { String(cString: $0) } ?? "Asian"
                    p.eeocVeteran = sqlite3_column_text(stmt, 21).map { String(cString: $0) } ?? "Not a protected veteran"
                    p.eeocDisability = sqlite3_column_text(stmt, 22).map { String(cString: $0) } ?? "No"
                    
                    sqlite3_finalize(stmt)
                    return p
                }
            }
            sqlite3_finalize(stmt)
            return nil
        }
    }
}
