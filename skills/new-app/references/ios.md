# iOS (SwiftUI, XcodeGen)

A SwiftUI app targeting iOS 17 with no third-party dependencies. `project.yml` is the source of truth for the project, and the
`.xcodeproj` is generated from it and not committed. Config comes from xcconfig files through Info.plist. Sign-in is hand-written
PKCE against Cognito managed login, run in an ephemeral `webAuthenticationSession`. Tokens are stored in the keychain.

iOS can only be built on macOS. On other machines, write the files and check them by reading (see the end of this file).

## Contents
- [Layout](#layout)
- [project.yml and config](#projectyml-and-config)
- [Auth](#auth)
- [API client](#api-client)
- [App structure and screens](#app-structure-and-screens)
- [Tests and done criteria](#tests-and-done-criteria)

## Layout

```
ios/
  project.yml  ExportOptions.plist  README.md  .gitignore
  Config/ Shared.xcconfig  Debug.xcconfig  Release.xcconfig  Local.xcconfig.example
  <App>/
    Info.plist
    App/ <App>App.swift  AppContainer.swift  RootView.swift  MainTabView.swift
    Config/ AppConfig.swift
    Data/ AccountRepository.swift  TermsAcceptance.swift
    Data/API/ APIClient.swift  APIError.swift  <App>API.swift  Models.swift
    Data/Auth/ AuthManager.swift  PKCE.swift  Keychain.swift
    UI/ SignIn/{SignInView,TermsView}.swift  Account/{AccountView,ProfileView}.swift  Home/HomeView.swift  Theme/Theme.swift
    Util/ Browser.swift  Format.swift
    Resources/ Assets.xcassets (AppIcon, AccentColor)  PrivacyInfo.xcprivacy
  <App>Tests/
```

## project.yml and config

```yaml
# XcodeGen spec for the <App> iOS app. The .xcodeproj is generated from this file and not committed:
#   brew install xcodegen && xcodegen generate
name: <App>
options:
  bundleIdPrefix: com.<company>
  deploymentTarget:
    iOS: "17.0"
  createIntermediateGroups: true
  developmentLanguage: en

configFiles:
  Debug: Config/Debug.xcconfig
  Release: Config/Release.xcconfig

settings:
  base:
    MARKETING_VERSION: 0.1.0
    CURRENT_PROJECT_VERSION: 1
    SWIFT_VERSION: "5.0"
    # Set your team in Config/Local.xcconfig (git-ignored) to run on a device.
    CODE_SIGN_STYLE: Automatic

targets:
  <App>:
    type: application
    platform: iOS
    sources:
      - path: <App>
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.<company>.<app>
        PRODUCT_NAME: <App>
        INFOPLIST_FILE: <App>/Info.plist
        TARGETED_DEVICE_FAMILY: "1"
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
        ENABLE_PREVIEWS: YES

  <App>Tests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: <App>Tests
    dependencies:
      - target: <App>
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
        PRODUCT_BUNDLE_IDENTIFIER: com.<company>.<app>.tests

schemes:
  <App>:
    build:
      targets:
        <App>: all
        <App>Tests: [test]
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - <App>Tests
    archive:
      config: Release
```

```
// Config/Shared.xcconfig
// App configuration shared by every build. Info.plist passes these to the app, and AppConfig.swift reads them.
// "//" starts a comment in xcconfig files, so URLs are written as https:/$()/... to keep the double slash.
//
// The Cognito iOS app client must list <APP>_REDIRECT_URI as a callback URL, and the API's Auth:ClientIds must
// include <APP>_COGNITO_CLIENT_ID.
<APP>_COGNITO_DOMAIN = <app>.auth.<region>.amazoncognito.com
<APP>_COGNITO_CLIENT_ID =
<APP>_REDIRECT_URI = com.<company>.<app>:/$()/callback
<APP>_WEB_URL = https:/$()/<domain>
```

```
// Config/Debug.xcconfig
#include "Shared.xcconfig"

// The simulator shares the Mac's network, so localhost reaches the API's "http" launch profile. To run on a
// device, point this at the Mac's LAN address in Local.xcconfig.
<APP>_API_URL = http:/$()/localhost:5142/

// Optional, git-ignored overrides (e.g. DEVELOPMENT_TEAM, <APP>_API_URL). See Local.xcconfig.example.
#include? "Local.xcconfig"
```

```
// Config/Release.xcconfig
#include "Shared.xcconfig"

<APP>_API_URL = https:/$()/api.<domain>/
```

`Local.xcconfig.example` documents `DEVELOPMENT_TEAM` and a LAN `<APP>_API_URL`, both commented out.

`Info.plist` contains:
- the standard bundle keys, using build-setting variables (`$(EXECUTABLE_NAME)`, `$(PRODUCT_BUNDLE_IDENTIFIER)`,
  `$(MARKETING_VERSION)`, `$(CURRENT_PROJECT_VERSION)`, and so on), with `CFBundleDisplayName` = `<App>`
- `LSRequiresIPhoneOS` = true and `ITSAppUsesNonExemptEncryption` = false
- `UIApplicationSceneManifest` with `UIApplicationSupportsMultipleScenes` = false, `UILaunchScreen` as an empty dict, and
  `UISupportedInterfaceOrientations` set to portrait
- `NSAppTransportSecurity` → `NSAllowsLocalNetworking` = true, so debug builds can call the API over HTTP on localhost or
  the LAN. It only covers local addresses, so it's safe in release builds too.
- the app config keys, which `AppConfig.swift` reads: `<App>APIURL` = `$(<APP>_API_URL)`, `<App>CognitoDomain` = `$(<APP>_COGNITO_DOMAIN)`,
  `<App>CognitoClientID`, `<App>RedirectURI` and `<App>WebURL`

There is no `CFBundleURLTypes` entry, because `webAuthenticationSession` receives the callback scheme directly.

```swift
import Foundation

/// Build-time configuration from Config/*.xcconfig, passed through Info.plist.
struct AppConfig: Sendable {
    let apiURL: URL
    let cognitoDomain: String
    let cognitoClientID: String
    let redirectURI: URL
    let webURL: URL

    static func fromBundle(_ bundle: Bundle = .main) -> AppConfig {
        func string(_ key: String) -> String {
            guard let value = bundle.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else {
                fatalError("Missing \(key) in Info.plist; it comes from ios/Config/*.xcconfig.")
            }
            return value
        }
        func url(_ key: String) -> URL {
            guard let url = URL(string: string(key)) else {
                fatalError("\(key) in Info.plist isn't a valid URL.")
            }
            return url
        }

        return AppConfig(
            apiURL: url("<App>APIURL"),
            cognitoDomain: string("<App>CognitoDomain"),
            cognitoClientID: string("<App>CognitoClientID"),
            redirectURI: url("<App>RedirectURI"),
            webURL: url("<App>WebURL")
        )
    }
}
```

## Auth

```swift
// Data/Auth/PKCE.swift
import CryptoKit
import Foundation
import Security

/// Proof Key for Code Exchange (RFC 7636) for the authorization code sign-in.
enum PKCE {
    /// A random, URL-safe string, used for both the code verifier and the state parameter.
    static func randomString(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        precondition(status == errSecSuccess, "Couldn't generate random bytes")
        return Data(bytes).base64URLEncodedString()
    }

    /// The S256 code challenge for `verifier`.
    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
```

```swift
// Data/Auth/Keychain.swift
import Foundation
import Security

/// Stores small secrets (the auth tokens) as generic passwords in the app's keychain.
struct Keychain {
    let service: String

    func data(for account: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    /// Saves `data`, or deletes the item when it's nil.
    func set(_ data: Data?, for account: String) {
        let match: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(match as CFDictionary)

        guard let data else {
            return
        }
        var item = match
        item[kSecValueData] = data
        // Readable in the background after the first unlock (e.g. for background refresh), never synced or restored.
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}
```

```swift
// Data/Auth/AuthManager.swift
import Foundation
import Observation
import os

/// Signs in against Cognito managed login with the authorization code + PKCE flow (the same flow the web and
/// Android apps use) and keeps the tokens in the keychain, refreshing them as they expire.
///
/// The view runs the browser step through SwiftUI's `webAuthenticationSession` with an ephemeral browser session,
/// so no login cookie outlives the sign-in and signing out only has to forget (and revoke) the tokens.
@MainActor
@Observable
final class AuthManager {
    private(set) var isSignedIn: Bool

    private let config: AppConfig
    private let keychain = Keychain(service: "com.<company>.<app>.auth")
    private let session = URLSession(configuration: .ephemeral)
    @ObservationIgnored private var tokens: Tokens?
    @ObservationIgnored private var refreshTask: Task<String?, Never>?

    private static let tokensAccount = "tokens"
    private static let installedKey = "auth.installed"
    // aws.cognito.signin.user.admin lets the API read the email and delete the account with this token.
    private static let scope = "aws.cognito.signin.user.admin email openid phone profile"
    private static let logger = Logger(subsystem: "com.<company>.<app>", category: "Auth")

    init(config: AppConfig) {
        self.config = config

        // Keychain items survive deleting the app, so don't let a reinstall pick up the old tokens.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Self.installedKey) {
            keychain.set(nil, for: Self.tokensAccount)
            defaults.set(true, forKey: Self.installedKey)
        }

        tokens = keychain.data(for: Self.tokensAccount).flatMap { try? JSONDecoder().decode(Tokens.self, from: $0) }
        isSignedIn = tokens != nil
    }

    var email: String? {
        tokens?.idToken.flatMap { JWT.claims(of: $0)?["email"] as? String }
    }

    /// The Cognito user's `sub`, which stays the same for the life of the account.
    var userID: String? {
        tokens?.idToken.flatMap { JWT.claims(of: $0)?["sub"] as? String }
    }

    /// Starts a sign-in; open `url` in a web authentication session and pass its callback to `completeSignIn`.
    func makeSignInRequest(signUp: Bool = false) -> SignInRequest {
        let verifier = PKCE.randomString()
        let state = PKCE.randomString(byteCount: 16)

        // The sign-up page takes the same parameters and finishes with the same redirect.
        var components = URLComponents()
        components.scheme = "https"
        components.host = config.cognitoDomain
        components.path = signUp ? "/signup" : "/oauth2/authorize"
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.cognitoClientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        return SignInRequest(
            url: components.url!,
            callbackScheme: config.redirectURI.scheme ?? "",
            state: state,
            codeVerifier: verifier
        )
    }

    /// Exchanges the authorization code in the sign-in callback for tokens.
    func completeSignIn(_ request: SignInRequest, callbackURL: URL) async throws {
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let error = value("error") {
            throw AuthError.authorizationFailed(value("error_description") ?? error)
        }
        guard value("state") == request.state, let code = value("code") else {
            throw AuthError.invalidCallback
        }

        let response = try await tokenRequest([
            "grant_type": "authorization_code",
            "client_id": config.cognitoClientID,
            "code": code,
            "redirect_uri": config.redirectURI.absoluteString,
            "code_verifier": request.codeVerifier,
        ])
        save(Tokens(response, previous: nil))
    }

    /// Returns a valid access token, refreshing it first when it's about to expire. Returns nil when signed out;
    /// a refresh token Cognito rejects (revoked or expired) signs the user out.
    func freshAccessToken() async -> String? {
        guard let current = tokens else {
            return nil
        }
        if current.expiresAt > Date().addingTimeInterval(60) {
            return current.accessToken
        }

        // Requests that arrive while a refresh is running wait for it rather than starting another.
        if let refreshTask {
            return await refreshTask.value
        }
        let task = Task { await refresh(current) }
        refreshTask = task
        let accessToken = await task.value
        refreshTask = nil
        return accessToken
    }

    /// Forgets the tokens and revokes the refresh token, so it can't be used again.
    func signOut() {
        let refreshToken = tokens?.refreshToken
        save(nil)

        guard let refreshToken else {
            return
        }
        Task {
            do {
                try await revoke(refreshToken)
            } catch {
                Self.logger.error("Failed to revoke the refresh token: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func refresh(_ current: Tokens) async -> String? {
        guard let refreshToken = current.refreshToken else {
            save(nil)
            return nil
        }

        do {
            let response = try await tokenRequest([
                "grant_type": "refresh_token",
                "client_id": config.cognitoClientID,
                "refresh_token": refreshToken,
            ])
            // The user may have signed out while the refresh was running.
            guard tokens?.refreshToken == refreshToken else {
                return nil
            }
            let updated = Tokens(response, previous: current)
            save(updated)
            return updated.accessToken
        } catch AuthError.invalidGrant {
            Self.logger.info("Refresh token was rejected; signing out")
            save(nil)
            return nil
        } catch {
            // Offline or Cognito is unavailable: stay signed in, and let this request fail without a token.
            Self.logger.error("Token refresh failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func tokenRequest(_ parameters: [String: String]) async throws -> TokenResponse {
        let data = try await postForm(path: "/oauth2/token", parameters)
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func revoke(_ refreshToken: String) async throws {
        _ = try await postForm(path: "/oauth2/revoke", ["token": refreshToken, "client_id": config.cognitoClientID])
    }

    private func postForm(path: String, _ parameters: [String: String]) async throws -> Data {
        var components = URLComponents()
        components.scheme = "https"
        components.host = config.cognitoDomain
        components.path = path

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = FormEncoding.encode(parameters)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let error = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data)
            throw error?.error == "invalid_grant" ? AuthError.invalidGrant : AuthError.requestFailed(status)
        }
        return data
    }

    private func save(_ tokens: Tokens?) {
        self.tokens = tokens
        keychain.set(tokens.flatMap { try? JSONEncoder().encode($0) }, for: Self.tokensAccount)
        if isSignedIn != (tokens != nil) {
            isSignedIn = tokens != nil
        }
    }
}

struct SignInRequest: Sendable {
    let url: URL
    let callbackScheme: String
    let state: String
    let codeVerifier: String
}

enum AuthError: LocalizedError {
    case authorizationFailed(String)
    case invalidCallback
    case invalidGrant
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .authorizationFailed(let message): message
        case .invalidCallback: "The sign-in response didn't match the request."
        case .invalidGrant: "The sign-in has expired."
        case .requestFailed(let status): "Cognito responded with status \(status)."
        }
    }
}

private struct Tokens: Codable {
    let accessToken: String
    let idToken: String?
    let refreshToken: String?
    let expiresAt: Date

    /// Cognito doesn't return a new refresh or ID token on every refresh, so keep the previous ones.
    init(_ response: TokenResponse, previous: Tokens?) {
        accessToken = response.access_token
        idToken = response.id_token ?? previous?.idToken
        refreshToken = response.refresh_token ?? previous?.refreshToken
        expiresAt = Date().addingTimeInterval(TimeInterval(response.expires_in))
    }
}

private struct TokenResponse: Decodable {
    let access_token: String
    let id_token: String?
    let refresh_token: String?
    let expires_in: Int
}

private struct OAuthErrorResponse: Decodable {
    let error: String
}

enum FormEncoding {
    /// `application/x-www-form-urlencoded` body for `parameters`.
    static func encode(_ parameters: [String: String]) -> Data {
        // Only unreserved characters (RFC 3986) go through unescaped.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let body = parameters
            .sorted { $0.key < $1.key }
            .map { key, value in
                let name = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(name)=\(encoded)"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }
}

enum JWT {
    /// The payload of a JWT, without verifying it; only for reading claims the API has already checked.
    static func claims(of token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3, let data = Data(base64URLEncoded: String(parts[1])) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
```

The sign-in view runs the browser step like this:

```swift
@Environment(\.webAuthenticationSession) private var webAuthenticationSession
// ...
let request = container.authManager.makeSignInRequest(signUp: signUp)
do {
    // Ephemeral, so managed login's session cookie doesn't outlive the sign-in and signing out is local.
    let callbackURL = try await webAuthenticationSession.authenticate(
        using: request.url,
        callbackURLScheme: request.callbackScheme,
        preferredBrowserSession: .ephemeral
    )
    try await container.authManager.completeSignIn(request, callbackURL: callbackURL)
} catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
    // The user closed the sign-in sheet.
} catch {
    self.error = "Sign-in failed. Please try again."
}
```

Import `AuthenticationServices` in that view.

## API client

```swift
import Foundation

/// Sends requests to the API with the signed-in user's bearer token, refreshing it first when needed.
/// The endpoints are in <App>API.swift.
final class APIClient: Sendable {
    let baseURL: URL
    private let authManager: AuthManager
    private let session: URLSession

    init(baseURL: URL, authManager: AuthManager) {
        self.baseURL = baseURL
        self.authManager = authManager
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        session = URLSession(configuration: configuration)
    }

    /// Sends a request and decodes the JSON response.
    func send<Response: Decodable>(
        _ method: String, _ path: String, query: [String: String?] = [:], body: (any Encodable)? = nil
    ) async throws -> Response {
        let data = try await perform(method, path, query: query, body: body)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    /// Sends a request whose response has no body worth reading.
    func send(_ method: String, _ path: String, query: [String: String?] = [:], body: (any Encodable)? = nil) async throws {
        _ = try await perform(method, path, query: query, body: body)
    }

    /// Sends a prepared request (e.g. a multipart upload) with the bearer token added; returns the response body.
    func perform(_ request: URLRequest) async throws -> Data {
        var request = request
        if let accessToken = await authManager.freshAccessToken() {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(status: http.statusCode, body: data)
        }
        return data
    }

    func url(_ path: String, query: [String: String?] = [:]) -> URL {
        let url = baseURL.appending(path: path)
        let items = query
            .compactMap { name, value in value.map { URLQueryItem(name: name, value: $0) } }
            .sorted { $0.name < $1.name }
        return items.isEmpty ? url : url.appending(queryItems: items)
    }

    private func perform(_ method: String, _ path: String, query: [String: String?], body: (any Encodable)?) async throws -> Data {
        var request = URLRequest(url: url(path, query: query))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        return try await perform(request)
    }
}
```

`APIError: LocalizedError` holds the status and body, and uses the body text as the message for 400s with a string body.
`<App>API.swift` is an extension on `APIClient` with one method per endpoint: `logUser()` (`POST users`), `updateMe(_:)` (`PUT users/me`)
and `deleteMe()` (`DELETE users/me`). `Models.swift` has `Codable` structs that mirror the OpenAPI schemas, with optionals for nullable fields.

## App structure and screens

- `AppContainer` (`@MainActor @Observable`) creates `AppConfig.fromBundle()`, `AuthManager`, `APIClient`, `AccountRepository` and `TermsAcceptance`.
  `<App>App` creates it once and passes it down with `.environment(container)`.
- `RootView` switches on `authManager.isSignedIn`: `SignInView` when signed out, `TermsView` until terms for this `sub` and version are accepted
  (same version string as the web and Android, stored in UserDefaults), and `MainTabView` otherwise. `MainTabView` calls `logUser()` once for each `sub`.
- `MainTabView` has Home (placeholder) and Account tabs. `AccountView` shows the email, Profile, Privacy Policy and Terms (opened with `openURL`
  to the web pages) and Sign out. `ProfileView` edits the name and deletes the account after a confirmation dialog, then signs out.
- `PrivacyInfo.xcprivacy` declares the data the core collects: email address and name, linked to the user, for app functionality, not tracking.

## Tests and done criteria

XCTest cases cover `PKCE` (challenge for a known verifier, URL-safe output), `FormEncoding`, `JWT.claims`, the `Tokens` refresh keeping the previous refresh token
(make the needed types `internal` or test through `AuthManager`), `APIError` messages, `Models` decoding with missing optionals, and `TermsAcceptance` versioning.

`ios/.gitignore` covers `*.xcodeproj/`, `*.xcworkspace/`, `xcuserdata/`, `DerivedData/`, `build/`, `*.xcresult`, `Config/Local.xcconfig`, `.swiftpm/` and `.build/`.

**Done when**, on macOS: `xcodegen generate`, then
`xcodebuild test -project <App>.xcodeproj -scheme <App> -destination 'platform=iOS Simulator,name=iPhone 17'` succeeds.

**On other machines:** check by reading that every source folder in `project.yml` exists, that every Info.plist key `AppConfig` reads is defined
and has a matching xcconfig variable, that each type referenced from the views exists, and that `ExportOptions.plist` (see `infrastructure.md`) is present.
Then report iOS as "not built: needs macOS".
