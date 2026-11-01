import SwiftUI
import WebKit

public struct WebBrowserView: NSViewRepresentable {
    @ObservedObject public var coordinator: WebKitCoordinator
    
    public init(coordinator: WebKitCoordinator = .shared) {
        self.coordinator = coordinator
    }
    
    public func makeNSView(context: Context) -> WKWebView {
        return coordinator.createConfiguredWebView()
    }
    
    public func updateNSView(_ nsView: WKWebView, context: Context) {
        // State updates are handled inside coordinator
    }
}

public struct BrowserContainerView: View {
    @ObservedObject public var coordinator: WebKitCoordinator = .shared
    @State private var inputURL: String = ""
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Navigation Bar
            HStack(spacing: 8) {
                Button(action: { coordinator.webView?.goBack() }) {
                    Image(systemName: "chevron.left")
                }
                .disabled(!(coordinator.webView?.canGoBack ?? false))
                .buttonStyle(.plain)
                
                Button(action: { coordinator.webView?.goForward() }) {
                    Image(systemName: "chevron.right")
                }
                .disabled(!(coordinator.webView?.canGoForward ?? false))
                .buttonStyle(.plain)
                
                Button(action: { coordinator.webView?.reload() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                
                // URL Field
                HStack {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.secondary)
                        .font(.caption2)
                    TextField("Enter URL or select job...", text: $inputURL, onCommit: {
                        var target = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !target.hasPrefix("http://") && !target.hasPrefix("https://") {
                            target = "https://" + target
                        }
                        coordinator.load(url: target)
                    })
                    .textFieldStyle(.plain)
                    .font(.callout)
                    
                    if coordinator.isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                // Autofill trigger button
                Button(action: {
                    Task {
                        _ = await coordinator.executeFormAutofill(candidate: ProfileService.shared.profile)
                    }
                }) {
                    Label("Autofill", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            
            // Direct Embed Banner if iframe detected
            if let directURL = coordinator.detectedDirectIframeURL {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .foregroundColor(.blue)
                    Text("Embedded Job Application Form Detected (Greenhouse/ATS)")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Button("Open Direct Application Form") {
                        coordinator.load(url: directURL)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.12))
            }
            
            // Direct ATS Application Banner (Greenhouse, Lever, Ashby)
            if let directApplyURL = coordinator.detectedDirectApplyURL {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Direct Application Form Found (\(coordinator.detectedJobPlatform ?? "ATS"))")
                            .font(.caption)
                            .fontWeight(.bold)
                        if let comp = coordinator.detectedJobCompany, let title = coordinator.detectedJobTitle {
                            Text("\(comp) • \(title)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button("Apply on \(coordinator.detectedJobPlatform ?? "Company Site") ↗") {
                        coordinator.load(url: directApplyURL)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.12))
            } else if coordinator.currentURL.contains("linkedin.com/jobs/view"),
                      let comp = coordinator.detectedJobCompany,
                      let title = coordinator.detectedJobTitle {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("Viewing role on LinkedIn: \(comp) • \(title)")
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Button("Search Careers Site ↗") {
                        let query = "\(comp) \(title) careers apply"
                            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        coordinator.load(url: "https://www.google.com/search?q=\(query)")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.blue.opacity(0.08))
            }
            
            // Workday Enterprise Portal Assistant Banner
            if coordinator.isWorkdayURL {
                WorkdayAssistantBanner(coordinator: coordinator)
            }
            
            Divider()
            
            // Web View
            WebBrowserView(coordinator: coordinator)
                .frame(minWidth: 400, minHeight: 400)
            
            Divider()
            
            // Status Footer
            HStack {
                Circle()
                    .fill(coordinator.isLoading ? Color.orange : Color.green)
                    .frame(width: 8, height: 8)
                Text(coordinator.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if let resume = coordinator.activeResumePath {
                    Text("Selected: \(URL(fileURLWithPath: resume).lastPathComponent)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .onReceive(coordinator.$currentURL) { newURL in
            if !newURL.isEmpty {
                self.inputURL = newURL
            }
        }
    }
}

struct WorkdayAssistantBanner: View {
    @ObservedObject var coordinator: WebKitCoordinator
    @State private var isExecuting: Bool = false
    
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: "briefcase.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 13, weight: .bold))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Workday Enterprise Portal")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text(stageBadge)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(stageBadgeColor.opacity(0.15))
                        .foregroundColor(stageBadgeColor)
                        .cornerRadius(4)
                }
                
                Text(stageDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                if coordinator.currentURL.contains("/apply/") {
                    Button {
                        Task {
                            isExecuting = true
                            _ = await coordinator.executeFormAutofill(candidate: ProfileService.shared.profile)
                            isExecuting = false
                        }
                    } label: {
                        Label(isExecuting ? "Autofilling..." : "Autofill Step", systemImage: "bolt.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                    .disabled(isExecuting)
                    
                    Button {
                        Task {
                            _ = await coordinator.triggerResumeUpload()
                        }
                    } label: {
                        Label("Attach Resume", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button {
                        Task {
                            _ = await coordinator.workdayAdvanceStep()
                        }
                    } label: {
                        Label("Next Step", systemImage: "arrow.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else if coordinator.currentURL.contains("/job/") || coordinator.currentURL.contains("myworkdayjobs.com") {
                    Button {
                        Task {
                            isExecuting = true
                            _ = await coordinator.workdayStartApply()
                            isExecuting = false
                        }
                    } label: {
                        Label("Start Workday Apply ⚡", systemImage: "play.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                    .disabled(isExecuting)
                } else {
                    Button {
                        Task {
                            isExecuting = true
                            _ = await coordinator.executeFormAutofill(candidate: ProfileService.shared.profile)
                            isExecuting = false
                        }
                    } label: {
                        Label("Autofill Step", systemImage: "bolt.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.08))
    }
    
    private var stageBadge: String {
        if coordinator.currentURL.contains("/apply/") {
            return "Application Wizard"
        } else if coordinator.currentURL.contains("/login") {
            return "Employer Sign In"
        } else if coordinator.currentURL.contains("/job/") {
            return "Job Details"
        } else {
            return "Workday"
        }
    }
    
    private var stageBadgeColor: Color {
        if coordinator.currentURL.contains("/apply/") {
            return .green
        } else if coordinator.currentURL.contains("/login") {
            return .blue
        } else {
            return .orange
        }
    }
    
    private var stageDescription: String {
        if coordinator.currentURL.contains("/apply/") {
            return "Wizard step active. Click 'Autofill Step' to populate fields, then 'Next Step ➔'."
        } else if coordinator.currentURL.contains("/login") {
            return "Workday accounts are per-employer. Sign in or create account to begin."
        } else if coordinator.currentURL.contains("/job/") {
            return "Click 'Start Workday Apply' to launch the application flow and attach resume."
        } else {
            return "Connected to Workday ATS."
        }
    }
}
