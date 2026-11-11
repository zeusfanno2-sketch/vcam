# CAMKEY

Panel cấp key + trang cài + server stream cho app camera OBS.

## Chạy
```powershell
cd projects\camkey
node server.js          # http://127.0.0.1:8787
```
Mật khẩu admin mặc định: `camkey2026` → đổi bằng biến môi trường `ADMIN_PASSWORD`.

## Cấp key
1. `/` → đăng nhập → nhập Số lượng + Số ngày → **Tạo key**.
2. Copy key gửi khách (dạng `XXXX-XXXX-XXXX-XXXX`).
3. Khách mở `/p/obs-cam` → nhập key + UDID → **Kích hoạt** → key bị khóa vào UDID đó.

## API
| Method | Endpoint | Việc |
|---|---|---|
| POST | `/api/v1/public/redeem` `{key, udid}` | Kích hoạt, gắn UDID, trả hạn |
| POST | `/api/v1/public/check` `{key, udid}` | App gọi mỗi lần mở → `{valid:true/false}` |
| GET | `/api/v1/public/package/obs-cam` | Thông tin gói + plist |
| POST | `/api/v1/auth/login` `{password}` | Lấy token admin |
| POST | `/api/v1/admin/keys` `{count,days,note}` | Tạo loạt key |
| GET | `/api/v1/admin/keys` | Danh sách + thống kê |
| DELETE | `/api/v1/admin/keys/:key` | Thu hồi |
| GET/POST | `/api/v1/admin/package` | Sửa tên/version/icon/plist |

## Luồng phát
```
OBS --RTMP--> MediaMTX --HLS--> iPhone (app ObsCam / tweak)
```
Chi tiết: `infra/OBS.md`

## iOS
- `ios/ObsCam` — app xem stream (SwiftUI + AVPlayer, LL-HLS, tự reconnect).
- `ios/ObsCamTweak` — tweak Theos hook `AVCaptureVideoDataOutput` để app đích nhận frame từ HLS.
- Build: `.github/workflows/ios.yml` (macOS runner) hoặc Xcode + Theos trên máy Mac.

## Key trong app
Trong app/tweak gọi `check` lúc mở; `valid=false` → chặn.
