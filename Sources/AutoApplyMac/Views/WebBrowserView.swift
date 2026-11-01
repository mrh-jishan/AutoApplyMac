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
