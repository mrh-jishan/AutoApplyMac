import Foundation
import PDFKit

public struct ParsedResume: Sendable {
    public var rawText: String
    public var suggestedName: String?
    public var suggestedEmail: String?
    public var suggestedPhone: String?
    public var suggestedLocation: String?
    public var suggestedLinkedIn: String?
    public var suggestedGitHub: String?
    public var suggestedPortfolio: String?
    public var detectedProfession: String
    public var seniority: String?
    public var keySkills: [String]
    public var suggestedTitles: [String]
    public var summary: String?
    public var localSavedPath: String
    
    public init(
        rawText: String,
        suggestedName: String? = nil,
        suggestedEmail: String? = nil,
        suggestedPhone: String? = nil,
        suggestedLocation: String? = nil,
        suggestedLinkedIn: String? = nil,
        suggestedGitHub: String? = nil,
        suggestedPortfolio: String? = nil,
        detectedProfession: String = "General",
        seniority: String? = nil,
        keySkills: [String] = [],
        suggestedTitles: [String] = [],
        summary: String? = nil,
        localSavedPath: String
    ) {
        self.rawText = rawText
        self.suggestedName = suggestedName
        self.suggestedEmail = suggestedEmail
        self.suggestedPhone = suggestedPhone
        self.suggestedLocation = suggestedLocation
        self.suggestedLinkedIn = suggestedLinkedIn
        self.suggestedGitHub = suggestedGitHub
        self.suggestedPortfolio = suggestedPortfolio
        self.detectedProfession = detectedProfession
        self.seniority = seniority
        self.keySkills = keySkills
        self.suggestedTitles = suggestedTitles
        self.summary = summary
        self.localSavedPath = localSavedPath
    }
}

public final class ResumeParser: @unchecked Sendable {
    public static let shared = ResumeParser()
    
    private init() {}
    
    /// Parses a PDF resume using AI Agent analysis (with local offline fallback)
    public func parsePDFAgent(at sourceURL: URL) async -> ParsedResume? {
        guard let fullText = extractText(from: sourceURL) else {
            return nil
        }
        
        let destURL = copyToLocalStorage(sourceURL: sourceURL)
        
        // 1. Attempt AI Parsing via Local CLI Agent or Gemini API
        if let ai = await AIAssistantService.shared.parseResumeWithAI(pdfText: fullText) {
            print("Successfully parsed resume with AI Agent: \(ai.fullName ?? "Unknown") [\(ai.profession ?? "General")]")
            return ParsedResume(
                rawText: fullText,
                suggestedName: ai.fullName,
                suggestedEmail: ai.email,
                suggestedPhone: ai.phone,
                suggestedLocation: ai.location,
                suggestedLinkedIn: ai.linkedinURL,
                suggestedGitHub: ai.githubURL,
                suggestedPortfolio: ai.portfolioURL,
                detectedProfession: ai.profession ?? "General",
                seniority: ai.seniority,
                keySkills: ai.keySkills ?? [],
                suggestedTitles: ai.targetJobTitles ?? [],
                summary: ai.summary,
                localSavedPath: destURL.path
            )
        }
        
        // 2. Offline Fallback using Native Heuristics
        print("Falling back to native offline regex/heuristic resume parser")
        return parseOffline(fullText: fullText, destURL: destURL)
    }
    
    /// Synchronous compatibility wrapper
    public func parsePDF(at sourceURL: URL) -> ParsedResume? {
        guard let fullText = extractText(from: sourceURL) else { return nil }
        let destURL = copyToLocalStorage(sourceURL: sourceURL)
        return parseOffline(fullText: fullText, destURL: destURL)
    }
    
    // MARK: - Helper Extraction
    
    private func extractText(from sourceURL: URL) -> String? {
        guard let pdf = PDFDocument(url: sourceURL) else {
            print("Failed to load PDFDocument at \(sourceURL)")
            return nil
        }
        
        var fullText = ""
        for i in 0..<pdf.pageCount {
            if let page = pdf.page(at: i), let pageText = page.string {
                fullText += pageText + "\n"
            }
        }
        return fullText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func copyToLocalStorage(sourceURL: URL) -> URL {
        let destName = sourceURL.lastPathComponent
        let destURL = AppPaths.shared.resumesDir.appendingPathComponent(destName)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try? FileManager.default.removeItem(at: destURL)
        }
        try? FileManager.default.copyItem(at: sourceURL, to: destURL)
        return destURL
    }
    
