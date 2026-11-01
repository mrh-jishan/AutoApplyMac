import Foundation
import PDFKit

public struct StructuredCandidateData: Codable {
    public var fullName: String?
    public var email: String?
    public var phone: String?
    public var location: String?
    public var linkedinURL: String?
    public var githubURL: String?
    public var portfolioURL: String?
    public var profession: String?
    public var seniority: String?
    public var keySkills: [String]?
    public var targetJobTitles: [String]?
    public var summary: String?
}

public enum AIAgentType: String, CaseIterable, Identifiable {
    case auto = "auto"
    case agy = "agy"
    case claude = "claude"
    case codex = "codex"
    case geminiApi = "gemini_api"
    case offline = "offline"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .auto: return "Auto-Detect Best Available (CLI or API)"
        case .agy: return "Google Antigravity CLI (agy)"
        case .claude: return "Claude Code CLI (claude)"
        case .codex: return "Codex CLI (codex)"
        case .geminiApi: return "Google Gemini API (Direct)"
        case .offline: return "Built-in Offline Parser (No AI / Local)"
        }
    }
}

public final class AIAssistantService: @unchecked Sendable {
    public static let shared = AIAssistantService()
    
    private init() {}
    
    // MARK: - Agent Discovery
    
    public func detectInstalledAgents() -> [String: String] {
        var detected: [String: String] = [:]
        
        let commonAgents = ["agy", "claude", "codex"]
        for agent in commonAgents {
            if let path = resolveCLIPath(agent) {
                detected[agent] = path
            }
        }
        
        return detected
    }
    
    public func resolveCLIPath(_ binaryName: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidatePaths = [
            "\(home)/.local/bin/\(binaryName)",
            "/opt/homebrew/bin/\(binaryName)",
            "/usr/local/bin/\(binaryName)",
            "/usr/bin/\(binaryName)"
        ]
        
        for path in candidatePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        
        // Dynamic search via login shell
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "which \(binaryName) 2>/dev/null"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus == 0, let output = String(data: data, encoding: .utf8) {
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && FileManager.default.isExecutableFile(atPath: trimmed) {
                    return trimmed
                }
            }
        } catch {}
        
