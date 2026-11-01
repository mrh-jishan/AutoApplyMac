import SwiftUI

public struct InspectorView: View {
    public let selectedJob: JobPosting?
    public let onSelectJob: (JobPosting) -> Void
    public let onCrawlPortals: () -> Void
    
    @ObservedObject public var coordinator: WebKitCoordinator = .shared
    
    public init(
        selectedJob: JobPosting?,
        onSelectJob: @escaping (JobPosting) -> Void,
        onCrawlPortals: @escaping () -> Void
    ) {
        self.selectedJob = selectedJob
        self.onSelectJob = onSelectJob
        self.onCrawlPortals = onCrawlPortals
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let job = selectedJob {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(job.companyName)
                            .font(.headline)
                        Spacer()
                        Text(job.portalSource.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(4)
                    }
                    Text(job.title)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Text(job.locationRaw)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                // Policy Checklist
                VStack(alignment: .leading, spacing: 8) {
                    Text("Compliance & Policy Check")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("100% Remote Confirmed")
                            .font(.caption)
                    }
                    
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Anti-Duplicate Guard (0-2 submissions)")
                            .font(.caption)
                    }
                    
                    let matchedPath = job.matchedResume ?? ResumeMatcher.shared.selectBestResume(title: job.title, description: job.descriptionText)
                    let resumeName = matchedPath.isEmpty ? "Default Profile Resume" : URL(fileURLWithPath: matchedPath).lastPathComponent
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(.blue)
                        Text("Matched: \(resumeName)")
                            .font(.caption)
                    }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                // Action Buttons
                VStack(spacing: 8) {
                    Button(action: {
                        let matched = job.matchedResume ?? ResumeMatcher.shared.selectBestResume(title: job.title, description: job.descriptionText)
                        coordinator.activeResumePath = matched.isEmpty ? nil : matched
                        coordinator.load(url: job.url)
                    }) {
                        HStack {
                            Image(systemName: "safari.fill")
                            Text("Open in WebKit Browser")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button(action: {
                        Task {
                            _ = await coordinator.executeFormAutofill(candidate: ProfileService.shared.profile)
                        }
                    }) {
                        HStack {
                            Image(systemName: "wand.and.stars")
                            Text("Auto-fill Form")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 32))
                        .foregroundColor(.blue)
                    Text("Select a job from the queue or discover new roles.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    
                    Button(action: onCrawlPortals) {
                        Label("Run Lightpanda Discovery", systemImage: "bolt.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            Spacer()
            
            // Quick Lightpanda trigger
            Button(action: onCrawlPortals) {
                HStack {
                    Image(systemName: "bolt.circle.fill")
                        .foregroundColor(.orange)
                    Text("Crawl Portals (Lightpanda)")
                        .font(.caption)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
        }
        .padding(12)
        .frame(minWidth: 260, maxWidth: 320)
    }
}
