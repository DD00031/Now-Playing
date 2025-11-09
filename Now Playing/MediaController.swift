import Foundation
import Combine
import CoreGraphics
import AppKit
import CoreImage

// 1. The Data Structure
struct MediaInfo {
    var isPlaying: Bool = false
    var title: String = "Nothing Playing"
    var artist: String = ""
    var album: String = ""
    var currentTime: Double = 0.0
    var totalTime: Double = 1.0
    var artwork: NSImage? = nil
    var dominantColor: NSColor? = nil
}

// 2. The Controller (ObservableObject)
class MediaController: ObservableObject {
    
    @Published var mediaInfo = MediaInfo()
    
    private var fetchTimer: Timer?
    
    // --- Album Art Cache ---
    private var artworkCache = [String: NSImage]()
    private var currentArtworkTask: URLSessionDataTask?
    
    // --- AppleScripts ---
    
    //Apple Music script
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
    
    //Spotify script
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
        // Request permissions on startup
        requestPermissions()

        // Run it once immediately on startup
        refreshMediaInfo()
    }
    
    deinit {
        fetchTimer?.invalidate()
    }

    // --- Core Functions ---
    @objc private func refreshMediaInfo() {
        DispatchQueue.global(qos: .background).async {
            self.fetchMediaInfo()
        }
    }
    
    private func fetchMediaInfo() {
        if readFoobarFile() {
            // We found foobar, but we still need to schedule the next fetch
        } else if runAppleScript(script: spotifyScript, parse: true) {
            // We found spotify, but we still need to schedule the next fetch
        } else if runAppleScript(script: musicScript, parse: true) {
            // We found music, but we still need to schedule the next fetch
        } else {
            DispatchQueue.main.async {
                // Only update if it's not already in the "Nothing Playing" state
                if self.mediaInfo.title != "Nothing Playing" {
                    self.updateMediaInfo(with: MediaInfo())
                }
            }
        }
        
        // --- Schedule the next fetch ---
        DispatchQueue.main.async {
            let nextInterval = self.mediaInfo.isPlaying ? 2.0 : 5.0 // 2s if playing, 5s if paused
            self.scheduleFetch(after: nextInterval)
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
            
            // Check if foobar is actually playing something
            let parts = content.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            
            // If it's the default "nothing playing" state, return false so other apps are checked
            if parts.count >= 2 && parts[1] == "Nothing Playing" {
                return false
            }
            
            // Pass the artwork file path as the 7th field
            let artworkPath = cacheDir.appendingPathComponent("foobar2000_artwork.jpg").path
            if parseScriptResult(content + "|" + artworkPath) {
                return true
            }
        } catch {
             // File doesn't exist or is locked, this is fine.
        }
        return false
    }

    
    // --- AppleScript Runner ---
    private func runAppleScript(script: String, parse: Bool) -> Bool {
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let result = scriptObject.executeAndReturnError(&error)
            
            if parse {
                if let output = result.stringValue {
                    // print("AppleScript output: \(output)") // Uncomment for debugging
                    return parseScriptResult(output)
                } else if let errorDict = error {
                     print("AppleScript Error: \(errorDict)")
                } else {
                    // print("AppleScript returned no string value") // Uncomment for debugging
                }
            } else {
                // This is for a permission check, we just care if it ran
                if error == nil {
                    print("Permission check script ran successfully.")
                    return true
                } else {
                    print("AppleScript Error: \(error!)")
                }
            }
        }
        return false
    }
    
    // --- Data Parser ---
    
    private func parseScriptResult(_ result: String) -> Bool {
        let parts = result.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        
        // Now expects 7 parts
        guard parts.count == 7 else {
            return false
        }
        
        // --- Check for "Not Playing" OR "Music not running" ---
        if parts[0] == "false" && (parts[1] == "Not Playing" || parts[1] == "Music not running") {
            // This is a true "nothing playing" state
            // --- Return false to allow checking other apps ---
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
            artwork: nil, // Artwork will be loaded async
            dominantColor: nil // Color will be loaded async
        )
        
        DispatchQueue.main.async {
            self.updateMediaInfo(with: newInfo, artworkData: artworkData)
        }
        
        return true
    }
    
    // --- UI Update & Timer Logic ---
    
    private func updateMediaInfo(with newInfo: MediaInfo, artworkData: String = "") {
        let titleChanged = (newInfo.title != self.mediaInfo.title || newInfo.artist != self.mediaInfo.artist)
        let playbackChanged = newInfo.isPlaying != self.mediaInfo.isPlaying
        
        // If it's a completely new track, load new artwork
        if titleChanged {
            self.mediaInfo.artwork = nil // Clear old art
            self.mediaInfo.dominantColor = nil // Clear old color
            loadArtwork(from: artworkData, cacheKey: newInfo.title)
        }
        
        // --- FIX for Pausing ---
        // Always update all properties *except* artwork/color
        // This preserves the art when pausing
        self.mediaInfo.isPlaying = newInfo.isPlaying
        self.mediaInfo.title = newInfo.title
        self.mediaInfo.artist = newInfo.artist
        self.mediaInfo.album = newInfo.album
        self.mediaInfo.currentTime = newInfo.currentTime
        self.mediaInfo.totalTime = newInfo.totalTime

    }
    
    // --- Function to schedule the next fetch ---
    private func scheduleFetch(after interval: TimeInterval) {
        // Invalidate any old timer
        fetchTimer?.invalidate()
        // Schedule a new one-shot timer
        fetchTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.refreshMediaInfo()
        }
    }
    
    // --- Permission Prober ---
    
    private func requestPermissions() {
        DispatchQueue.global(qos: .userInitiated).async {
            let musicScript = "tell application \"Music\" to return version"
            print("Proactively checking Music permissions...")
            _ = self.runAppleScript(script: musicScript, parse: false)
            
            let spotifyScript = "tell application \"Spotify\" to return version"
            print("Proactively checking Spotify permissions...")
            _ = self.runAppleScript(script: spotifyScript, parse: false)
        }
    }
    
    // --- Artwork Functions ---
    
    private func loadArtwork(from data: String, cacheKey: String) {
        currentArtworkTask?.cancel()
        
        if cacheKey.isEmpty || cacheKey == "Nothing Playing" {
            // Reset to default
            DispatchQueue.main.async {
                self.mediaInfo.artwork = nil
                self.mediaInfo.dominantColor = nil
            }
            return
        }
        
        if let cachedImage = artworkCache[cacheKey] {
            let avgColor = cachedImage.averageColor()
            DispatchQueue.main.async {
                self.mediaInfo.artwork = cachedImage
                self.mediaInfo.dominantColor = avgColor
            }
            return
        }
        
        // Handle Spotify URLs
        if data.starts(with: "http") {
            guard let url = URL(string: data) else { return }
            
            currentArtworkTask = URLSession.shared.dataTask(with: url) { [weak self] (data, response, error) in
                guard let self = self, let data = data, error == nil, let image = NSImage(data: data) else { return }
                
                let avgColor = image.averageColor()
                
                DispatchQueue.main.async {
                    self.artworkCache[cacheKey] = image
                    if self.mediaInfo.title == cacheKey {
                        self.mediaInfo.artwork = image
                        self.mediaInfo.dominantColor = avgColor
                    }
                }
            }
            currentArtworkTask?.resume()
        }
        // Handle foobar2000 file paths
        else if data.hasSuffix(".jpg") || data.hasSuffix(".png") {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                if let imageData = try? Data(contentsOf: URL(fileURLWithPath: data), options: .uncachedRead),
                   let image = NSImage(data: imageData) {
                    
                    let avgColor = image.averageColor()
                    
                    DispatchQueue.main.async {
                        self.artworkCache[cacheKey] = image
                        if self.mediaInfo.title == cacheKey {
                            self.mediaInfo.artwork = image
                            self.mediaInfo.dominantColor = avgColor
                        }
                    }
                }
            }
        }
        // Handle Apple Music - fetch artwork separately
        else if data == "MUSIC_ART" {
            fetchAppleMusicArtwork(for: cacheKey)
        }
    }
    
    // Separate function to fetch Apple Music artwork
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
                    
                    let avgColor = image.averageColor() // <-- Get average color
                    
                    DispatchQueue.main.async {
                        self.artworkCache[cacheKey] = image
                        if self.mediaInfo.title == cacheKey {
                            self.mediaInfo.artwork = image
                            self.mediaInfo.dominantColor = avgColor // <-- Store it
                        }
                    }
                }
            }
        }
    }
    
    // --- Playback Controls ---
    
    func togglePlayPause() {
        pressMediaKey(16) // NX_KEYTYPE_PLAY
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.refreshMediaInfo() }
    }
    
    func nextTrack() {
        pressMediaKey(17) // NX_KEYTYPE_NEXT
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.refreshMediaInfo() }
    }
    
    func prevTrack() {
        pressMediaKey(18) // NX_KEYTYPE_PREVIOUS
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.refreshMediaInfo() }
    }

    private func pressMediaKey(_ key: Int) {
        let eventDown = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8, // NX_SUBTYPE_AUX_CONTROL_BUTTONS
            data1: (key << 16) | (0xA << 8), // key code + key down
            data2: -1
        )
        
        let eventUp = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: (key << 16) | (0xB << 8), // key code + key up
            data2: -1
        )

        eventDown?.cgEvent?.post(tap: CGEventTapLocation.cgSessionEventTap)
        eventUp?.cgEvent?.post(tap: CGEventTapLocation.cgSessionEventTap)
    }
}