    private func parseOffline(fullText: String, destURL: URL) -> ParsedResume {
        let email = extractFirstMatch(pattern: "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}", in: fullText)
        let phone = extractFirstMatch(pattern: "\\(?\\d{3}\\)?[\\s.-]?\\d{3}[\\s.-]?\\d{4}", in: fullText)
        let linkedin = extractFirstMatch(pattern: "https?://(www\\.)?linkedin\\.com/in/[a-zA-Z0-9_-]+", in: fullText)
        let github = extractFirstMatch(pattern: "https?://(www\\.)?github\\.com/[a-zA-Z0-9_-]+", in: fullText)
        
        // Name heuristic: look at the top lines
        let lines = fullText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var detectedName: String? = nil
        for line in lines.prefix(5) {
            if !line.contains("@") && !line.contains("http") && line.components(separatedBy: " ").count >= 2 && line.components(separatedBy: " ").count <= 4 {
                detectedName = line
                break
            }
        }
        
        let lower = fullText.lowercased()
        var profession = "General / Professional"
        var titles = ["Specialist", "Manager", "Analyst"]
        
        let techCount = countKeywords(lower, ["software", "developer", "engineer", "sre", "cloud", "python", "kubernetes", "golang", "java", "backend", "frontend", "ios", "swift"])
        let healthCount = countKeywords(lower, ["nurse", "nursing", "patient", "clinical", "hospital", "healthcare", "medical", "doctor", "ehr", "triage"])
        let salesCount = countKeywords(lower, ["sales", "quota", "account executive", "sdr", "b2b", "revenue", "pipeline", "client", "crm", "closing"])
        let marketingCount = countKeywords(lower, ["marketing", "seo", "campaign", "social media", "content", "brand", "growth", "copywriter", "ads"])
        let financeCount = countKeywords(lower, ["finance", "accounting", "cpa", "gaap", "audit", "tax", "ledger", "budget", "financial", "treasury"])
        let legalCount = countKeywords(lower, ["attorney", "counsel", "legal", "compliance", "contract", "litigation", "paralegal", "regulatory"])
        
        let maxCount = max(techCount, healthCount, salesCount, marketingCount, financeCount, legalCount)
        if maxCount > 0 {
            if maxCount == techCount {
                profession = "Technology & Software"
                titles = ["Software Engineer", "Senior Engineer", "Tech Lead", "Platform Engineer", "Engineering Manager"]
            } else if maxCount == healthCount {
                profession = "Healthcare & Medicine"
                titles = ["Registered Nurse", "Clinical Specialist", "Nurse Practitioner", "Healthcare Manager"]
            } else if maxCount == salesCount {
                profession = "Sales & Business Development"
                titles = ["Account Executive", "Senior Account Executive", "Sales Manager", "Business Development Manager"]
            } else if maxCount == marketingCount {
                profession = "Marketing & Growth"
                titles = ["Marketing Manager", "Director of Marketing", "Growth Lead", "Brand Strategist"]
            } else if maxCount == financeCount {
                profession = "Finance & Accounting"
                titles = ["Financial Analyst", "Senior Accountant", "Accounting Manager", "Financial Controller"]
            } else if maxCount == legalCount {
                profession = "Legal & Compliance"
                titles = ["Corporate Counsel", "Compliance Manager", "Legal Counsel", "Contracts Specialist"]
            }
        }
        
        return ParsedResume(
            rawText: fullText,
            suggestedName: detectedName,
            suggestedEmail: email,
            suggestedPhone: phone,
            suggestedLinkedIn: linkedin,
            suggestedGitHub: github,
            detectedProfession: profession,
            suggestedTitles: titles,
            localSavedPath: destURL.path
        )
    }
    
    private func extractFirstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = regex.firstMatch(in: text, options: [], range: range),
           let matchRange = Range(match.range, in: text) {
            return String(text[matchRange])
        }
        return nil
    }
    
    private func countKeywords(_ text: String, _ keywords: [String]) -> Int {
        var c = 0
        for kw in keywords {
            if text.contains(kw) { c += 1 }
        }
        return c
    }
}
