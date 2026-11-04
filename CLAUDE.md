# Làng Quê Việt — Demo cảnh quan 2.5D low-poly

> File hướng dẫn cho Claude Code. Đặt file này ở thư mục gốc của dự án Godot.
> Mục tiêu giai đoạn này: **chỉ dựng cảnh quan để ngắm**, CHƯA có gameplay
> (không di chuyển nhân vật, không túi đồ, không nhiệm vụ).
> Ngoại lệ duy nhất: **vào/ra các toà nhà bằng cách bấm cửa** (mục 10) — vẫn không có nhân vật điều khiển.

---

## 1. Mục tiêu demo

Dựng một khung cảnh làng quê Bắc Bộ nhỏ, nhìn chéo từ trên xuống (2.5D), phong cách
low-poly màu phẳng, nhẹ nhàng, ấm áp. Người xem có thể xoay / zoom / kéo camera để ngắm,
và chỉnh giờ trong ngày để thấy ánh sáng thay đổi.

Cảm giác mong muốn: chiều muộn yên bình, gió nhẹ làm lúa và tre đung đưa, mặt ao lăn tăn.

## 2. Công nghệ

- **Engine:** **Godot 4.5.1-stable** (cố định phiên bản; muốn nâng cấp thì đổi ở đây trước),
  renderer **Forward+** (fallback **Compatibility** nếu máy yếu).
- **Ngôn ngữ:** GDScript, có type hint đầy đủ (`var speed: float = 2.0`).
- **Asset:** ở giai đoạn demo, **toàn bộ mô hình được sinh bằng code** (procedural mesh
  qua `SurfaceTool` / `ArrayMesh`), không dùng file .glb/.blend bên ngoài.
  Lý do: Claude Code có thể tự tạo và chỉnh mọi thứ chỉ bằng văn bản.
  Sau này có thể thay dần bằng model Blender mà không đổi cấu trúc scene.
- **Shader:** Godot Shading Language (`.gdshader`) cho nước, gió, bầu trời.

## 3. Phong cách hình ảnh

- **Low-poly, flat shading:** mỗi mặt một màu, không texture.
  Khi sinh mesh bằng `SurfaceTool`, gọi `set_smooth_group(-1)` trước khi thêm đỉnh
  rồi `generate_normals()` để được pháp tuyến phẳng.
  Dùng `MeshBuilder` (`scripts/mesh_builder.gd`): mọi khối có **đáy ở y = 0, tâm đáy ở gốc**,
  đặt vị trí bằng tham số `xform`; gộp nhiều khối của một vật thành một mesh để ít draw call.
- **Vật liệu:** `StandardMaterial3D`, `roughness = 1.0`, `metallic = 0`,
  màu lấy từ bảng màu bên dưới. Dùng `vertex_color_use_as_albedo = true`
  để một mesh có thể mang nhiều màu, **và `vertex_color_is_srgb = true`**
  để màu hiển thị đúng mã hex trong bảng màu.
- **Vật thể có gió** (lúa, lá tre, tán đa) dùng `ShaderMaterial` với `wind_sway.gdshader`
  thay cho `StandardMaterial3D`; shader vẫn đọc màu đỉnh (`COLOR`) và giữ flat shading.
- **Khử răng cưa:** bật MSAA 3D 4x trong `project.godot` (cạnh low-poly rất dễ lộ răng cưa).
- **Ánh sáng mềm:** 1 `DirectionalLight3D` (mặt trời) có đổ bóng,
  `WorldEnvironment` với ambient light ấm, fog nhẹ màu kem để tạo chiều sâu.
  Tonemap: Filmic hoặc AgX, hơi tăng saturation.
  Bóng: `directional_shadow_max_distance` khoảng 60–80 m cho vừa cảnh, chỉnh `shadow_bias`
  để không bị vệt sọc (shadow acne) trên mặt phẳng.
- **Không** dùng hiệu ứng gắt: không bloom mạnh, không lens flare, không viền đen dày.

### Mức chi tiết (tránh đơn điệu)

