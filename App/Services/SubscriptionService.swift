import Foundation
import UIKit

/// Saved state of the account subscription: its URL, servers and usage.
struct StoredSubscription: Codable, Equatable {
    var url: String
    var title: String?
    var supportURL: String?
    var usage: SubscriptionUsage?
    var servers: [ServerConfig]
    var updatedAt: Date
}

enum SubscriptionError: LocalizedError {
    case http(Int, deviceLimit: Bool)
    case empty

    var errorDescription: String? {
        switch self {
        case .http(_, true): return "Достигнут лимит устройств. Отключите старое устройство в личном кабинете."
        case .http(let code, false): return "Сервер подписки ответил ошибкой \(code)"
        case .empty: return "В подписке нет серверов"
        }
    }
}

/// Downloads the subscription with the HWID headers the panel's device limit counts.
enum SubscriptionService {
    private static let fileName = "subscription.json"

    static func fetch(url urlString: String) async throws -> StoredSubscription {
        guard let url = URL(string: urlString), let host = url.host else { throw SubscriptionError.empty }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(FreedomConfig.userAgent, forHTTPHeaderField: "User-Agent")
        for (key, value) in deviceHeaders(host: host) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        let limitReached = (http?.value(forHTTPHeaderField: "x-hwid-max-devices-reached") ?? "") == "true"
        guard (200..<300).contains(code), !limitReached else { throw SubscriptionError.http(code, deviceLimit: limitReached) }
        let servers = try SubscriptionParser.parseServers(data)
        guard !servers.isEmpty else { throw SubscriptionError.empty }
        return StoredSubscription(
            url: urlString,
            title: SubscriptionParser.decodeTitle(http?.value(forHTTPHeaderField: "profile-title")),
            supportURL: http?.value(forHTTPHeaderField: "support-url"),
            usage: SubscriptionParser.parseUsage(http?.value(forHTTPHeaderField: "subscription-userinfo")),
            servers: servers,
            updatedAt: Date()
        )
    }

    static func deviceHeaders(host: String) -> [String: String] {
        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: &system.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return [
            "x-hwid": HWID.value(secret: Keychain.hwidSecret, host: host),
            "x-device-os": "iOS",
            "x-ver-os": HWID.headerValue(UIDevice.current.systemVersion),
            "x-device-model": HWID.headerValue(machine),
        ]
    }

    // MARK: Local copy

    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    static func load() -> StoredSubscription? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(StoredSubscription.self, from: data)
    }

    static func save(_ subscription: StoredSubscription?) {
        let url = fileURL
        guard let subscription else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(subscription) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
