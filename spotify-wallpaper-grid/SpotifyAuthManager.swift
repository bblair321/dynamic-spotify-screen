import Foundation
import CommonCrypto
import AppKit
import Swifter

class SpotifyAuthManager {
    static let shared = SpotifyAuthManager()  // Singleton instance
    
    private let clientID = "9937376f32a54e00a929c3b004e4a143"  // Replace with your client ID
    private let redirectURI = "https://61f9-73-157-186-168.ngrok-free.app/callback"  // Your ngrok URL
    private var codeVerifier: String = ""

    // Computed property to generate the authURL
    func authURL() -> URL? {
        codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(codeVerifier: codeVerifier)

        let urlString = "https://accounts.spotify.com/authorize?" +
                        "client_id=\(clientID)&" +
                        "response_type=code&" +
                        "redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)&" +
                        "scope=user-library-read&" +
                        "code_challenge_method=S256&" +
                        "code_challenge=\(codeChallenge)"
        
        return URL(string: urlString)
    }

    // Start the login process
    func startLogin() {
        if let authURL = authURL() {
            // Now `authURL` is safely unwrapped and can be used as a non-optional `URL`
            NSWorkspace.shared.open(authURL)
            startLocalServer()  // Start the local server to catch the redirect with the code
        } else {
            print("Failed to generate the auth URL")
        }
    }

    // Generate the code verifier (random string)
    private func generateCodeVerifier() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        return String((0..<128).compactMap { _ in chars.randomElement() })
    }

    // Generate the code challenge from the code verifier
    private func generateCodeChallenge(codeVerifier: String) -> String {
        guard let data = codeVerifier.data(using: .utf8) else { return "" }

        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }

        let base64 = Data(hash).base64EncodedString()
        return base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // Start local server to capture the callback from Spotify
    func startLocalServer() {
        let server = HttpServer()
        let authManager = self  // Reference to self for use in closure
        
        // Handle the /callback route with CORRECT closure syntax
        server["/callback"] = { request in
            print("Received callback request")
            print("URL path: \(request.path)")
            
            // Extract the code from the URL
            if let urlComponents = URLComponents(string: "https://example.com\(request.path)"),
               let codeItem = urlComponents.queryItems?.first(where: { $0.name == "code" }),
               let code = codeItem.value {
                
                print("Found authorization code: \(code)")
                
                // Use the authManager reference to call the method
                Task {
                    await authManager.exchangeCodeForToken(code: code)
                }
                
                return HttpResponse.ok(.text("Login successful! You can close this window."))
            }
            
            // Return a not found response if the code is missing
            print("Could not extract code from URL")
            return HttpResponse.notFound
        }

        // Start the server on port 8888
        do {
            try server.start(8888)
            print("Server started on port 8888")
        } catch {
            print("Failed to start server:", error)
        }
    }

    // Exchange the authorization code for an access token
    func exchangeCodeForToken(code: String) async {
        let url = URL(string: "https://accounts.spotify.com/api/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Prepare parameters for token exchange
        let params = [
            "client_id": clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": codeVerifier
        ]
        
        // Convert params to URL-encoded string
        request.httpBody = params.map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        // Send request to Spotify
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let accessToken = json["access_token"] as? String,
                   let refreshToken = json["refresh_token"] as? String,
                   let expiresIn = json["expires_in"] as? Int {

                    // Store the access token and refresh token (and expiration time)
                    UserDefaults.standard.set(accessToken, forKey: "access_token")
                    UserDefaults.standard.set(refreshToken, forKey: "refresh_token")
                    UserDefaults.standard.set(Date().addingTimeInterval(TimeInterval(expiresIn)), forKey: "token_expiry")

                    print("Access Token: \(accessToken)")
                    print("Refresh Token: \(refreshToken)")
                    print("Token Expires In: \(expiresIn) seconds")
                }
            }
        } catch {
            print("Token exchange failed:", error)
        }
    }
    // Refresh the access token using the refresh token
    func refreshAccessToken() async {
        guard let refreshToken = UserDefaults.standard.string(forKey: "refresh_token") else {
            print("No refresh token found.")
            return
        }
        
        let url = URL(string: "https://accounts.spotify.com/api/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Prepare parameters for token refresh
        let params = [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        
        // Convert params to URL-encoded string
        request.httpBody = params.map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        // Send request to Spotify
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let accessToken = json["access_token"] as? String,
                   let expiresIn = json["expires_in"] as? Int {
                    
                    // Store the new access token and expiration time
                    UserDefaults.standard.set(accessToken, forKey: "access_token")
                    UserDefaults.standard.set(Date().addingTimeInterval(TimeInterval(expiresIn)), forKey: "token_expiry")

                    print("Refreshed Access Token: \(accessToken)")
                    print("Token Expires In: \(expiresIn) seconds")
                }
            }
        } catch {
            print("Token refresh failed:", error)
        }
    }
    func getAccessToken() -> String? {
        if let expiryDate = UserDefaults.standard.object(forKey: "token_expiry") as? Date {
            // Check if the token has expired
            if Date() > expiryDate {
                print("Access token expired, refreshing...")
                Task {
                    await refreshAccessToken()
                }
                return nil // Token will be refreshed soon
            } else {
                // Return the valid access token
                return UserDefaults.standard.string(forKey: "access_token")
            }
        }
        return nil
    }
}