- **Ghép nhiều khối nhỏ** cho mỗi vật: nhà có thềm, cột hiên, mái chìa, bờ nóc, hàng ngói,
  khung cửa; cây có nhiều nhánh/khối tán. Không dựng vật chính chỉ bằng 1–2 khối.
- **Lệch màu từng mặt:** `MeshBuilder.new(seed, jitter)` với `jitter` khoảng 0.03–0.06;
  vật đứng trên đất bật `contact_shade_height` để chân vật tối dần như bóng tiếp xúc.
- **Không thẳng tuyệt đối:** kích thước, góc xoay, vị trí lệch ngẫu nhiên nhẹ theo seed;
  bờ, đường, viền ao hơi cong vẹo.
- **Lấp khoảng trống** bằng vật nhỏ rải bằng MultiMesh (cỏ, hoa, sỏi, lá rụng).
- Màu thêm ngoài bảng (ví dụ `DIKE`, `EARTH`) khai báo trong `palette.gd`, ghi chú "(bổ sung)".

### Bảng màu (hex)

| Thành phần | Màu chính | Màu mặt tối |
|---|---|---|
| Bầu trời (chiều) | `#f6e7c8` | — |
| Mặt trời | `#f7c873` | — |
| Núi xa | `#9bb3a4` | `#87a291` |
| Nền cỏ | `#8fbf5a` | — |
| Lúa (3 thửa) | `#b5d66b`, `#a6cc5f`, `#c9dd74` | luống: `#7fa84a` |
| Nước ao | `#6fb0c2` | sáng: `#84c3d2` |
| Tường nhà | `#e8d6b0` | `#d4bd92` |
| Sân gạch/đất | `#c9a77a` | — |
| Mái ngói | `#c4563f` | `#a8432f` |
| Gỗ (cửa, cột) | `#7a5233` | — |
| Thân tre | `#7d8f3a` | — |
| Lá tre | `#6e9a3c` | `#5d8a32` |
| Tán cây đa | `#4f7d38`, `#5c8f40` | `#426b2f` |
| Thân cây đa | `#6b4a2e` | — |
| Trâu | `#5a5552` | `#4a4543`, sừng `#d9cfc0` |
| Người nông dân | áo `#3f6f8f`, da `#e3b58c` | quần `#5a3d28` |
| Nón lá | `#efd9a0` | `#d8c084` |

Đặt bảng màu này trong `scripts/palette.gd` (một `class_name Palette` với các hằng
`Color`), mọi script đều lấy màu từ đây, không viết cứng mã hex rải rác.

## 4. Bố cục cảnh (khoảng 40 × 40 đơn vị, 1 đơn vị ≈ 1 mét)

Nhìn từ camera chéo, bố cục giống ảnh concept:

- **Hậu cảnh (phía sau, xa):** dãy núi low-poly thấp, màu xanh xám, mờ dần trong fog.
- **Góc trái:** **nhà mái ngói** 3 gian: tường vàng kem, mái dốc 2 mái màu đỏ gạch,
  1 cửa gỗ, 1 cửa sổ, sân gạch trước nhà.
- **Giữa phía sau:** **lũy tre** gồm 8–12 cây tre (thân trụ mảnh nhiều đốt + chùm lá
  hình chóp), mọc thành cụm, cao không đều nhau.
- **Giữa bên phải:** **cây đa** lớn: thân to, tán gồm 3–4 khối đa diện chồng lên nhau.
- **Tiền cảnh:** **ruộng lúa** 3 thửa có bờ đất ngăn cách, mỗi thửa một sắc xanh,
  lúa là nhiều khóm nhỏ (dùng `MultiMeshInstance3D`, ~2.000–5.000 khóm).
- **Bên phải:** **ao nước** hình bất quy tắc, có bờ.
- **Trên ruộng:** **1 con trâu** đứng gặm cỏ và **1 người đội nón lá** đứng gần đó
  (dạng tượng tĩnh low-poly, chỉ có animation "thở" nhẹ: scale lên xuống 1–2%).
