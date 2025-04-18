//
//  ContentView.swift
//  spotify-wallpaper-grid
//
//  Created by Brady Blair on 4/18/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Text("Spotify Grid")
                .font(.title)
            
            Button("Login with Spotify") {
                if let url = SpotifyAuthManager.shared.authURL() {
                    NSWorkspace.shared.open(url)
                } else {
                    print("Failed to generate the Spotify auth URL")
                }
            }
        }
        .frame(width: 300, height: 200)
    }
}

#Preview {
    ContentView()
}
