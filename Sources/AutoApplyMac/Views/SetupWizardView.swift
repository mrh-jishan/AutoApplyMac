import SwiftUI
import AppKit

public struct SetupWizardView: View {
    @Binding public var isPresented: Bool
    public let onComplete: () -> Void
    
    @State private var currentStep: Int = 1
    @State private var profile: CandidateProfile = CandidateProfile()
    @State private var selectedResumeFileName: String = ""
    @State private var detectedProfession: String = ""
    @State private var targetTitlesInput: String = ""
    @State private var isAnalyzing: Bool = false
    
    public init(isPresented: Binding<Bool>, onComplete: @escaping () -> Void) {
        self._isPresented = isPresented
        self.onComplete = onComplete
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            // Header Progress
            HStack(spacing: 12) {
                stepBadge(number: 1, title: "Resume", active: currentStep == 1, done: currentStep > 1)
                Rectangle().frame(height: 2).foregroundColor(.secondary.opacity(0.3))
                stepBadge(number: 2, title: "Your Info", active: currentStep == 2, done: currentStep > 2)
                Rectangle().frame(height: 2).foregroundColor(.secondary.opacity(0.3))
                stepBadge(number: 3, title: "Job Targets", active: currentStep == 3, done: currentStep > 3)
                Rectangle().frame(height: 2).foregroundColor(.secondary.opacity(0.3))
                stepBadge(number: 4, title: "Get Started", active: currentStep == 4, done: false)
            }
            .padding(.top, 24)
            .padding(.horizontal, 40)
            
            Divider()
            
            // Content
            VStack {
                switch currentStep {
                case 1:
                    stepOneResumeUpload
                case 2:
                    stepTwoPersonalInfo
                case 3:
                    stepThreeJobTargets
                case 4:
                    stepFourCompletion
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: 600, minHeight: 340)
            .padding(.horizontal, 30)
            
            Divider()
            
            // Navigation Buttons
            HStack {
                if currentStep > 1 {
                    Button("Back") {
                        currentStep -= 1
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
                
                if currentStep < 4 {
                    Button("Continue") {
                        currentStep += 1
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Launch AutoApply Pro") {
                        ProfileService.shared.updateProfile(profile)
                        AppPaths.shared.hasCompletedSetup = true
                        onComplete()
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 20)
        }
        .frame(width: 680, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Steps
    
    private var stepOneResumeUpload: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            
            Text("Welcome to AutoApply Pro!")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("To get started, select your PDF resume. Our smart parser will automatically extract your contact details and skills for you.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            Button(action: selectResumeFromFinder) {
                Label("Choose PDF Resume...", systemImage: "arrow.up.doc.fill")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAnalyzing)
            
            if isAnalyzing {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Analyzing resume with AI Agent... extracting contact details & profession")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .padding(8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            } else if !selectedResumeFileName.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Loaded: \(selectedResumeFileName)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .padding(8)
                .background(Color.green.opacity(0.1))
                .cornerRadius(6)
            }
        }
    }
    
    private var stepTwoPersonalInfo: some View {
        Form {
            Section(header: Text("Contact Details (Auto-extracted from your resume)")) {
                TextField("Full Name", text: $profile.fullName)
                TextField("Email Address", text: $profile.email)
                TextField("Phone Number", text: $profile.phone)
                TextField("City, State, Zip", text: $profile.address)
            }
            
            Section(header: Text("Work Authorization")) {
                Toggle("Authorized to work in the country you are located", isOn: $profile.isUSCitizen)
                Toggle("Will require visa sponsorship now or in the future", isOn: $profile.requiresSponsorship)
            }
        }
    }
    
    private var stepThreeJobTargets: some View {
        Form {
            Section(header: Text("What kind of jobs are you looking for?")) {
                TextField("Detected Field / Profession", text: $detectedProfession)
                TextField("Target Job Titles (comma separated)", text: $targetTitlesInput)
                Text("Example: Marketing Director, Senior Growth Manager or Software Engineer, Tech Lead")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("Search Preferences")) {
                Toggle("Only find 100% Remote positions", isOn: $profile.only100PercentRemote)
                Toggle("Require my review before clicking 'Submit Application'", isOn: $profile.requireApprovalBeforeSubmit)
            }
        }
    }
    
    private var stepFourCompletion: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(.green)
            
            Text("You're all set, \(profile.fullName.isEmpty ? "there" : profile.fullName)!")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("AutoApply Pro will now search Google Jobs, LinkedIn, Workday, Greenhouse, and Ashby for remote jobs matching your background.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("• Active Resume: \(selectedResumeFileName.isEmpty ? "Primary Resume" : selectedResumeFileName)")
                Text("• Target Field: \(detectedProfession.isEmpty ? "General" : detectedProfession)")
                Text("• Mode: \(profile.requireApprovalBeforeSubmit ? "Supervised (You review before submitting)" : "Auto-Pilot")")
            }
            .font(.caption)
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
    
    private func stepBadge(number: Int, title: String, active: Bool, done: Bool) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(done ? Color.green : (active ? Color.blue : Color.secondary.opacity(0.3)))
                    .frame(width: 24, height: 24)
                if done {
                    Image(systemName: "checkmark")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                } else {
                    Text("\(number)")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                }
            }
            Text(title)
                .font(.caption)
                .fontWeight(active ? .bold : .regular)
                .foregroundColor(active ? .primary : .secondary)
        }
    }
    
    private func selectResumeFromFinder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.pdf]
        
        if panel.runModal() == .OK, let url = panel.url {
            selectedResumeFileName = url.lastPathComponent
            isAnalyzing = true
            
            Task {
                let parsed = await ResumeParser.shared.parsePDFAgent(at: url)
                await MainActor.run {
                    isAnalyzing = false
                    if let parsed = parsed {
                        if let name = parsed.suggestedName { profile.fullName = name }
                        if let email = parsed.suggestedEmail { profile.email = email }
                        if let phone = parsed.suggestedPhone { profile.phone = phone }
                        if let loc = parsed.suggestedLocation { profile.address = loc }
                        if let li = parsed.suggestedLinkedIn { profile.linkedinURL = li }
                        if let gh = parsed.suggestedGitHub { profile.githubURL = gh }
                        if let port = parsed.suggestedPortfolio { profile.portfolioURL = port }
                        
                        detectedProfession = parsed.detectedProfession
                        profile.profession = parsed.detectedProfession
                        if !parsed.suggestedTitles.isEmpty {
                            targetTitlesInput = parsed.suggestedTitles.joined(separator: ", ")
                            profile.targetJobTitles = parsed.suggestedTitles
                        }
                        
                        let resumeRecord = UserResume(
                            name: url.lastPathComponent,
                            filePath: parsed.localSavedPath,
                            detectedProfession: parsed.detectedProfession,
                            isDefault: true
                        )
                        profile.resumes = [resumeRecord]
                        WebKitCoordinator.shared.activeResumePath = parsed.localSavedPath
                    }
                }
            }
        }
    }
}
