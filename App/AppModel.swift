import Foundation
import SwiftUI
import UIKit

/// App state: session, the account subscription, selected server and pings.
/// Mirrors the Android app's AccountManager + home screen ViewModel.
@MainActor
final class AppModel: ObservableObject {
    enum LoginState: Equatable {
        case idle
        case waitingTelegram(link: URL)
        case working
        case failed(String)
    }

    @Published var loginState: LoginState = .idle
    @Published private(set) var isLoggedIn = Keychain.get("access_token") != nil
    @Published private(set) var subscription: StoredSubscription? = SubscriptionService.load()
    @Published var selectedServerId: String? = UserDefaults.standard.string(forKey: "selected_server")
    @Published private(set) var pings: [String: Int] = [:]
    @Published private(set) var isPinging = false
    @Published private(set) var isUpdating = false
    @Published var toast: String?
    @Published private(set) var account: CabinetAPI.SubscriptionData?
    @Published private(set) var trial: CabinetAPI.TrialInfo?

    let vpn = VPNController()
    private var pollTask: Task<Void, Never>?

    var servers: [ServerConfig] { subscription?.servers ?? [] }
    var selectedServer: ServerConfig? {
        servers.first { $0.id == selectedServerId } ?? servers.first
    }
    /// Welcome screen: signed out and no servers.
    var needsWelcome: Bool { !isLoggedIn && servers.isEmpty }

    // MARK: Startup

    func start() async {
        await vpn.load()
        if subscription != nil { await updateSubscription(silent: true) }
        if isLoggedIn { await loadAccount() }
    }

    // MARK: Session

    private var accessToken: String? { Keychain.get("access_token") }

    private func saveSession(_ auth: CabinetAPI.AuthResult) {
        Keychain.set("access_token", auth.accessToken)
        if !auth.refreshToken.isEmpty { Keychain.set("refresh_token", auth.refreshToken) }
        isLoggedIn = true
    }

    /// Runs a call with the access token; on 401 refreshes the session once and retries.
    private func withToken<T>(_ block: (String) async throws -> T) async throws -> T {
        do {
            return try await block(accessToken ?? "")
        } catch let error as CabinetAPI.APIError where error.status == 401 {
            guard let refresh = Keychain.get("refresh_token") else { throw error }
            let auth = try await CabinetAPI.refresh(refresh)
            saveSession(auth)
            return try await block(auth.accessToken)
        }
    }

    func logout() {
        pollTask?.cancel()
        Keychain.set("access_token", nil)
        Keychain.set("refresh_token", nil)
        isLoggedIn = false
        account = nil
        trial = nil
        loginState = .idle
    }

    // MARK: Telegram login (deep link to the bot, then poll)

    func startTelegramLogin() async {
        loginState = .working
        do {
            let link = try await CabinetAPI.requestDeepLink()
            let bot = (link.botUsername?.isEmpty == false ? link.botUsername! : FreedomConfig.botUsername)
            // tg:// opens Telegram directly: t.me is often blocked without a VPN.
            let app = URL(string: "tg://resolve?domain=\(bot)&start=webauth_\(link.token)")!
            let web = URL(string: "https://t.me/\(bot)?start=webauth_\(link.token)")!
            loginState = .waitingTelegram(link: web)
            if UIApplication.shared.canOpenURL(app) {
                await UIApplication.shared.open(app)
            } else {
                await UIApplication.shared.open(web)
            }
            poll(token: link.token, lifetime: TimeInterval(link.expiresIn ?? 600))
        } catch {
            loginState = .failed(error.localizedDescription)
        }
    }

