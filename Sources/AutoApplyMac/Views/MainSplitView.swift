import SwiftUI

public struct MainSplitView: View {
    @State private var navigationSection: NavigationSection? = .queuedJobs
    @State private var queuedJobs: [JobPosting] = []
    @State private var applications: [ApplicationRecord] = []
    @State private var outreaches: [OutreachRecord] = []
    @State private var portalCounts: [PortalSource: Int] = [:]
    @State private var selectedJob: JobPosting?
    @State private var selectedApplication: ApplicationRecord?
    @State private var isCrawling: Bool = false
    @State private var showSettings: Bool = false
    @State private var showSetupWizard: Bool = !AppPaths.shared.hasCompletedSetup
    
    private let db = DatabaseManager.shared
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            SidebarView(
                selection: $navigationSection,
                queuedCount: queuedJobs.count,
                applicationCount: applications.count,
                outreachCount: outreaches.count,
                portalCounts: portalCounts
            )
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 290)
        } content: {
            Group {
                switch navigationSection {
                case .queuedJobs:
                    JobsListView(
                        title: "Pending Queue (\(queuedJobs.count))",
                        jobs: queuedJobs,
                        selectedJob: $selectedJob,
                        onSelect: { job in selectJob(job) }
                    )
                case .portal(let portal):
                    let portalJobs = queuedJobs.filter { $0.portalSource == portal }
                    PortalJobsView(
                        portal: portal,
                        jobs: portalJobs,
                        selectedJob: $selectedJob,
                        isCrawling: isCrawling,
                        onSelect: { job in selectJob(job) },
                        onCrawlPortal: { crawlSpecificPortal(portal) },
                        onOpenPortalLive: { openPortalInBrowser(portal) }
                    )
                case .applicationsLedger:
                    ApplicationsListView(
                        applications: applications,
                        selectedApp: $selectedApplication,
                        onSelect: { app in
                            self.selectedApplication = app
                            WebKitCoordinator.shared.load(url: app.url)
                        }
                    )
                case .outreachCampaigns:
                    OutreachListView(outreaches: outreaches)
                case .candidateProfile:
                    ProfileMiddleColumnView(onSwitchToBrowser: {
                        navigationSection = .queuedJobs
                    })
                case .none:
                    Text("Select a section")
                }
            }
            .navigationSplitViewColumnWidth(min: 270, ideal: 310, max: 390)
        } detail: {
            if navigationSection == .candidateProfile {
                FullPageProfileAndSettingsView()
            } else {
                HStack(spacing: 0) {
                    // Foreground Interactive WebKit Browser
                    BrowserContainerView()
                    
                    Divider()
                    
                    // Inspector & Policy Panel
                    InspectorView(
                        selectedJob: selectedJob,
                        onSelectJob: { job in
                            selectJob(job)
                        },
                        onCrawlPortals: {
                            triggerLightpandaCrawl()
                        }
                    )
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: reloadData) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: triggerLightpandaCrawl) {
                    HStack(spacing: 4) {
                        if isCrawling {
                            ProgressView().scaleEffect(0.6)
                        } else {
                            Image(systemName: "sparkle.magnifyingglass")
                        }
                        Text("Find Jobs (All Portals)")
                    }
                }
                .disabled(isCrawling)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    if navigationSection == .candidateProfile {
                        navigationSection = .queuedJobs
                    } else {
                        navigationSection = .candidateProfile
                    }
                }) {
                    Label(navigationSection == .candidateProfile ? "Job Browser" : "Profile & Settings",
                          systemImage: navigationSection == .candidateProfile ? "safari" : "person.crop.circle.badge.gearshape")
                }
            }
        }
        .sheet(isPresented: $showSetupWizard) {
            SetupWizardView(isPresented: $showSetupWizard, onComplete: {
                reloadData()
            })
        }
        .onAppear {
            reloadData()
        }
    }
    
    private func selectJob(_ job: JobPosting) {
        self.selectedJob = job
        let matched = job.matchedResume ?? ResumeMatcher.shared.selectBestResume(title: job.title, description: job.descriptionText)
        WebKitCoordinator.shared.activeResumePath = matched.isEmpty ? nil : matched
        WebKitCoordinator.shared.load(url: job.url)
    }
    
    private func reloadData() {
        self.queuedJobs = db.fetchQueuedJobs()
        self.applications = db.fetchApplications()
        self.outreaches = db.fetchOutreachRecords()
        self.portalCounts = db.fetchPortalCounts()
        if selectedJob == nil, let first = queuedJobs.first {
            selectedJob = first
        }
    }
    
    private func triggerLightpandaCrawl() {
        guard !isCrawling else { return }
        isCrawling = true
        WebKitCoordinator.shared.statusMessage = "Searching LinkedIn, Workday, Lever, Greenhouse & Ashby..."
        
        Task {
            let res = await LightpandaService.shared.crawlAllPortals(db: db)
            let total = res.ashby + res.greenhouse + res.linkedin + res.workday + res.lever
            
            await MainActor.run {
                self.isCrawling = false
                self.reloadData()
                WebKitCoordinator.shared.statusMessage = "Crawl complete: +\(res.linkedin) LinkedIn, +\(res.workday) Workday, +\(res.lever) Lever, +\(res.greenhouse) Greenhouse, +\(res.ashby) Ashby (\(total) new)"
            }
        }
    }
    
    private func crawlSpecificPortal(_ portal: PortalSource) {
        guard !isCrawling else { return }
        isCrawling = true
        WebKitCoordinator.shared.statusMessage = "Crawling \(portal.displayName)..."
        
        Task {
            var added = 0
            switch portal {
            case .linkedin:
                added = await LightpandaService.shared.crawlLinkedInJobs(db: db)
            case .workday:
                added = await LightpandaService.shared.crawlWorkdayJobs(db: db)
            case .lever:
                added = await LightpandaService.shared.crawlLeverJobs(db: db)
            case .greenhouse:
                for b in ["stripe", "airbnb", "figma", "notion", "databricks", "gusto", "pinterest", "robinhood"] {
                    added += await LightpandaService.shared.crawlGreenhouseBoard(boardSlug: b, db: db)
                }
            case .ashby:
                for b in ["vantage", "incident", "warp", "postman", "sentry", "retool", "neon", "axiom"] {
                    added += await LightpandaService.shared.crawlAshbyBoard(orgSlug: b, db: db)
                }
            default:
                break
            }
            
            await MainActor.run {
                self.isCrawling = false
                self.reloadData()
                WebKitCoordinator.shared.statusMessage = "Found \(added) new roles on \(portal.displayName)."
            }
        }
    }
    
    private func openPortalInBrowser(_ portal: PortalSource) {
        let profile = ProfileService.shared.profile
        let target = profile.targetJobTitles.first ?? (profile.profession.isEmpty || profile.profession == "General" ? "Software Engineer" : profile.profession)
        let encoded = target.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "remote"
        
        let targetURL: String
        switch portal {
        case .linkedin:
            targetURL = "https://www.linkedin.com/jobs/search/?keywords=\(encoded)&f_WT=2"
        case .workday:
            targetURL = "https://www.google.com/search?q=site:myworkdayjobs.com+\(encoded)+remote"
        case .googleJobs:
            targetURL = "https://www.google.com/search?q=\(encoded)+remote+jobs&ibp=htl;jobs"
        case .greenhouse:
            targetURL = "https://www.google.com/search?q=site:job-boards.greenhouse.io+\(encoded)+remote"
        case .ashby:
            targetURL = "https://www.google.com/search?q=site:jobs.ashbyhq.com+\(encoded)+remote"
        case .lever:
            targetURL = "https://www.google.com/search?q=site:jobs.lever.co+\(encoded)+remote"
        case .direct:
            targetURL = "https://www.google.com/search?q=\(encoded)+remote+careers"
        }
        
        WebKitCoordinator.shared.load(url: targetURL)
    }
}

