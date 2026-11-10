# Lumi для iOS 12 (jailbreak) — нативный клиент

Нативный клиент [Lumi.ai](https://lumi.site) для устройств на **iOS 12 с джейлбрейком**. В отличие от предыдущей версии это не `WKWebView`-оболочка: приложение работает напрямую с API Lumi, поэтому не зависит от современного JavaScript, который WebKit на iOS 12 не поддерживает.

> Неофициальный клиент. Не связан с Lumi AI. Используйте на свой риск.

## Статус 1.2.0 (beta)

**Проверено вручную и в CI:**

- публичный каталог `GET https://api.lumi.site/gallery/list?limit=50`;
- карточка персонажа `GET https://api.lumi.site/public/characters/{id}`;
- восстановление пароля `POST https://api.lumi.site/auth/forgot-password` (без капчи, отвечает `{"ok":true}`);
- нативный API отвечает и требует JWT: `POST /api/users/login/`, `GET /api/users/profile/`, `GET /api/chat/sessions/`, `POST /api/chat/`;
- Google OAuth: авторизационный URL с iOS client ID, redirect URI `com.googleusercontent.apps.…:/oauth2callback` и `audience=<web client ID>` принимается Google (нет `redirect_uri_mismatch`);
- эндпоинт `POST /api/users/social/google/` валидирует `id_token` (пустой → `token_required`, битый → `invalid_token`);
- сборка `.deb` и подпись `ldid` в GitHub Actions.

**Не проверено end-to-end (нет тестового аккаунта):**

- успешный вход с реальной парой email/пароль;
- успешный вход через Google (обмен кода на `id_token` и его приём бэкендом);
- создание сессии персонажа;
- отправка сообщения и получение ответа.

Эндпоинты и формат запросов восстановлены из официального Android-приложения (Expo/React Native bundle) и проверены на уровне валидации API. Если Lumi изменит API, клиент потребует обновления.

## Возможности

- Нативный UIKit-интерфейс, тёмная тема, iPhone и iPad.
- Публичный каталог персонажей без входа.
- Карточка персонажа: аватар, описание, теги, первое сообщение.
- Вход и регистрация по email/паролю через нативный API Lumi (JWT `access`/`refresh`).
- Вход через Google: OAuth 2.0 Authorization Code + PKCE в `SFAuthenticationSession`, затем обмен `id_token` на JWT Lumi.
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
| Вход через Google | `POST /api/users/social/google/` `{provider:"google",id_token}` | `https://lumi-api.nexoragroup.dev` |
| Обновление токена | `POST /api/users/token/refresh/` `{refresh}` | `https://lumi-api.nexoragroup.dev` |
| Профиль | `GET /api/users/profile/` | `https://lumi-api.nexoragroup.dev` |
| Список чатов | `GET /api/chat/sessions/?pinned=false` | `https://lumi-api.nexoragroup.dev` |
| История | `GET /api/chat/sessions/{id}/messages/` | `https://lumi-api.nexoragroup.dev` |
| Отправка | `POST /api/chat/` `{message,session_id}` | `https://lumi-api.nexoragroup.dev` |
| Каталог | `GET /gallery/list?limit=50` | `https://api.lumi.site` |
| Персонаж | `GET /public/characters/{id}` | `https://api.lumi.site` |
| Сброс пароля | `POST /auth/forgot-password` `{email}` | `https://api.lumi.site` |

Авторизованные запросы используют `Authorization: Bearer <access>`. Токены хранятся в `NSUserDefaults` (не в Keychain — осознанное упрощение MVP; для продакшена стоит перенести в Keychain).

### Вход через Google

Приложение повторяет схему официального Android-клиента и не тянет внешний GoogleSignIn SDK:

1. `SFAuthenticationSession` открывает `https://accounts.google.com/o/oauth2/v2/auth` с iOS client ID, `response_type=code`, `scope=openid email profile`, PKCE (`S256`) и `audience=<web client ID>`.
2. Google возвращает код по схеме `com.googleusercontent.apps.1032314291008-enums0tts15iutfse3tl0j2jdr8npi75:/oauth2callback`; схема зарегистрирована в `Info.plist` (`CFBundleURLTypes`).
3. Код меняется на токены через `https://oauth2.googleapis.com/token` с тем же `audience`, чтобы `id_token` имел аудиторию веб-клиента Lumi.
4. `id_token` отправляется в `POST /api/users/social/google/`; полученные `access`/`refresh` сохраняются как при обычном входе.

Параметр `state` проверяется, отмена окна Google обрабатывается без ошибки. При ошибке бэкенда текст показывается на экране входа.

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
     dpkg -i com.w3rn1ght.lumi_1.2.0_iphoneos-arm.deb
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

Готовый файл: `packages/com.w3rn1ght.lumi_1.2.0_iphoneos-arm.deb`.

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
│   ├── LumiAuthViewController      # вход/регистрация/Google/сброс пароля
│   ├── LumiGoogleAuth.{h,m}        # Google OAuth 2.0 + PKCE (SFAuthenticationSession)
│   ├── LumiProfileViewController   # профиль
│   └── LumiImageLoader.{h,m}
├── layout/DEBIAN/                  # postinst / postrm (uicache)
└── .github/workflows/build.yml
```

## Ограничения

- **Бета:** успешный вход (email/пароль и Google) и чат не проверены без тестового аккаунта.
- **Google OAuth без SDK:** используется `SFAuthenticationSession` и PKCE. Если бэкенд Lumi принимает только `id_token` с аудиторией iOS-клиента (а не веб-клиента), вход через Google вернёт ошибку — параметр `audience` можно поменять в `Sources/LumiGoogleAuth.m`.
- **WebP:** аватары Lumi отдаются в WebP, а iOS 12 не умеет его декодировать. Сейчас показывается градиентный placeholder. Исправление — встроить libwebp или использовать прокси-конвертацию.
- **Чат без WebSocket:** приложение отправляет `POST /api/chat/` и опрашивает историю. Если сервер стримит ответ только по WebSocket, ответ может не появиться.
- **Нет входа через Apple и Discord.**
- **Нет загрузки изображений и голоса.**
- **Токены в NSUserDefaults**, а не в Keychain.
- API может быть недоступен из некоторых сетей: `lumi-api.nexoragroup.dev` использует Cloudflare.

## Дисклеймер

Проект предоставляется «как есть», без гарантий. Все права на Lumi, контент и товарные знаки принадлежат их владельцам. Автор не несёт ответственности за блокировки аккаунта или нарушения условий использования сервиса.
