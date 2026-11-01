import Foundation

public final class ResumeMatcher: @unchecked Sendable {
    public static let shared = ResumeMatcher()
    
    private init() {}
    
    /// Dynamically selects the best matching resume for a given job posting
    public func selectBestResume(title: String, description: String, candidateResumes: [UserResume] = []) -> String {
        // 1. If candidate has provided resumes
        if !candidateResumes.isEmpty {
            if candidateResumes.count == 1 {
                return candidateResumes[0].filePath
            }
            
            // Dynamic scoring across user's resumes
            let text = "\(title) \(description)".lowercased()
            var bestMatch: UserResume? = nil
            var highestScore = -1
            
            for r in candidateResumes {
                var score = 0
                let profTokens = r.detectedProfession.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 }
                for token in profTokens {
                    if text.contains(token) { score += 5 }
                }
                
                let nameTokens = r.name.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 }
                for token in nameTokens {
                    if text.contains(token) { score += 2 }
                }
                
                if r.isDefault {
                    score += 1 // Slight bias towards designated default if tied
                }
                
                if score > highestScore {
                    highestScore = score
                    bestMatch = r
                }
            }
            
            if let best = bestMatch, highestScore > 0 {
                return best.filePath
            }
            
            // Fallback to default or first registered resume
            if let defaultResume = candidateResumes.first(where: { $0.isDefault }) {
                return defaultResume.filePath
            }
            return candidateResumes[0].filePath
        }
        
        // 2. Check candidate profile registered in ProfileService
        let profileResumes = ProfileService.shared.profile.resumes
        if !profileResumes.isEmpty {
            return selectBestResume(title: title, description: description, candidateResumes: profileResumes)
        }
        
        // 3. Check App Support sandbox resumes directory
        if let files = try? FileManager.default.contentsOfDirectory(atPath: AppPaths.shared.resumesDir.path) {
            let pdfs = files.filter { $0.lowercased().hasSuffix(".pdf") }
            if let first = pdfs.first {
                return AppPaths.shared.resumesDir.appendingPathComponent(first).path
            }
        }
        
        // 4. Return empty if no resume exists anywhere
        return ""
    }
    
    /// Async semantic AI matching for high-precision role selection
    public func selectBestResumeAI(title: String, description: String, candidateResumes: [UserResume] = []) async -> String {
        let resumes = candidateResumes.isEmpty ? ProfileService.shared.profile.resumes : candidateResumes
        guard !resumes.isEmpty else { return selectBestResume(title: title, description: description) }
        
        if let aiResult = await AIAssistantService.shared.matchResumeWithAI(resumes: resumes, jobTitle: title, jobDescription: description) {
            print("AI matched resume: \(aiResult.matchedResume.name) (Score: \(aiResult.score)%) - \(aiResult.reason)")
            return aiResult.matchedResume.filePath
        }
        
        return selectBestResume(title: title, description: description, candidateResumes: resumes)
    }
}
