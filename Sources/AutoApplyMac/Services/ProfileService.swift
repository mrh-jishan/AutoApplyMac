import Foundation

public final class ProfileService: ObservableObject {
    public static let shared = ProfileService()
    
    @Published public var profile: CandidateProfile
    
    private init() {
        if let saved = DatabaseManager.shared.fetchProfile() {
            self.profile = saved
            print("Loaded candidate profile from SQLite for: \(saved.fullName)")
        } else {
            // Fresh blank profile for new user
            self.profile = CandidateProfile()
            print("Initialized fresh candidate profile for new user")
        }
    }
    
    public func updateProfile(_ newProfile: CandidateProfile) {
        self.profile = newProfile
        DatabaseManager.shared.saveProfile(newProfile)
    }
}
