import Foundation

public final class LightpandaService: @unchecked Sendable {
    public static let shared = LightpandaService()
    
    public var binaryPath: String {
        // 1. Check bundled helper inside AutoApply.app/Contents/Helpers/lightpanda
        if let bundledURL = Bundle.main.url(forAuxiliaryExecutable: "lightpanda"),
           FileManager.default.isExecutableFile(atPath: bundledURL.path) {
            return bundledURL.path
        }
        
        let bundleHelper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/lightpanda").path
        if FileManager.default.isExecutableFile(atPath: bundleHelper) {
            return bundleHelper
        }
        
        // 2. Check user's home ~/.local/bin/lightpanda dynamically
        let localPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/lightpanda").path
        if FileManager.default.isExecutableFile(atPath: localPath) {
            return localPath
        }
        
        // 3. Common macOS binary paths
        let standardPaths = [
            "/opt/homebrew/bin/lightpanda",
            "/usr/local/bin/lightpanda",
            "/usr/bin/lightpanda"
        ]
        for p in standardPaths {
            if FileManager.default.isExecutableFile(atPath: p) {
                return p
            }
        }
        
        // 4. Dynamic search via login shell
        if let whichPath = AIAssistantService.shared.resolveCLIPath("lightpanda") {
            return whichPath
        }
        
        return localPath
    }
    
    private init() {}
    
    public var isAvailable: Bool {
        return FileManager.default.isExecutableFile(atPath: binaryPath)
    }
    
    public func fetchPage(url: String) async -> String? {
        guard isAvailable else {
            print("Lightpanda binary not found at \(binaryPath)")
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: self.binaryPath)
                process.arguments = ["fetch", url]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    if let output = String(data: data, encoding: .utf8) {
                        continuation.resume(returning: output)
                    } else {
                        continuation.resume(returning: nil)
                    }
                } catch {
                    print("Lightpanda process error: \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    // MARK: - Dynamic Matching Filter
    
    public func matchesRoleFilter(title: String) -> Bool {
        let lower = title.lowercased()
        let profile = ProfileService.shared.profile
        
        // If candidate configured specific target titles, match them
        if !profile.targetJobTitles.isEmpty {
            for target in profile.targetJobTitles {
                let targetTokens = target.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 }
                if targetTokens.allSatisfy({ lower.contains($0) }) || lower.contains(target.lowercased()) {
                    return true
                }
            }
            let allKeywords = profile.targetJobTitles.flatMap { $0.lowercased().components(separatedBy: " ") }.filter { $0.count > 3 }
            if allKeywords.contains(where: { lower.contains($0) }) {
                return true
            }
        }
        
        // If profession tokens are available
        if !profile.profession.isEmpty && profile.profession.lowercased() != "general" {
            let profTokens = profile.profession.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 3 }
            if profTokens.contains(where: { lower.contains($0) }) {
                return true
            }
        }
        
        // General default matching: non-intern, professional titles
        let defaultBroadMatches = ["senior", "lead", "specialist", "manager", "staff", "analyst", "director", "engineer", "coordinator", "consultant", "developer", "administrator"]
        return defaultBroadMatches.contains(where: { lower.contains($0) })
    }
    
    // MARK: - Multi-Portal Master Crawler
    
    public func crawlAllPortals(db: DatabaseManager) async -> (ashby: Int, greenhouse: Int, linkedin: Int, workday: Int, lever: Int) {
        // 1. Ashby Boards
        var ashbyCount = 0
        let ashbyTargets = ["vantage", "incident", "warp", "postman", "sentry", "retool", "neon", "axiom", "couchbase", "pagerduty"]
        for t in ashbyTargets {
            if !db.isCompanySaturated(t) {
                ashbyCount += await crawlAshbyBoard(orgSlug: t, db: db)
            }
        }
        
        // 2. Greenhouse Boards
        var greenhouseCount = 0
        let greenhouseTargets = ["stripe", "airbnb", "figma", "notion", "databricks", "gusto", "pinterest", "robinhood", "affirm"]
        for t in greenhouseTargets {
            if !db.isCompanySaturated(t) {
                greenhouseCount += await crawlGreenhouseBoard(boardSlug: t, db: db)
            }
        }
        
        // 3. LinkedIn Jobs
        let linkedinCount = await crawlLinkedInJobs(db: db)
        
        // 4. Workday Boards
        let workdayCount = await crawlWorkdayJobs(db: db)
        
        // 5. Lever Boards
        let leverCount = await crawlLeverJobs(db: db)
        
        return (ashbyCount, greenhouseCount, linkedinCount, workdayCount, leverCount)
    }
    
