import Foundation

/// Service addresses (same as the Android app's FreedomConfig).
enum FreedomConfig {
    static let cabinetURL = URL(string: "https://cabinet.topfreedomhub.com")!
    static let cabinetAPI = URL(string: "https://cabinet.topfreedomhub.com/api/cabinet")!
    static let botUsername = "Topfreedom_bot"
    static let supportURL = URL(string: "https://t.me/topfreedom_support_bot")!
    static var userAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        // The panel's "Freedom VPN JSON" rule matches "freedomvpn" and answers with XRAY_JSON.
        return "FreedomVPN-iOS/\(version)"
    }
}

/// Minimal client for the Bedolaga cabinet API (what the web cabinet and the Android app use).
enum CabinetAPI {
    struct APIError: LocalizedError {
        let status: Int
        let message: String
        var errorDescription: String? { message }
    }

    struct AuthResult: Decodable {
        let accessToken: String
        let refreshToken: String
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
        }
    }

    struct DeepLinkToken: Decodable {
        let token: String
        let botUsername: String?
        let expiresIn: Int?
        enum CodingKeys: String, CodingKey {
            case token
            case botUsername = "bot_username"
            case expiresIn = "expires_in"
        }
    }

    enum PollResult {
        case pending, expired
        case done(AuthResult)
    }

    struct SubscriptionData: Decodable {
        let subscriptionUrl: String?
        let isActive: Bool?
        let isTrial: Bool?
        let endDate: String?
        let daysLeft: Int?
        let timeLeftDisplay: String?
        let trafficLimitGb: Double?
        let trafficUsedGb: Double?
        let deviceLimit: Int?
        let tariffName: String?
        enum CodingKeys: String, CodingKey {
            case subscriptionUrl = "subscription_url"
            case isActive = "is_active"
            case isTrial = "is_trial"
            case endDate = "end_date"
            case daysLeft = "days_left"
            case timeLeftDisplay = "time_left_display"
            case trafficLimitGb = "traffic_limit_gb"
            case trafficUsedGb = "traffic_used_gb"
            case deviceLimit = "device_limit"
            case tariffName = "tariff_name"
        }
    }

    struct SubscriptionStatus: Decodable {
        let hasSubscription: Bool?
        let subscription: SubscriptionData?
        enum CodingKeys: String, CodingKey {
            case hasSubscription = "has_subscription"
            case subscription
        }
    }

    struct TrialInfo: Decodable {
        let isAvailable: Bool?
        let durationDays: Int?
        let requiresPayment: Bool?
        enum CodingKeys: String, CodingKey {
            case isAvailable = "is_available"
            case durationDays = "duration_days"
            case requiresPayment = "requires_payment"
        }
    }

    struct ConnectionLink: Decodable {
        let subscriptionUrl: String?
        let displayLink: String?
        enum CodingKeys: String, CodingKey {
            case subscriptionUrl = "subscription_url"
            case displayLink = "display_link"
        }
    }

    struct ReferralInfo: Decodable {
        let referralLink: String?
        let botReferralLink: String?
        let totalReferrals: Int?
        let activeReferrals: Int?
        enum CodingKeys: String, CodingKey {
            case referralLink = "referral_link"
            case botReferralLink = "bot_referral_link"
            case totalReferrals = "total_referrals"
            case activeReferrals = "active_referrals"
        }
    }

    private struct Empty: Encodable {}

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    private static func call(
        _ method: String,
        _ path: String,
        body: [String: Any]? = nil,
        token: String? = nil
    ) async throws -> (Int, Data) {
        var request = URLRequest(url: cabinetURL(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(FreedomConfig.userAgent, forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if method != "GET" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body ?? [:])
        }
        let (data, response) = try await session.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    private static func cabinetURL(_ path: String) -> URL {
        URL(string: FreedomConfig.cabinetAPI.absoluteString + path)!
    }

    private static func parse<T: Decodable>(_ status: Int, _ data: Data) throws -> T {
        guard (200..<300).contains(status) else { throw APIError(status: status, message: detail(data) ?? "HTTP \(status)") }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func detail(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let text = obj["detail"] as? String { return text }
        if let dict = obj["detail"] as? [String: Any] { return dict["message"] as? String }
        return nil
    }

    // MARK: Telegram (deep link to the bot)

    static func requestDeepLink() async throws -> DeepLinkToken {
        let (s, d) = try await call("POST", "/auth/deeplink/request")
        return try parse(s, d)
    }

    static func pollDeepLink(_ token: String) async throws -> PollResult {
        let (s, d) = try await call("POST", "/auth/deeplink/poll", body: ["token": token])
        switch s {
        case 202: return .pending
        case 410: return .expired
        default: return .done(try parse(s, d))
        }
    }

    static func refresh(_ refreshToken: String) async throws -> AuthResult {
        let (s, d) = try await call("POST", "/auth/refresh", body: ["refresh_token": refreshToken])
        return try parse(s, d)
    }

    // MARK: Account

    static func subscriptionStatus(_ token: String) async throws -> SubscriptionStatus {
        let (s, d) = try await call("GET", "/subscription", token: token)
        return try parse(s, d)
    }

    static func trialInfo(_ token: String) async throws -> TrialInfo {
        let (s, d) = try await call("GET", "/subscription/trial", token: token)
        return try parse(s, d)
    }

    static func activateTrial(_ token: String) async throws {
        let (s, d) = try await call("POST", "/subscription/trial", body: [:], token: token)
        guard (200..<300).contains(s) else { throw APIError(status: s, message: detail(d) ?? "HTTP \(s)") }
    }

    static func connectionLink(_ token: String) async throws -> ConnectionLink {
        let (s, d) = try await call("GET", "/subscription/connection-link", token: token)
        return try parse(s, d)
    }

    static func referralInfo(_ token: String) async throws -> ReferralInfo {
        let (s, d) = try await call("GET", "/referral", token: token)
        return try parse(s, d)
    }
}
