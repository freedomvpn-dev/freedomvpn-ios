import Foundation
import NetworkExtension

/// Owns the VPN profile (NETunnelProviderManager) and reports the connection status.
@MainActor
final class VPNController: ObservableObject {
    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var connectedSince: Date?
    @Published var lastError: String?

    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?

    var isConnected: Bool { status == .connected }
    var isBusy: Bool { status == .connecting || status == .disconnecting || status == .reasserting }

    func load() async {
        let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
        manager = managers.first
        observe()
        refresh()
    }

    /// Writes the server config for the extension and starts the tunnel.
    func connect(server: ServerConfig) async {
        lastError = nil
        do {
            try FreedomShared.saveSelectedConfig(server.json)
            let manager = try await preparedManager()
            try manager.connection.startVPNTunnel()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func disconnect() {
        manager?.connection.stopVPNTunnel()
    }

    /// Restart with another server while connected.
    func reconnect(server: ServerConfig) async {
        guard isConnected || status == .connecting else {
            try? FreedomShared.saveSelectedConfig(server.json)
            return
        }
        disconnect()
        for _ in 0..<20 where status != .disconnected {
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        await connect(server: server)
    }

    private func preparedManager() async throws -> NETunnelProviderManager {
        let manager = self.manager ?? NETunnelProviderManager()
        let proto = (manager.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        proto.providerBundleIdentifier = FreedomShared.tunnelBundleId
        proto.serverAddress = "Freedom VPN"
        manager.protocolConfiguration = proto
        manager.localizedDescription = "Freedom VPN"
        manager.isEnabled = true
        // First save shows the system "Add VPN configuration" prompt.
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        self.manager = manager
        observe()
        return manager
    }

    private func observe() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        guard let connection = manager?.connection else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: connection, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func refresh() {
        status = manager?.connection.status ?? .invalid
        connectedSince = status == .connected ? manager?.connection.connectedDate : nil
    }
}