- **Chi tiết điểm xuyết:** vài bụi cỏ, vài hòn đá, một cái giếng hoặc chum nước ở sân,
  đường đất nhỏ nối sân nhà ra bờ ruộng.

## 5. Tính năng của demo

1. **Camera ngắm cảnh** (`scripts/camera_rig.gd`)
   - Góc nhìn chéo kiểu isometric: pitch khoảng -35° đến -45°.
   - Chuột phải kéo: xoay quanh tâm cảnh. Lăn chuột: zoom (có giới hạn min/max).
     Chuột giữa kéo hoặc WASD: di chuyển tâm. Mọi chuyển động đều có nội suy mượt (lerp).
   - Phím `P`: đổi giữa camera phối cảnh (perspective) và trực giao (orthographic).
     Ở chế độ trực giao, zoom thay đổi `size` của camera chứ không đổi khoảng cách.
2. **Chu kỳ ngày đêm** (`scripts/day_night.gd`)
   - Biến `time_of_day` (0–24). Mặt trời xoay theo giờ, màu ánh sáng và màu trời
     chuyển giữa: sáng sớm (hồng nhạt), trưa (trắng ấm), chiều (cam vàng),
     đêm (xanh tím đậm, ánh sáng yếu).
   - Phím `[` / `]`: lùi / tiến giờ. Phím `T`: bật/tắt tự chạy thời gian
     (1 ngày = 2 phút). Mặc định khởi động lúc **17:00**.
   - Ban đêm: bật `OmniLight3D` vàng ấm ở cửa sổ nhà, vài đom đóm (`GPUParticles3D`).
   - Ánh sáng ambient ban đêm có mức tối thiểu (`@export`) để cảnh vẫn nhìn rõ.
3. **Gió** (`shaders/wind_sway.gdshader`)
   - Vertex shader làm lúa, lá tre, tán đa đung đưa theo sin(thời gian + vị trí).
     Biên độ tăng theo chiều cao của đỉnh (gốc đứng yên, ngọn lay).
   - Pha gió lấy theo **vị trí world** của từng vật/khóm (`MODEL_MATRIX` hoặc
     `INSTANCE_CUSTOM`), để hàng nghìn khóm lúa không lắc cùng một nhịp.
4. **Mặt nước** (`shaders/water.gdshader`)
   - Màu phẳng, hơi trong suốt, sóng nhẹ ở vertex, viền sáng ở mép bờ nếu làm được.
5. **Không khí**
   - Fog nhẹ, vài đám mây low-poly trôi chậm, khói bếp bốc lên từ mái nhà (particles).
6. **HUD tối giản** — góc trên trái hiển thị giờ hiện tại, góc dưới hiển thị phím tắt.
   Phím `H` để ẩn/hiện HUD. Font phải hỗ trợ đầy đủ dấu tiếng Việt
   (ví dụ Be Vietnam Pro hoặc Nunito, tải từ Google Fonts, đặt trong `assets/fonts/`
   kèm file giấy phép `OFL.txt`).
7. **Phím tắt** khai báo trong **Input Map** của `project.godot` (tên action tiếng Anh:
   `cam_forward`, `cam_back`, `cam_left`, `cam_right`, `toggle_projection`, `time_back`,
   `time_forward`, `toggle_time`, `toggle_hud`, `interact` (E), `exit_interior` (Esc)),
   không bắt phím cứng trong code.

## 6. Cấu trúc thư mục

