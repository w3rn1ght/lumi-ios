# Lumi для iOS 12 (jailbreak)

Неофициальный нативный клиент [lumi.site](https://lumi.site) для устройств на **iOS 12 с джейлбрейком**. Приложение представляет собой аккуратную нативную оболочку на `WKWebView` с сохранением сессии, загрузкой фото/файлов, pull-to-refresh, обработкой офлайна и меню.

> Проект не связан с Lumi AI. Это сторонний клиент, использующий публичный сайт lumi.site.

## Возможности

- Полноценный веб-клиент Lumi (вход, чаты, персонажи, истории, генерация аватаров).
- Постоянная сессия: cookies и localStorage сохраняются между запусками.
- Нативный `Safari`-User-Agent — сайт отдаёт полноценную версию, а не упрощённую.
- Pull-to-refresh и тонкий индикатор загрузки.
- Экран ошибки сети с кнопкой «Повторить» и «Открыть в Safari».
- Загрузка изображений из галереи и файлов через `UIDocumentPicker`.
- Нативные диалоги `alert` / `confirm` / `prompt`.
- Внешние ссылки открываются в Safari, OAuth-редиректы остаются внутри приложения.
- Свайп от левого края — назад (системный жест `WKWebView`).
- Меню: обновить, на главную, открыть в Safari, поделиться, очистить cookies/кэш, о приложении.
- Тёмная тема, safe-area для iPhone X, поддержка iPhone и iPad.

## Меню

Меню открывается одним из способов:

- **три пальца** — тап по экрану;
- **два пальца** — свайп вниз;
- **встряхнуть устройство**.

## Требования

- Джейлбрейк на iOS **12.0–12.5.7** (unc0ver, checkra1n, Chimera и т.п.).
- Rootful-бутстрап (`iphoneos-arm`), архитектура **arm64**.
- Установленный `uicache` (входит в UIKit Tools / большинство бутстрапов).

## Установка

1. Скачайте `.deb` из вкладки **Actions** (артефакт `lumi-deb`) или из **Releases**.
2. Установите одним из способов:
   - через **Sileo / Zebra / Cydia** — «Install from file»;
   - через **Filza** — тап по `.deb` → Install;
   - по SSH:
     ```sh
     dpkg -i com.w3rn1ght.lumi_1.0.0_iphoneos-arm.deb
     uicache -p /Applications/Lumi.app
     ```
3. Если иконка не появилась — выполните `uicache` или сделайте respring.

Удаление: `dpkg -r com.w3rn1ght.lumi` (или через пакетный менеджер).

## Сборка

### Автоматически на GitHub

Workflow `.github/workflows/build.yml` собирает пакет на `macos-15` с Xcode 16.2, Theos и официальным SDK iPhoneOS 12.4:

- каждый push в `main` → артефакт `lumi-deb`;
- push тега `v*` → дополнительно создаётся GitHub Release с `.deb`.

Репозиторий: `w3rn1ght/lumi-ios` (private).

### Локально на macOS

Нужны Xcode, Homebrew, Theos и `ldid`:

```sh
brew install ldid xz
export THEOS=$HOME/theos
git clone --recursive https://github.com/theos/theos.git "$THEOS"

# iOS 12.4 SDK
git clone --depth=1 --filter=blob:none --sparse https://github.com/theos/sdks.git /tmp/theos-sdks
cd /tmp/theos-sdks && git sparse-checkout set iPhoneOS12.4.sdk
mkdir -p "$THEOS/sdks" && cp -R iPhoneOS12.4.sdk "$THEOS/sdks/"

cd /path/to/lumi-ios
make package FINALPACKAGE=1
```

Готовый файл появится в `packages/`.

## Структура проекта

```
.
├── Makefile                     # Theos application target, iOS 12.4 SDK, arm64
├── control                      # метаданные Debian-пакета
├── Resources/                   # Info.plist, иконки, LaunchLogo
├── Support/LaunchScreen.storyboard
├── Sources/
│   ├── main.m
│   ├── LumiApplication.{h,m}    # обработка shake
│   ├── LumiAppDelegate.{h,m}
│   └── LumiWebViewController.{h,m}
├── layout/DEBIAN/               # postinst / postrm (uicache)
└── .github/workflows/build.yml  # CI-сборка .deb
```

## Ограничения

- Это оболочка вокруг сайта, а не реверс-инжиниринг закрытого API Lumi. Если сайт изменится, интерфейс изменится вместе с ним.
- Push-уведомления не поддерживаются (для них нужен APNs-сертификат и нативная интеграция).
- `getUserMedia` / запись голоса в `WKWebView` на iOS 12 ограничены возможностями WebKit.
- Приложение не подписано сертификатом Apple — только ad-hoc подпись `ldid`, достаточная для джейлбрейка.

## Дисклеймер

Проект предоставляется «как есть», без гарантий. Используйте на свой риск. Все права на Lumi, контент и товарные знаки принадлежат их владельцам. Автор не несёт ответственности за блокировки аккаунта или нарушения условий использования сервиса.
