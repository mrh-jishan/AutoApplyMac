import SwiftUI
import AppKit

// MARK: - Column 2: Outreach List View

public struct OutreachListView: View {
    @Binding public var outreaches: [OutreachRecord]
    @Binding public var selectedOutreach: OutreachRecord?
    public let onRefresh: () -> Void
    
    @State private var filterStatus: String = "all"
    @State private var searchText: String = ""
    @State private var showAddSheet: Bool = false
    
    // Add contact form state
    @State private var newCompany: String = ""
    @State private var newName: String = ""
    @State private var newTitle: String = "Technical Recruiter"
    @State private var newEmail: String = ""
    @State private var newRole: String = ""
    
    public init(
        outreaches: Binding<[OutreachRecord]>,
        selectedOutreach: Binding<OutreachRecord?>,
        onRefresh: @escaping () -> Void
    ) {
        self._outreaches = outreaches
        self._selectedOutreach = selectedOutreach
        self.onRefresh = onRefresh
    }
    
    public var filteredOutreaches: [OutreachRecord] {
        outreaches.filter { o in
            let matchesStatus = filterStatus == "all" || o.emailStatus.lowercased() == filterStatus
            let matchesSearch = searchText.isEmpty ||
                o.recruiterName.localizedCaseInsensitiveContains(searchText) ||
                o.companyName.localizedCaseInsensitiveContains(searchText) ||
                o.roleTargeted.localizedCaseInsensitiveContains(searchText)
            return matchesStatus && matchesSearch
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header & Action Bar
            VStack(spacing: 8) {
                HStack {
                    Text("Recruiters (\(outreaches.count))")
                        .font(.headline)
                    Spacer()
                    Button(action: {
                        let added = DatabaseManager.shared.autoDiscoverRecruiters()
                        onRefresh()
                        if let first = DatabaseManager.shared.fetchOutreachRecords().first {
                            selectedOutreach = first
                        }
                        WebKitCoordinator.shared.statusMessage = "Auto-discovered \(added) recruiter contacts from queued roles."
                    }) {
                        Label("Auto-Discover", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                    Button(action: { showAddSheet = true }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                // Search Field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    TextField("Search recruiter, company, role...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.callout)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                
                // Status Filters
                Picker("", selection: $filterStatus) {
                    Text("All (\(outreaches.count))").tag("all")
                    Text("Drafted").tag("drafted")
                    Text("Sent").tag("sent")
                    Text("Replied").tag("replied")
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
            }
            .padding(12)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Recruiter List
            if filteredOutreaches.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No outreach contacts yet")
                        .font(.headline)
                    Text("Click 'Auto-Discover' to automatically target recruiters for your queued jobs.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Button("Auto-Discover Recruiters") {
                        _ = DatabaseManager.shared.autoDiscoverRecruiters()
                        onRefresh()
                        selectedOutreach = DatabaseManager.shared.fetchOutreachRecords().first
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Spacer()
                }
            } else {
                List(filteredOutreaches, selection: $selectedOutreach) { rec in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(rec.recruiterName)
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            Spacer()
                            outreachStatusBadge(rec.emailStatus)
                        }
                        
                        HStack(spacing: 4) {
                            Text(rec.companyName)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(rec.recruiterTitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        Text("Role: \(rec.roleTargeted)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 4)
                    .tag(rec)
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            addRecruiterSheet
        }
    }
    
    private var addRecruiterSheet: some View {
        VStack(spacing: 18) {
            Text("Add Recruiter Contact")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 10) {
                TextField("Company Name (e.g. Anthropic)", text: $newCompany)
                    .textFieldStyle(.roundedBorder)
                TextField("Recruiter Full Name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                TextField("Recruiter Title (e.g. Lead Tech Recruiter)", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                TextField("Recruiter Email", text: $newEmail)
                    .textFieldStyle(.roundedBorder)
                TextField("Role Targeted", text: $newRole)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Button("Cancel") {
                    showAddSheet = false
                }
                Spacer()
                Button("Save Contact") {
                    guard !newCompany.isEmpty && !newName.isEmpty else { return }
                    let profile = ProfileService.shared.profile
                    let subject = "Quick note regarding \(newRole.isEmpty ? "Engineering roles" : newRole) at \(newCompany) — \(profile.fullName)"
                    let body = "Hi \(newName),\n\nI noticed \(newCompany)'s recent openings for \(newRole) and wanted to reach out directly.\n\nBest regards,\n\(profile.fullName)\n\(profile.email)"
                    
                    let newRecord = OutreachRecord(
                        id: UUID().uuidString,
                        companyName: newCompany,
                        recruiterName: newName,
                        recruiterTitle: newTitle,
                        recruiterEmail: newEmail,
                        linkedinUrl: "",
                        resumeAttached: profile.resumes.first?.filePath ?? "",
                        roleTargeted: newRole,
                        emailStatus: "drafted",
                        subjectLine: subject,
                        emailBody: body
                    )
                    DatabaseManager.shared.recordOutreach(newRecord)
                    onRefresh()
                    selectedOutreach = newRecord
                    showAddSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newCompany.isEmpty || newName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

// MARK: - Column 3: Outreach Detail Workspace View

public struct OutreachDetailWorkspaceView: View {
    @Binding public var selectedOutreach: OutreachRecord?
    public let onRefresh: () -> Void
    
    @State private var isGeneratingAI: Bool = false
    @State private var selectedTone: String = "Cold Outreach"
    @State private var copiedNotice: Bool = false
    
    public init(
        selectedOutreach: Binding<OutreachRecord?>,
        onRefresh: @escaping () -> Void
    ) {
        self._selectedOutreach = selectedOutreach
        self.onRefresh = onRefresh
    }
    
    public var body: some View {
        if let rec = selectedOutreach {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Top Header Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [Color.purple, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 48, height: 48)
                                Text(String(rec.recruiterName.prefix(1)))
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text(rec.recruiterName)
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    outreachStatusBadge(rec.emailStatus)
                                }
                                
                                Text("\(rec.recruiterTitle) at \(rec.companyName)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            // Status Selector Menu
                            Menu {
                                Button("Drafted") { updateStatus(rec, to: "drafted") }
                                Button("Sent") { updateStatus(rec, to: "sent") }
                                Button("Replied") { updateStatus(rec, to: "replied") }
                            } label: {
                                Label("Status: \(rec.emailStatus.capitalized)", systemImage: "flag.fill")
                            }
                            .menuStyle(.borderedButton)
                        }
                        
                        Divider()
                        
                        // Action buttons
                        HStack(spacing: 12) {
                            if !rec.recruiterEmail.isEmpty {
                                Label(rec.recruiterEmail, systemImage: "envelope.fill")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                            
                            Spacer()
                            
                            if !rec.linkedinUrl.isEmpty {
                                Button(action: {
                                    if let url = URL(string: rec.linkedinUrl) {
                                        NSWorkspace.shared.open(url)
                                    }
                                }) {
                                    Label("Search LinkedIn ↗", systemImage: "network")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            
                            Button(role: .destructive, action: {
                                DatabaseManager.shared.deleteOutreach(id: rec.id)
                                selectedOutreach = nil
                                onRefresh()
                            }) {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(18)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                    
                    // Targeted Role Card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("OUTREACH CONTEXT")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Targeted Role")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(rec.roleTargeted.isEmpty ? "Engineering Role" : rec.roleTargeted)
                                    .font(.callout)
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Target Company")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(rec.companyName)
                                    .font(.callout)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .padding(14)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                    .cornerRadius(8)
                    
                    // AI Email Composer
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Personalized Outreach Email", systemImage: "sparkles")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                            
                            Picker("", selection: $selectedTone) {
                                Text("Cold Outreach").tag("Cold Outreach")
                                Text("Referral Inquiry").tag("Referral Inquiry")
                                Text("Application Follow-Up").tag("Application Follow-Up")
                                Text("Executive Pitch").tag("Executive Pitch")
                            }
                            .pickerStyle(.menu)
                            .controlSize(.small)
                            
                            Button(action: { generateAIEmail(for: rec) }) {
                                HStack(spacing: 4) {
                                    if isGeneratingAI {
                                        ProgressView().scaleEffect(0.6)
                                    } else {
                                        Image(systemName: "wand.and.stars")
                                    }
                                    Text("Generate with AI")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isGeneratingAI)
                            .controlSize(.small)
                        }
                        
                        // Subject Line
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Subject Line")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            TextField("Subject line...", text: Binding(
                                get: { rec.subjectLine },
                                set: { newValue in
                                    var updated = rec
                                    updated.subjectLine = newValue
                                    DatabaseManager.shared.recordOutreach(updated)
                                    selectedOutreach = updated
                                    onRefresh()
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                        
                        // Email Body
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Email Message Body")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            TextEditor(text: Binding(
                                get: { rec.emailBody },
                                set: { newValue in
                                    var updated = rec
                                    updated.emailBody = newValue
                                    DatabaseManager.shared.recordOutreach(updated)
                                    selectedOutreach = updated
                                    onRefresh()
                                }
                            ))
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 220)
                            .padding(4)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                        }
                        
                        // Actions Bar: Mail.app & Clipboard
                        HStack(spacing: 12) {
                            Button(action: {
                                openInMailApp(rec)
                                updateStatus(rec, to: "sent")
                            }) {
                                Label("Open in Mail.app ✉️", systemImage: "paperplane.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button(action: {
                                copyToClipboard(rec)
                            }) {
                                Label(copiedNotice ? "Copied!" : "Copy to Clipboard", systemImage: copiedNotice ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            
                            Spacer()
                            
                            if rec.emailStatus != "sent" {
                                Button("Mark as Sent") {
                                    updateStatus(rec, to: "sent")
                                }
                                .buttonStyle(.bordered)
                            } else {
                                Button("Mark as Replied 🎉") {
                                    updateStatus(rec, to: "replied")
                                }
                                .buttonStyle(.bordered)
                                .tint(.green)
                            }
                        }
                    }
                    .padding(18)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                }
                .padding(24)
                .frame(maxWidth: 880)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        } else {
            // Empty State
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "paperplane.circle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.purple.opacity(0.8))
                
                Text("Recruiter Outreach Suite")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Proactively contact hiring managers and talent partners at target companies to bypass automated filters and fast-track interviews.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                
                HStack(spacing: 12) {
                    Button("Auto-Discover Recruiters from Queued Roles") {
                        let added = DatabaseManager.shared.autoDiscoverRecruiters()
                        onRefresh()
                        selectedOutreach = DatabaseManager.shared.fetchOutreachRecords().first
                        WebKitCoordinator.shared.statusMessage = "Auto-discovered \(added) recruiter contacts!"
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 8)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
    
    private func updateStatus(_ record: OutreachRecord, to newStatus: String) {
        var updated = record
        updated.emailStatus = newStatus
        DatabaseManager.shared.recordOutreach(updated)
        selectedOutreach = updated
        onRefresh()
    }
    
    private func copyToClipboard(_ record: OutreachRecord) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let fullMessage = "Subject: \(record.subjectLine)\n\n\(record.emailBody)"
        pasteboard.setString(fullMessage, forType: .string)
        copiedNotice = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            copiedNotice = false
        }
    }
    
    private func openInMailApp(_ record: OutreachRecord) {
        let email = record.recruiterEmail
        let subject = record.subjectLine.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let body = record.emailBody.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:\(email)?subject=\(subject)&body=\(body)") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func generateAIEmail(for record: OutreachRecord) {
        isGeneratingAI = true
        let profile = ProfileService.shared.profile
        let prompt = """
        Write a concise, high-impact cold recruiter outreach email.
        Candidate Name: \(profile.fullName)
        Candidate Profession: \(profile.profession)
        Recruiter Name: \(record.recruiterName)
        Recruiter Title: \(record.recruiterTitle)
        Company Name: \(record.companyName)
        Target Role: \(record.roleTargeted)
        Tone: \(selectedTone)
        Candidate Contact: \(profile.email), \(profile.phone), \(profile.linkedinURL)
        
        Output only the subject line on line 1 prefixed with 'SUBJECT: ', followed by two newlines and the email body.
        Keep it professional, compelling, and under 160 words.
        """
        
        Task {
            let reply = await AIAssistantService.shared.runAIPrompt(prompt) ?? ""
            await MainActor.run {
                self.isGeneratingAI = false
                guard !reply.isEmpty else { return }
                
                var subject = record.subjectLine
                var body = reply
                if reply.hasPrefix("SUBJECT:") {
                    let parts = reply.components(separatedBy: "\n\n")
                    if let first = parts.first {
                        subject = first.replacingOccurrences(of: "SUBJECT:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if parts.count > 1 {
                        body = parts.dropFirst().joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                
                var updated = record
                updated.subjectLine = subject
                updated.emailBody = body
                DatabaseManager.shared.recordOutreach(updated)
                self.selectedOutreach = updated
                self.onRefresh()
            }
        }
    }
}

@ViewBuilder
public func outreachStatusBadge(_ status: String) -> some View {
    let badgeColor: Color = {
        switch status.lowercased() {
        case "sent": return Color.green
        case "replied": return Color.blue
        default: return Color.purple
        }
    }()
    
    Text(status.capitalized)
        .font(.caption2)
        .fontWeight(.semibold)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(badgeColor.opacity(0.15))
        .foregroundColor(badgeColor)
        .cornerRadius(4)
}
