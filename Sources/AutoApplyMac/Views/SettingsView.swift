import SwiftUI
import AppKit

public struct SettingsView: View {
    @ObservedObject private var profileService = ProfileService.shared
    @State private var profile: CandidateProfile = CandidateProfile()
    @State private var detectedAgents: [String: String] = [:]
    @State private var aiTestStatus: String = ""
    @State private var isTestingAI: Bool = false
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    public var body: some View {
        TabView {
            // Tab 1: Personal Info
            Form {
                Section(header: Text("Personal Contact Details")) {
                    TextField("Full Name", text: $profile.fullName)
                    TextField("Email Address", text: $profile.email)
                    TextField("Phone Number", text: $profile.phone)
                    TextField("City, State, Zip", text: $profile.address)
                }
                
                Section(header: Text("Target Profession & Job Titles")) {
                    TextField("Primary Profession / Industry", text: $profile.profession)
                    TextField("Target Job Titles (comma-separated)", text: Binding(
                        get: { profile.targetJobTitles.joined(separator: ", ") },
                        set: { profile.targetJobTitles = $0.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                    ))
                }
                
                Section(header: Text("Online Profiles & Links")) {
                    TextField("LinkedIn Profile URL", text: $profile.linkedinURL)
                    TextField("GitHub / Portfolio URL", text: $profile.githubURL)
                    TextField("Personal Website", text: $profile.portfolioURL)
                }
                
                Section(header: Text("Work Authorization")) {
                    Toggle("Authorized to work in local country", isOn: $profile.isUSCitizen)
                    Toggle("Require visa sponsorship", isOn: $profile.requiresSponsorship)
                }
            }
            .padding()
            .tabItem {
                Label("Profile", systemImage: "person.circle")
            }
            
            // Tab 2: Resumes
            VStack(alignment: .leading, spacing: 14) {
                Text("Manage Your Resumes")
                    .font(.headline)
                
                Text("Upload versions of your resume for different roles. AutoApply will match the best resume to each job description automatically.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if profile.resumes.isEmpty {
                    Text("No resumes added yet. Click below to add your PDF resume.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                } else {
                    List {
                        ForEach(profile.resumes) { r in
                            HStack {
                                Image(systemName: "doc.fill")
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading) {
                                    Text(r.name).font(.subheadline).fontWeight(.medium)
                                    Text(r.detectedProfession).font(.caption2).foregroundColor(.secondary)
                                }
                                Spacer()
                                if r.isDefault {
                                    Text("Default")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.2))
                                        .foregroundColor(.green)
                                        .cornerRadius(4)
                                } else {
                                    Button("Set Default") {
                                        setDefaultResume(r)
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption)
                                }
                                
                                Button(action: { removeResume(r) }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .frame(height: 160)
                }
                
                Button(action: addResume) {
                    Label("Add Another Resume...", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.bordered)
                
                Spacer()
            }
            .padding()
            .tabItem {
                Label("Resumes", systemImage: "doc.on.doc")
            }
            
            // Tab 3: AI Intelligence
            Form {
                Section(header: Text("AI Parsing & Automation Engine")) {
                    Picker("Active AI Provider", selection: $profile.aiProvider) {
                        ForEach(AIAgentType.allCases) { type in
                            Text(type.displayName).tag(type.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    if profile.aiProvider == "gemini_api" {
                        SecureField("Gemini API Key", text: $profile.geminiApiKey)
                        Text("Get an API key from Google AI Studio. Your key is stored locally on this Mac.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Detected Agents On This Mac")) {
                    HStack {
                        Image(systemName: detectedAgents["agy"] != nil ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundColor(detectedAgents["agy"] != nil ? .green : .secondary)
                        Text("Antigravity CLI (agy)")
                        Spacer()
                        Text(detectedAgents["agy"] != nil ? "Detected" : "Not Found")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Image(systemName: detectedAgents["claude"] != nil ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundColor(detectedAgents["claude"] != nil ? .green : .secondary)
                        Text("Claude Code CLI (claude)")
                        Spacer()
                        Text(detectedAgents["claude"] != nil ? "Detected" : "Not Found")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Image(systemName: detectedAgents["codex"] != nil ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundColor(detectedAgents["codex"] != nil ? .green : .secondary)
                        Text("Codex CLI (codex)")
                        Spacer()
                        Text(detectedAgents["codex"] != nil ? "Detected" : "Not Found")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Verification")) {
                    HStack {
                        Button(action: testAI) {
                            HStack {
                                if isTestingAI {
                                    ProgressView().scaleEffect(0.6)
                                } else {
                                    Image(systemName: "bolt.fill")
                                }
                                Text("Test AI Connection")
                            }
                        }
                        .disabled(isTestingAI)
                        
                        if !aiTestStatus.isEmpty {
                            Text(aiTestStatus)
                                .font(.caption)
                                .foregroundColor(aiTestStatus.contains("Success") ? .green : .orange)
                        }
                    }
                }
            }
            .padding()
            .tabItem {
                Label("AI Engine", systemImage: "sparkles")
            }
            
            // Tab 4: Preferences & Storage
            Form {
                Section(header: Text("Search Preferences")) {
                    Toggle("Ask for my review before submitting each application", isOn: $profile.requireApprovalBeforeSubmit)
                    Toggle("Only search for 100% Remote positions", isOn: $profile.only100PercentRemote)
                }
                
                Section(header: Text("Local Storage (On Your Mac)")) {
                    Text("Database: autoapply.sqlite")
                        .font(.caption)
                    Button("Open App Storage in Finder") {
                        NSWorkspace.shared.open(AppPaths.shared.appSupportDir)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .tabItem {
                Label("Preferences", systemImage: "gearshape")
            }
        }
        .frame(width: 600, height: 460)
        .onAppear {
            self.profile = profileService.profile
            self.detectedAgents = AIAssistantService.shared.detectInstalledAgents()
        }
        .onDisappear {
            profileService.updateProfile(profile)
        }
    }
    
    private func setDefaultResume(_ resume: UserResume) {
        for i in 0..<profile.resumes.count {
            profile.resumes[i].isDefault = (profile.resumes[i].id == resume.id)
        }
        profileService.updateProfile(profile)
        WebKitCoordinator.shared.activeResumePath = resume.filePath
    }
    
    private func removeResume(_ resume: UserResume) {
        profile.resumes.removeAll(where: { $0.id == resume.id })
        if !profile.resumes.isEmpty && !profile.resumes.contains(where: { $0.isDefault }) {
            profile.resumes[0].isDefault = true
        }
        profileService.updateProfile(profile)
    }
    
    private func addResume() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf]
        
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                let parsed = await ResumeParser.shared.parsePDFAgent(at: url)
                await MainActor.run {
                    let prof = parsed?.detectedProfession ?? "General"
                    let path = parsed?.localSavedPath ?? url.path
                    let newRecord = UserResume(
                        name: url.lastPathComponent,
                        filePath: path,
                        detectedProfession: prof,
                        isDefault: profile.resumes.isEmpty
                    )
                    profile.resumes.append(newRecord)
                    profileService.updateProfile(profile)
                }
            }
        }
    }
    
    private func testAI() {
        isTestingAI = true
        aiTestStatus = "Connecting..."
        Task {
            let res = await AIAssistantService.shared.runAIPrompt("Respond ONLY with: Connected successfully.")
            await MainActor.run {
                isTestingAI = false
                if let res = res, !res.isEmpty {
                    aiTestStatus = "Success: \(res.prefix(40))"
                } else {
                    aiTestStatus = "Offline Mode Active (Local fallback ready)"
                }
            }
        }
    }
}
