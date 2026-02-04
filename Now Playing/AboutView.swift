import Foundation
import SwiftUI

private var acknowledgementsURL: URL {
    Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt")!
}

struct AboutView: View {
    var body: some View {
        VStack{
            Section(header: Text("About") .font(.title2)){
                HStack{
                    Text("Version")
                        .font(.headline)
                    Spacer()
                    Text("1.1")
                }
                HStack{
                    Text("Copyright")
                        .font(.headline)
                    Spacer()
                    Text("©2026 RKI/exitcode0-dev")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            
            Section(header: Text("Acknowledgements") .font(.title2)){
                VStack{
                    HStack{
                        Text("MediaRemote Framework")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.top, 1)
                        Spacer()
                        Text("0.7.2")
                    }
                    Text("Huge thanks to the MediaRemote team for providing the underlying capabilities to interface with system-wide media playback.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 5)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("View full acknowlegdements"){
                        NSWorkspace.shared.open(acknowledgementsURL)
                    }
                    .padding(.bottom, 20)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
    }
}