```
project.godot
CLAUDE.md
.gitignore             # bỏ .godot/ và screenshots/
scenes/
  main.tscn            # scene gốc: môi trường, ánh sáng, camera, các node con
  props/               # (sau này) scene riêng cho từng loại vật thể
scripts/
  palette.gd           # bảng màu
  mesh_builder.gd      # hàm tiện ích sinh mesh low-poly: hộp, lăng trụ, chóp, đa diện ngẫu nhiên
  world_builder.gd     # dựng toàn cảnh khi chạy (_ready): gọi các builder bên dưới
  builders/
    terrain.gd         # nền đất, bờ ruộng, ao, đường đất
    house.gd
    bamboo.gd
    banyan.gd
    rice_field.gd      # MultiMesh lúa
    mountains.gd
    characters.gd      # trâu + người nón lá
    props.gd           # đá, cỏ, hoa, giếng, chum, rơm, lá súng
    clouds.gd          # mây trôi (bay thấp hơn camera để lọt khung nhìn chéo)
    village.gd         # làng: lũy tre, cổng, đường trục, ngõ, lô đất, đình, chùa, ao, giếng (mục 11)
    village_house.gd   # sinh kiểu nhà không trùng + dựng từng lô (nhà, mái, rào, sân, vườn)
  interior.gd          # không gian trong nhà kiểu nhà búp bê (mục 10)
  house_entry.gd       # bấm cửa / E để vào, Esc để ra; chuyển camera, HUD, hiệu ứng mờ
  camera_rig.gd
  day_night.gd         # giờ, màu trời/đèn, đèn cửa sổ, đom đóm, khói bếp
  hud.gd
shaders/
  wind_sway.gdshader
  water.gdshader       # nước low-poly, viền sáng bằng màu đỉnh (không cần depth texture)
assets/
  fonts/
tools/
  screenshot.gd        # chụp ảnh cảnh để tự kiểm tra (xem mục 8)
screenshots/           # ảnh chụp, không commit
```

## 7. Lộ trình thực hiện (làm lần lượt, mỗi bước phải chạy được)

| Bước | Nội dung | Tiêu chí hoàn thành |
|---|---|---|
| 1 | Tạo dự án Godot, `main.tscn`, `WorldEnvironment`, mặt trời, camera_rig | Chạy lên thấy mặt phẳng màu cỏ, xoay/zoom camera mượt |
| 2 | `palette.gd` + `mesh_builder.gd` | Có hàm sinh hộp, chóp, lăng trụ flat-shaded; test hiển thị vài khối |
| 3 | Địa hình: nền, 3 thửa ruộng, bờ, ao, đường đất | Bố cục giống concept khi nhìn từ góc mặc định |
| 4 | Nhà mái ngói + sân | Nhà đọc rõ là nhà Việt: tường kem, mái ngói đỏ dốc |
| 5 | Lũy tre + cây đa + núi xa | Cảnh có chiều sâu, có tiền/trung/hậu cảnh |
| 6 | Lúa MultiMesh + shader gió | Lúa và tre đung đưa nhẹ, vẫn ≥ 60 FPS |
| 7 | Trâu + người nón lá + chi tiết nhỏ | Cảnh có "sự sống" |
| 8 | Chu kỳ ngày đêm, đèn cửa sổ, đom đóm, khói bếp | Chuyển giờ mượt, ban đêm vẫn nhìn rõ |
| 9 | Nước, mây, HUD, tinh chỉnh màu | Cảnh hoàn chỉnh, sẵn sàng chụp ảnh giới thiệu |

## 8. Quy tắc cho Claude Code

- **Làm từng bước một** theo bảng trên. Xong mỗi bước: dừng lại, tóm tắt đã làm gì,
  hướng dẫn tôi chạy thử, chờ tôi xác nhận rồi mới sang bước tiếp.
- **Kiểm tra lỗi** sau mỗi lần sửa code (nếu có lệnh `godot` trong PATH):
  `godot --headless --path . --import` rồi `godot --headless --path . --quit-after 10`,
  đọc output, sửa hết lỗi/cảnh báo script.
- **Tự kiểm tra hình ảnh:** lỗi script chỉ là một nửa; trước khi báo xong một bước, chụp ảnh
  cảnh và tự xem lại (bố cục, màu, ánh sáng có đúng mô tả không). Chụp bằng renderer
  Forward+ (giống máy thật) qua Vulkan phần mềm:
  `xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --resolution 1920x1080 -s tools/screenshot.gd -- --out=screenshots/step.png`
  Tham số thêm: `--hour=17` (giờ, khi đã có chu kỳ ngày đêm — chụp ít nhất 17:00 và 22:00),
  `--yaw=`, `--pitch=`, `--distance=`, `--focus=x,z`, `--ortho`, `--frames=`.
  Máy cloud cần cài trước: `apt-get install -y mesa-vulkan-drivers libvulkan1` (lavapipe).
  Thêm `--rendering-method gl_compatibility` để kiểm tra chế độ Compatibility; mọi hiệu ứng
  phải có **phương án dự phòng cho Compatibility** (ví dụ `CPUParticles3D` thay
  `GPUParticles3D`, bỏ viền sáng mép nước nếu không có depth texture).
