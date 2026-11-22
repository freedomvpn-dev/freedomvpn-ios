import NetworkExtension
import SwiftUI

/// Home: connection card with the round button, one-line subscription strip, servers with ping.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var vpn: VPNController
    @State private var showInvite = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ConnectionCard()
                if let usage = model.subscription?.usage {
                    SubscriptionStrip(usage: usage, canInvite: model.isLoggedIn) { showInvite = true }
                }
                serversHeader
                ServerList()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Freedom VPN")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Link(destination: supportURL) { Image(systemName: "paperplane") }
                    .accessibilityLabel("Поддержка")
            }
        }
        .refreshable { await model.updateSubscription() }
        .sheet(isPresented: $showInvite) { NavigationStack { InviteView() } }
        .task { if model.pings.isEmpty { await model.pingAll() } }
    }

    private var supportURL: URL {
        model.subscription?.supportURL.flatMap(URL.init(string:)) ?? FreedomConfig.supportURL
    }

    private var serversHeader: some View {
        HStack {
            Text("Серверы").font(.title3.weight(.heavy))
            Spacer()
            Button {
                Task { await model.pingAll() }
            } label: {
                Label(model.isPinging ? "Проверяем…" : "Пинг", systemImage: "speedometer")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Theme.card, in: Capsule())
            }
            .disabled(model.isPinging)
            Button {
                Task { await model.updateSubscription() }
            } label: {
                Image(systemName: "arrow.clockwise").font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("Обновить список серверов")
        }
        .padding(.top, 8)
    }
}

private struct ConnectionCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var vpn: VPNController

    var body: some View {
        let on = vpn.isConnected
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                Circle().fill(on ? Color.green : Color.secondary).frame(width: 8, height: 8)
                Text(statusText).font(.subheadline.weight(.bold)).lineLimit(1)
            }
            .foregroundStyle(on ? Color.white : Color.primary)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(on ? Color.white.opacity(0.16) : Theme.cardLow, in: Capsule())

            Button {
                Task { await model.toggleVPN() }
            } label: {
                VStack(spacing: 6) {
                    if vpn.isBusy {
                        ProgressView().tint(on ? Theme.accent : .white).scaleEffect(1.6)
                    } else {
                        Image(systemName: "power").font(.system(size: 54, weight: .semibold))
                    }
                    Text(on ? "Отключить" : "Подключить").font(.headline.weight(.heavy))
                }
                .foregroundStyle(on ? Theme.accent : Color.white)
                .frame(width: 196, height: 196)
                .background(on ? Color.white : Theme.accent, in: Circle())
                .overlay(Circle().stroke(on ? Color.white.opacity(0.22) : Theme.accentSoft, lineWidth: 10))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .disabled(model.selectedServer == nil)
            .accessibilityValue(on ? "Защищено" : "Не подключено")

            if on, let since = vpn.connectedSince {
                Text(since, style: .timer)
                    .font(.title2.weight(.heavy).monospacedDigit())
                    .foregroundStyle(.white)
            } else if !on {
                Text("Нажмите, чтобы защитить соединение")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(on ? Theme.accent : Theme.card, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: on)
    }

    private var statusText: String {
        switch vpn.status {
        case .connected: return "Защищено · \(model.selectedServer?.displayName ?? "")"
        case .connecting, .reasserting: return "Подключаемся…"
        case .disconnecting: return "Отключаемся…"
        default: return "Не подключено"
        }
    }
}

private struct SubscriptionStrip: View {
    let usage: SubscriptionUsage
    let canInvite: Bool
    let onInvite: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(headline).font(.subheadline.weight(.heavy))
                        .foregroundStyle(expired ? Color.red : Color.primary)
                    Text(details).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if usage.totalBytes > 0 {
                    ProgressView(value: min(1, Double(usage.usedBytes) / Double(usage.totalBytes)))
                        .tint(Theme.accent)
                }
            }
            Spacer(minLength: 0)
            if canInvite {
                Button(action: onInvite) {
                    Label("Пригласить", systemImage: "person.badge.plus")
                        .font(.subheadline.weight(.heavy))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Theme.accentSoft, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 16).padding(.trailing, 10).padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var expired: Bool { (usage.expire ?? .infinity) < Date().timeIntervalSince1970 }

    private var headline: String {
        guard let expire = usage.expire else { return "Без срока" }
        if expired { return "Подписка закончилась" }
        let days = Int(ceil((expire - Date().timeIntervalSince1970) / 86_400))
        return "\(days) \(Self.daysWord(days))"
    }

    private var details: String {
        let formatter = ByteCountFormatter()
        let used = formatter.string(fromByteCount: usage.usedBytes)
        let traffic = usage.totalBytes > 0 ? "\(used) из \(formatter.string(fromByteCount: usage.totalBytes))" : "\(used) · без лимита"
        guard let expire = usage.expire else { return traffic }
        let date = Date(timeIntervalSince1970: expire).formatted(date: .numeric, time: .omitted)
        return "до \(date) · \(traffic)"
    }

    static func daysWord(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return "день" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "дня" }
        return "дней"
    }
}

private struct ServerList: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 2) {
            if model.servers.isEmpty {
                Text("Серверов пока нет. Войдите в аккаунт или добавьте ссылку подписки во вкладке «Ещё».")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(20)
            }
            ForEach(model.servers) { server in
                row(server)
            }
        }
        .padding(6)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func row(_ server: ServerConfig) -> some View {
        let selected = server.id == model.selectedServer?.id
        return HStack(spacing: 12) {
            Text(server.flag ?? "🌐").font(.title3)
                .frame(width: 38, height: 38)
                .background(Theme.cardLow, in: Circle())
                .accessibilityHidden(true)
            Text(server.displayName).font(.body.weight(.bold)).lineLimit(2)
            Spacer(minLength: 8)
            pingChip(server)
            if selected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent).font(.title3)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(minHeight: 60)
        .background(selected ? Theme.accentSoft : Color.clear,
                    in: RoundedRectangle(cornerRadius: selected ? 22 : 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { model.select(server) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func pingChip(_ server: ServerConfig) -> some View {
        let ms = model.pings[server.id]
        Button {
            Task { await model.ping([server]) }
        } label: {
            Group {
                if let ms {
                    let colors = Theme.delayColors(ms, dark: scheme == .dark)
                    Text(ms < 0 ? "нет связи" : "\(ms) мс")
                        .foregroundStyle(colors.fg)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(colors.bg, in: Capsule())
                } else if model.isPinging {
                    Text("…").padding(.horizontal, 10).padding(.vertical, 4)
                } else {
                    Image(systemName: "speedometer").foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Theme.cardLow, in: Capsule())
                }
            }
            .font(.caption.weight(.bold))
        }
        .buttonStyle(.plain)
        .disabled(model.isPinging)
        .accessibilityLabel("Проверить пинг: \(server.displayName)")
    }
}

extension ServerConfig {
    /// "🇳🇱 Netherlands" -> flag "🇳🇱", name "Netherlands" (same split as the Android app).
    var flag: String? { Self.split(name).0 }
    var displayName: String { Self.split(name).1 }

    static func split(_ remarks: String) -> (String?, String) {
        let trimmed = remarks.trimmingCharacters(in: .whitespaces)
        guard let space = trimmed.firstIndex(of: " ") else { return (nil, trimmed) }
        let head = String(trimmed[..<space])
        guard !head.contains(where: { $0.isLetter || $0.isNumber }) else { return (nil, trimmed) }
        let rest = trimmed[space...].trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? (nil, trimmed) : (head, rest)
    }
}
