import Foundation
import Combine
import CoreGraphics
import AppKit
import CoreImage

struct MediaInfo: Equatable {
    var isPlaying: Bool = false
    var title: String = "Nothing Playing"
    var artist: String = ""
    var album: String = ""
    var currentTime: Double = 0.0
    var totalTime: Double = 1.0
    var artwork: NSImage? = nil
    var dominantColor: NSColor? = nil
    var gradientColors: [NSColor] = []
    var source: String = ""
    
    static func == (lhs: MediaInfo, rhs: MediaInfo) -> Bool {
        return lhs.title == rhs.title && lhs.artist == rhs.artist && lhs.isPlaying == rhs.isPlaying
    }
}

class MediaController: ObservableObject {
    
    @Published var mediaInfo = MediaInfo()
    private var settings = SettingsManager.shared
    private var fetchTimer: Timer?
    
    // --- Album Art Cache ---
    private var artworkCache = [String: NSImage]()
    private var currentArtworkTask: URLSessionDataTask?
    
    // Track last known source to detect switches
    private var lastKnownSource: String = ""
    
    // --- Scripts ---
    private let musicScript = """
    try
        tell application "Music"
            if it is running then
                try
                    if player state is stopped then
                        return "false|Not Playing|||0|0|"
                    end if
                    set currentTrack to current track
                    set trackTitle to name of currentTrack
                    set trackArtist to artist of currentTrack
                    set trackAlbum to album of currentTrack
                    set playerPos to player position
                    set trackDuration to duration of currentTrack
                    if player state is playing then
                        return "true|" & trackTitle & "|" & trackArtist & "|" & trackAlbum & "|" & playerPos & "|" & trackDuration & "|MUSIC_ART"
                    else if player state is paused then
                        return "false|" & trackTitle & "|" & trackArtist & "|" & trackAlbum & "|" & playerPos & "|" & trackDuration & "|MUSIC_ART"
                    else
                        return "false|Not Playing|||0|0|"
                    end if
                on error errMsg
                    return "false|Error: " & errMsg & "|||0|0|"
                end try
            else
                return "false|Music not running|||0|0|"
            end if
        end tell
    on error outerErr
        return "false|Outer Error: " & outerErr & "|||0|0|"
    end try
    """
    
    private let spotifyScript = """
    if application "Spotify" is running then
        tell application "Spotify"
            try
                set trackTitle to name of current track
                set trackArtist to artist of current track
                set trackAlbum to album of current track
                set playerPos to player position
                set trackDuration to (duration of current track) / 1000.0
                set artURL to ""
                try
                    set artURL to artwork url of current track
                on error
                    set artURL to ""
                end try
                if player state is playing then
                    return "true|" & trackTitle & "|" & trackArtist & "|" & trackAlbum & "|" & playerPos & "|" & trackDuration & "|" & artURL
                else if player state is paused then
                    return "false|" & trackTitle & "|" & trackArtist & "|" & trackAlbum & "|" & playerPos & "|" & trackDuration & "|" & artURL
                else
                    return "false|Not Playing|||0|0|"
                end if
            on error
                return "false|Not Playing|||0|0|"
            end try
        end tell
    end if
    return "false|Not Playing|||0|0|"
    """
    
    init() {
        requestPermissions()
        refreshMediaInfo()
    }
    
    deinit {
        fetchTimer?.invalidate()
    }

    @objc private func refreshMediaInfo() {
        DispatchQueue.global(qos: .userInteractive).async {
            self.fetchMediaInfo()
        }
    }
    
