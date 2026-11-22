import CoreImage.CIFilterBuiltins
import SwiftUI

/// First start: sign in through Telegram or paste a subscription link.
struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showLink = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "globe.europe.africa.fill")
                    .font(.system(size: 72)).foregroundStyle(Theme.accent)
                    .padding(.top, 48)
                Text("Freedom VPN").font(.largeTitle.weight(.heavy))
                Text("Регистрация за минуту и 7 дней бесплатно")
                    .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                LoginBlock()
                Button("У меня уже есть ссылка на подписку") { showLink = true }
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 8)
            }
            .padding(24)
        }
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: $showLink) { AddLinkSheet() }
    }
}

/// Telegram sign-in (Google and Yandex need Universal Links on the cabinet: next step).
struct LoginBlock: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            switch model.loginState {
            case .waitingTelegram(let link):
                ProgressView()
                Text("Подтвердите вход в Telegram и вернитесь сюда")
                    .multilineTextAlignment(.center)
                Link("Открыть Telegram ещё раз", destination: link)
                Button("Отмена") { model.cancelLogin() }
            case .working:
                ProgressView()
            case .failed(let message):
                Text(message).foregroundStyle(.red).multilineTextAlignment(.center)
                telegramButton
            case .idle:
                telegramButton
                Text("Пользовались ботом @\(FreedomConfig.botUsername)? Выберите Telegram — подписка подтянется.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(.top, 16)
    }

    private var telegramButton: some View {
        Button {
            Task { await model.startTelegramLogin() }
        } label: {
            Label("Продолжить с Telegram", systemImage: "paperplane.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
    }
}

struct AddLinkSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…", text: $link, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("Вставить из буфера обмена") { link = UIPasteboard.general.string ?? link }
                } footer: {
                    Text("Ссылка подписки Freedom VPN — на странице подписки или в личном кабинете.")
                }
            }
            .navigationTitle("Ссылка на подписку")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        Task {
                            await model.importSubscription(url: link)
                            dismiss()
                        }
                    }
                    .disabled(!link.trimmingCharacters(in: .whitespaces).hasPrefix("http"))
                }
            }
        }
    }
}

/// Account: subscription status, trial, renewal (in the web cabinet), sign-out.
struct AccountView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            if !model.isLoggedIn {
                Section { LoginBlock() }
            } else {
                Section("Подписка") {
                    if let sub = model.account, sub.isActive == true {
                        LabeledContent("Тариф", value: sub.tariffName ?? (sub.isTrial == true ? "Пробный период" : "—"))
                        LabeledContent("Осталось", value: sub.timeLeftDisplay ?? "\(sub.daysLeft ?? 0) дн.")
                        if let limit = sub.deviceLimit, limit > 0 {
                            LabeledContent("Устройств", value: "до \(limit)")
                        }
                    } else {
                        Text("Активной подписки нет")
                        if model.trial?.isAvailable == true, model.trial?.requiresPayment != true {
                            Button("Попробовать бесплатно — \(model.trial?.durationDays ?? 7) дн.") {
                                Task { await model.activateTrial() }
                            }
                        }
                    }
                    // Payments open the web cabinet (Platega, CryptoBot): not inside the app.
                    Link(model.account?.isActive == true ? "Продлить подписку" : "Купить подписку",
                         destination: FreedomConfig.cabinetURL)
                }
                Section {
                    Button("Обновить") { Task { await model.loadAccount() } }
                    Button("Выйти", role: .destructive) { model.logout() }
                }
            }
        }
        .navigationTitle("Аккаунт")
        .refreshable { await model.loadAccount() }
    }
}

/// Invite a friend: QR code of the referral link, share, copy.
struct InviteView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var link: String?
    @State private var counts = (0, 0)
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let link {
                    Text("Покажите QR-код другу или отправьте ему ссылку. Кто зарегистрируется по ней, станет вашим приглашённым.")
                        .multilineTextAlignment(.center)
                    if let image = Self.qr(link) {
                        Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                            .padding(16).background(Color.white, in: RoundedRectangle(cornerRadius: 24))
                            .frame(width: 280, height: 280)
                            .accessibilityLabel("QR-код вашей ссылки-приглашения")
                    }
                    Text(link).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                    ShareLink(item: URL(string: link)!, message: Text("Подключайся к Freedom VPN — быстрый и стабильный VPN")) {
                        Label("Поделиться ссылкой", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        UIPasteboard.general.string = link
                        model.toast = "Ссылка скопирована"
                    } label: {
                        Label("Скопировать ссылку", systemImage: "doc.on.doc").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    Text("Приглашено: \(counts.0) · с подпиской: \(counts.1)").font(.subheadline.weight(.bold))
                } else if failed {
                    Text("Не удалось загрузить ссылку-приглашение. Проверьте интернет и попробуйте ещё раз.")
                        .multilineTextAlignment(.center)
                    Button("Повторить") { Task { await load() } }
                } else {
                    ProgressView().padding(.top, 48)
                }
            }
            .padding(24)
        }
        .navigationTitle("Пригласить друга")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        .task { await load() }
    }

    private func load() async {
        failed = false
        do {
            let info = try await model.referralLink()
            link = info.link
            counts = (info.total, info.active)
        } catch {
            failed = true
        }
    }

    static func qr(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// More: subscription link, cabinet, support, about.
struct MoreView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showLink = false

    var body: some View {
        List {
            Section {
                Button("Добавить ссылку на подписку") { showLink = true }
                Link("Личный кабинет", destination: FreedomConfig.cabinetURL)
                Link("Поддержка", destination: FreedomConfig.supportURL)
                Link("Инструкция для iPhone", destination: URL(string: "https://cabinet.topfreedomhub.com/ios/")!)
            }
            Section {
                LabeledContent("Версия", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
            }
        }
        .navigationTitle("Ещё")
        .sheet(isPresented: $showLink) { AddLinkSheet() }
    }
}