    // MARK: - Lever Jobs Crawler
    
    public func crawlLeverJobs(db: DatabaseManager) async -> Int {
        let leverTargets = ["palantir", "spotify", "rover", "wealthfront", "kinsta"]
        var totalAdded = 0
        for t in leverTargets {
            if !db.isCompanySaturated(t) {
                totalAdded += await crawlLeverBoard(boardSlug: t, db: db)
            }
        }
        return totalAdded
    }
    
    public func crawlLeverBoard(boardSlug: String, db: DatabaseManager) async -> Int {
        guard !db.isCompanySaturated(boardSlug) else { return 0 }
        
        let apiURL = "https://api.lever.co/v0/postings/\(boardSlug)?mode=json"
        guard let url = URL(string: apiURL),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return 0
        }
        
        var addedCount = 0
        let profile = ProfileService.shared.profile
        
        for j in json {
            guard let title = j["text"] as? String,
                  let id = j["id"] as? String,
                  let applyUrl = (j["applyUrl"] as? String) ?? (j["hostedUrl"] as? String) else { continue }
            
            let categories = j["categories"] as? [String: Any]
            let location = categories?["location"] as? String ?? "Remote US"
            let workplaceType = j["workplaceType"] as? String ?? ""
            let isRemote = workplaceType.lowercased() == "remote" || location.lowercased().contains("remote")
            
            guard matchesRoleFilter(title: title) else { continue }
            
            if profile.only100PercentRemote && !isRemote {
                continue
            }
            
            let desc = (j["descriptionPlain"] as? String) ?? ""
            
            let posting = JobPosting(
                id: UUID().uuidString,
                portalSource: .lever,
                externalJobId: id,
                companyName: boardSlug.capitalized,
                title: stripHTML(title),
                url: applyUrl,
                locationRaw: stripHTML(location),
                isRemote: isRemote,
                descriptionText: desc,
                status: .discovered
            )
            
            if db.insertJobPosting(posting) {
                addedCount += 1
            }
        }
        