// MARK: - Job Row View (Hyperlink Style)

struct JobRowView: View {
    let job: JobPosting
    let isSelected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 4) {
                Text(job.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.accentColor)
                    .lineLimit(2)
                
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundColor(.accentColor.opacity(0.8))
                
                Spacer()
            }
            
            HStack(spacing: 6) {
                if job.isRemote {
                    Text("Remote")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                }
                
                Text(job.locationRaw)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                Text(job.portalSource.displayName)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.8))
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Portal Jobs View

struct PortalJobsView: View {
    let portal: PortalSource
    let jobs: [JobPosting]
    @Binding var selectedJob: JobPosting?
    let isCrawling: Bool
    let onSelect: (JobPosting) -> Void
    let onCrawlPortal: () -> Void
    let onOpenPortalLive: () -> Void
    
    private var groupedJobs: [String: [JobPosting]] {
        Dictionary(grouping: jobs, by: { $0.companyName })
    }
    
    private var sortedCompanies: [String] {
        groupedJobs.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Portal Action Header Bar
            HStack(spacing: 8) {
                Button(action: onCrawlPortal) {
                    HStack(spacing: 4) {
                        if isCrawling {
                            ProgressView().scaleEffect(0.6)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text("Crawl \(portal.displayName)")
                    }
                    .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCrawling)
                
                Button(action: onOpenPortalLive) {
                    HStack(spacing: 4) {
                        Image(systemName: "safari")
                        Text("Live Portal")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            if jobs.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No \(portal.displayName) Jobs Yet")
                        .font(.headline)
                    Text("Click 'Crawl \(portal.displayName)' to search for remote positions matching your profile, or 'Live Portal' to browse.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Spacer()
                }
            } else {
                List(selection: $selectedJob) {
                    ForEach(sortedCompanies, id: \.self) { company in
                        Section {
                            ForEach(groupedJobs[company]!) { job in
                                JobRowView(job: job, isSelected: selectedJob?.id == job.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        onSelect(job)
                                    }
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: "building.2.crop.circle")
                                    .foregroundColor(.blue)
                                Text(company)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                Spacer()
                                Text("\(groupedJobs[company]!.count) \(groupedJobs[company]!.count == 1 ? "role" : "roles")")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("\(portal.displayName) (\(jobs.count))")
    }
}

// MARK: - Jobs List View

struct JobsListView: View {
    let title: String
    let jobs: [JobPosting]
    @Binding var selectedJob: JobPosting?
    let onSelect: (JobPosting) -> Void
    
    private var groupedJobs: [String: [JobPosting]] {
        Dictionary(grouping: jobs, by: { $0.companyName })
    }
    
    private var sortedCompanies: [String] {
        groupedJobs.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    var body: some View {
        List(selection: $selectedJob) {
            ForEach(sortedCompanies, id: \.self) { company in
                Section {
                    ForEach(groupedJobs[company]!) { job in
                        JobRowView(job: job, isSelected: selectedJob?.id == job.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelect(job)
                            }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: "building.2.crop.circle")
                            .foregroundColor(.blue)
                        Text(company)
                            .font(.caption)
                            .fontWeight(.bold)
                        Spacer()
                        Text("\(groupedJobs[company]!.count) \(groupedJobs[company]!.count == 1 ? "role" : "roles")")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle(title)
    }
}

// MARK: - Applications List View

struct ApplicationsListView: View {
    let applications: [ApplicationRecord]
    @Binding var selectedApp: ApplicationRecord?
    let onSelect: (ApplicationRecord) -> Void
    
    var body: some View {
        List(applications, selection: $selectedApp) { app in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(app.companyName)
                        .font(.headline)
                    Spacer()
                    Text(app.status.uppercased())
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                }
                Text(app.jobTitle)
                    .font(.subheadline)
                    .lineLimit(1)
                Text("Submitted: \(app.submittedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect(app)
            }
        }
        .navigationTitle("Ledger (\(applications.count))")
    }
}

// MARK: - Outreach List View

struct OutreachListView: View {
    let outreaches: [OutreachRecord]
    
    var body: some View {
        List(outreaches) { o in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(o.companyName)
                        .font(.headline)
                    Spacer()
                    Text(o.emailStatus.capitalized)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.2))
                        .foregroundColor(.purple)
                        .cornerRadius(4)
                }
                Text("\(o.recruiterName) — \(o.recruiterTitle)")
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Text("Role: \(o.roleTargeted)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Outreach (\(outreaches.count))")
    }
}

// MARK: - Profile Middle Column View

struct ProfileMiddleColumnView: View {
    let onSwitchToBrowser: () -> Void
    @ObservedObject var profileService = ProfileService.shared
    
    var body: some View {
        let p = profileService.profile
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(p.fullName.isEmpty ? "Candidate Profile" : p.fullName)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(p.profession.isEmpty ? "General" : p.profession)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("WORKSPACE SECTIONS")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    Image(systemName: "person.text.rectangle")
                        .foregroundColor(.blue)
                    Text("Personal & Contact Details")
                        .font(.caption)
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "target")
                        .foregroundColor(.purple)
                    Text("Career Targets (\(p.targetJobTitles.count))")
                        .font(.caption)
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.green)
                    Text("Resumes Managed (\(p.resumes.count))")
                        .font(.caption)
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.orange)
                    Text("AI Engine (\(p.aiProvider.capitalized))")
                        .font(.caption)
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "cylinder")
                        .foregroundColor(.secondary)
                    Text("Local SQLite Storage")
                        .font(.caption)
                }
            }
            
            Spacer()
            
            Button(action: onSwitchToBrowser) {
                HStack {
                    Image(systemName: "safari")
                    Text("Back to Job Browser")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 8)
        }
        .padding()
        .navigationTitle("Profile & Settings")
    }
}