        return nil
    }
    
    // MARK: - AI Execution Dispatcher
    
    public func runAIPrompt(_ prompt: String, preferredProvider: String? = nil, apiKey: String? = nil) async -> String? {
        let provider = preferredProvider ?? ProfileService.shared.profile.aiProvider
        
        switch provider {
        case "gemini_api":
            let key = (apiKey?.isEmpty == false ? apiKey : ProfileService.shared.profile.geminiApiKey) ?? ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""
            if !key.isEmpty {
                return await executeGeminiAPI(prompt: prompt, apiKey: key)
            }
            return await runAutoCLI(prompt: prompt)
            
        case "agy":
            if let path = resolveCLIPath("agy") {
                return await executeCLI(binaryPath: path, arguments: ["-p", prompt])
            }
            return await runAutoCLI(prompt: prompt)
            
        case "claude":
            if let path = resolveCLIPath("claude") {
                return await executeCLI(binaryPath: path, arguments: ["-p", prompt])
            }
            return await runAutoCLI(prompt: prompt)
            
        case "codex":
            if let path = resolveCLIPath("codex") {
                return await executeCLI(binaryPath: path, arguments: ["exec", prompt])
            }
            return await runAutoCLI(prompt: prompt)
            
        case "offline":
            return nil // Caller falls back to regex/PDFKit
            
        case "auto", _:
            return await runAutoCLI(prompt: prompt)
        }
    }
    
    private func runAutoCLI(prompt: String) async -> String? {
        // Priority 1: agy
        if let agy = resolveCLIPath("agy") {
            if let res = await executeCLI(binaryPath: agy, arguments: ["-p", prompt]), !res.isEmpty {
                return res
            }
        }
        
        // Priority 2: Gemini API if key exists
        let geminiKey = ProfileService.shared.profile.geminiApiKey.isEmpty ? (ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? "") : ProfileService.shared.profile.geminiApiKey
        if !geminiKey.isEmpty {
            if let res = await executeGeminiAPI(prompt: prompt, apiKey: geminiKey), !res.isEmpty {
                return res
            }
        }
        
        // Priority 3: claude
        if let claude = resolveCLIPath("claude") {
            if let res = await executeCLI(binaryPath: claude, arguments: ["-p", prompt]), !res.isEmpty {
                return res
            }
        }
        
        // Priority 4: codex
        if let codex = resolveCLIPath("codex") {
            if let res = await executeCLI(binaryPath: codex, arguments: ["exec", prompt]), !res.isEmpty {
                return res
            }
        }
        
        return nil
    }
    
    // MARK: - Process Execution (Login Shell)
    
    public func executeCLI(binaryPath: String, arguments: [String]) async -> String? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: binaryPath)
                process.arguments = arguments
                
                // Inherit user environment
                var env = ProcessInfo.processInfo.environment
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                env["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                env["HOME"] = home
                process.environment = env
                
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                
                do {
                    try process.run()
                    let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    
                    if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                        continuation.resume(returning: output)
                    } else {
                        continuation.resume(returning: nil)
                    }
                } catch {
                    print("CLI execution failed for \(binaryPath): \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    // MARK: - Gemini REST API
    
    public func executeGeminiAPI(prompt: String, apiKey: String) async -> String? {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=\(apiKey)") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.2,
                "responseMimeType": "application/json"
            ]
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = httpBody
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let candidates = json["candidates"] as? [[String: Any]],
               let firstCandidate = candidates.first,
               let content = firstCandidate["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let firstPart = parts.first,
               let text = firstPart["text"] as? String {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            print("Gemini API error: \(error)")
        }
        
        return nil
    }
    
    // MARK: - Resume Parsing via AI
    
    public func parseResumeWithAI(pdfText: String) async -> StructuredCandidateData? {
        let cleanText = String(pdfText.prefix(8000))
        let prompt = """
        You are an expert HR and candidate evaluation AI assistant.
        Parse the following resume text from any profession (e.g. Healthcare, Software, Marketing, Finance, Sales, Education, Operations, Legal, etc.).
        
        Extract the candidate's core details and respond with ONLY a raw JSON object (no markdown code blocks, no ```json formatting, no commentary) with exactly these keys:
        {
          "fullName": "Candidate full name",
          "email": "Email address",
          "phone": "Phone number",
          "location": "City, State or Country",
          "linkedinURL": "LinkedIn URL or empty",
          "githubURL": "GitHub or portfolio URL or empty",
          "portfolioURL": "Personal website or portfolio URL or empty",
          "profession": "Primary professional field (e.g. Healthcare & Nursing, Software Engineering, Sales & BD, Corporate Finance, Digital Marketing, Product Design)",
          "seniority": "Seniority level (e.g. Staff, Senior, Lead, Director, Entry, Mid)",
          "keySkills": ["skill1", "skill2", "skill3", "skill4", "skill5"],
          "targetJobTitles": ["Target Title 1", "Target Title 2", "Target Title 3", "Target Title 4"],
          "summary": "1-2 sentence executive summary of candidate experience"
        }

        Resume Text:
        \(cleanText)
        """
        
        guard let aiOutput = await runAIPrompt(prompt) else {
            return nil
        }
        
        // Clean possible markdown code fences if AI added them
        var jsonString = aiOutput
        if jsonString.hasPrefix("```") {
            let lines = jsonString.components(separatedBy: .newlines)
            let filtered = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
            jsonString = filtered.joined(separator: "\n")
        }
        
        guard let jsonData = jsonString.data(using: .utf8),
              let structured = try? JSONDecoder().decode(StructuredCandidateData.self, from: jsonData) else {
            print("Failed to decode structured candidate JSON from AI output: \(aiOutput)")
            return nil
        }
        
        return structured
    }
    
    // MARK: - Semantic Resume Matcher via AI
    
    public func matchResumeWithAI(resumes: [UserResume], jobTitle: String, jobDescription: String) async -> (matchedResume: UserResume, score: Int, reason: String)? {
        guard !resumes.isEmpty else { return nil }
        if resumes.count == 1 {
            return (resumes[0], 90, "Primary resume automatically selected.")
        }
        
        let resumeDescriptions = resumes.enumerated().map { idx, r in
            "[\(idx)] Name: \(r.name), Detected Profession: \(r.detectedProfession), Path: \(r.filePath)"
        }.joined(separator: "\n")
        
        let prompt = """
        You are an intelligent recruitment matching system.
        Evaluate which of the following candidate resumes best matches the job opening.

        Job Title: \(jobTitle)
        Job Description: \(String(jobDescription.prefix(1500)))

        Candidate Resumes:
        \(resumeDescriptions)

        Respond with ONLY a raw JSON object (no markdown, no backticks):
        {
          "selectedIndex": 0,
          "suitabilityScore": 85,
          "matchReason": "Short 1-sentence reason why this resume matches best"
        }
        """
        
        guard let output = await runAIPrompt(prompt) else {
            return nil
        }
        
        var cleanJson = output
        if cleanJson.hasPrefix("```") {
            let lines = cleanJson.components(separatedBy: .newlines)
            cleanJson = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }.joined(separator: "\n")
        }
        
        guard let data = cleanJson.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idx = json["selectedIndex"] as? Int,
              idx >= 0 && idx < resumes.count else {
            return nil
        }
        
        let score = json["suitabilityScore"] as? Int ?? 85
        let reason = json["matchReason"] as? String ?? "Best alignment with job requirements"
        return (resumes[idx], score, reason)
    }
}
