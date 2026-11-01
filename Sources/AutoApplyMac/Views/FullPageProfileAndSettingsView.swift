import SwiftUI
import AppKit

public struct FullPageProfileAndSettingsView: View {
    @ObservedObject private var profileService = ProfileService.shared
    @State private var profile: CandidateProfile = CandidateProfile()
    @State private var selectedTab: Int = 0
    @State private var detectedAgents: [String: String] = [:]
    @State private var aiTestStatus: String = ""
    @State private var isTestingAI: Bool = false
    @State private var isAnalyzingResume: Bool = false
    @State private var saveNotification: String = ""
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.blue, Color.cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 52, height: 52)
                    Image(systemName: "person.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(profile.fullName.isEmpty ? "New Candidate Profile" : profile.fullName)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(profile.profession.isEmpty ? "General" : profile.profession)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(6)
                    }
                    
                    Text(profile.email.isEmpty ? "Configure your details and AI settings below" : "\(profile.email) • \(profile.phone.isEmpty ? "No phone" : profile.phone) • \(profile.address.isEmpty ? "Location not set" : profile.address)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Saved indicator
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Saved to SQLite")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Segmented Tab Picker
            Picker("", selection: $selectedTab) {
                Text("Personal Info").tag(0)
                Text("Career & Targets").tag(1)
                Text("Resumes (\(profile.resumes.count))").tag(2)
                Text("AI Engine").tag(3)
                Text("Preferences & Storage").tag(4)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            
            Divider()
            
            // Scrollable Tab Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case 0:
                        personalInfoSection
                    case 1:
                        careerTargetsSection
                    case 2:
                        resumesSection
                    case 3:
                        aiEngineSection
                    case 4:
                        preferencesAndStorageSection
                    default:
                        EmptyView()
                    }
                }
                .padding(28)
                .frame(maxWidth: 860)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
        .onAppear {
            self.profile = profileService.profile
            self.detectedAgents = AIAssistantService.shared.detectInstalledAgents()
        }
        .onChange(of: profile.fullName) { save() }
        .onChange(of: profile.email) { save() }
        .onChange(of: profile.phone) { save() }
        .onChange(of: profile.address) { save() }
        .onChange(of: profile.city) { save() }
        .onChange(of: profile.state) { save() }
        .onChange(of: profile.postalCode) { save() }
        .onChange(of: profile.isUSCitizen) { save() }
        .onChange(of: profile.requiresSponsorship) { save() }
        .onChange(of: profile.profession) { save() }
        .onChange(of: profile.targetJobTitles) { save() }
        .onChange(of: profile.linkedinURL) { save() }
        .onChange(of: profile.githubURL) { save() }
        .onChange(of: profile.portfolioURL) { save() }
        .onChange(of: profile.only100PercentRemote) { save() }
        .onChange(of: profile.requireApprovalBeforeSubmit) { save() }
        .onChange(of: profile.aiProvider) { save() }
        .onChange(of: profile.geminiApiKey) { save() }
        .onChange(of: profile.eeocGender) { save() }
        .onChange(of: profile.eeocRace) { save() }
        .onChange(of: profile.eeocVeteran) { save() }
        .onChange(of: profile.eeocDisability) { save() }
    }
    
    private func save() {
        profileService.updateProfile(profile)
    }
    
    // MARK: - 1. Personal Info Section
    
    private var personalInfoSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "Contact Details", subtitle: "These details are used to auto-fill job applications across all ATS portals.")
            
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    labeledTextField(label: "Full Name", text: $profile.fullName, placeholder: "e.g. Jane Doe")
                    labeledTextField(label: "Email Address", text: $profile.email, placeholder: "e.g. jane.doe@example.com")
                }
                HStack(spacing: 16) {
                    labeledTextField(label: "Phone Number", text: $profile.phone, placeholder: "e.g. (555) 123-4567")
                    labeledTextField(label: "Location / Address", text: $profile.address, placeholder: "e.g. Austin, TX or Remote US")
                }
                HStack(spacing: 16) {
                    labeledTextField(label: "City", text: $profile.city, placeholder: "e.g. Austin")
                    labeledTextField(label: "State", text: $profile.state, placeholder: "e.g. TX")
                    labeledTextField(label: "Zip Code", text: $profile.postalCode, placeholder: "e.g. 78701")
                }
            }
            .padding(18)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(10)
            
            sectionHeader(title: "Work Authorization", subtitle: "Standard legal authorization questions asked on application forms.")
            
            VStack(spacing: 14) {
                Toggle("Legally authorized to work in the country you are applying for", isOn: $profile.isUSCitizen)
                Toggle("Will require visa sponsorship now or in the future", isOn: $profile.requiresSponsorship)
            }
            .padding(18)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(10)
            
            sectionHeader(title: "Voluntary Equal Opportunity (EEOC) Defaults", subtitle: "Pre-fills demographic questions on Greenhouse, Workday, and Ashby applications.")
            
            VStack(spacing: 14) {
                Picker("Gender Identity", selection: $profile.eeocGender) {
                    Text("Decline to self-identify").tag("Decline to self-identify")
                    Text("Male").tag("Male")
                    Text("Female").tag("Female")
                    Text("Non-binary").tag("Non-binary")
                }
                Picker("Race / Ethnicity", selection: $profile.eeocRace) {
                    Text("Decline to self-identify").tag("Decline to self-identify")
                    Text("Asian").tag("Asian")
                    Text("White").tag("White")
                    Text("Black or African American").tag("Black or African American")
                    Text("Hispanic or Latino").tag("Hispanic or Latino")
                    Text("Two or More Races").tag("Two or More Races")
                }
                Picker("Veteran Status", selection: $profile.eeocVeteran) {
                    Text("Decline to self-identify").tag("Decline to self-identify")
                    Text("Not a protected veteran").tag("Not a protected veteran")
                    Text("Protected veteran").tag("Protected veteran")
                }
                Picker("Disability Status", selection: $profile.eeocDisability) {
                    Text("Decline to self-identify").tag("Decline to self-identify")
                    Text("No, I do not have a disability").tag("No, I do not have a disability")
                    Text("Yes, I have a disability").tag("Yes, I have a disability")
                }
            }
            .padding(18)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(10)
        }
    }
    
    // MARK: - 2. Career & Targets Section
    
    private var careerTargetsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "Target Profession & Roles", subtitle: "Defines the filters used when crawling LinkedIn, Workday, Greenhouse, and Ashby.")
            
            VStack(spacing: 16) {
                labeledTextField(label: "Primary Profession / Field", text: $profile.profession, placeholder: "e.g. Software Engineering, Healthcare, Marketing, Corporate Finance")
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Target Job Titles (comma-separated)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    TextField("e.g. Senior Software Engineer, Tech Lead, Staff SRE", text: Binding(
                        get: { profile.targetJobTitles.joined(separator: ", ") },
                        set: { profile.targetJobTitles = $0.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                    ))
                    .textFieldStyle(.roundedBorder)
                    
                    Text("AutoApply Pro will discover and rank positions matching any of these specific titles.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(18)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(10)
            
            sectionHeader(title: "Online Portfolios & Links", subtitle: "Links inserted into careers forms and submitted to recruiters.")
            
            VStack(spacing: 12) {
                labeledTextField(label: "LinkedIn Profile URL", text: $profile.linkedinURL, placeholder: "https://www.linkedin.com/in/username")
                labeledTextField(label: "GitHub / Portfolio URL", text: $profile.githubURL, placeholder: "https://github.com/username")
                labeledTextField(label: "Personal Website / Blog", text: $profile.portfolioURL, placeholder: "https://yourwebsite.com")
            }
            .padding(18)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(10)
        }
    }
    
    // MARK: - 3. Resumes Section
    
    private var resumesSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                sectionHeader(title: "Managed Resumes", subtitle: "AutoApply Pro dynamically matches the best resume to each job description.")
                Spacer()
                Button(action: addResumeWithAI) {
                    HStack(spacing: 6) {
                        if isAnalyzingResume {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "plus.circle.fill")
                        }
                        Text("Add PDF Resume...")
                    }
                    .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAnalyzingResume)
            }
            
            if isAnalyzingResume {
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.8)
                    Text("Analyzing resume with AI Agent... extracting contact details and target job titles")
                        .font(.callout)
                        .foregroundColor(.blue)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            if profile.resumes.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text("No Resumes Uploaded Yet")
                        .font(.headline)
                    Text("Click 'Add PDF Resume...' to upload your resume. Our AI Agent will automatically extract your contact details and skills.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(10)
            } else {
                VStack(spacing: 12) {
                    ForEach(profile.resumes) { r in
                        HStack(spacing: 14) {
                            Image(systemName: "doc.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(r.name)
                                        .font(.headline)
                                    
                                    if r.isDefault {
                                        Text("DEFAULT")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.green.opacity(0.2))
                                            .foregroundColor(.green)
                                            .cornerRadius(4)
                                    }
                                    
                                    Text(r.detectedProfession)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.15))
                                        .cornerRadius(4)
                                }
                                
                                Text(r.filePath)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            if !r.isDefault {
                                Button("Set Default") {
                                    setDefaultResume(r)
                                }
                                .buttonStyle(.bordered)
                                .font(.caption)
                            }
                            
                            Button(action: {
                                NSWorkspace.shared.selectFile(r.filePath, inFileViewerRootedAtPath: "")
                            }) {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.plain)
                            .help("Show in Finder")
                            
                            Button(action: { removeResume(r) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Remove Resume")
                        }
                        .padding(14)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }
    
    // MARK: - 4. AI Engine Section
    
    private var aiEngineSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "AI Parsing & Agent Configuration", subtitle: "Configure how AutoApply Pro extracts resume details and semantically matches jobs.")
            
            VStack(alignment: .leading, spacing: 16) {
                Picker("Active AI Engine", selection: $profile.aiProvider) {
                    ForEach(AIAgentType.allCases) { type in
                        Text(type.displayName).tag(type.rawValue)
                    }
                }
                .pickerStyle(.menu)
                
                if profile.aiProvider == "gemini_api" {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Gemini API Key")
                            .font(.caption)
                            .fontWeight(.semibold)
                        SecureField("Enter your Gemini API key from Google AI Studio", text: $profile.geminiApiKey)
                            .textFieldStyle(.roundedBorder)
                        Text("Your API key is stored locally on this Mac and never shared.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(18)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(10)
            
            sectionHeader(title: "Detected Host Terminal Agents", subtitle: "Signed-in CLI agents detected in your macOS shell.")
            
            VStack(spacing: 12) {
                agentStatusRow(name: "Google Antigravity CLI (agy)", isDetected: detectedAgents["agy"] != nil, path: detectedAgents["agy"])
                agentStatusRow(name: "Claude Code CLI (claude)", isDetected: detectedAgents["claude"] != nil, path: detectedAgents["claude"])
                agentStatusRow(name: "OpenAI Codex CLI (codex)", isDetected: detectedAgents["codex"] != nil, path: detectedAgents["codex"])
            }
            .padding(18)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(10)
            
            sectionHeader(title: "Agent Verification", subtitle: "Test the active AI connection with a live query.")
            
            HStack(spacing: 14) {
                Button(action: testAIConnection) {
                    HStack(spacing: 6) {
                        if isTestingAI {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "bolt.fill")
                        }
                        Text("Test AI Connection")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isTestingAI)
                
                if !aiTestStatus.isEmpty {
                    Text(aiTestStatus)
                        .font(.callout)
                        .foregroundColor(aiTestStatus.contains("Connected") ? .green : .orange)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(10)
        }
    }
    
    // MARK: - 5. Preferences & Storage Section
    
    private var preferencesAndStorageSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "Automation & Safety Settings", subtitle: "Control application approval behavior and location filtering.")
            
            VStack(spacing: 14) {
                Toggle("Ask for my review before clicking 'Submit Application'", isOn: $profile.requireApprovalBeforeSubmit)
                Toggle("Strict Filter: Only search for 100% Remote positions", isOn: $profile.only100PercentRemote)
            }
            .padding(18)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(10)
            
            sectionHeader(title: "Local On-Device Database (SQLite)", subtitle: "All application data, receipts, and profiles are stored locally on your Mac.")
            
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SQLite Database Path:")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text(AppPaths.shared.databaseFilePath)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Open in Finder") {
                        NSWorkspace.shared.open(AppPaths.shared.databaseDir)
                    }
                    .buttonStyle(.bordered)
                }
                
                Divider()
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Application Support Folder:")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text(AppPaths.shared.appSupportDir.path)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Open App Storage") {
                        NSWorkspace.shared.open(AppPaths.shared.appSupportDir)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(18)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(10)
        }
    }
    
    // MARK: - Subcomponents & Helpers
    
    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func labeledTextField(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func agentStatusRow(name: String, isDetected: Bool, path: String?) -> some View {
        HStack {
            Image(systemName: isDetected ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(isDetected ? .green : .secondary)
            Text(name)
                .font(.subheadline)
            Spacer()
            Text(isDetected ? (path ?? "Ready") : "Not Found")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func setDefaultResume(_ resume: UserResume) {
        for i in 0..<profile.resumes.count {
            profile.resumes[i].isDefault = (profile.resumes[i].id == resume.id)
        }
        save()
        WebKitCoordinator.shared.activeResumePath = resume.filePath
    }
    
    private func removeResume(_ resume: UserResume) {
        profile.resumes.removeAll(where: { $0.id == resume.id })
        if !profile.resumes.isEmpty && !profile.resumes.contains(where: { $0.isDefault }) {
            profile.resumes[0].isDefault = true
        }
        save()
    }
    
    private func addResumeWithAI() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf]
        
        if panel.runModal() == .OK, let url = panel.url {
            isAnalyzingResume = true
            Task {
                let parsed = await ResumeParser.shared.parsePDFAgent(at: url)
                await MainActor.run {
                    isAnalyzingResume = false
                    let prof = parsed?.detectedProfession ?? "General"
                    let path = parsed?.localSavedPath ?? url.path
                    
                    if let parsed = parsed {
                        if profile.fullName.isEmpty, let n = parsed.suggestedName { profile.fullName = n }
                        if profile.email.isEmpty, let e = parsed.suggestedEmail { profile.email = e }
                        if profile.phone.isEmpty, let p = parsed.suggestedPhone { profile.phone = p }
                        if profile.address.isEmpty, let loc = parsed.suggestedLocation { profile.address = loc }
                        if profile.targetJobTitles.isEmpty && !parsed.suggestedTitles.isEmpty {
                            profile.targetJobTitles = parsed.suggestedTitles
                        }
                    }
                    
                    let newRecord = UserResume(
                        name: url.lastPathComponent,
                        filePath: path,
                        detectedProfession: prof,
                        isDefault: profile.resumes.isEmpty
                    )
                    profile.resumes.append(newRecord)
                    save()
                }
            }
        }
    }
    
    private func testAIConnection() {
        isTestingAI = true
        aiTestStatus = "Testing connection..."
        Task {
            let res = await AIAssistantService.shared.runAIPrompt("Respond ONLY with: Connected successfully.")
            await MainActor.run {
                isTestingAI = false
                if let res = res, !res.isEmpty {
                    aiTestStatus = "Connected successfully (\(res.trimmingCharacters(in: .whitespacesAndNewlines)))"
                } else {
                    aiTestStatus = "Offline Mode Active (Built-in PDFKit parser ready)"
                }
            }
        }
    }
}
