import CryptoKit
import Foundation

/// Values shared by the app and the packet tunnel extension.
enum FreedomShared {
    static let appGroup = "group.com.topfreedom.vpn"
    static let tunnelBundleId = "com.topfreedom.vpn.tunnel"
    /// Local SOCKS inbound that hev-socks5-tunnel forwards the device traffic to.
    static let socksPort = 10808

    /// The Xray config the tunnel runs; the app writes it before starting the VPN.
    static var selectedConfigURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("selected-config.json")
    }

    static func saveSelectedConfig(_ json: String) throws {
        guard let url = selectedConfigURL else { throw FreedomError.noAppGroup }
        try Data(json.utf8).write(to: url, options: .atomic)
    }

    static func loadSelectedConfig() -> String? {
        guard let url = selectedConfigURL, let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

enum FreedomError: LocalizedError {
    case noAppGroup
    case noConfig
    case badConfig(String)
    case xray(String)
    case tunnelFd

    var errorDescription: String? {
        switch self {
        case .noAppGroup: return "App Group недоступна"
        case .noConfig: return "Сервер не выбран"
        case .badConfig(let why): return "Неверная конфигурация сервера: \(why)"
        case .xray(let why): return "Xray: \(why)"
        case .tunnelFd: return "Не найден интерфейс VPN"
        }
    }
}

/// One server of a subscription: a complete Xray config from the panel (XRAY_JSON).
struct ServerConfig: Codable, Identifiable, Equatable {
    /// Stable id: hash of the name and config, so a refreshed subscription keeps unchanged servers.
    let id: String
    let name: String
    let json: String
}

/// Usage and expiry from the `subscription-userinfo` header.
struct SubscriptionUsage: Codable, Equatable {
    var uploadBytes: Int64 = 0
    var downloadBytes: Int64 = 0
    var totalBytes: Int64 = 0
    /// Unix seconds; nil when the plan has no end date.
    var expire: TimeInterval?

    var usedBytes: Int64 { uploadBytes + downloadBytes }
}

enum SubscriptionParser {
    /// The panel answers our User-Agent with a JSON array of Xray configs, each with "remarks".
    static func parseServers(_ body: Data) throws -> [ServerConfig] {
        guard let array = try JSONSerialization.jsonObject(with: body) as? [[String: Any]] else {
            throw FreedomError.badConfig("ожидался список конфигураций Xray")
        }
        return array.compactMap { item in
            guard let data = try? JSONSerialization.data(withJSONObject: item, options: [.sortedKeys]),
                  let json = String(data: data, encoding: .utf8) else { return nil }
            let name = (item["remarks"] as? String)?.trimmingCharacters(in: .whitespaces) ?? "Сервер"
            return ServerConfig(id: shortHash(name + "|" + json), name: name, json: json)
        }
    }

    /// `upload=1; download=2; total=3; expire=1765000000`
    static func parseUsage(_ header: String?) -> SubscriptionUsage? {
        guard let header, !header.isEmpty else { return nil }
        var usage = SubscriptionUsage()
        for part in header.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2 else { continue }
            let value = Int64(kv[1]) ?? 0
            switch kv[0].lowercased() {
            case "upload": usage.uploadBytes = value
            case "download": usage.downloadBytes = value
            case "total": usage.totalBytes = value
            case "expire": usage.expire = value > 0 ? TimeInterval(value) : nil
            default: break
            }
        }
        return usage
    }

    /// `profile-title` may be "base64:..." (Remnawave rwEncodeBase64).
    static func decodeTitle(_ header: String?) -> String? {
        guard let header, !header.isEmpty else { return nil }
        if header.hasPrefix("base64:"), let data = Data(base64Encoded: String(header.dropFirst(7))) {
            return String(data: data, encoding: .utf8)
        }
        return header
    }

    static func shortHash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

enum XrayConfigPatcher {
    /// Prepares a panel config for the tunnel: our SOCKS inbound (with sniffing, so domain rules
    /// like geosite:category-ru work), no file logs (the extension cannot write there), warnings only.
    static func prepareForTunnel(_ json: String, socksPort: Int = FreedomShared.socksPort) throws -> String {
        guard var root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            throw FreedomError.badConfig("не JSON-объект")
        }
        guard let outbounds = root["outbounds"] as? [Any], !outbounds.isEmpty else {
            throw FreedomError.badConfig("нет outbounds")
        }
        root["inbounds"] = [[
            "tag": "socks-in",
            "protocol": "socks",
            "listen": "127.0.0.1",
            "port": socksPort,
            "settings": ["auth": "noauth", "udp": true],
            "sniffing": [
                "enabled": true,
                "destOverride": ["http", "tls", "quic"],
                "routeOnly": true,
            ] as [String: Any],
        ] as [String: Any]]
        root["log"] = ["loglevel": "warning"]
        root.removeValue(forKey: "remarks")
        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else { throw FreedomError.badConfig("кодировка") }
        return text
    }

    /// hev-socks5-tunnel settings: device packets -> local SOCKS inbound of Xray.
    static func hevConfig(socksPort: Int = FreedomShared.socksPort, mtu: Int = 9000) -> String {
        """
        tunnel:
          mtu: \(mtu)
        socks5:
          port: \(socksPort)
          address: 127.0.0.1
          udp: 'udp'
        misc:
          task-stack-size: 24576
          log-level: warn
        """
    }
}

enum HWID {
    /// Same scheme as the Android app: 32 hex chars of SHA-256 over a per-install secret and the
    /// subscription host, so different providers cannot match one device. Fits Remnawave's x-hwid format.
    static func value(secret: String, host: String) -> String {
        let digest = SHA256.hash(data: Data("freedomvpn-hwid|\(secret)|\(host.lowercased())".utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(32))
    }

    /// OkHttp-style safety: header values must be printable ASCII.
    static func headerValue(_ text: String) -> String {
        String(String(text.unicodeScalars.filter { $0.value >= 0x20 && $0.value <= 0x7E }).prefix(64))
            .trimmingCharacters(in: .whitespaces)
    }
}
