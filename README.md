# Freedom VPN для iOS

Клиент Freedom VPN для iPhone и iPad — по образцу Android-приложения
([FreedomVPN-app/freedomvpn-android](https://github.com/FreedomVPN-app/freedomvpn-android)).

## Как устроено

- **Приложение (SwiftUI)**: вход через Telegram по API кабинета, импорт подписки аккаунта
  (или ссылки вручную), главный экран — круглая кнопка подключения, строка подписки, серверы с пингом;
  вкладки «Главная / Аккаунт / Ещё», «Пригласить друга» с QR-кодом.
- **Расширение PacketTunnel**: пакеты устройства → hev-socks5-tunnel → локальный SOCKS-вход Xray →
  сервер. Конфигурация сервера — полный Xray JSON из панели (правило «Freedom VPN JSON» по User-Agent).
- **Ядро**: [libXray](https://github.com/XTLS/libXray) (Xray-core, gomobile) и
  [hev-socks5-tunnel](https://github.com/heiher/hev-socks5-tunnel); собираются в CI скриптом
  `scripts/build-deps.sh` в `Frameworks/`. Гео-файлы RoscomVPN кладутся в `PacketTunnel/Geo/`.
- **HWID** при загрузке подписки — как в Android: `x-hwid` = 32 hex SHA-256 (секрет установки из
  Keychain + домен подписки), `x-device-os`, `x-ver-os`, `x-device-model`.

## Сборка

Проект описан в `project.yml` (XcodeGen). На Mac:

```bash
bash scripts/build-deps.sh   # Go, Python 3, Xcode
brew install xcodegen && xcodegen generate
open FreedomVPN.xcodeproj
```

CI (`.github/workflows/ios.yml`) собирает зависимости, гоняет тесты общего кода на симуляторе и
собирает приложение без подписи. Подпись и загрузка в TestFlight — после подключения аккаунта
Apple Developer (Team ID и ключ App Store Connect API в секретах репозитория).

## Пока не сделано

- Вход через Google и Яндекс (нужны Universal Links: файл apple-app-site-association на кабинете с Team ID).
- Покупка внутри приложения: продление открывает личный кабинет в Safari.
- Напоминания об окончании подписки, уведомления о скидках, промокоды.
