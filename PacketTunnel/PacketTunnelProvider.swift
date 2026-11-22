import HevSocks5Tunnel
import LibXray
import NetworkExtension
import os

/// Freedom VPN tunnel: device packets -> hev-socks5-tunnel -> local SOCKS inbound -> Xray -> server.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let log = Logger(subsystem: "com.topfreedom.vpn.tunnel", category: "tunnel")
    private var hevThread: Thread?

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let xrayJson: String
        do {
            guard let raw = FreedomShared.loadSelectedConfig() else { throw FreedomError.noConfig }
            xrayJson = try XrayConfigPatcher.prepareForTunnel(raw)
        } catch {
            log.error("config: \(error.localizedDescription, privacy: .public)")
            completionHandler(error)
            return
        }

        // geosite.dat / geoip.dat (RoscomVPN) shipped with the extension: rules like geosite:category-ru.
        if let geo = Bundle.main.resourceURL?.appendingPathComponent("Geo").path {
            setenv("XRAY_LOCATION_ASSET", geo, 1)
        }

        setTunnelNetworkSettings(Self.networkSettings()) { [weak self] error in
            guard let self else { return }
            if let error {
                completionHandler(error)
                return
            }
            do {
                try self.startXray(xrayJson)
                try self.startHev()
                completionHandler(nil)
            } catch {
                self.log.error("start: \(error.localizedDescription, privacy: .public)")
                self.stopAll()
                completionHandler(error)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        stopAll()
        completionHandler()
    }

    // MARK: - Network settings

    private static func networkSettings() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "254.1.1.1")
        settings.mtu = 9000

        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4

        let ipv6 = NEIPv6Settings(addresses: ["fd6e:a81b:704f:1211::1"], networkPrefixLengths: [64])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = ipv6

        // DNS queries go into the tunnel; Xray's routing decides where they leave.
        let dns = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
        dns.matchDomains = [""]
        settings.dnsSettings = dns
        return settings
    }

    // MARK: - Xray

    private func startXray(_ json: String) throws {
        let response = invoke(method: "runXray", payload: ["xrayJson": json])
        guard response.success else { throw FreedomError.xray(response.error ?? "не запустился") }
    }

    private func invoke(method: String, payload: [String: Any]) -> (success: Bool, error: String?) {
        let request: [String: Any] = ["apiVersion": 3, "method": method, "payload": payload]
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let text = String(data: data, encoding: .utf8) else { return (false, "запрос") }
        let answer = LibXrayInvoke(text)
        guard let obj = try? JSONSerialization.jsonObject(with: Data(answer.utf8)) as? [String: Any] else {
            return (false, answer)
        }
        return ((obj["success"] as? Bool) ?? false, obj["error"] as? String)
    }

    // MARK: - hev-socks5-tunnel

    private func startHev() throws {
        let fd = fvpn_find_utun_fd()
        guard fd >= 0 else { throw FreedomError.tunnelFd }
        let config = XrayConfigPatcher.hevConfig()
        let thread = Thread {
            let bytes = Array(config.utf8)
            let code = bytes.withUnsafeBufferPointer { buffer in
                hev_socks5_tunnel_main_from_str(buffer.baseAddress, UInt32(buffer.count), fd)
            }
            Logger(subsystem: "com.topfreedom.vpn.tunnel", category: "hev").notice("hev exited: \(code)")
        }
        thread.name = "hev-socks5-tunnel"
        thread.stackSize = 1 << 20
        thread.start()
        hevThread = thread
    }

    private func stopAll() {
        if hevThread != nil {
            hev_socks5_tunnel_quit()
            hevThread = nil
        }
        _ = invoke(method: "stopXray", payload: [:])
    }
}
