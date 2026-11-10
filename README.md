# Lumi для iOS 12 (jailbreak) — нативный клиент

Нативный клиент [Lumi.ai](https://lumi.site) для устройств на **iOS 12 с джейлбрейком**. В отличие от предыдущей версии это не `WKWebView`-оболочка: приложение работает напрямую с API Lumi, поэтому не зависит от современного JavaScript, который WebKit на iOS 12 не поддерживает.

> Неофициальный клиент. Не связан с Lumi AI. Используйте на свой риск.

## Статус 1.1.0 (beta)

**Проверено вручную и в CI:**

- публичный каталог `GET https://api.lumi.site/gallery/list?limit=50`;
- карточка персонажа `GET https://api.lumi.site/public/characters/{id}`;
- восстановление пароля `POST https://api.lumi.site/auth/forgot-password` (без капчи, отвечает `{"ok":true}`);
- нативный API отвечает и требует JWT: `POST /api/users/login/`, `GET /api/users/profile/`, `GET /api/chat/sessions/`, `POST /api/chat/`;
- сборка `.deb` и подпись `ldid` в GitHub Actions.

**Не проверено end-to-end (нет тестового аккаунта):**

- успешный вход с реальной парой email/пароль;
- создание сессии персонажа;
- отправка сообщения и получение ответа.

Эндпоинты и формат запросов восстановлены из официального Android-приложения (Expo/React Native bundle) и проверены на уровне валидации API. Если Lumi изменит API, клиент потребует обновления.

## Возможности

- Нативный UIKit-интерфейс, тёмная тема, iPhone и iPad.
- Публичный каталог персонажей без входа.
- Карточка персонажа: аватар, описание, теги, первое сообщение.
- Вход и регистрация по email/паролю через нативный API Lumi (JWT `access`/`refresh`).
- Автоматическое обновление access-токена.
- Восстановление пароля по email (нативный запрос, без капчи).
- Список чатов, история сообщений, отправка сообщения.
- Выход из аккаунта, очистка токенов.
- Никакого `WKWebView`, JavaScript и капчи в основном потоке.

## Экраны

1. **Персонажи** — витрина Lumi, доступна без входа.
2. **Персонаж** — описание и кнопка «Начать чат».
3. **Чаты** — список сессий; без входа показывает кнопку «Войти».
4. **Чат** — история и отправка сообщений.
5. **Профиль** — вход/выход, восстановление пароля, информация о приложении.

## API

| Назначение | Метод и путь | База |
|---|---|---|
| Вход | `POST /api/users/login/` `{email,password}` | `https://lumi-api.nexoragroup.dev` |
| Регистрация | `POST /api/users/register/` `{email,password}` | `https://lumi-api.nexoragroup.dev` |
| Обновление токена | `POST /api/users/token/refresh/` `{refresh}` | `https://lumi-api.nexoragroup.dev` |
| Профиль | `GET /api/users/profile/` | `https://lumi-api.nexoragroup.dev` |
| Список чатов | `GET /api/chat/sessions/?pinned=false` | `https://lumi-api.nexoragroup.dev` |
| История | `GET /api/chat/sessions/{id}/messages/` | `https://lumi-api.nexoragroup.dev` |
| Отправка | `POST /api/chat/` `{message,session_id}` | `https://lumi-api.nexoragroup.dev` |
| Каталог | `GET /gallery/list?limit=50` | `https://api.lumi.site` |
| Персонаж | `GET /public/characters/{id}` | `https://api.lumi.site` |
| Сброс пароля | `POST /auth/forgot-password` `{email}` | `https://api.lumi.site` |

Авторизованные запросы используют `Authorization: Bearer <access>`. Токены хранятся в `NSUserDefaults` (не в Keychain — осознанное упрощение MVP; для продакшена стоит перенести в Keychain).

## Требования

- Джейлбрейк на iOS **12.0–12.5.7** (unc0ver, checkra1n, Chimera и т.п.).
- Rootful-бутстрап (`iphoneos-arm`), arm64.
- `uicache` (UIKit Tools / бутстрап).

## Установка

1. Скачайте `.deb` из **Actions** (артефакт `lumi-deb`) или из **Releases**.
2. Установите:
   - через **Sileo / Zebra / Cydia** — «Install from file»;
   - через **Filza** — тап по `.deb` → Install;
   - по SSH:
     ```sh
     dpkg -i com.w3rn1ght.lumi_1.1.0_iphoneos-arm.deb
     uicache -p /Applications/Lumi.app
     ```
3. Если иконка не появилась — `uicache` или respring.

Удаление: `dpkg -r com.w3rn1ght.lumi`.

## Сборка

### GitHub Actions

Workflow `.github/workflows/build.yml` собирает пакет на `macos-15` с Xcode 16.2, Theos и SDK iPhoneOS 12.4:

- push в `main` → артефакт `lumi-deb`;
- push тега `v*` → GitHub Release с `.deb`.

Репозиторий: `w3rn1ght/lumi-ios` (private).

### Локально на macOS

```sh
brew install ldid xz
export THEOS=$HOME/theos
git clone --recursive https://github.com/theos/theos.git "$THEOS"

git clone --depth=1 --filter=blob:none --sparse https://github.com/theos/sdks.git /tmp/theos-sdks
cd /tmp/theos-sdks && git sparse-checkout set iPhoneOS12.4.sdk
mkdir -p "$THEOS/sdks" && cp -R iPhoneOS12.4.sdk "$THEOS/sdks/"

cd /path/to/lumi-ios
make package FINALPACKAGE=1
```

Готовый файл: `packages/com.w3rn1ght.lumi_1.1.0_iphoneos-arm.deb`.

## Структура

```
.
├── Makefile
├── control
├── Resources/                      # Info.plist, иконки, launch images, placeholder
├── Sources/
│   ├── LumiAPIClient.{h,m}         # HTTP-клиент, JWT, публичный API
│   ├── LumiMainViewController      # таб-бар
│   ├── LumiCatalogViewController   # каталог (без входа)
│   ├── LumiCharacterViewController # карточка персонажа
│   ├── LumiChatsViewController     # список чатов
│   ├── LumiChatViewController      # чат
│   ├── LumiAuthViewController      # вход/регистрация/сброс пароля
│   ├── LumiProfileViewController   # профиль
│   └── LumiImageLoader.{h,m}
├── layout/DEBIAN/                  # postinst / postrm (uicache)
└── .github/workflows/build.yml
```

## Ограничения

- **Бета:** успешный вход и чат не проверены без тестового аккаунта.
- **WebP:** аватары Lumi отдаются в WebP, а iOS 12 не умеет его декодировать. Сейчас показывается градиентный placeholder. Исправление — встроить libwebp или использовать прокси-конвертацию.
- **Чат без WebSocket:** приложение отправляет `POST /api/chat/` и опрашивает историю. Если сервер стримит ответ только по WebSocket, ответ может не появиться.
- **Нет OAuth:** только email/пароль; Google/Discord/Apple не реализованы.
- **Нет загрузки изображений и голоса.**
- **Токены в NSUserDefaults**, а не в Keychain.
- API может быть недоступен из некоторых сетей: `lumi-api.nexoragroup.dev` использует Cloudflare.

## Дисклеймер

Проект предоставляется «как есть», без гарантий. Все права на Lumi, контент и товарные знаки принадлежат их владельцам. Автор не несёт ответственности за блокировки аккаунта или нарушения условий использования сервиса.
