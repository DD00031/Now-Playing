import SwiftUI
import AppKit

struct ScaleOnTapButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

struct ContentView: View {
    @StateObject var mediaController = MediaController()
    @ObservedObject var settings = SettingsManager.shared
    
    // --- View-local state for smooth time updates ---
    @State private var displayTime: Double = 0.0
    @State private var displayTimer: Timer? = nil
    
    // For smooth progress bar updates
    @State private var smoothProgress: Double = 0.0
    
    // --- Dynamic Background State ---
    @State private var bgStart = UnitPoint.topLeading
    @State private var bgEnd = UnitPoint.bottomTrailing
    
    // Keep track of last gradient to prevent flashing
    @State private var lastGradientColors: [Color] = []
    @State private var fallbackTimer: Timer?
    @State private var shouldShowFallback = false
    
    let albumArt = "photo.artframe"
    
    private var gradientColors: [Color] {
        if !mediaController.mediaInfo.gradientColors.isEmpty {
            return mediaController.mediaInfo.gradientColors.map { Color(nsColor: $0) }
        }
        // If nothing is playing and we should show fallback, use pink/purple
        if shouldShowFallback || mediaController.mediaInfo.title == "Nothing Playing" {
            return [Color.pink, Color.purple]
        }
        // Otherwise keep last known colors
        if !lastGradientColors.isEmpty {
            return lastGradientColors
        }
        return [Color.pink, Color.purple]
    }
    
    private var dominantColor: Color {
        if let nsColor = mediaController.mediaInfo.dominantColor {
            return Color(nsColor: nsColor)
        }
        return Color.gray
    }
    
