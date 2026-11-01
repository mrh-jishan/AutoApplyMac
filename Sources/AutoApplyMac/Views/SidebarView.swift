import SwiftUI

public enum NavigationSection: Hashable {
    case queuedJobs
    case applicationsLedger
    case outreachCampaigns
    case candidateProfile
    case portal(PortalSource)
}

public struct SidebarView: View {
    @Binding public var selection: NavigationSection?
    public let queuedCount: Int
    public let applicationCount: Int
    public let outreachCount: Int
    public let portalCounts: [PortalSource: Int]
    
    public init(
        selection: Binding<NavigationSection?>,
        queuedCount: Int,
        applicationCount: Int,
        outreachCount: Int,
        portalCounts: [PortalSource: Int] = [:]
    ) {
        self._selection = selection
        self.queuedCount = queuedCount
        self.applicationCount = applicationCount
        self.outreachCount = outreachCount
        self.portalCounts = portalCounts
    }
    
    public var body: some View {
        List(selection: $selection) {
            Section(header: Text("Portals & Discovery")) {
                NavigationLink(value: NavigationSection.queuedJobs) {
                    Label {
                        HStack {
                            Text("Pending Queue")
                            Spacer()
                            Text("\(queuedCount)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(8)
                        }
                    } icon: {
                        Image(systemName: "tray.full.fill")
                            .foregroundColor(.blue)
                    }
                }
                
                ForEach(PortalSource.allCases) { portal in
                    NavigationLink(value: NavigationSection.portal(portal)) {
                        Label {
                            HStack {
                                Text(portal.displayName)
                                Spacer()
                                let count = portalCounts[portal] ?? 0
                                if count > 0 {
                                    Text("\(count)")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.15))
                                        .cornerRadius(8)
                                }
                            }
                        } icon: {
                            Image(systemName: portalIcon(for: portal))
                        }
                    }
                }
            }
            
            Section(header: Text("Audit & Outreach")) {
                NavigationLink(value: NavigationSection.applicationsLedger) {
                    Label {
                        HStack {
                            Text("Applications Ledger")
                            Spacer()
                            Text("\(applicationCount)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(8)
                        }
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                    }
                }
                
                NavigationLink(value: NavigationSection.outreachCampaigns) {
                    Label {
                        HStack {
                            Text("Recruiter Outreach")
                            Spacer()
                            Text("\(outreachCount)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.2))
                                .cornerRadius(8)
                        }
                    } icon: {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(.purple)
                    }
                }
            }
            
            Section(header: Text("Profile & Settings")) {
                NavigationLink(value: NavigationSection.candidateProfile) {
                    Label("Candidate Profile & Settings", systemImage: "person.crop.circle.badge.gearshape.fill")
                }
            }
        }
        .listStyle(.sidebar)
    }
    
    private func portalIcon(for portal: PortalSource) -> String {
        switch portal {
        case .googleJobs: return "magnifyingglass"
        case .linkedin: return "network"
        case .workday: return "building.2.fill"
        case .greenhouse: return "leaf.fill"
        case .ashby: return "bolt.fill"
        case .lever: return "slider.horizontal.3"
        case .direct: return "globe"
        }
    }
}
