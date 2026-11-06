# AutoEject

Ứng dụng menu bar cho macOS: **gập máy là tự động eject toàn bộ ổ cứng/USB ngoài**.

## Tính năng
- Phát hiện gập nắp (đọc `AppleClamshellState`), kể cả khi cắm màn hình ngoài.
- Eject thêm khi máy sắp ngủ (phòng hờ).
- Chỉ eject ổ ngoài/tháo được; bỏ qua ổ trong, ổ hệ thống, ổ mạng.
- **Mount lại khi mở máy**: khi máy thức dậy hoặc mở nắp, đợi ~3s rồi tự mount các ổ ngoài đang cắm (thử lại ở ~5s và ~9s nếu USB chưa sẵn sàng). Tắt được trong menu.
- Báo lỗi bằng notification nếu ổ đang bận.
- Menu: bật/tắt tự động, "Eject tất cả ngay", khởi động cùng máy.

## Cài đặt nhanh (không cần build)
1. Tải `AutoEject.zip` ở mục **Releases**, giải nén, kéo `AutoEject.app` vào `/Applications`.
2. **Lần đầu mở**: bấm chuột phải vào app → **Open** → **Open** (app chưa được Apple công chứng nên macOS cảnh báo).
   Nếu vẫn bị chặn, chạy:
   ```bash
   xattr -dr com.apple.quarantine /Applications/AutoEject.app
   ```
3. Icon eject hiện trên menu bar. Bật "Khởi động cùng máy" trong menu nếu muốn.

Hỗ trợ macOS 13+, cả Apple Silicon lẫn Intel (universal).

## Build từ mã nguồn
Yêu cầu: macOS 13+, Xcode Command Line Tools (`swiftc`).

```bash
./build.sh --install     # build universal, chép vào /Applications, chạy
./build.sh --zip         # đóng gói build/AutoEject.zip để phát hành
```

Kiểm thử: `AutoEject --dry-run` (không eject thật), `AutoEject --remount-now` (mount lại ngay).

## Icon
`make_icon.swift` vẽ icon nút bấm 3D → `AppIcon.iconset` → `AppIcon.icns`:
```bash
swiftc -O make_icon.swift -o /tmp/make_icon && /tmp/make_icon AppIcon.iconset && iconutil -c icns AppIcon.iconset -o AppIcon.icns
```
