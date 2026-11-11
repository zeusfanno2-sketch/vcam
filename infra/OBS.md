# OBS → MediaMTX → iPhone

## 1. Bật server
Chạy `infra\run-mediamtx.bat`. Mở port: RTMP 1935, HLS 8888.

## 2. OBS
Settings → Stream → Custom:

- Server: `rtmp://<IP-PC>:1935/live`
- Stream Key: `test`

Output: encoder x264, keyframe interval **1s** (bắt buộc để HLS mượt), 1080x1920, 30fps, 2500–4000 kbps.
Audio: AAC 128k.

## 3. URL phát
| Kiểu | URL |
|---|---|
| HLS (app/tweak) | `http://<IP-PC>:8888/live/test/index.m3u8` |
| WebRTC (độ trễ thấp) | `http://<IP-PC>:8888/live/test` |

## 4. Kiểm tra
```powershell
ffprobe -v error -show_entries stream=codec_name,width,height,avg_frame_rate `
  "http://127.0.0.1:8888/live/test/index.m3u8"
```

Firewall: mở inbound TCP 1935, 8888, 8189 (WebRTC) cho dải LAN.
