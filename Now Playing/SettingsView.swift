import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var hoveredPlayer: String?
    @Environment(\.openWindow) var openWindow
    
    var body: some View {
        ZStack {
            // Background with material
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image("Icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 90, height: 90)
                        
                        Text("Now Playing Settings")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    .padding(.top, 20)
                    
                    // Appearance Section
                    SettingsSection(title: "Appearance", icon: "paintbrush.fill") {
                        SettingsToggleRow(
                            icon: "textformat.size",
                            title: "Compact Mode",
                            description: "Minimized text-only display",
                            isOn: $settings.isTextMode
                        )
                        
                        SettingsToggleRow(
                            icon: "sparkles",
                            title: "Dynamic Background",
                            description: "Animated gradient background",
                            isOn: $settings.useDynamicBackground
                        )
                        
                        SettingsToggleRow(
                            icon: "chart.bar.fill",
                            title: "Progress Bar",
                            description: "Show progress bar instead of time",
                            isOn: $settings.showProgressBar
                        )
                    }
                    
                    // Data Source Section
                    SettingsSection(title: "Data Source", icon: "antenna.radiowaves.left.and.right") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("", selection: $settings.retrievalMode) {
                                Label("Music Players", systemImage: "music.note.list")
                                    .tag(0)
                                Label("All Media", systemImage: "waveform")
                                    .tag(1)
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                            
                            Text(settings.retrievalMode == 0
                                 ? "Uses specific integrations for Apple Music, Spotify, and Foobar2000. Configure priority below."
                                 : "Uses macOS MediaRemote to detect any playing media from any app.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 8)
                        }
                    }
                    
                    // Player Priority Section (only in Music Players mode)
                    if settings.retrievalMode == 0 {
                        SettingsSection(title: "Player Priority", icon: "list.number") {
                            VStack(spacing: 0) {
                                List {
                                    ForEach(settings.playerOrder, id: \.self) { player in
                                        if let index = settings.playerOrder.firstIndex(of: player) {
                                            PlayerRow(
                                                player: player,
                                                index: index,
                                                isEnabled: settings.isPlayerEnabled(player),
                                                isHovered: hoveredPlayer == player,
                                                onToggle: { settings.togglePlayer(player) }
                                            )
                                            .listRowInsets(EdgeInsets())
                                            .listRowBackground(Color.clear)
                                            .listRowSeparator(.hidden)
                                            .onHover { isHovered in
                                                hoveredPlayer = isHovered ? player : nil
                                            }
                                        }
                                    }
                                    .onMove(perform: move)
                                }
                                .listStyle(.plain)
                                .scrollContentBackground(.hidden)
                                .frame(height: CGFloat(settings.playerOrder.count * 60))
                                
                                Text("Drag to reorder • Toggle to enable/disable")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(12)
                            }
                        }
                        .animation(.default, value: settings.playerOrder)
                    }
                    
                    // Footer
                    VStack(spacing: 8) {
                        Text("Now Playing V1.1")
                            .font(.footnote)
                            .foregroundColor(.primary)
                        Text("􀀈2026 RKI/exitcode0-dev")
                            .font(.footnote)
                            .foregroundColor(.primary)
                        Button("About") {
                            openWindow(id: "about-window")
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 550)
    }
    
    func move(from source: IndexSet, to destination: Int) {
        settings.playerOrder.move(fromOffsets: source, toOffset: destination)
    }
}

// MARK: - Settings Section
struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue)
                
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .padding(.leading, 4)
            
            VStack(spacing: 0) {
                content
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
}

// MARK: - Toggle Row
struct SettingsToggleRow: View {
    let icon: String
    let title: String
    let description: String
    @Binding var isOn: Bool
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.blue.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.blue)
        }
        .padding(12)
        .background(isHovered ? Color.white.opacity(0.05) : Color.clear)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Player Row
struct PlayerRow: View {
    let player: String
    let index: Int
    let isEnabled: Bool
    let isHovered: Bool
    let onToggle: () -> Void
    
    private var playerIcon: String {
        switch player {
        case "Apple Music": return "music.note"
        case "Spotify": return "play.circle.fill"
        case "Foobar2000": return "waveform"
        default: return "music.note"
        }
    }
    
    private var playerColor: Color {
        switch player {
        case "Apple Music": return .red
        case "Spotify": return .green
        case "Foobar2000": return .orange
        default: return .blue
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14))
                .foregroundColor(.secondary.opacity(isHovered ? 0.8 : 0.4))
                .frame(width: 20)
            
            // Priority number
            ZStack {
                Circle()
                    .fill(playerColor.opacity(0.2))
                    .frame(width: 28, height: 28)
                
                Text("\(index + 1)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(playerColor)
            }
            
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(playerColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: playerIcon)
                    .font(.system(size: 16))
                    .foregroundColor(playerColor)
            }
            
            // Name
            Text(player)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(isEnabled ? .primary : .secondary)
            
            Spacer()
            
            // Toggle
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(playerColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isHovered ? Color.white.opacity(0.05) : Color.clear)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .opacity(isEnabled ? 1.0 : 0.6)
    }
}

// Preview
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