    private func fetchMediaInfo() {
        var foundActivePlayer = false
        var newSource = ""
        
        // Mode 1: All Media (MediaRemote Adapter)
        if settings.retrievalMode == 1 {
            if fetchMediaRemote() {
                foundActivePlayer = true
                newSource = "MediaRemote"
            }
        }
        // Mode 0: Priority List (Music Players)
        else {
            let players = settings.playerOrder
            
            for player in players {
                if foundActivePlayer { break }
                
                // Skip disabled players
                if !settings.isPlayerEnabled(player) { continue }
                
                switch player {
                case "Foobar2000":
                    if readFoobarFile() {
                        foundActivePlayer = true
                        newSource = "Foobar2000"
                    }
                case "Spotify":
                    if runAppleScript(script: spotifyScript, parse: true, sourceName: "Spotify") {
                        foundActivePlayer = true
                        newSource = "Spotify"
                    }
                case "Apple Music":
                    if runAppleScript(script: musicScript, parse: true, sourceName: "Apple Music") {
                        foundActivePlayer = true
                        newSource = "Apple Music"
                    }
                default:
                    break
                }
            }
        }
        
        // Detect source switch and force artwork reload
        if newSource != lastKnownSource && !newSource.isEmpty {
            print("Source switched from \(lastKnownSource) to \(newSource) - forcing artwork reload")
            lastKnownSource = newSource
            // Clear current artwork to force reload
            DispatchQueue.main.async {
                if self.mediaInfo.source != newSource {
                    self.mediaInfo.artwork = nil
                    self.mediaInfo.gradientColors = []
                    self.mediaInfo.dominantColor = nil
                }
            }
        }
        
        if !foundActivePlayer {
            DispatchQueue.main.async {
                // Only reset if we aren't already blank
                if self.mediaInfo.title != "Nothing Playing" {
                    self.lastKnownSource = ""
                    self.updateMediaInfo(with: MediaInfo())
                }
            }
        }
        
        DispatchQueue.main.async {
            let nextInterval = self.mediaInfo.isPlaying ? 1.0 : 2.0
            self.scheduleFetch(after: nextInterval)
        }
    }
    
