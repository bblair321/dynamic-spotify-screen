//
//  AppDelegate.swift
//  spotify-wallpaper-grid
//
//  Created by Brady Blair on 4/18/25.
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication,
                     open urls: [URL]) {
        guard let url = urls.first,
              url.scheme == "spotifygrid",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else { return }

        // Inside an async context (e.g., within a Task)
        Task {
            await SpotifyAuthManager.shared.exchangeCodeForToken(code: code)
            print("Token exchange complete")
        }
    }
}