    private var progress: Double {
        guard mediaController.mediaInfo.totalTime > 0 else { return 0 }
        return min(displayTime / mediaController.mediaInfo.totalTime, 1.0)
    }
    
    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            
            ZStack {
                // --- Background Layer with Extracted Gradient ---
                if settings.useDynamicBackground {
                    LinearGradient(
                        colors: gradientColors.map { $0.opacity(0.8) } + [Color.black.opacity(0.9)],
                        startPoint: bgStart,
                        endPoint: bgEnd
                    )
                    .ignoresSafeArea()
                    .onAppear {
                        withAnimation(.easeInOut(duration: 5.0).repeatForever(autoreverses: true)) {
                            bgStart = .top
                            bgEnd = .bottom
                        }
                    }
                } else {
                    LinearGradient(
                        colors: gradientColors.map { $0.opacity(0.9) } + [Color.black.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                }
                
                // Blur overlay
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                
                // --- Main Content ---
                VStack(spacing: 0) {
                    
                    if settings.isTextMode {
                        // --- TEXT MODE UI ---
                        VStack(spacing: 4) {
                            Spacer()
                            MarqueeText(
                                content: mediaController.mediaInfo.title,
                                font: .systemFont(ofSize: 16, weight: .bold)
                            )
                            .foregroundColor(.white)
                            
                            MarqueeText(
                                content: mediaController.mediaInfo.artist,
                                font: .systemFont(ofSize: 13, weight: .medium)
                            )
                            .foregroundColor(.white.opacity(0.8))
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        
                    } else {
                        // --- NORMAL MODE UI ---
                        Spacer()
                        
                        // Album Art
                        let artworkSize = min(max(size.width * 0.7, 200), 320)
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.1))
                                .shadow(color: gradientColors.first?.opacity(0.5) ?? .clear, radius: 30, x: 0, y: 15)
                            
                            if let art = mediaController.mediaInfo.artwork {
                                Image(nsImage: art)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .transition(.opacity)
                                    .id(mediaController.mediaInfo.title)
                            } else {
                                Image("Icon")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: artworkSize * 0.6)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        .frame(width: artworkSize, height: artworkSize)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .animation(.easeInOut, value: mediaController.mediaInfo.artwork)
                        
                        Spacer().frame(height: 30)
                        
                        // Text Info
                        VStack(spacing: 6) {
                            MarqueeText(
                                content: mediaController.mediaInfo.title,
                                font: .systemFont(ofSize: 22, weight: .semibold)
                            )
                            .foregroundColor(.white)
                            
                            MarqueeText(
                                content: mediaController.mediaInfo.artist + "   -   " + mediaController.mediaInfo.album,
                                font: .systemFont(ofSize: 16, weight: .regular)
                            )
                            .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.horizontal, 20)
                        
                        Spacer().frame(height: 20)
                        
                        // Progress Bar or Time Display
                        if settings.showProgressBar {
                            VStack(spacing: 8) {
                                // Draggable Progress Bar
                                DraggableProgressBar(
                                    progress: smoothProgress,
                                    gradientColors: [Color.white, dominantColor],
                                    onSeek: { newProgress in
                                        let seekTime = newProgress * mediaController.mediaInfo.totalTime
                                        mediaController.seek(to: seekTime)
                                        displayTime = seekTime
                                    }
                                )
                                .frame(height: 6)
                                .padding(.horizontal, geo.size.width*0.06)
                                .frame(maxWidth: 1300)
                                
                                // Time labels
                                HStack {
                                    Text(formatTime(displayTime))
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.6))
                                    
                                    Spacer()
                                    
                                    Text(formatTime(mediaController.mediaInfo.totalTime))
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                .padding(.horizontal, geo.size.width*0.06)
                                .frame(maxWidth: 1300)
                            }
                        } else {
                            // Time only display
                            Text("\(formatTime(displayTime)) / \(formatTime(mediaController.mediaInfo.totalTime))")
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        
                        Spacer().frame(height: 30)
                        
                        // Controls
                        HStack(spacing: 40) {
                            ControlBtn(icon: "backward.fill") {
                                mediaController.prevTrack()
                            }
                            
                            Button {
                                mediaController.togglePlayPause()
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(.gray)
                                        .frame(width: 60, height: 60)
                                        .opacity(0.15)
                                        .shadow(color: gradientColors.first?.opacity(0.5) ?? .clear, radius: 4, x: 0, y: 0)

                                    Image(systemName: mediaController.mediaInfo.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                }
                            }
                            .buttonStyle(ScaleOnTapButtonStyle())
                            
                            ControlBtn(icon: "forward.fill") {
                                mediaController.nextTrack()
                            }
                        }
                        
                        Spacer()
                    }
                }
            }
        }
        // --- Window Resizing Logic ---
        .onChange(of: settings.isTextMode) { isText in
            if let window = NSApp.windows.first {
                var frame = window.frame
                if isText {
                    // Shrink
                    frame.size = CGSize(width: 300, height: 100)
                } else {
                    // Restore
                    frame.size = CGSize(width: 350, height: 600)
                }
                window.setFrame(frame, display: true, animate: true)
            }
        }
        .frame(minWidth: settings.isTextMode ? 250 : 320,
               minHeight: settings.isTextMode ? 80 : 600)
        // --- Timer logic ---
        .onAppear {
            displayTime = mediaController.mediaInfo.currentTime
            smoothProgress = progress
            startDisplayTimer(if: mediaController.mediaInfo.isPlaying)
        }
        .onDisappear {
            displayTimer?.invalidate()
            fallbackTimer?.invalidate()
        }
        .onChange(of: mediaController.mediaInfo.currentTime) {
            displayTime = mediaController.mediaInfo.currentTime
            withAnimation(.linear(duration: 0.3)) {
                smoothProgress = progress
            }
        }
        .onChange(of: mediaController.mediaInfo.isPlaying) { isPlaying in
            startDisplayTimer(if: isPlaying)
        }
        .onChange(of: progress) { newProgress in
            if mediaController.mediaInfo.isPlaying {
                withAnimation(.linear(duration: 0.5)) {
                    smoothProgress = newProgress
                }
            } else {
                smoothProgress = newProgress
            }
        }
        .onChange(of: mediaController.mediaInfo.gradientColors) { newColors in
            // Update last gradient colors when we have valid ones (prevents flash)
            if !newColors.isEmpty {
                // Cancel fallback timer since we have new colors
                fallbackTimer?.invalidate()
                shouldShowFallback = false
                
                withAnimation(.easeInOut(duration: 0.6)) {
                    lastGradientColors = newColors.map { Color(nsColor: $0) }
                }
            }
        }
        .onChange(of: mediaController.mediaInfo.title) { newTitle in
            // When track changes to "Nothing Playing", start a 3s timer before showing fallback
            if newTitle == "Nothing Playing" {
                fallbackTimer?.invalidate()
                fallbackTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                    withAnimation(.easeInOut(duration: 1.0)) {
                        shouldShowFallback = true
                    }
                }
            } else {
                // If we start playing something, cancel the fallback
                fallbackTimer?.invalidate()
                shouldShowFallback = false
            }
        }
    }
    
    // --- Helpers ---
    private func startDisplayTimer(if isPlaying: Bool) {
        displayTimer?.invalidate()
        if isPlaying {
            displayTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                displayTime += 0.1
            }
        }
    }
    
    func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Draggable Progress Bar
