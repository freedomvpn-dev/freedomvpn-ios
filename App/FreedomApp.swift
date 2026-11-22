import SwiftUI

@main
struct FreedomApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.vpn)
                .tint(Theme.accent)
                .task { await model.start() }
                .onOpenURL { url in
                    // freedomvpn://install-sub?url=<subscription>  (button on the subscription page)
                    guard url.scheme == "freedomvpn", url.host == "install-sub",
                          let sub = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                            .queryItems?.first(where: { $0.name == "url" })?.value else { return }
                    Task { await model.importSubscription(url: sub) }
                }
        }
    }
}

/// Colors of the web cabinet (same as the Android app): champagne / navy, dark navy at night.
enum Theme {
    static let accent = Color("AccentColor")
    static let background = Color("Background")
    static let card = Color("Card")
    static let cardLow = Color("CardLow")
    static let accentSoft = Color("AccentSoft")

    static func delayColors(_ ms: Int, dark: Bool) -> (fg: Color, bg: Color) {
        switch ms {
        case ..<0: return (.red, Color.red.opacity(0.15))
        case ..<300: return (dark ? Color(red: 0.29, green: 0.87, blue: 0.5) : Color(red: 0.08, green: 0.5, blue: 0.24),
                             dark ? Color(red: 0.07, green: 0.21, blue: 0.14) : Color(red: 0.86, green: 0.95, blue: 0.89))
        case ..<800: return (dark ? Color(red: 0.98, green: 0.8, blue: 0.08) : Color(red: 0.54, green: 0.33, blue: 0.0),
                             dark ? Color(red: 0.23, green: 0.19, blue: 0.07) : Color(red: 0.98, green: 0.92, blue: 0.82))
        default: return (.red, Color.red.opacity(0.15))
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.needsWelcome {
                WelcomeView()
            } else {
                MainTabs()
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 90)
                    .transition(.opacity)
                    .task(id: toast) {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        model.toast = nil
                    }
            }
        }
        .animation(.easeInOut, value: model.toast)
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Главная", systemImage: "house.fill") }
            NavigationStack { AccountView() }
                .tabItem { Label("Аккаунт", systemImage: "person.fill") }
            NavigationStack { MoreView() }
                .tabItem { Label("Ещё", systemImage: "line.3.horizontal") }
        }
    }
}