        print("Scraped Lever [\(boardSlug)]: queued \(addedCount) matching roles")
        return addedCount
    }
    
    // MARK: - LinkedIn Jobs Crawler (Guest API)
    
    public func crawlLinkedInJobs(query: String? = nil, db: DatabaseManager) async -> Int {
        let profile = ProfileService.shared.profile
        let searchQuery = query ?? profile.targetJobTitles.first ?? (profile.profession.isEmpty || profile.profession == "General" ? "Software Engineer" : profile.profession)
        let encodedQuery = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "remote"
        
        var totalAdded = 0
        
        // Crawl first 2 pages (50 potential jobs)
        for pageStart in [0, 25] {
            let apiURL = "https://www.linkedin.com/jobs-guest/jobs/api/seeMoreJobPostings/search?keywords=\(encodedQuery)&location=United%20States&f_WT=2&start=\(pageStart)"
            guard let url = URL(string: apiURL) else { continue }
            
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
            
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let html = String(data: data, encoding: .utf8) else {
                continue
            }
            
            let cards = html.components(separatedBy: "<div class=\"base-card")
            guard cards.count > 1 else { continue }
            
            let titleRegex = try? NSRegularExpression(pattern: "<h3 class=\"base-search-card__title\">\\s*([\\s\\S]*?)\\s*</h3>", options: [.dotMatchesLineSeparators])
            let compRegex = try? NSRegularExpression(pattern: "<h4 class=\"base-search-card__subtitle\">[\\s\\S]*?(?:<a[^>]*>)?\\s*([\\s\\S]*?)\\s*(?:</a>)?\\s*</h4>", options: [.dotMatchesLineSeparators])
            let linkRegex = try? NSRegularExpression(pattern: "href=\"(https://www.linkedin.com/jobs/view/[^\"]+)\"", options: [])
            let locRegex = try? NSRegularExpression(pattern: "<span class=\"job-search-card__location\">\\s*([\\s\\S]*?)\\s*</span>", options: [.dotMatchesLineSeparators])
            
            for card in cards.dropFirst() {
                guard let titleRaw = extractFirstGroup(titleRegex, in: card),
                      let linkRaw = extractFirstGroup(linkRegex, in: card) else {
                    continue
                }
                
                // Strictly strip any HTML tags from title, company, and location
                let title = stripHTML(titleRaw)
                let compRaw = extractFirstGroup(compRegex, in: card) ?? "Company on LinkedIn"
                let company = stripHTML(compRaw)
                let locRaw = extractFirstGroup(locRegex, in: card) ?? "Remote US"
                let location = stripHTML(locRaw)
                
                // Clean link URL (strip tracking params)
                let cleanURL = linkRaw.components(separatedBy: "?").first ?? linkRaw
                
                // Filter by saturation guard
                guard !db.isCompanySaturated(company) else { continue }
                
                // Role match filter
                guard matchesRoleFilter(title: title) else { continue }
                
                let posting = JobPosting(
                    id: UUID().uuidString,
                    portalSource: .linkedin,
                    externalJobId: cleanURL.components(separatedBy: "-").last,
                    companyName: company,
                    title: title,
                    url: cleanURL,
                    locationRaw: location.isEmpty ? "Remote US" : location,
                    isRemote: true,
                    descriptionText: "Discovered via LinkedIn Guest Jobs API for '\(searchQuery)'",
                    status: .discovered
                )
                
                if db.insertJobPosting(posting) {
                    totalAdded += 1
                }
            }
        }
        
        print("Scraped LinkedIn: queued \(totalAdded) roles for query '\(searchQuery)'")
        return totalAdded
    }
    
    // MARK: - Workday Jobs Crawler (Public CXS API)
    
    public func crawlWorkdayJobs(query: String? = nil, db: DatabaseManager) async -> Int {
        let profile = ProfileService.shared.profile
        let searchQuery = query ?? profile.targetJobTitles.first ?? (profile.profession.isEmpty || profile.profession == "General" ? "remote" : profile.profession)
        
        struct WorkdayBoardDef {
            let companyName: String
            let cxsUrl: String
            let baseUrl: String
        }
        
        let boards: [WorkdayBoardDef] = [
            WorkdayBoardDef(companyName: "NVIDIA", cxsUrl: "https://nvidia.wd5.myworkdayjobs.com/wday/cxs/nvidia/NVIDIAExternalCareerSite/jobs", baseUrl: "https://nvidia.wd5.myworkdayjobs.com/en-US/NVIDIAExternalCareerSite"),
            WorkdayBoardDef(companyName: "Adobe", cxsUrl: "https://adobe.wd5.myworkdayjobs.com/wday/cxs/adobe/external_experienced/jobs", baseUrl: "https://adobe.wd5.myworkdayjobs.com/en-US/external_experienced"),
            WorkdayBoardDef(companyName: "Target", cxsUrl: "https://target.wd5.myworkdayjobs.com/wday/cxs/target/TargetCareers/jobs", baseUrl: "https://target.wd5.myworkdayjobs.com/en-US/TargetCareers"),
            WorkdayBoardDef(companyName: "Broadcom", cxsUrl: "https://broadcom.wd1.myworkdayjobs.com/wday/cxs/broadcom/External_Career/jobs", baseUrl: "https://broadcom.wd1.myworkdayjobs.com/en-US/External_Career"),
            WorkdayBoardDef(companyName: "Autodesk", cxsUrl: "https://autodesk.wd1.myworkdayjobs.com/wday/cxs/autodesk/Ext/jobs", baseUrl: "https://autodesk.wd1.myworkdayjobs.com/en-US/Ext")
        ]
        
        var totalAdded = 0
        
        for board in boards {
            guard !db.isCompanySaturated(board.companyName) else { continue }
            guard let url = URL(string: board.cxsUrl) else { continue }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")
            
            let body: [String: Any] = [
                "appliedFacets": [String: Any](),
                "limit": 20,
                "offset": 0,
                "searchText": searchQuery
            ]
            
            guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { continue }
            request.httpBody = httpBody
            
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let postings = json["jobPostings"] as? [[String: Any]] else {
                continue
            }
            
            for p in postings {
                guard let title = p["title"] as? String,
                      let externalPath = p["externalPath"] as? String else { continue }
                
                let locationsText = p["locationsText"] as? String ?? "Remote US"
                let bulletFields = p["bulletFields"] as? [String] ?? []
                let reqId = bulletFields.first
                
                guard matchesRoleFilter(title: title) else { continue }
                
                // Workday job URL
                let appURL = "\(board.baseUrl)\(externalPath)"
                
                let posting = JobPosting(
                    id: UUID().uuidString,
                    portalSource: .workday,
                    externalJobId: reqId,
                    companyName: board.companyName,
                    title: stripHTML(title),
                    url: appURL,
                    locationRaw: stripHTML(locationsText),
                    isRemote: true,
                    descriptionText: "Discovered via Workday CXS API for '\(searchQuery)'",
                    status: .discovered
                )
                
                if db.insertJobPosting(posting) {
                    totalAdded += 1
                }
            }
        }
        
        print("Scraped Workday: queued \(totalAdded) roles for query '\(searchQuery)'")
        return totalAdded
    }
    
    // MARK: - Ashby Board Crawler
    
    public func crawlAshbyBoard(orgSlug: String, db: DatabaseManager) async -> Int {
        guard !db.isCompanySaturated(orgSlug) else {
            return 0
        }
        
        let apiURL = "https://api.ashbyhq.com/posting-api/job-board/\(orgSlug)"
        guard let url = URL(string: apiURL),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jobs = json["jobs"] as? [[String: Any]] else {
            return 0
        }
        
        var addedCount = 0
        let profile = ProfileService.shared.profile
        
        for j in jobs {
            guard let title = j["title"] as? String,
                  let id = j["id"] as? String else { continue }
            
            let isRemote = j["isRemote"] as? Bool ?? false
            let location = j["location"] as? String ?? ""
            let lowerLoc = location.lowercased()
            
            guard matchesRoleFilter(title: title) else { continue }
            
            if profile.only100PercentRemote {
                let matchesRemote = isRemote || lowerLoc.contains("remote") || lowerLoc.contains("united states") || lowerLoc.contains("usa")
                guard matchesRemote else { continue }
                guard !lowerLoc.contains("hybrid") && !lowerLoc.contains("in-office") else { continue }
            }
            
            let appURL = "https://jobs.ashbyhq.com/\(orgSlug)/\(id)/application"
            let posting = JobPosting(
                id: UUID().uuidString,
                portalSource: .ashby,
                externalJobId: id,
                companyName: orgSlug.capitalized,
                title: stripHTML(title),
                url: appURL,
                locationRaw: location.isEmpty ? "Remote US" : stripHTML(location),
                isRemote: true,
                descriptionText: "",
                status: .discovered
            )
            
            if db.insertJobPosting(posting) {
                addedCount += 1
            }
        }
        
        return addedCount
    }
    
    // MARK: - Greenhouse Board Crawler
    
    public func crawlGreenhouseBoard(boardSlug: String, db: DatabaseManager) async -> Int {
        guard !db.isCompanySaturated(boardSlug) else {
            return 0
        }
        
        let apiURL = "https://boards-api.greenhouse.io/v1/boards/\(boardSlug)/jobs"
        guard let url = URL(string: apiURL),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jobs = json["jobs"] as? [[String: Any]] else {
            return 0
        }
        
        var addedCount = 0
        let profile = ProfileService.shared.profile
        
        for j in jobs {
            guard let title = j["title"] as? String,
                  let idInt = j["id"] as? Int else { continue }
            
            let locDict = j["location"] as? [String: Any]
            let location = locDict?["name"] as? String ?? ""
            let lowerLoc = location.lowercased()
            
            guard matchesRoleFilter(title: title) else { continue }
            
            if profile.only100PercentRemote {
                let matchesRemote = lowerLoc.contains("remote") || lowerLoc.contains("united states") || lowerLoc.contains("americas")
                guard matchesRemote else { continue }
                guard !lowerLoc.contains("hybrid") else { continue }
            }
            
            let appURL = "https://job-boards.greenhouse.io/\(boardSlug)/jobs/\(idInt)"
            let posting = JobPosting(
                id: UUID().uuidString,
                portalSource: .greenhouse,
                externalJobId: String(idInt),
                companyName: boardSlug.capitalized,
                title: stripHTML(title),
                url: appURL,
                locationRaw: location.isEmpty ? "Remote US" : stripHTML(location),
                isRemote: true,
                descriptionText: "",
                status: .discovered
            )
            
            if db.insertJobPosting(posting) {
                addedCount += 1
            }
        }
        
        return addedCount
    }
    
    // MARK: - HTML Utility Functions
    
    public func stripHTML(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) else {
            return unescapeHTML(text)
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let cleaned = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        return unescapeHTML(cleaned).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func extractFirstGroup(_ regex: NSRegularExpression?, in text: String) -> String? {
        guard let regex = regex else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1 {
            if let r = Range(match.range(at: 1), in: text) {
                return String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
    
    private func unescapeHTML(_ text: String) -> String {
        var res = text
        let entities = [
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&nbsp;": " "
        ]
        for (ent, val) in entities {
            res = res.replacingOccurrences(of: ent, with: val)
        }
        return res.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