struct DraggableProgressBar: View {
    let progress: Double
    let gradientColors: [Color]
    let onSeek: (Double) -> Void
    
    @State private var isDragging = false
    @State private var dragProgress: Double?
    
    private var displayProgress: Double {
        isDragging ? (dragProgress ?? progress) : progress
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                    )
                
                // Progress fill
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: gradientColors.isEmpty ?
                                [.white.opacity(0.9), .gray.opacity(0.8)] :
                                gradientColors.map { $0.opacity(0.9) },
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * displayProgress)
                    .shadow(color: gradientColors.first?.opacity(0.5) ?? .clear, radius: 4, x: 0, y: 0)
                
                // Thumb (only visible when dragging or hovering)
                if isDragging {
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        .offset(x: geometry.size.width * displayProgress - 7)
                }
            }
            .contentShape(Rectangle()) // Make entire area tappable
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let newProgress = max(0, min(1, value.location.x / geometry.size.width))
                        dragProgress = newProgress
                    }
                    .onEnded { value in
                        let finalProgress = max(0, min(1, value.location.x / geometry.size.width))
                        onSeek(finalProgress)
                        isDragging = false
                        dragProgress = nil
                    }
            )
        }
    }
}

struct ControlBtn: View {
    let icon: String
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button {
            action()
        } label: {
            ZStack {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(ScaleOnTapButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

// --- MarqueeText View ---
struct MarqueeText: View {
    let content: String
    let font: NSFont
    
    @State private var textWidth: CGFloat = 0
    @State private var animate = false
    private let spacing: CGFloat = 40

    var body: some View {
        let duration = (textWidth + spacing) / 40
        let textView = Text(content).font(Font(font)).lineLimit(1).fixedSize()

        GeometryReader { geometry in
            let containerWidth = geometry.size.width
            let shouldAnimate = textWidth > containerWidth
            
            ZStack(alignment: .center) {
                if shouldAnimate {
                    HStack(spacing: spacing) { textView; textView }
                        .offset(x: animate ? -(textWidth + spacing) : 0)
                        .animation(
                            animate ? Animation.linear(duration: duration).delay(3.0).repeatForever(autoreverses: false) : .default,
                            value: animate
                        )
                        .frame(minWidth: containerWidth, alignment: .leading)
                } else {
                    textView
                }
            }
            .frame(width: containerWidth)
            .onAppear {
                self.textWidth = content.width(usingFont: font)
                self.animate = self.textWidth > containerWidth
            }
            .onChange(of: content) {
                self.animate = false
                self.textWidth = content.width(usingFont: font)
                DispatchQueue.main.async { self.animate = self.textWidth > containerWidth }
            }
            .onChange(of: geometry.size.width) {
                self.animate = false
                DispatchQueue.main.async { self.animate = self.textWidth > containerWidth }
            }
        }
        .frame(height: font.pointSize * 1.5)
        .clipped()
    }
}

extension String {
    func width(usingFont font: NSFont) -> CGFloat {
        let fontAttributes = [NSAttributedString.Key.font: font]
        let size = self.size(withAttributes: fontAttributes)
        return size.width
    }
}
