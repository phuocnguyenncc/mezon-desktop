# Auto-update — cơ chế tự cập nhật (kiểu Zed)

App tự kiểm tra version mới, tải về, verify checksum, cài đè tại chỗ, rồi người dùng
bấm **Restart to update** là chạy ngay bản mới — không cần tải installer thủ công.

## Kiến trúc

| Thành phần | Vai trò |
|---|---|
| `crates/mezon-updater` | Engine thuần tokio: fetch manifest, so sánh semver, download + verify sha512, install per-platform |
| `mezon_store::AutoUpdateStore` | Entity GPUI global: poll mỗi 60 phút (chỉ release build), giữ status cho UI, gọi `cx.set_restart_path` |
| Settings screen (dưới nút Quit) | Hiện trạng thái: Check for Updates / Downloading x% / Restart to update |
| Tray → "Check for Updates" | Mở app + trigger check thủ công |
| GPUI `cx.restart()` | Đợi process thoát rồi tự mở lại app (macOS `open`, Linux exec, Windows `Start-Process`) |

Feed URL lấy từ `AppConfig.update_url` — bake lúc build qua env `NX_UPDATE_URL`
(CI đang set `https://cdn.mezon.ai/release/`).

## File trên feed (per version)

Tên file `latest-native-*` để **không đụng** feed của bản Electron trong cùng thư mục:

| Platform | Manifest | Artifact |
|---|---|---|
| macOS (universal) | `latest-native-mac.yml` | `Mezon-<v>-universal.dmg` |
| Linux x86_64 | `latest-native-linux-x86_64.yml` | `mezon-<v>-linux-x86_64.tar.gz` (chứa `mezon` + `mezon.png` + `mezon.desktop`) + `mezon_<v>-1_amd64.deb` (cho bản cài .deb) |
| Windows x64 | `latest-native-windows-x86_64.yml` | `mezon-<v>-windows-x86_64.zip` (chứa `mezon.exe`) |

Kèm theo (không bắt buộc cho updater): `install-linux.sh` — installer cho kênh
tar.gz trên Linux.

Manifest dạng electron-builder yml:

```yaml
version: 0.2.0
path: Mezon-0.2.0-universal.dmg
sha512: <base64 của SHA-512>
size: 123456789
releaseDate: '2026-07-20T10:00:00.000Z'
```

Manifest Linux có thêm 2 field tùy chọn cho bản cài `.deb` (client cũ bỏ qua):

```yaml
deb: mezon_0.2.0-1_amd64.deb
debSha512: <base64 của SHA-512>
```

## Hành vi từng platform

- **macOS** — mount DMG bằng `hdiutil`, `rsync -a --delete` đè lên `.app` đang chạy
  (giống Zed). Yêu cầu app chạy từ `.app` bundle (cài trong `/Applications`).
  Bản cài **đầu tiên** phải là DMG đã ký Developer ID + notarize (`just dist`);
  các lần auto-update sau không dính Gatekeeper vì file do chính app ghi (không có
  quarantine attribute).
  **Quan trọng:** DMG đưa lên feed cũng phải là bản ký Developer ID + notarize.
  Keychain (session đăng nhập) và quyền TCC (mic/camera/screen) gắn với chữ ký
  code — update user sang bản ký ad-hoc sẽ làm mất session và bị hỏi lại toàn bộ
  quyền.
- **Linux** — hai kênh cài đặt:
  - **tar.gz** — cài bằng `scripts/install-linux.sh`: binary vào
    `~/.local/share/mezon/mezon`, symlink `~/.local/bin/mezon`, desktop entry +
    icon vào `~/.local/share`. Updater thay binary bằng `rename` (atomic, thư mục
    user ghi được), hoàn toàn im lặng.
  - **.deb** — cài vào `/usr/bin` (root-owned) nên cần quyền root để update:
    app tải `.deb` từ feed (field `deb`/`debSha512` trong manifest), verify
    sha512 rồi chạy `pkexec dpkg -i` — polkit hiện hộp thoại nhập mật khẩu.
    Auto-poll nền **không** tự bật hộp thoại: khi có bản mới nó chỉ hiện trạng
    thái "Có bản cập nhật — bấm để cài đặt" (title bar + settings); bấm vào mới
    tải + cài (đây là lúc polkit hỏi mật khẩu). Check thủ công thì cài luôn.
    Nếu manifest cũ chưa có field `deb` (hoặc thiếu `pkexec`), app báo lỗi ngay
    từ trước khi tải, hướng dẫn update qua package manager.
