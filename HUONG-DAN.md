# CAMKEY — Hướng dẫn sử dụng

## 1. Bật server
- Double-click `F:\cong cu\vcam\run.bat`
- Cửa sổ đen hiện `CAMKEY server: http://127.0.0.1:8787` → đóng cửa sổ = tắt server
- Muốn tự chạy khi mở máy: `schtasks /Change /TN "CAMKEY Server" /ENABLE`

## 2. Trang quản trị
`https://<domain-hiện-tại>/keys` — mật khẩu `camkey2026`

- **Tạo key**: nhập Số lượng + Số ngày → Tạo key. Key dạng `XXXX-XXXX-XXXX-XXXX`
- **Copy**: copy key để gửi khách
- **Thu hồi**: key bị khóa, app đang dùng bị đá ra (key còn trong danh sách)
- **Xóa**: xóa vĩnh viễn khỏi database
- Cột **Số ngày** và **Ngày hết hạn**: hạn tính từ lúc tạo key
- **Gói**: dán `IPA URL` (bản iOS đã ký) → trang cài tự sinh plist, nút Cài hoạt động

## 3. Khách cài app
**Android:** tải `https://<domain>/files/CAMKEY.apk` → bật "Cài từ nguồn không rõ" → cài → mở app → nhập key.

**iOS:** cài qua Sideloadly (free 7 ngày) hoặc link OTA nếu đã ký enterprise:
1. Sideloadly → kéo `ObsCam-unsigned.ipa` → nhập Apple ID → Start
2. iPhone: `Cài đặt → Cài đặt chung → VPN & Quản lý thiết bị` → Tin cậy
3. `Cài đặt → Quyền riêng tư & Bảo mật → Chế độ nhà phát triển` → bật
4. Mở app → nhập key

## 4. Trong app
- Màn đầu: nhập key, hiện Tên máy / ID máy / Model
- Sau khi kích hoạt: góc phải hiện số ngày còn lại
- Nút ⓘ: Tên / ID / Model / Key / Hạn / Còn lại / Stream / Phiên bản
- Nút URL (Android) hoặc icon anten (iOS): đổi link stream OBS
- Mỗi lần mở app tự `check` → key sai/hết hạn/thu hồi thì bị đá về màn nhập key
- Key khóa cứng vào ID máy: máy khác nhập → "Key đã dùng trên thiết bị khác"

## 5. Nguồn video OBS
```
OBS → Stream: rtmp://<ip-pc>:1935/live  key: test
    → iPhone/Android đọc: http://<ip-pc>:8888/live/test/index.m3u8
```
Chạy `infra\run-mediamtx.bat` trên PC để có server RTMP/HLS.

## 6. Lưu ý
- Server chạy trên laptop: tắt máy là web/app không kết nối được.
- Link đổi khi tunnel restart; app tự đọc `server.txt` trên GitHub nên không cần cài lại.
- Muốn link cố định: mua domain + named tunnel.