// --- Helper to find the average color of an image ---
// This must be OUTSIDE the MediaController class
extension NSImage {
    func averageColor() -> NSColor? {
        // 1. Resize the image to 1x1. This is a very fast way to get the average color.
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let inputImage = CIImage(cgImage: cgImage)

        // 2. Create a Core Image filter that averages a region.
        let extentVector = CIVector(x: inputImage.extent.origin.x, y: inputImage.extent.origin.y, z: inputImage.extent.size.width, w: inputImage.extent.size.height)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: inputImage, kCIInputExtentKey: extentVector]) else { return nil }
        guard let outputImage = filter.outputImage else { return nil }

        // 3. Get the 1x1 output pixel data.
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull!])
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)

        // 4. Convert the pixel data to NSColor.
        let avgColor = NSColor(red: CGFloat(bitmap[0]) / 255.0,
                               green: CGFloat(bitmap[1]) / 255.0,
                               blue: CGFloat(bitmap[2]) / 255.0,
                               alpha: CGFloat(bitmap[3]) / 255.0)
        
        // --- Boost Saturation & Brightness ---
        // Convert the average color to HSB (Hue, Saturation, Brightness)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        
        avgColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        
        // Boost saturation (e.g., by 40%) but don't exceed 1.0
        saturation = min(saturation * 1.4, 1.0)
        
        // Boost brightness (e.g., by 20%) but don't exceed 1.0
        brightness = min(brightness * 1.2, 1.0)
        
        // Return the new, more vibrant color
        return NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
        // --- END OF NEW SECTION ---
    }
}