- **Windows** — giải nén zip (dùng `tar.exe` có sẵn của Windows 10+), rename
  `mezon.exe` đang chạy thành `mezon-old-<pid>.exe` (Windows cho phép rename file
  đang chạy), đặt exe mới vào chỗ cũ. File `mezon-old-*.exe` được dọn ở lần khởi
  động sau. Yêu cầu `mezon.exe` nằm trong thư mục user ghi được.
  Cài lần đầu cho end user: **`Mezon-Setup-<v>.exe`** (Inno Setup, CI build kèm
  trong release) — double-click là cài vào `%LOCALAPPDATA%\Programs\Mezon`,
  có Start Menu + mục trong Settings→Apps + uninstaller, không cần quyền admin.
  Kênh phụ cho dev: `scripts/install-windows.ps1` (tải + verify sha512 + cài +
  Unblock-File). Zip trong feed chỉ dành cho updater.
  Lưu ý SmartScreen: khi chưa ký Authenticode, lần chạy setup đầu tiên user
  thấy "Windows protected your PC" → bấm **More info → Run anyway** (chỉ lần
  đầu; các lần auto-update sau không dính vì file do chính app ghi, không có
  Mark-of-the-Web). CI đã wire sẵn ký Authenticode — thêm 2 secrets là tự bật
  (ký cả `mezon.exe` trong zip lẫn `Mezon-Setup-<v>.exe`):

  | Secret | Nội dung |
  |---|---|
  | `WINDOWS_CERT_PFX` | file `.pfx` chứa cert code-signing (OV/EV), encode base64 |
  | `WINDOWS_CERT_PASSWORD` | mật khẩu của file .pfx |

  Chọn cert: **EV cert hoặc Azure Trusted Signing** có SmartScreen reputation
  gần như ngay lập tức; **OV cert** rẻ hơn nhưng vẫn bị SmartScreen cảnh báo
  thêm một thời gian đầu cho tới khi tích đủ reputation. Nếu công ty chọn Azure
  Trusted Signing (không có file .pfx, ký qua cloud) thì bước CI cần đổi sang
  `azuresigntool` — chưa wire sẵn.

## Các bước phát hành

### 0. Bump version

Sửa `version = "x.y.z"` trong `Cargo.toml` (workspace root). Client chỉ update khi
version trên feed **lớn hơn** (semver) version đang chạy.

### 1. Build artifact + manifest

```bash
# macOS (trên máy Mac có cert):
just dist                                                # ký + notarize -> target/dist/Mezon.dmg
bash scripts/make-update-feed.sh macos target/dist/Mezon.dmg

# Linux:
cargo build --release -p mezon-app --locked
bash scripts/make-update-feed.sh linux

# Windows (chạy trong Git Bash):
cargo build --release -p mezon-app --locked
bash scripts/make-update-feed.sh windows
```

Kết quả nằm trong `target/update-feed/` (artifact + manifest tương ứng).

### 2. Upload

**Option A — CDN `cdn.mezon.ai` (mặc định của build hiện tại):**

Upload vào đúng thư mục mà `NX_UPDATE_URL` trỏ tới (`https://cdn.mezon.ai/release/`):

1. Upload **artifacts trước**: `.dmg`, `.tar.gz`, `.zip`.
2. Upload **3 file `latest-native-*.yml` sau cùng** — manifest là "công tắc" bật
   version mới; upload sau để không có client nào thấy manifest mới mà artifact
   chưa sẵn sàng.

**Option B — GitHub Releases:**

1. Push tag `v<version>` → workflow `.github/workflows/release.yml` tự build cả 3
   platform và tạo **draft release** đính kèm đủ artifacts + manifests.
2. Review rồi **publish** release.
3. Build app với
   `NX_UPDATE_URL=https://github.com/<org>/mezon-desktop/releases/latest/download/`
   — đường dẫn `releases/latest/download/<file>` luôn redirect tới release mới
   nhất, không dính rate-limit API.

