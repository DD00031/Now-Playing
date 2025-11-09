import SwiftUI

// --- ButtonStyle for the bouncy animation ---
struct ScaleOnTapButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Scale down when pressed
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            // Animate the scale effect with a spring
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

struct ContentView: View {
    @StateObject var mediaController = MediaController()
    
    // --- View-local state for smooth time updates ---
    @State private var displayTime: Double = 0.0
    @State private var displayTimer: Timer? = nil
    
    let albumArt = "photo.artframe" // Placeholder
    
    private var dominantColor: Color {
        if let nsColor = mediaController.mediaInfo.dominantColor {
            return Color(nsColor: nsColor)
        }
        return Color.gray
    }
    
    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            let artworkSize = min(max(size.width * 0.7, 280), 320) // 70% of width, min 280, max 320
            let titleFontSize = min(max(size.width * 0.07, 24), 28) // 7% of width, min 24, max 28
            let artistFontSize = min(max(size.width * 0.045, 16), 20) // min 16, max 20
            let albumFontSize = min(max(size.width * 0.035, 14), 16) // min 14, max 16
            let timeFontSize = min(max(size.width * 0.038, 15), 16) // min 15, max 16
            let buttonFontSize = min(max(size.width * 0.07, 28), 32) // min 28, max 32
            let playButtonSize = min(max(size.width * 0.175, 70), 80) // min 70, max 80
            let mainSpacing = min(max(size.height * 0.03, 20), 24) // min 20, max 24
            
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        dominantColor.opacity(0.9),
                        dominantColor.opacity(0.6),
                        Color.black.opacity(0.9)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 1.0), value: dominantColor)
                
                // Blur effect overlay
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                
                VStack(spacing: mainSpacing) { // Use responsive spacing
                    Spacer(minLength: 10)
                    
                    // Album Art
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.1))
                            .shadow(color: dominantColor.opacity(0.5), radius: 30, x: 0, y: 15)
                        
                        // --- Inner ZStack for fade animation ---
                        ZStack {
                            if let art = mediaController.mediaInfo.artwork {
                                Image(nsImage: art)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .transition(.opacity)
                                    // Use title as ID to force transition on change
                                    .id(mediaController.mediaInfo.title)
                            } else {
                                // Placeholder
                                Image(systemName: albumArt)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: artworkSize * 0.8, height: artworkSize * 0.8) // Scale placeholder
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [dominantColor.opacity(0.8), dominantColor.opacity(0.5)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .transition(.opacity)
                                    .id("placeholder") // ID for placeholder
                            }
                        }
                        // --- Animate when artwork (which is optional) changes ---
                        .animation(.easeInOut(duration: 0.75), value: mediaController.mediaInfo.artwork)
                        .frame(width: artworkSize, height: artworkSize) // Apply frame to inner ZStack
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        
                    }
                    .frame(width: artworkSize, height: artworkSize) // Apply frame to outer ZStack
                    
                    // --- Song Info now uses MarqueeText ---
                    VStack(spacing: 8) {
                        MarqueeText(
                            content: mediaController.mediaInfo.title,
                            font: .systemFont(ofSize: titleFontSize, weight: .semibold)
                        )
                        .foregroundColor(.white)
                        
                        MarqueeText(
                            content: mediaController.mediaInfo.artist,
                            font: .systemFont(ofSize: artistFontSize, weight: .regular)
                        )
                        .foregroundColor(.white.opacity(0.7))

                        MarqueeText(
                            content: mediaController.mediaInfo.album,
                            font: .systemFont(ofSize: albumFontSize, weight: .regular)
                        )
                        .foregroundColor(.white.opacity(0.5))
                    }
                    // --- Widen padding ---
                    .padding(.horizontal, 20)
                    
                    // --- Use local displayTime ---
                    Text("\(formatTime(displayTime)) / \(formatTime(mediaController.mediaInfo.totalTime))")
                        .font(.system(size: timeFontSize, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                    
                    // Playback Controls - Responsive
                    HStack(spacing: 50) {
                        // Previous Button
                        Button(action: mediaController.prevTrack) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: buttonFontSize))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(ScaleOnTapButtonStyle()) // --- Apply animation
                        
                        // Play/Pause Button
                        Button(action: mediaController.togglePlayPause) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.2))
                                    .frame(width: playButtonSize, height: playButtonSize) // Responsive size
                                
                                Image(systemName: mediaController.mediaInfo.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: buttonFontSize)) // Responsive icon
                                    .foregroundColor(.white)
                                    .offset(x: mediaController.mediaInfo.isPlaying ? 0 : 2)
                            }
                        }
                        .buttonStyle(ScaleOnTapButtonStyle()) // --- Apply animation
                        
                        // Next Button
                        Button(action: mediaController.nextTrack) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: buttonFontSize))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(ScaleOnTapButtonStyle()) // --- Apply animation
                    }
                    
                    Spacer(minLength: 10) // Use minLength Spacer
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                .padding(.horizontal, max(size.width * 0.05, 20)) // Responsive horizontal padding
            }
        }
        .frame(minWidth: 320, minHeight: 650) // Min height is 650
        // --- Timer logic for smooth time display ---
        .onAppear {
            // Sync time on appear
            displayTime = mediaController.mediaInfo.currentTime
            // Start timer if playing
            startDisplayTimer(if: mediaController.mediaInfo.isPlaying)
        }
        .onDisappear {
            // Clean up timer
            displayTimer?.invalidate()
        }
        .onChange(of: mediaController.mediaInfo.currentTime) {
            // Sync displayTime when the model updates (e.g., new song)
            displayTime = mediaController.mediaInfo.currentTime
        }
        .onChange(of: mediaController.mediaInfo.isPlaying) { isPlaying in
            // Start/stop the timer when play state changes
            startDisplayTimer(if: isPlaying)
        }
    }
    
    // --- Helper function to manage the view's timer ---
    private func startDisplayTimer(if isPlaying: Bool) {
        displayTimer?.invalidate()
        if isPlaying {
            displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                // Only increment here. Syncing happens in .onChange
                displayTime += 1.0
            }
        }
    }
    
    func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
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
        // --- Set a slower, fixed speed (40 pixels per second) ---
        // Duration = Distance / Speed
        let duration = (textWidth + spacing) / 40
        
        // This is the view that will be displayed
        let textView = Text(content)
            .font(Font(font))
            .lineLimit(1)
            .fixedSize()

        // This ZStack will hold everything.
        // It's in a GeometryReader to get the container width.
        GeometryReader { geometry in
            let containerWidth = geometry.size.width
            let shouldAnimate = textWidth > containerWidth
            
            // This ZStack is for alignment.
            // It centers the content if it's not animating.
            ZStack(alignment: .center) {
                if shouldAnimate {
                    // The animating HStack
                    HStack(spacing: spacing) {
                        textView
                        textView
                    }
                    .offset(x: animate ? -(textWidth + spacing) : 0)
                    .animation(
                        animate ?
                        // --- MODIFIED: Longer delay (3.0s) and new duration ---
                        Animation.linear(duration: duration).delay(3.0).repeatForever(autoreverses: false)
                        : .default,
                        value: animate
                    )
                    // This frame is *crucial*. It makes the HStack
                    // start at the leading edge for the offset to work.
                    .frame(minWidth: containerWidth, alignment: .leading)
                    
                } else {
                    // The static, centered text
                    textView
                }
            }
            .frame(width: containerWidth) // Center the ZStack
            .onAppear {
                self.textWidth = content.width(usingFont: font)
                self.animate = self.textWidth > containerWidth
            }
            .onChange(of: content) {
                self.animate = false // Reset animation
                self.textWidth = content.width(usingFont: font)
                DispatchQueue.main.async { // Allow state to reset
                    self.animate = self.textWidth > containerWidth
                }
            }
            .onChange(of: geometry.size.width) {
                self.animate = false // Reset animation
                DispatchQueue.main.async { // Allow state to reset
                    self.animate = self.textWidth > containerWidth
                }
            }
        }
        .frame(height: font.pointSize * 1.5)
        .clipped() // Clip everything
    }
}


// Helper to get text width
extension String {
    func width(usingFont font: NSFont) -> CGFloat {
        let fontAttributes = [NSAttributedString.Key.font: font]
        let size = self.size(withAttributes: fontAttributes)
        return size.width
    }
}

// Preview with color scheme options
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

// App Entry Point
@main
struct NowPlayingApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
