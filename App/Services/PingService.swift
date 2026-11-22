import Foundation
import LibXray

/// Real delay of servers through Xray (libXray pingBatch), like "real ping" in the Android app.
enum PingService {
    /// Returns delay in ms per server id; -1 for no connection.
    static func ping(_ servers: [ServerConfig]) async -> [String: Int] {
        await Task.detached(priority: .userInitiated) {
            let configs = servers.map { ["xrayJson": stripInbounds($0.json)] }
            let request: [String: Any] = [
                "apiVersion": 3,
                "method": "pingBatch",
                "payload": [
                    "configs": configs,
                    "timeout": 5,
                    "url": "https://www.gstatic.com/generate_204",
                ] as [String: Any],
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: request),
                  let text = String(data: data, encoding: .utf8) else { return [:] }
            let answer = LibXrayInvoke(text)
            guard let obj = try? JSONSerialization.jsonObject(with: Data(answer.utf8)) as? [String: Any],
                  let payload = obj["data"] as? [String: Any],
                  let results = payload["results"] as? [[String: Any]] else { return [:] }
            var out: [String: Int] = [:]
            for (index, result) in results.enumerated() where index < servers.count {
                let ok = (result["success"] as? Bool) ?? false
                let delay = (result["delay"] as? NSNumber)?.intValue ?? 0
                out[servers[index].id] = ok && delay > 0 ? delay : -1
            }
            return out
        }.value
    }

    /// Ping builds its own probe; the panel's inbounds (ports) are not needed and may clash.
    private static func stripInbounds(_ json: String) -> String {
        guard var root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return json }
        root.removeValue(forKey: "inbounds")
        root["log"] = ["loglevel": "none"]
        guard let data = try? JSONSerialization.data(withJSONObject: root),
              let text = String(data: data, encoding: .utf8) else { return json }
        return text
    }
}