    // --- MediaRemote Adapter Integration ---
    private func fetchMediaRemote() -> Bool {
        // 1. Locate the Perl script in Resources
        guard let scriptPath = Bundle.main.path(forResource: "mediaremote-adapter", ofType: "pl") else {
            print("ERROR: mediaremote-adapter.pl not found in Bundle Resources.")
            return false
        }
        
        // 2. The framework path should ALWAYS end at .framework
        let frameworkPath = Bundle.main.bundlePath + "/Contents/Frameworks/MediaRemoteAdapter.framework"
        
        // Verify framework directory exists
        if !FileManager.default.fileExists(atPath: frameworkPath) {
            print("ERROR: MediaRemoteAdapter.framework not found at: \(frameworkPath)")
            return false
        }
        
        // Verify the binary exists
        let flatBinaryPath = frameworkPath + "/MediaRemoteAdapter"
        let versionedBinaryPath = frameworkPath + "/Versions/A/MediaRemoteAdapter"
        
        let binaryExists = FileManager.default.fileExists(atPath: flatBinaryPath) ||
                           FileManager.default.fileExists(atPath: versionedBinaryPath)
        
        if !binaryExists {
            print("ERROR: MediaRemoteAdapter binary not found")
            return false
        }

        // 3. Setup Process
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [scriptPath, frameworkPath, "get"]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        do {
            try task.run()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            
            // Log any errors from stderr
            if !errorData.isEmpty, let errorString = String(data: errorData, encoding: .utf8) {
                print("MediaRemote stderr: \(errorString)")
            }
            
            if task.terminationStatus != 0 {
                print("ERROR: MediaRemote script exited with code: \(task.terminationStatus)")
                return false
            }
            
            // 4. Parse JSON output
            guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                print("ERROR: Failed to parse JSON from mediaremote-adapter")
                return false
            }
            
            // Check if we have valid media info
            guard let title = json["title"] as? String, !title.isEmpty else {
                return false
            }
            
            let artist = json["artist"] as? String ?? ""
            let album = json["album"] as? String ?? ""
            let isPlaying = json["playing"] as? Bool ?? false
            let duration = json["duration"] as? Double ?? 1.0
            let elapsedTime = json["elapsedTime"] as? Double ?? 0.0
            let timestamp = json["timestamp"] as? Double ?? Date().timeIntervalSince1970
            
            // Calculate precise current time
            var currentCalc = elapsedTime
            if isPlaying {
                let diff = Date().timeIntervalSince1970 - timestamp
                currentCalc += diff
            }
            
            // Decode base64 artwork if available
            var fetchedImage: NSImage? = nil
            if let artworkBase64 = json["artworkData"] as? String,
               !artworkBase64.isEmpty,
               let artworkData = Data(base64Encoded: artworkBase64) {
                fetchedImage = NSImage(data: artworkData)
            }
            
            let newInfo = MediaInfo(
                isPlaying: isPlaying,
                title: title,
                artist: artist,
                album: album,
                currentTime: currentCalc,
                totalTime: duration,
                artwork: fetchedImage,
                dominantColor: nil,
                gradientColors: [],
                source: "MediaRemote"
            )
            
            DispatchQueue.main.async {
                self.updateMediaInfo(with: newInfo, directImage: fetchedImage)
            }
            return true
            
        } catch {
            print("ERROR: MediaRemote execution failed: \(error.localizedDescription)")
            return false
        }
    }
    
    // --- foobar2000 Function ---
    private func readFoobarFile() -> Bool {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let cacheDir = homeDir.appendingPathComponent("Library/Caches")
        let filePath = cacheDir.appendingPathComponent("foobar2000_nowplaying.txt").path

        do {
            let content = try String(contentsOfFile: filePath, encoding: .utf8)
            if content.isEmpty { return false }
            
            let parts = content.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            
            if parts.count >= 2 && parts[1] == "Nothing Playing" { return false }
            
            let artworkPath = cacheDir.appendingPathComponent("foobar2000_artwork.jpg").path
            if parseScriptResult(content + "|" + artworkPath, sourceName: "Foobar2000") {
                return true
            }
        } catch { }
        return false
    }

    // --- AppleScript Runner ---
    private func runAppleScript(script: String, parse: Bool, sourceName: String = "Unknown") -> Bool {
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let result = scriptObject.executeAndReturnError(&error)
            
            if parse {
                if let output = result.stringValue {
                    return parseScriptResult(output, sourceName: sourceName)
                }
            } else {
                if error == nil { return true }
            }
        }
        return false
    }
    
    // --- Data Parser ---
    private func parseScriptResult(_ result: String, sourceName: String) -> Bool {
        let parts = result.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 7 else { return false }
        
        if parts[0] == "false" && (parts[1] == "Not Playing" || parts[1] == "Music not running") {
            return false
        }

        let currentTimeString = parts[4].replacingOccurrences(of: ",", with: ".")
        let totalTimeString = parts[5].replacingOccurrences(of: ",", with: ".")
        let artworkData = parts[6]

        let newInfo = MediaInfo(
            isPlaying: parts[0] == "true",
            title: parts[1],
            artist: parts[2],
            album: parts[3],
            currentTime: Double(currentTimeString) ?? 0.0,
            totalTime: Double(totalTimeString) ?? 1.0,
            artwork: nil,
            dominantColor: nil,
            gradientColors: [],
            source: sourceName
        )
        
        DispatchQueue.main.async {
            self.updateMediaInfo(with: newInfo, artworkData: artworkData)
        }
        return true
    }
    
    // --- UI Update & Timer Logic ---
    private func updateMediaInfo(with newInfo: MediaInfo, artworkData: String = "", directImage: NSImage? = nil) {
        let titleChanged = (newInfo.title != self.mediaInfo.title || newInfo.artist != self.mediaInfo.artist)
        let sourceChanged = (newInfo.source != self.mediaInfo.source)
        
        // Artwork Handling - Force reload on source change
        if titleChanged || sourceChanged {
            if let image = directImage {
                // If we got an image directly (MediaRemote), use it immediately
                let colors = image.extractGradientColors()
                self.mediaInfo.artwork = image
                self.mediaInfo.gradientColors = colors
                self.mediaInfo.dominantColor = colors.first
                artworkCache[newInfo.title] = image
            } else if !artworkData.isEmpty {
                // If we got a URL/Path (AppleScript/Foobar), fetch it
                // Clear current artwork immediately to prevent flash
                if sourceChanged {
                    self.mediaInfo.artwork = nil
                    self.mediaInfo.gradientColors = []
                    self.mediaInfo.dominantColor = nil
                }
                loadArtwork(from: artworkData, cacheKey: newInfo.title, forceReload: sourceChanged)
            } else {
                // No art
                self.mediaInfo.artwork = nil
                self.mediaInfo.dominantColor = nil
                self.mediaInfo.gradientColors = []
            }
        } else if directImage != nil {
             // Ensure existing art matches if we are refreshing via MediaRemote
             if self.mediaInfo.artwork == nil {
                 let colors = directImage!.extractGradientColors()
                 self.mediaInfo.artwork = directImage
                 self.mediaInfo.gradientColors = colors
                 self.mediaInfo.dominantColor = colors.first
             }
        }
        
        self.mediaInfo.isPlaying = newInfo.isPlaying
        self.mediaInfo.title = newInfo.title
        self.mediaInfo.artist = newInfo.artist
        self.mediaInfo.album = newInfo.album
        self.mediaInfo.currentTime = newInfo.currentTime
        self.mediaInfo.totalTime = newInfo.totalTime
        self.mediaInfo.source = newInfo.source
    }
    
    private func scheduleFetch(after interval: TimeInterval) {
        fetchTimer?.invalidate()
        fetchTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.refreshMediaInfo()
        }
    }
    
    // --- Permission Prober ---
    private func requestPermissions() {
        DispatchQueue.global(qos: .userInitiated).async {
            let musicScript = "tell application \"Music\" to return version"
            _ = self.runAppleScript(script: musicScript, parse: false)
            let spotifyScript = "tell application \"Spotify\" to return version"
            _ = self.runAppleScript(script: spotifyScript, parse: false)
        }
    }
    
    // --- Artwork Functions ---
    private func loadArtwork(from data: String, cacheKey: String, forceReload: Bool = false) {
        currentArtworkTask?.cancel()
        
        if cacheKey.isEmpty || cacheKey == "Nothing Playing" { return }
        
        // Check cache first, but skip if force reload (source changed)
        if !forceReload, let cachedImage = artworkCache[cacheKey] {
            let colors = cachedImage.extractGradientColors()
            DispatchQueue.main.async {
                self.mediaInfo.artwork = cachedImage
                self.mediaInfo.gradientColors = colors
                self.mediaInfo.dominantColor = colors.first
            }
            return
        }
        
        if data.starts(with: "http") {
            guard let url = URL(string: data) else { return }
            currentArtworkTask = URLSession.shared.dataTask(with: url) { [weak self] (data, response, error) in
                guard let self = self, let data = data, error == nil, let image = NSImage(data: data) else { return }
                let colors = image.extractGradientColors()
                DispatchQueue.main.async {
                    self.artworkCache[cacheKey] = image
                    if self.mediaInfo.title == cacheKey {
                        self.mediaInfo.artwork = image
                        self.mediaInfo.gradientColors = colors
                        self.mediaInfo.dominantColor = colors.first
                    }
                }
            }
            currentArtworkTask?.resume()
        } else if data.hasSuffix(".jpg") || data.hasSuffix(".png") {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                if let imageData = try? Data(contentsOf: URL(fileURLWithPath: data), options: .uncachedRead),
                   let image = NSImage(data: imageData) {
                    let colors = image.extractGradientColors()
                    DispatchQueue.main.async {
                        self.artworkCache[cacheKey] = image
                        if self.mediaInfo.title == cacheKey {
                            self.mediaInfo.artwork = image
                            self.mediaInfo.gradientColors = colors
                            self.mediaInfo.dominantColor = colors.first
                        }
                    }
                }
            }
        } else if data == "MUSIC_ART" {
            fetchAppleMusicArtwork(for: cacheKey)
        }
    }
    
    private func fetchAppleMusicArtwork(for cacheKey: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let script = """
            tell application "Music"
                try
                    set currentTrack to current track
                    if (count of artworks of currentTrack) > 0 then
                        set artworkData to data of artwork 1 of currentTrack
                        return artworkData
                    end if
                end try
            end tell
            return missing value
            """
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                let result = scriptObject.executeAndReturnError(&error)
                let artworkData = result.data
                if !artworkData.isEmpty, let image = NSImage(data: artworkData) {
                    let colors = image.extractGradientColors()
                    DispatchQueue.main.async {
                        self.artworkCache[cacheKey] = image
                        if self.mediaInfo.title == cacheKey {
                            self.mediaInfo.artwork = image
                            self.mediaInfo.gradientColors = colors
                            self.mediaInfo.dominantColor = colors.first
                        }
                    }
                }
            }
        }
    }
    
    // --- Playback Controls ---
    func togglePlayPause() {
        // In Music Players mode, try to control the current source directly
        if settings.retrievalMode == 0 && !mediaInfo.source.isEmpty {
            sendPlayPauseToSource(mediaInfo.source)
        } else {
            // Try media keys first
            if !pressMediaKey(16) {
                sendPlayPauseCommand()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.refreshMediaInfo() }
    }
    
    func nextTrack() {
        // In Music Players mode, try to control the current source directly
        if settings.retrievalMode == 0 && !mediaInfo.source.isEmpty {
            sendNextToSource(mediaInfo.source)
        } else {
            if !pressMediaKey(17) {
                sendNextCommand()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.refreshMediaInfo() }
    }
    
    func prevTrack() {
        // In Music Players mode, try to control the current source directly
        if settings.retrievalMode == 0 && !mediaInfo.source.isEmpty {
            sendPreviousToSource(mediaInfo.source)
        } else {
            if !pressMediaKey(18) {
                sendPreviousCommand()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.refreshMediaInfo() }
    }
    
    func seek(to time: Double) {
        // Seeking only works with Apple Music and Spotify
        if mediaInfo.source == "Apple Music" || mediaInfo.source == "Spotify" {
            let seekTime = max(0, min(time, mediaInfo.totalTime))
            
            let script: String
            if mediaInfo.source == "Spotify" {
                script = """
                tell application "Spotify"
                    try
                        set player position to \(seekTime)
                    end try
                end tell
                """
            } else { // Apple Music
                script = """
                tell application "Music"
                    try
                        set player position to \(seekTime)
                    end try
                end tell
                """
            }
            
            // Update display immediately for responsiveness
            DispatchQueue.main.async {
                self.mediaInfo.currentTime = seekTime
            }
            
            _ = runAppleScript(script: script, parse: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.refreshMediaInfo() }
        }
    }

    @discardableResult
    private func pressMediaKey(_ key: Int) -> Bool {
        guard let eventDown = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: (key << 16) | (0xA << 8),
            data2: -1
        ), let eventUp = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: (key << 16) | (0xB << 8),
            data2: -1
        ) else {
            return false
        }
        
        eventDown.cgEvent?.post(tap: .cgSessionEventTap)
        eventUp.cgEvent?.post(tap: .cgSessionEventTap)
        return true
    }
    
    // --- Source-Specific Controls ---
    private func sendPlayPauseToSource(_ source: String) {
        let script: String
        switch source {
        case "Spotify":
            script = "tell application \"Spotify\" to playpause"
        case "Apple Music":
            script = "tell application \"Music\" to playpause"
        default:
            // For Foobar or others, fall back to media keys
            _ = pressMediaKey(16)
            return
        }
        _ = runAppleScript(script: script, parse: false)
    }
    
    private func sendNextToSource(_ source: String) {
        let script: String
        switch source {
        case "Spotify":
            script = "tell application \"Spotify\" to next track"
        case "Apple Music":
            script = "tell application \"Music\" to next track"
        default:
            _ = pressMediaKey(17)
            return
        }
        _ = runAppleScript(script: script, parse: false)
    }
    
    private func sendPreviousToSource(_ source: String) {
        let script: String
        switch source {
        case "Spotify":
            script = "tell application \"Spotify\" to previous track"
        case "Apple Music":
            script = "tell application \"Music\" to previous track"
        default:
            _ = pressMediaKey(18)
            return
        }
        _ = runAppleScript(script: script, parse: false)
    }
    
    // --- AppleScript Fallback Controls ---
    private func sendPlayPauseCommand() {
        let script = """
        if application "Spotify" is running then
            tell application "Spotify" to playpause
        else if application "Music" is running then
            tell application "Music" to playpause
        end if
        """
        _ = runAppleScript(script: script, parse: false)
    }
    
    private func sendNextCommand() {
        let script = """
        if application "Spotify" is running then
            tell application "Spotify" to next track
        else if application "Music" is running then
            tell application "Music" to next track
        end if
        """
        _ = runAppleScript(script: script, parse: false)
    }
    
    private func sendPreviousCommand() {
        let script = """
        if application "Spotify" is running then
            tell application "Spotify" to previous track
        else if application "Music" is running then
            tell application "Music" to previous track
        end if
        """
        _ = runAppleScript(script: script, parse: false)
    }
}

