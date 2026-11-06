# AutoEject

Ứng dụng menu bar cho macOS: **gập máy là tự động eject toàn bộ ổ cứng/USB ngoài**.

## Tính năng
- Phát hiện gập nắp (đọc `AppleClamshellState`), kể cả khi cắm màn hình ngoài.
- Eject thêm khi máy sắp ngủ (phòng hờ).
- Chỉ eject ổ ngoài/tháo được; bỏ qua ổ trong, ổ hệ thống, ổ mạng.
- Báo lỗi bằng notification nếu ổ đang bận.
- Menu: bật/tắt tự động, "Eject tất cả ngay", khởi động cùng máy.

## Build & cài
Yêu cầu: macOS 13+, Xcode Command Line Tools (`swiftc`).

```bash
./build.sh --install     # build, chép vào /Applications, chạy
```

Kiểm thử không eject thật: `AutoEject --dry-run`.

## Icon
`make_icon.swift` vẽ icon nút bấm 3D → `AppIcon.iconset` → `AppIcon.icns`:
```bash
swiftc -O make_icon.swift -o /tmp/make_icon && /tmp/make_icon AppIcon.iconset && iconutil -c icns AppIcon.iconset -o AppIcon.icns
```