- Ưu tiên **dựng cảnh bằng script** (`world_builder.gd`) thay vì sửa tay file `.tscn`
  phức tạp. File `.tscn` chỉ giữ cấu trúc node đơn giản.
- Mọi con số tinh chỉnh được (biên độ gió, tốc độ ngày, số khóm lúa, vị trí vật thể)
  đặt thành `@export var` để tôi chỉnh trong Inspector.
- Dùng **random có seed cố định** (`RandomNumberGenerator` với `seed`) để cảnh
  sinh ra giống nhau mỗi lần chạy.
- **Hiệu năng:** mục tiêu ≥ 60 FPS ở 1080p trên máy tầm trung. Vật thể lặp lại nhiều
  (lúa, cỏ, đá) phải dùng `MultiMeshInstance3D`.
- Comment trong code bằng **tiếng Việt**, ngắn gọn. Tên biến, hàm, file bằng tiếng Anh.
- Không thêm gameplay (điều khiển nhân vật, inventory, nhiệm vụ) ở giai đoạn này.
- Dùng Git: commit sau mỗi bước hoàn thành, message rõ ràng
  (ví dụ: `step 4: add tiled-roof house`).

## 9. Ngoài phạm vi (để giai đoạn sau)

Điều khiển nhân vật, trồng trọt, NPC và hội thoại, lưu game, âm thanh và nhạc nền,
thay mesh procedural bằng model Blender, các mùa trong năm, thời tiết mưa.

## 10. Vào trong nhà (giai đoạn 1b)

- **Cách vào:** rê chuột vào cửa nhà chính → cửa sáng viền + gợi ý "Vào nhà"; bấm chuột trái
  hoặc nhấn `E` để vào. Bên trong: `Esc`, `E`, nút "Ra sân" hoặc bấm vào ô cửa để ra.
  Không có nhân vật điều khiển.
- **Chuyển cảnh:** màn hình mờ dần sang đen rồi sáng lại (~0,35 s). Cảnh ngoài sân và trong nhà
  cùng nằm trong một scene; chỉ đổi camera, ẩn/hiện, HUD — giờ trong ngày vẫn chạy liên tục.
- **Không gian trong nhà** (`interior.gd`) đặt ở xa (z = 1000), ngoài tầm camera ngoài sân.
  Kiểu **nhà búp bê**: bỏ mái, tường trước cắt thấp, nhìn chéo từ trên vào cả 3 gian; vẫn
  xoay/zoom bằng một `CameraRig` riêng. Kích thước nhà lấy từ `House` để khớp bên ngoài.
- **Bày trí 3 gian Bắc Bộ:** gian giữa bàn thờ gia tiên, hoành phi câu đối, bàn trà;
  gian trái giường, tủ; gian phải chạn bát, chum gạo, nong nia, quang gánh.
  Đèn dầu thuộc nhóm `night_light` để tự sáng khi tối.
- **Vùng bấm** là `StaticBody3D` ở lớp va chạm 2, tạo bằng `HouseEntry.make_click_target()`.
- **Mọi toà đều vào được** (nhà mình, 44 nhà làng, đình, chùa): cửa tạo bằng
  `HouseEntry.make_entry_target(parent, xform, size, hint, spec, key)`. `spec` là thông số
  nội thất; `Interior.load_spec(spec)` xoá nội thất cũ và dựng lại lúc màn hình tối, nên chỉ
  có MỘT nội thất tồn tại tại một thời điểm (không tốn FPS ngoài làng). Khoá: `main`, `dinh`,
  `pagoda`, `house_0`…`house_43`; chụp ảnh bằng `--enter=<khoá>`.