**Lưu ý macOS trên CI (bắt buộc đọc trước khi publish):** khi chưa cấu hình
secrets ký code, job macOS ký **ad-hoc** — chỉ dùng để test pipeline. Mỗi bản
ad-hoc có identity chữ ký khác nhau, nên update production bằng bản ad-hoc sẽ làm
user **bị hỏi mật khẩu keychain sau mỗi lần update** (mất session) và bị hỏi lại
quyền mic/camera/screen (keychain/TCC gắn với chữ ký code).

**Cách chuẩn — CI tự ký Developer ID + notarize:** thêm secrets vào repo
(Settings → Secrets and variables → Actions):

| Secret | Nội dung |
|---|---|
| `MACOS_CERT_P12` | file `.p12` chứa cert "Developer ID Application" (export từ Keychain Access), encode base64: `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERT_PASSWORD` | mật khẩu của file .p12 |
| `APPLE_API_KEY_P8` | (tùy chọn, để notarize) nội dung file API key `.p8` của App Store Connect |
| `APPLE_API_KEY_ID` | Key ID của API key |
| `APPLE_API_ISSUER` | Issuer ID của API key |

Có `MACOS_CERT_P12` → CI ký Developer ID (hardened runtime + entitlements
`packaging/macos/entitlements.plist`); có thêm bộ `APPLE_API_*` → CI notarize +
staple DMG. Khi đó mọi bản build có cùng identity → **user không bao giờ bị hỏi
keychain khi update**, và DMG cài lần đầu qua browser cũng không bị Gatekeeper
chặn (nếu đã notarize).

Nếu chưa có secrets, quy trình publish thủ công thay thế:

1. Trên máy Mac có cert: `just dist` (ký + notarize) rồi
   `bash scripts/make-update-feed.sh macos target/dist/Mezon.dmg`.
2. Trong **draft release** CI vừa tạo: thay `Mezon-<v>-universal.dmg` và
   `latest-native-mac.yml` bằng 2 file vừa build ở bước 1.
3. Publish release.

### Cài đặt lần đầu trên Linux (kênh tar.gz)

```bash
bash scripts/install-linux.sh
# hoặc từ GitHub Releases:
MEZON_UPDATE_URL=https://github.com/<org>/mezon-desktop/releases/latest/download/ bash install-linux.sh
```

Script tải manifest + tar.gz từ feed, verify sha512, cài vào `~/.local` và tạo
menu entry. Từ đó trở đi app tự update. (`install-linux.sh` cũng được CI đính kèm
vào mỗi GitHub Release.)

### 3. Client nhận update

Trong tối đa 60 phút (hoặc ngay khi bấm Check for Updates), client sẽ:
Checking → Downloading x% → Installing → **Restart to update (vX.Y.Z)**.
Bấm nút là app khởi động lại vào bản mới. Không bấm thì lần mở app sau cũng là
bản mới (macOS/Linux đã thay bits tại chỗ; Windows đã swap exe).

## Test local (không cần CDN)

Chỉ hoạt động ở **debug build** + env opt-in (release build bắt buộc https + host
allowlist):

```bash
mkdir -p /tmp/feed && cd /tmp/feed
# copy artifact + manifest (make-update-feed.sh) vào đây, sửa version trong yml lớn hơn bản đang chạy
python3 -m http.server 8000

# build app trỏ vào feed local:
NX_UPDATE_URL=http://127.0.0.1:8000/ cargo build
MEZON_ALLOW_INSECURE_UPDATE_URL=1 ./target/debug/mezon
```

## Công tắc

- `MEZON_DISABLE_AUTO_UPDATE=1` (runtime) — tắt hẳn check/poll.
- Auto-poll chỉ bật ở release build **cài đặt thật** (binary không nằm trong thư mục
  `target/` của cargo — tránh build dev bị update đè). Check thủ công luôn dùng được.

## Bảo mật

- Chỉ chấp nhận `https` + host trong allowlist (`mezon.ai`, `cdn.mezon.ai`,
  `cdn.komu.vn`, `github.com`, `objects.githubusercontent.com`) hoặc đúng host của
  `NX_UPDATE_URL` đã bake lúc build.
- Artifact được stream-hash SHA-512 và so với `sha512` trong manifest trước khi cài;
  sai checksum là hủy, không cài.
- Ngoại lệ `http` chỉ tồn tại ở debug build + `MEZON_ALLOW_INSECURE_UPDATE_URL` +
  host loopback.
