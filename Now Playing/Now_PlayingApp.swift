import SwiftUI

@main
struct Now_PlayingApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        
        .commands{
            CommandGroup(replacing: .newItem){}
        }
        
        Settings {
            SettingsView()
        }
        
        Window("About", id: "about-window") {
            AboutView()
                .frame(width: 500, height: 300)
        }
        .windowResizability(.contentSize)
    }
}