- **Nhà làng:** kích thước, tường, mặt tiền khớp bên ngoài (do `VillageHouse.build_house` trả
  về). Gian giữa luôn là bàn thờ + bàn trà; các gian bên chọn theo seed từ `Interior.ROOM_TYPES`
  (buồng ngủ, phản + chõng tre, kho, khung cửi, cối xay thóc, góc học), luôn có chỗ ngủ.
  Nhà tranh/vách đất: nền đất nện, đồ gỗ mộc, không hoành phi.
- **Đình:** lưới cột lim + xà, hậu cung (khám, ngai, bài vị), hương án, hạc chầu trên lưng rùa,
  hoành phi câu đối, trống đại, chiêng, bát bửu, kiệu, chiếu hội, đèn lồng.
  **Chùa:** Phật điện ba cấp (Tam Thế, A Di Đà, Quan Âm – Thế Chí, Cửu Long), ban thờ, chuông,
  mõ, hai hộ pháp, bồ đoàn.
- Nhấn `E` ngoài sân: vào toà đang rê chuột, nếu không thì toà có cửa gần tâm camera nhất
  (trong `HouseEntry.interact_radius`). Sau khi dựng nội thất gọi `DayNight.refresh()` để đèn
  mới sáng đúng giờ.

## 11. Làng (giai đoạn 1c)

- **Vị trí:** khu nhà chính + ruộng giữ nguyên ở gốc toạ độ; làng nằm phía bắc (z âm),
  trong elip `Village.center` (0, −105), bán kính (100, 70). Đất làng phẳng (y = 0) do
  `Terrain.village_rect` dựng; ngoài làng là đồng (`Terrain.outer_fields`) và đường đất
  (`Terrain.roads`) nối cổng làng ra đồng.
- **Quy hoạch kiểu làng Bắc Bộ:** lũy tre dày bao quanh, cổng làng phía nam, đường trục lát gạch
  từ cổng tới đình, các ngõ ngang toả hai bên (xương cá, hơi uốn). Lô đất nằm phía bắc mỗi ngõ,
  nhà quay hướng nam; lô sâu/rộng khác nhau, xoay theo ngõ, có khe giữa các lô.
- **Nhà không trùng:** mỗi nhà là một tổ hợp duy nhất của số gian · loại mái (ngói đỏ, ngói nâu,
  rạ) · kiểu mái (hai mái, bốn mái có đầu đao, tường hồi bít đốc) · tường (vôi vàng, vôi trắng,
  gạch, đất) · mặt tiền (hiên cột gỗ, hiên cột gạch, cửa bức bàn) · bố cục lô (một nếp, chữ L
  trái/phải, chữ U, bếp riêng). `VillageHouse.signature()` dùng để kiểm tra trùng; nhà tranh
  được ưu tiên để chiếm khoảng 1/3. Khi chạy in ra số nhà và thống kê từng đặc điểm.
- **Công trình chung:** đình (nghi môn, sân gạch, hồ bán nguyệt, tả mạc hữu mạc, mái bốn mái
  đầu đao, lưỡng long chầu nguyệt, cây đa), chùa (tam quan, chính điện mái chồng diêm, gác
  chuông), ao làng, giếng làng, điếm canh, cây đa đầu làng; vườn tạp lấp chỗ trống.
- **Hiệu năng:** gộp mesh theo từng dãy ngõ (nhà, lá có gió, nền, ô cửa phát sáng); cả cảnh
  khoảng 400 nghìn tam giác, ~80 node mesh. Cửa sổ/khe cửa các nhà phát sáng ban đêm (nhóm
  `night_glow`); chỉ đình, chùa có đèn thật (`night_light`).
- Khi thêm chi tiết cho nhà làng: mọi khối đặt bằng `xf * ...` (toạ độ lô) — quên `xf` thì vật
  rơi về gốc toạ độ (đã từng xảy ra với cửa sổ tròn).
