import Foundation

public struct UserResume: Codable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var filePath: String
    public var detectedProfession: String
    public var isDefault: Bool
    
    public init(id: String = UUID().uuidString, name: String, filePath: String, detectedProfession: String = "General", isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.filePath = filePath
        self.detectedProfession = detectedProfession
        self.isDefault = isDefault
    }
}

public struct CandidateProfile: Codable, Identifiable {
    public var id: String = "primary"
    public var fullName: String = ""
    public var email: String = ""
    public var phone: String = ""
    public var address: String = ""
    public var city: String = ""
    public var state: String = ""
    public var postalCode: String = ""
    public var country: String = "United States"
    public var isUSCitizen: Bool = true
    public var requiresSponsorship: Bool = false
    public var linkedinURL: String = ""
    public var githubURL: String = ""
    public var portfolioURL: String = ""
    
    // Profession & Targets
    public var profession: String = "General"
    public var targetJobTitles: [String] = []
    public var only100PercentRemote: Bool = true
    public var requireApprovalBeforeSubmit: Bool = true
    public var resumes: [UserResume] = []
    
    // AI Integration
    public var aiProvider: String = "auto"
    public var geminiApiKey: String = ""

    // EEOC standard defaults
    public var eeocGender: String = "Decline to self-identify"
    public var eeocRace: String = "Decline to self-identify"
    public var eeocVeteran: String = "Decline to self-identify"
    public var eeocDisability: String = "Decline to self-identify"

    public init(
        id: String = "primary",
        fullName: String = "",
        email: String = "",
        phone: String = "",
        address: String = "",
        city: String = "",
        state: String = "",
        postalCode: String = "",
        country: String = "United States",
        isUSCitizen: Bool = true,
        requiresSponsorship: Bool = false,
        linkedinURL: String = "",
        githubURL: String = "",
        portfolioURL: String = "",
        profession: String = "General",
        targetJobTitles: [String] = [],
        only100PercentRemote: Bool = true,
        requireApprovalBeforeSubmit: Bool = true,
        resumes: [UserResume] = [],
        aiProvider: String = "auto",
        geminiApiKey: String = "",
        eeocGender: String = "Decline to self-identify",
        eeocRace: String = "Decline to self-identify",
        eeocVeteran: String = "Decline to self-identify",
        eeocDisability: String = "Decline to self-identify"
    ) {
        self.id = id
        self.fullName = fullName
        self.email = email
        self.phone = phone
        self.address = address
        self.city = city
        self.state = state
        self.postalCode = postalCode
        self.country = country
        self.isUSCitizen = isUSCitizen
        self.requiresSponsorship = requiresSponsorship
        self.linkedinURL = linkedinURL
        self.githubURL = githubURL
        self.portfolioURL = portfolioURL
        self.profession = profession
        self.targetJobTitles = targetJobTitles
        self.only100PercentRemote = only100PercentRemote
        self.requireApprovalBeforeSubmit = requireApprovalBeforeSubmit
        self.resumes = resumes
        self.aiProvider = aiProvider
        self.geminiApiKey = geminiApiKey
        self.eeocGender = eeocGender
        self.eeocRace = eeocRace
        self.eeocVeteran = eeocVeteran
        self.eeocDisability = eeocDisability
    }
}

public enum PortalSource: String, Codable, CaseIterable, Identifiable {
    case googleJobs = "google_jobs"
    case linkedin = "linkedin"
    case workday = "workday"
    case greenhouse = "greenhouse"
    case ashby = "ashby"
    case lever = "lever"
    case direct = "direct"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .googleJobs: return "Google Jobs"
        case .linkedin: return "LinkedIn Jobs"
        case .workday: return "Workday"
        case .greenhouse: return "Greenhouse"
        case .ashby: return "Ashby"
        case .lever: return "Lever"
        case .direct: return "Direct Career Portal"
        }
    }
}

public enum JobStatus: String, Codable, CaseIterable {
    case discovered = "discovered"
    case queued = "queued"
    case evaluating = "evaluating"
    case applied = "applied"
    case discarded = "discarded"
}

public struct JobPosting: Codable, Identifiable, Hashable {
    public let id: String
    public var portalSource: PortalSource
    public var externalJobId: String?
    public var companyName: String
    public var title: String
    public var url: String
    public var locationRaw: String
    public var isRemote: Bool
    public var salaryMin: Double?
    public var salaryMax: Double?
    public var descriptionText: String
    public var matchedResume: String?
    public var status: JobStatus
    public var discardReason: String?
    public var discoveredAt: Date
    
    public init(
        id: String = UUID().uuidString,
        portalSource: PortalSource,
        externalJobId: String? = nil,
        companyName: String,
        title: String,
        url: String,
        locationRaw: String = "Remote US",
        isRemote: Bool = true,
        salaryMin: Double? = nil,
        salaryMax: Double? = nil,
        descriptionText: String = "",
        matchedResume: String? = nil,
        status: JobStatus = .discovered,
        discardReason: String? = nil,
        discoveredAt: Date = Date()
    ) {
        self.id = id
        self.portalSource = portalSource
        self.externalJobId = externalJobId
        self.companyName = companyName
        self.title = title
        self.url = url
        self.locationRaw = locationRaw
        self.isRemote = isRemote
        self.salaryMin = salaryMin
        self.salaryMax = salaryMax
        self.descriptionText = descriptionText
        self.matchedResume = matchedResume
        self.status = status
        self.discardReason = discardReason
        self.discoveredAt = discoveredAt
    }
}

public struct CompanyRecord: Codable, Identifiable {
    public let id: String
    public var name: String
    public var domain: String?
    public var applicationCount: Int
    public var maxAllowed: Int
    public var isBlocked: Bool
    
    public var isSaturated: Bool {
        return applicationCount >= maxAllowed || isBlocked
    }
}

public struct ApplicationRecord: Codable, Identifiable, Hashable {
    public let id: String
    public var companyName: String
    public var jobTitle: String
    public var reqId: String?
    public var url: String
    public var resumePath: String
    public var status: String // "submitted", "review", etc.
    public var confirmationUrl: String?
    public var confirmationText: String?
    public var reviewScreenshot: String?
    public var submittedScreenshot: String?
    public var evidence: String
    public var submittedAt: Date
}

public struct OutreachRecord: Codable, Identifiable, Hashable {
    public let id: String
    public var companyName: String
    public var recruiterName: String
    public var recruiterTitle: String
    public var recruiterEmail: String
    public var linkedinUrl: String
    public var resumeAttached: String
    public var roleTargeted: String
    public var emailStatus: String // "sent", "drafted"
    public var linkedinStatus: String // "pending", "note_sent"
    public var sentAt: Date
}
