import Foundation
import Combine
import SwiftUI

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    // Keys for UserDefaults
    private let kPlayerOrder = "playerOrder"
    private let kDisabledPlayers = "disabledPlayers"
    private let kIsTextMode = "isTextMode"
    private let kDynamicBackground = "useDynamicBackground"
    private let kRetrievalMode = "retrievalMode"
    private let kShowProgressBar = "showProgressBar"
    
    // Default Order
    let defaultOrder = ["Apple Music", "Spotify", "Foobar2000"]
    
    @Published var playerOrder: [String] {
        didSet {
            UserDefaults.standard.set(playerOrder, forKey: kPlayerOrder)
        }
    }
    
    @Published var disabledPlayers: [String: Bool] {
        didSet {
            UserDefaults.standard.set(disabledPlayers, forKey: kDisabledPlayers)
        }
    }
    
    @Published var isTextMode: Bool {
        didSet {
            UserDefaults.standard.set(isTextMode, forKey: kIsTextMode)
        }
    }
    
    @Published var useDynamicBackground: Bool {
        didSet {
            UserDefaults.standard.set(useDynamicBackground, forKey: kDynamicBackground)
        }
    }
    
    @Published var showProgressBar: Bool {
        didSet {
            UserDefaults.standard.set(showProgressBar, forKey: kShowProgressBar)
        }
    }
    
    // 0 = Music Players (Priority List), 1 = All Media (MediaRemote)
    @Published var retrievalMode: Int {
        didSet {
            UserDefaults.standard.set(retrievalMode, forKey: kRetrievalMode)
        }
    }
    
    init() {
        self.playerOrder = UserDefaults.standard.stringArray(forKey: kPlayerOrder) ?? defaultOrder
        self.disabledPlayers = UserDefaults.standard.object(forKey: kDisabledPlayers) as? [String: Bool] ?? [:]
        self.isTextMode = UserDefaults.standard.bool(forKey: kIsTextMode)
        self.useDynamicBackground = UserDefaults.standard.object(forKey: kDynamicBackground) as? Bool ?? true
        self.showProgressBar = UserDefaults.standard.object(forKey: kShowProgressBar) as? Bool ?? true
        self.retrievalMode = UserDefaults.standard.integer(forKey: kRetrievalMode)
    }
    
    func isPlayerEnabled(_ name: String) -> Bool {
        return disabledPlayers[name] ?? true
    }
    
    func togglePlayer(_ name: String) {
        var current = disabledPlayers[name] ?? true
        disabledPlayers[name] = !current
    }
}
