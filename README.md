# Làng Quê Việt

Demo cảnh quan làng quê Bắc Bộ 2.5D low-poly, dựng hoàn toàn bằng code trong Godot.
Chỉ để ngắm cảnh, chưa có gameplay.

## Chạy thử

1. Cài **Godot 4.5.1-stable** (bản Standard): https://godotengine.org/download/archive/4.5.1-stable/
2. Mở Godot → **Import** → chọn `project.godot` → **Import & Edit**.
3. Nhấn **F5**.

Máy yếu hoặc lỗi Vulkan: chạy bằng renderer Compatibility

```bash
godot --path . --rendering-method gl_compatibility
```

## Phím tắt

| Phím | Tác dụng |
|---|---|
| Chuột phải + kéo | Xoay quanh cảnh |
| Lăn chuột | Zoom |
| Chuột giữa + kéo, WASD / mũi tên | Di chuyển tâm nhìn |
| Bấm vào cửa bất kỳ toà nào / `E` | Vào trong (nhà, đình, chùa — kiểu nhà búp bê); `E` vào toà gần nhất |
| `Esc` / `E` / nút "Ra sân" | Ra sân |
| `P` | Đổi phối cảnh ↔ trực giao |
| `[` / `]` (giữ) | Lùi / tiến giờ |
| `T` | Bật/tắt tự chạy giờ (1 ngày = 2 phút) |
| Bấm vào người / con vật | Xem tên, nhà, việc đang làm |
| `F` | Camera đi theo người đang chọn |
| `R` | Đổi ngay sang thời tiết ngẫu nhiên khác (thời tiết luôn tự đổi ngẫu nhiên) |
| `H` | Ẩn/hiện HUD |

Phía bắc khu nhà là một làng Bắc Bộ xưa với 44 ngôi nhà, mỗi nhà một kiến trúc khác nhau,
cùng đình, chùa, ao, giếng, lũy tre. Lăn chuột để lùi camera ra xa, kéo chuột giữa (hoặc W)
để đi vào làng.

Thông số (vị trí vật thể, gió, số khóm lúa, màu sương…) chỉnh trong Inspector
ở các node con của `World`, `DayNight` và `CameraRig`.

Font Be Vietnam Pro theo giấy phép SIL OFL (`assets/fonts/OFL.txt`).