    private func poll(token: String, lifetime: TimeInterval) {
        pollTask?.cancel()
        let deadline = Date().addingTimeInterval(lifetime)
        pollTask = Task { [weak self] in
            while !Task.isCancelled, Date() < deadline {
                do {
                    switch try await CabinetAPI.pollDeepLink(token) {
                    case .pending:
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                    case .expired:
                        self?.loginState = .failed("Время входа истекло. Попробуйте ещё раз.")
                        return
                    case .done(let auth):
                        self?.saveSession(auth)
                        self?.loginState = .idle
                        await self?.afterLogin()
                        return
                    }
                } catch is CancellationError {
                    return
                } catch {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
            }
            if !Task.isCancelled { self?.loginState = .failed("Время входа истекло. Попробуйте ещё раз.") }
        }
    }

    func cancelLogin() {
        pollTask?.cancel()
        loginState = .idle
    }

    // MARK: Account and subscription

    private func afterLogin() async {
        await loadAccount()
        if account?.isActive == true { await importAccountSubscription() }
    }

    func loadAccount() async {
        do {
            let status = try await withToken { try await CabinetAPI.subscriptionStatus($0) }
            account = status.hasSubscription == true ? status.subscription : nil
            if account?.isActive != true {
                trial = try? await withToken { try await CabinetAPI.trialInfo($0) }
            } else {
                trial = nil
                if subscription == nil { await importAccountSubscription() }
            }
        } catch let error as CabinetAPI.APIError where error.status == 401 {
            logout()
        } catch {
            toast = error.localizedDescription
        }
    }

    func activateTrial() async {
        do {
            try await withToken { try await CabinetAPI.activateTrial($0) }
            await loadAccount()
            await importAccountSubscription()
        } catch {
            toast = error.localizedDescription
        }
    }

    private func importAccountSubscription() async {
        var url = account?.subscriptionUrl
        if url?.hasPrefix("http") != true {
            let link = try? await withToken { try await CabinetAPI.connectionLink($0) }
            url = link?.subscriptionUrl ?? link?.displayLink
        }
        guard let url, url.hasPrefix("http") else {
            toast = "Ссылка подписки пока недоступна"
            return
        }
        await importSubscription(url: url)
    }

    /// "I have a link": any subscription of our panel (others need the XRAY_JSON format too).
    func importSubscription(url: String) async {
        isUpdating = true
        defer { isUpdating = false }
        do {
            let fresh = try await SubscriptionService.fetch(url: url.trimmingCharacters(in: .whitespacesAndNewlines))
            apply(fresh)
            toast = "Список серверов обновлён"
        } catch {
            toast = error.localizedDescription
        }
    }

    func updateSubscription(silent: Bool = false) async {
        guard let url = subscription?.url else { return }
        isUpdating = true
        defer { isUpdating = false }
        do {
            apply(try await SubscriptionService.fetch(url: url))
            if !silent { toast = "Список серверов обновлён" }
        } catch {
            if !silent { toast = error.localizedDescription }
        }
    }

    private func apply(_ fresh: StoredSubscription) {
        subscription = fresh
        SubscriptionService.save(fresh)
        if selectedServerId == nil || !fresh.servers.contains(where: { $0.id == selectedServerId }) {
            select(fresh.servers.first)
        }
        pings = pings.filter { id, _ in fresh.servers.contains { $0.id == id } }
        Task { await pingAll() }
    }

    // MARK: Servers

    func select(_ server: ServerConfig?) {
        selectedServerId = server?.id
        UserDefaults.standard.set(server?.id, forKey: "selected_server")
        if let server { Task { await vpn.reconnect(server: server) } }
    }

    func toggleVPN() async {
        if vpn.isConnected || vpn.isBusy {
            vpn.disconnect()
        } else if let server = selectedServer {
            await vpn.connect(server: server)
            if let error = vpn.lastError { toast = error }
        }
    }

    func pingAll() async {
        await ping(servers)
    }

    func ping(_ list: [ServerConfig]) async {
        guard !isPinging, !list.isEmpty else { return }
        isPinging = true
        defer { isPinging = false }
        for server in list { pings[server.id] = nil }
        let result = await PingService.ping(list)
        pings.merge(result) { _, new in new }
    }

    // MARK: Invite

    func referralLink() async throws -> (link: String, total: Int, active: Int) {
        let info = try await withToken { try await CabinetAPI.referralInfo($0) }
        let link = [info.referralLink, info.botReferralLink]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("https://") }
        guard let link else { throw CabinetAPI.APIError(status: 0, message: "Ссылка-приглашение недоступна") }
        return (link, info.totalReferrals ?? 0, info.activeReferrals ?? 0)
    }
}