// MARK: - NSImage Extensions
extension NSImage {
    /// Extract a gradient of 3-4 dominant colors from the image
    func extractGradientColors(count: Int = 4) -> [NSColor] {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return [.gray, .darkGray, .black]
        }
        
        // Resize image to small size for faster processing
        let size = CGSize(width: 50, height: 50)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return [.gray, .darkGray, .black]
        }
        
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        
        guard let data = context.data else {
            return [.gray, .darkGray, .black]
        }
        
        // Sample colors from different regions
        let pixelData = data.bindMemory(to: UInt8.self, capacity: Int(size.width * size.height * 4))
        var colorCounts: [String: (color: NSColor, count: Int)] = [:]
        
        // Sample every few pixels to get representative colors
        let sampleStride = 5
        for y in stride(from: 0, to: Int(size.height), by: sampleStride) {
            for x in stride(from: 0, to: Int(size.width), by: sampleStride) {
                let offset = (y * Int(size.width) + x) * 4
                let r = CGFloat(pixelData[offset]) / 255.0
                let g = CGFloat(pixelData[offset + 1]) / 255.0
                let b = CGFloat(pixelData[offset + 2]) / 255.0
                
                // Quantize colors to reduce variation
                let quantized = NSColor(
                    red: round(r * 8) / 8,
                    green: round(g * 8) / 8,
                    blue: round(b * 8) / 8,
                    alpha: 1.0
                )
                
                let key = "\(quantized.redComponent),\(quantized.greenComponent),\(quantized.blueComponent)"
                if var existing = colorCounts[key] {
                    existing.count += 1
                    colorCounts[key] = existing
                } else {
                    colorCounts[key] = (quantized, 1)
                }
            }
        }
        
        // Sort by frequency and get top colors
        let sortedColors = colorCounts.values
            .sorted { $0.count > $1.count }
            .map { $0.color }
        
        // Filter out very dark and very light colors for better gradients
        let filteredColors = sortedColors.filter { color in
            let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3.0
            return brightness > 0.1 && brightness < 0.9
        }
        
        // Take top N colors
        var result = Array(filteredColors.prefix(count))
        
        // If we don't have enough colors, add darker variants
        while result.count < count {
            if let last = result.last {
                let darker = last.blended(withFraction: 0.6, of: .black) ?? .darkGray
                result.append(darker)
            } else {
                result.append(.gray)
            }
        }
        
        // Enhance saturation for more vibrant gradients
        return result.map { color in
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            saturation = min(saturation * 1.3, 1.0)
            brightness = min(brightness * 1.1, 1.0)
            return NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
        }
    }
}
