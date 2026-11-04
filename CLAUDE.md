# Làng Quê Việt — Demo cảnh quan 2.5D low-poly

> File hướng dẫn cho Claude Code. Đặt file này ở thư mục gốc của dự án Godot.
> Mục tiêu giai đoạn này: **chỉ dựng cảnh quan để ngắm**, CHƯA có gameplay
> (không di chuyển nhân vật, không túi đồ, không nhiệm vụ).
> Ngoại lệ: **vào/ra các toà nhà bằng cách bấm cửa** (mục 10), **dân làng tự đi lại** (mục 13),
> mini-game câu cá (mục 16), sân bóng (mục 17), **nhập vai góc nhìn thứ nhất** (mục 18, phím `V`)
> **trò chuyện với dân làng** (mục 19), **dân làng nhờ việc** (mục 20) và **lên đò, chèo đò trên sông** (mục 24) — chưa có túi đồ đầy đủ,
> chưa lưu game.

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
- **Ngoại lệ — con người dùng "low-poly mềm":** tay chân, thân, đầu dựng bằng
  `MeshBuilder.add_capsule()` (ống bo tròn hai đầu) và `add_ellipsoid()` (khối trứng) với pháp tuyến
  cong (bóng mượt), nhưng vẫn ít mặt và màu phẳng không texture. Mọi thứ khác giữ flat shading.
  Pháp tuyến do `MeshBuilder._tri` tự đặt cho từng đỉnh (mặt phẳng = pháp tuyến mặt, khối mượt =
  pháp tuyến tính từ hình dạng); `commit()` KHÔNG gọi `generate_normals()` nữa (hàm đó không trung
  bình pháp tuyến như mong đợi khi dùng smooth group).
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
   `time_forward`, `toggle_time`, `toggle_hud`, `interact` (E), `exit_interior` (Esc),
   `cycle_weather` (R), `follow_npc` (F), `fish_reel` (Space + chuột trái),
   `toggle_first_person` (V), `fp_run` (Shift), `fp_jump` (Space), `dialog_1`…`dialog_4` (phím 1–4),
   `toggle_minimap` (M)),
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
    river.gd           # sông móng ngựa quanh làng: đê, lòng sông, nước, cá, đầm sen, đò (mục 14)
    school.gd          # trường tiểu học kiểu năm 2000 phía tây nhà mình (mục 15)
    football.gd        # sân bóng làng + bóng + trận đấu của dân làng (mục 17)
  interior.gd          # không gian trong nhà kiểu nhà búp bê (mục 10)
  house_entry.gd       # bấm cửa / E để vào, Esc để ra; chuyển camera, HUD, hiệu ứng mờ
  camera_rig.gd
  day_night.gd         # giờ, màu trời/đèn, đèn cửa sổ, đom đóm, khói bếp
  weather.gd           # thời tiết: mây, mưa, giông, chớp, sương mù (mục 12)
  villagers.gd         # dân làng + con vật: đồ thị đường, lịch sinh hoạt, chọn xem tin (mục 13)
  villager.gd          # một NPC: hình có khớp, dáng đi/làm việc, đi theo đường
  hud.gd
  fishing.gd           # mini-game câu cá ở các bến sông (mục 16)
  first_person.gd      # nhập vai góc nhìn thứ nhất: đi lại, va chạm, tương tác (mục 18)
  dialogue.gd          # trò chuyện với dân làng: lời thoại, xưng hô, khung thoại (mục 19)
  quests.gd            # dân làng nhờ việc: gánh nước, nhắn tin, câu cá, tìm đồ, sút bóng (mục 20)
  indoor_folk.gd       # dân làng ở trong nhà / đình / chùa / lớp học theo lịch (mục 22)
  minimap.gd           # bản đồ nhỏ góc màn hình, phím M (mục 23)
  boat_ride.gd         # lên đò, chèo đò trên sông, lên bờ (mục 24)
                       # (interior.gd có thêm kiểu đi bộ bên trong cho nhập vai — mục 21)
shaders/
  wind_sway.gdshader
  water.gdshader       # nước low-poly, viền sáng bằng màu đỉnh (không cần depth texture)
  fish.gdshader        # cá MultiMesh: đuôi ngoe nguẩy, mỗi con một nhịp (INSTANCE_ID)
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
- Không thêm gameplay ngoài các ngoại lệ đã ghi (câu cá, sân bóng, nhập vai đi lại, trò chuyện,
  việc nhờ, chèo đò); túi đồ đầy đủ, lưu game vẫn để giai đoạn sau.
- Dùng Git: commit sau mỗi bước hoàn thành, message rõ ràng
  (ví dụ: `step 4: add tiled-roof house`).

## 9. Ngoài phạm vi (để giai đoạn sau)

Trồng trọt, lưu game, âm thanh và nhạc nền,
thay mesh procedural bằng model Blender, các mùa trong năm, âm thanh mưa/sấm.

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
- **Mọi toà đều vào được** (nhà mình, 41 nhà làng, đình, chùa): cửa tạo bằng
  `HouseEntry.make_entry_target(parent, xform, size, hint, spec, key)`. `spec` là thông số
  nội thất; `Interior.load_spec(spec)` xoá nội thất cũ và dựng lại lúc màn hình tối, nên chỉ
  có MỘT nội thất tồn tại tại một thời điểm (không tốn FPS ngoài làng). Khoá: `main`, `dinh`,
  `pagoda`, `house_0`…`house_40`; chụp ảnh bằng `--enter=<khoá>`.
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

## 12. Thời tiết (giai đoạn 1d)

- `scripts/weather.gd` (node `Weather`): 5 kiểu `clear` (nắng), `cloudy` (nhiều mây),
  `drizzle` (mưa phùn), `storm` (mưa giông, có chớp), `fog` (sương mù). Mỗi kiểu là bộ thông số
  `PRESETS` (độ phủ mây, lượng mưa, hệ số gió, sương); giá trị hiện tại chuyển dần
  (`transition_time`) nên đổi thời tiết không giật.
- **Luôn ngẫu nhiên:** mở game bắt đầu bằng một kiểu bất kỳ, rồi tự đổi theo `AUTO_WEIGHTS`
  mỗi 70–140 giây; mỗi lần chạy mỗi khác (ngoại lệ có chủ đích với quy tắc seed cố định —
  bật `fixed_seed` để lặp lại). Phím `R`: đổi ngay sang kiểu ngẫu nhiên khác. HUD hiện tên.
- **Ánh sáng:** Weather đặt `DayNight.weather_cover` / `weather_mist` rồi gọi `refresh()`;
  DayNight làm yếu nắng, ngả xám trời/sương/ambient (giữ độ sáng theo giờ), và trời giông thì
  nhà thắp đèn sớm. Weather chỉnh thêm `adjustment_brightness/saturation` và vùng sương
  (`fog_depth_begin/end`). Chớp = cộng thêm vào `adjustment_brightness` trong ~0,2 s.
- **Gió và mặt nước:** biến toàn cục shader `weather_wind`, `weather_rain` (khai báo trong
  `[shader_globals]` của `project.godot`). Shader mới có lá/nước nên đọc các biến này.
- **Mưa:** hạt mưa (vệt billboard) + vòng nước bắn trên mặt đất, đi theo tâm camera ngoài sân,
  vùng mưa rộng theo độ xa camera; ẩn khi vào trong nhà. GPUParticles3D ở Forward+,
  CPUParticles3D (bớt hạt) ở Compatibility. Mây (`Clouds.coverage`) dày và xám dần theo độ phủ.
- Chụp ảnh: `--weather=<kiểu>` (tắt tự đổi), `--flash` (giữ khoảnh khắc chớp).

## 13. Dân làng đi lại (giai đoạn 1e)

- `scripts/villagers.gd` (node `World/Villagers`, dựng sau `Village`) + `scripts/villager.gd`.
  Mặc định 36 người (12 nông dân vác cuốc, 6 người gánh hàng, 6 cụ già chống gậy, 8 trẻ con,
  4 trẻ chăn trâu) và 37 con vật (4 trâu theo trẻ chăn, 3 chó theo chủ, 6 sân gà × 4, 6 vịt
  bơi nối đuôi ở ao làng). Số lượng chỉnh bằng `@export`. Dân số sinh theo `random_seed` cố định.
- **Đường đi:** `AStar3D` dựng từ đường trục, các ngõ (`Village.lane_points/alley_lines`),
  đường đất (`Terrain.roads`) và lối sân nhà mình. Ra khỏi nhà: cửa → trước hiên → cổng
  (`Village.homes[i].gate`) → đồ thị; về nhà thì ngược lại rồi ẩn ("vào nhà"). Mỗi người lệch
  sang một bên đường (`side_offset`, tính theo hướng CỐ ĐỊNH của đoạn đường — tính theo vị trí
  hiện tại thì NPC sẽ quay vòng mãi quanh điểm mốc).
- **Lịch:** `Villagers._choices()` cho trọng số việc theo vai trò + giờ (ra đồng, chăn trâu,
  gánh nước ở giếng, nghỉ gốc đa, lễ chùa, chơi sân đình/bờ ao, sang nhà hàng xóm, làm việc
  ngoài sân, vào nhà). Mỗi việc kéo dài vài chục giây thật nên làng vẫn động khi giờ đứng yên.
  Tối (≥ 20:30) ai cũng về nhà, trừ vài người cầm đèn lồng đi chơi tới 22:00.
- **Thời tiết:** mưa phùn đi nhanh hơn, bớt đi chơi; mưa giông thì mọi người chạy về nhà trú,
  tạnh mới ra lại. Gà vào chuồng khi giông hoặc tối.
- **Xem tin:** bấm chuột trái vào người/vật (lớp va chạm 3) → vòng sáng dưới chân + khung
  thông tin góc trên phải (tên, vai trò, nhà, việc đang làm); `F` cho camera đi theo.
- **Hình người "mềm"** (`Villager._build_person_rig`): hông → đùi → khớp gối (`knees`) → ống chân
  + bàn chân; vai → bắp tay → khớp khuỷu (`elbows`) → cẳng tay + bàn tay; hông, thân dẹt, cổ, đầu
  dùng chung `Villager.soft_head()` (tai, chỏm tóc, búi tóc cho phụ nữ, mắt, lông mày, má hồng) —
  người câu cá (`Fishing`) và tượng nông dân (`Characters`) cũng dùng hàm này. Dáng đi: gối co khi
  chân đưa lên, thân lắc / xoay nhẹ theo bước, khuỷu hơi gập (tay cầm đồ thì thẳng), thở khi đứng
  yên, ngồi thì gập gối (hông hạ đúng một đoạn đùi). Mỗi người ~2.100 tam giác (36 người ~75 nghìn).
  Bộ đồ (`_outfits`) lưu cả `knees` / `elbows`.
- **Hiệu năng:** mesh từng bộ phận dùng chung qua bộ đệm; chỉ diễn hoạt NPC trong
  `animate_distance` quanh camera; mỗi phần có `visibility_range_end`.
- Chụp ảnh: `--npc=<chỉ số|vai trò>` chọn NPC và cho camera đi theo.

## 14. Sông quanh làng (giai đoạn 1f)

- `scripts/builders/river.gd` (node `World/River`, dựng sau `Village`). Sông hình móng ngựa
  ôm ba mặt làng (tây → bắc → đông) theo elip của làng nới ra `offset_radii` (130, 98), uốn
  khúc nhẹ; hai đầu (`west_tail`, `east_tail`) vòng thoải rồi chảy xa ra đồng. Mặt nam để trống
  (cổng làng, ruộng). Dài khoảng 1 km, rộng 18–26 m (`width_range`). Nới rộng sông thì phải nới
  `offset_radii` theo, nếu không chân đê phía trong lấn vào lũy tre.
- **Cả lòng sông nằm TRÊN nền cỏ:** lòng bùn ở `bed_level` 0,06, mặt nước `water_level` 0,32,
  đê cao `levee_height` 0,85. Nếu để mặt nước sát nền y = 0 thì cỏ lộ qua làn nước trong
  (đã gặp: mảng xanh giữa sông). Mặt cắt bờ: lòng bùn → mái đất → mặt đê cỏ → mái thoải.
- Khúc nối vào vòng phải cua đủ rộng (bán kính ≫ nửa bề rộng sông + đê ~15 m), nếu không
  mặt bờ phía trong bị gấp lại thành "mũi nhọn". Tim sông làm mượt Chaikin 3 lần.
- **Cá:** 220 con (chép đỏ, vàng, trắng, trắm xám) — một MultiMesh, cập nhật vị trí mỗi khung
  theo độ dài dọc sông (`River.sample(s)`), bơi xuôi ngược, lượn ngang; thỉnh thoảng một con
  gần camera nhảy lên khỏi mặt nước, để lại gợn tròn. Đuôi uốn trong `fish.gdshader`.
- **Sen:** 12 đầm sát bờ, mỗi đầm ~30–40 lá nổi, 6–12 lá vươn cao, 4–9 hoa (¼ sen trắng),
  3–6 nụ; tất cả MultiMesh, lá/hoa có thân dùng shader gió. `River.lotus_spots` /
  `boat_spots` lưu toạ độ để chụp ảnh.
- **Đò:** 3 con đò to (mục 24) neo ven bờ đoạn vòng quanh làng, tránh bến và đầm sen.
- **Cây cỏ ven sông** (`_build_vegetation`, mật độ `reed_density`, `hyacinth_density`,
  `grass_density`, `flower_density`, `banana_density`, `tree_density`): lau sậy có bông ở mép nước,
  cụm bèo tây (có hoa tím) nổi gần bờ, cỏ + hoa dại (vàng, trắng, tím) trên mái và mặt đê, bụi chuối
  và cây to ở chân đê phía ngoài vòng sông (không trồng ở hai đuôi ngoài đồng). Tất cả MultiMesh có
  gió, trừ thân cây to (mesh thường → nhập vai không đi xuyên). `_veg_blocked` né bến, lối xuống
  sông, đò neo. Chọn điểm dọc sông bằng `_bank_point(d_range)` (d = khoảng cách tới mép nước).
- Đồi và núi sau làng đã lùi ra xa hơn (`Mountains`) để không lấn vào sông.
- **Lối ra sông (3 lối: tây, đông, bắc):** `Village.access_paths` — hai ngõ được nối dài
  (`river_access_alleys`) và một lối đi thẳng lên bắc từ ngõ cuối (`north_access_x`), lát gạch,
  xuyên qua khe trong lũy tre (không xây lô, không trồng tre/vườn tạp lên hành lang này).
  Ngoài lũy là đường đất bám theo mặt cắt đê (`River.bank_height`) xuống **bến nước**
  (`River.landings`): bậc đá, cầu ván trên cọc tre, tảng đá giặt, chum nước.
- **Dân làng ra sông:** việc mới `river` (giặt giũ — người gánh hàng, nông dân), `swim` (trẻ con
  tắm sông), `fishing` (cụ già ngồi câu trên cầu ván); chỉ ban ngày, không khi mưa. Đồ thị
  AStar có thêm đường ra bến kèm độ cao; `Villager` nội suy độ cao theo đường (`_path_y`) để
  leo đê, lên cầu ván.

## 15. Trường học kiểu năm 2000 (giai đoạn 1g)

- `scripts/builders/school.gd` (node `World/School`): khu đất `site` (x −98…−42, z −42…−4),
  phía tây khu nhà mình; thửa ruộng tây bắc (`Terrain.outer_fields[0]`) đã thu nhỏ để nhường chỗ.
  Cổng mở về hướng đông ra đường đất `Terrain.roads[0]` (x ≈ −24,5), biển "TRƯỜNG TIỂU HỌC"
  bằng `Label3D` (font Be Vietnam Pro).
- Kiến trúc nông thôn Bắc Bộ khoảng năm 2000: dãy lớp học 2 tầng 5 phòng (tường vôi vàng
  `SCHOOL_WALL`, viền/cột trắng `SCHOOL_TRIM`, hành lang trước có lan can con tiện, cửa chớp xanh
  `SHUTTER`, mái ngói đỏ 4 mái KHÔNG có đầu đao — dùng `_hip_roof` riêng, không dùng
  `VillageHouse.roof`), cầu thang ngoài ở đầu hồi, trống trường ở hiên; dãy hiệu bộ 1 tầng;
  nhà xe mái tôn có xe đạp; khu vệ sinh; sân xi măng kẻ ô; cột cờ đỏ sao vàng; bồn hoa; cây
  bàng (tán xếp tầng) và phượng (hoa đỏ); tường rào vàng thấp có song sắt.
- Vào được một lớp học (khoá `school`, `Interior._build_classroom`): bục giảng, bảng đen, khẩu
  hiệu "TIÊN HỌC LỄ - HẬU HỌC VĂN", bàn giáo viên, 2 dãy bàn ghế băng, vở sách, tủ đồ dùng.
- Trẻ con trong làng đi học 7–11h và 13:30–16:30 (việc `school`): đi theo đường đất vào cổng,
  chơi ở sân trường (giờ ra chơi). Cửa sổ trường sáng nhẹ ban đêm (`night_glow`).
- **Đồng phục:** mỗi trẻ con có thêm một bộ khung hình thứ hai (`Villager.add_uniform`): áo
  trắng, quần xanh sẫm, khăn quàng đỏ. `set_outfit(true)` khi bắt đầu việc `school`, thay ra khi
  đã về trong nhà. Áo thường của trẻ con không dùng màu trắng để khỏi lẫn.
- `Villagers.replan()` lên lại lịch theo giờ hiện tại (công cụ chụp ảnh gọi khi có `--hour`).

## 16. Mini-game câu cá (giai đoạn 2a)

- Ngoại lệ có chủ đích với "không gameplay": một mini-game câu cá, **không có nhân vật
  điều khiển đi lại** — người câu là hình ngồi cố định, chỉ hiện khi đang câu.
- `scripts/fishing.gd` (node `Fishing`, con cuối của `Main` để nhận chuột trước). Mỗi bến sông
  (`River.landings`) có một **chỗ ngồi câu** (`fish_spot`: ghế đẩu, cần tre dựng, giỏ cá) cạnh
  cầu ván. Rê chuột vào chỗ ngồi → gợi ý "Ngồi câu cá"; bấm hoặc `E` để vào (vùng bấm lớp 2,
  meta `activate` — `HouseEntry` gọi Callable thay vì vào nhà). `Esc` / `E` để thôi câu.
- **Diễn biến:** giữ chuột trái (hoặc `Space`, action `fish_reel`) để lấy đà → thả để quăng phao
  → chờ một con cá THẬT trong MultiMesh sông bơi tới (`River.lure_fish`) → phao nhấp vài lần
  (giật lúc này cá sợ bỏ đi) → phao chìm hẳn: bấm trong `bite_window` giây để giật cần →
  kéo cá: giữ chuột để cuộn dây, thả khi dây căng; dây căng quá thì đứt, chùng lâu thì cá sổng.
- **Loài cá** lấy theo màu của con cá mắc câu (chép, chép đỏ, diếc, trắm cỏ, trê, mè trắng);
  cân nặng theo cỡ con cá, loài to giãy khoẻ hơn. Câu được thì cá về giỏ, con cá trong sông
  sinh lại ở đoạn xa. Sổ câu (số con, con nặng nhất từng loài) chỉ giữ trong lần chạy (chưa lưu game).
- **Giờ & thời tiết:** cá ăn mạnh lúc sáng sớm và chiều muộn, kém buổi trưa, rất kém ban đêm;
  mưa phùn cá ăn hơn; mưa giông thì không câu được (đang câu thì tự thu cần về).
  Ban đêm đèn bão cạnh chỗ ngồi tự sáng (nhóm `night_light`).
- Chụp ảnh: `--fish=<chỉ số bến>` vào câu, `--fish-state=charge|wait|nibble|bite|reel|caught`
  dựng sẵn trạng thái để kiểm tra giao diện. `tools/fish_test.gd` chơi thử tự động (headless), in
  diễn biến từng lượt câu.
- **Cá giữ vị trí riêng** (`_fish[i].pos`): renderer headless không lưu transform MultiMesh,
  nên không đọc ngược vị trí cá từ MultiMesh.

## 17. Sân bóng làng (giai đoạn 2b)

- `scripts/builders/football.gd` (node `World/Football`, đứng SAU `Villagers` để điều khiển
  cầu thủ sau khi Villagers tick xong mỗi khung). Sân 30 × 18 m ở `Village.pitch_rect`
  (x −62…−32, z −154…−136): góc tây bắc làng, sau ngõ cuối, cạnh lối ra sông phía bắc.
  `Village._reserved` và vườn tạp né vùng này nên làng còn 41 nhà (3 lô nhường chỗ).
- **Sân kiểu làng:** cỏ mòn thành đất ở khung thành và giữa sân, vạch vôi hơi xiêu, khung thành
  tre có lưới cước, cờ góc đỏ, ghế băng tre, bảng tỉ số gỗ (Label3D, tên hai đội "Xóm Đông" đỏ –
  "Xóm Đoài" xanh), hai cây bàng, đống rơm, xe đạp dựng.
- **Đội cởi trần:** Xóm Đoài (`SHIRTLESS_TEAM`) cởi áo khi vào sân, như đá bóng làng ngày xưa;
  con gái luôn vào đội mặc áo (Xóm Đông). Bộ hình cởi trần (`Villager.add_shirtless()`, thân và
  tay màu da, không cầm đồ) chỉ dựng lần đầu người đó cần; ra sân thì mặc lại bộ cũ (lưu ở meta
  `outfit_before`, nên học sinh mặc lại đồng phục). Các bộ đồ của một người nằm trong
  `Villager._outfits` (casual, uniform, shirtless), đổi bằng `wear(tên)`.
- **Bóng:** vật lý tự viết (trọng lực, nảy, ma sát lăn `rolling_friction`, chạm cột/xà bật ra,
  vào lưới thì nằm lại), tường ảo quanh sân để bóng không bay vào nhà dân. Ra biên: sau 1 s đặt
  lại ở vạch (ném biên / phát bóng). Người xem **bấm vào bóng để sút** (vùng bấm lớp 2, meta
  `activate`, giống chỗ câu cá); sút vào lưới cũng hiện chữ "VÀO!".
- **Ai ra sân:** việc `football` 16:18–18:36 — trẻ con (trọng số cao), nông dân nam (vào đá),
  cụ già và phụ nữ (đứng xem bên biên phía nam). `Football.arrive(v)` khi tới nơi: còn chỗ
  (`max_players` 12) thì vào đội ít người hơn, có vòng màu đội dưới chân, cất cuốc
  (`Villager.prop_node`); hết chỗ thì đứng xem. Đủ 2 người là giao bóng; trận dài
  `match_length` giây thật rồi mọi người tản đi. Ai bị Villagers gọi đi (tối, giông) thì tự rời đội.
- **Lối chơi:** mỗi đội người gần bóng nhất lao vào bóng, người thứ hai chạy đỡ, còn lại giữ
  đội hình `FORMATION` trượt theo bóng; đội từ 4 người có thủ môn. Cú chạm: trong tầm 14 m thì
  sút (đôi khi chệch cột), không thì chuyền cho đồng đội phía trên hoặc dẫn bóng lách đối phương;
  sau mỗi cú chạm có nhịp 0,3 s (`_touch_gap`) để hai bên không đá qua đá lại tại chỗ.
- Chụp ảnh: `--football=<số người>` đưa người ra sân đá ngay (chạy trước 6 s), camera nhìn vào
  sân. `tools/football_test.gd -- --players=12 --seconds=240` mô phỏng một trận không giao diện,
  in bàn thắng / số lần chạm bóng / bóng ra biên (thường 4–7 bàn, ~150 lần chạm, ~10 lần ra biên
  mỗi 4 phút). Bóng chỉ mất đà khi rơi xuống thật mạnh (`vel.y < -1.5`): nếu trừ đà mỗi khi
  `vel.y < 0` thì lúc lăn (trọng lực kéo nhẹ mỗi khung) bóng mất 20 % tốc độ mỗi khung và khựng lại.

## 18. Nhập vai góc nhìn thứ nhất (giai đoạn 3a)

- `scripts/first_person.gd` (node `FirstPerson`, `CharacterBody3D`, con cuối của `Main` để nhận
  chuột/phím trước cả `Fishing`). Phím `V` bật/tắt (chỉ khi đang ở ngoài sân, không câu):
  bật thì đứng ở tâm camera ngắm cảnh, tắt thì camera ngắm cảnh quay về chỗ đang đứng.
- **Điều khiển:** chuột nhìn (chuột bị giữ; bấm vào cửa sổ để giữ lại), WASD đi (dùng lại action
  `cam_*`), Shift chạy, Space nhảy, `Esc` hoặc `V` thôi nhập vai. Tự bước lên bậc thấp
  (`step_height` 0,35 m: thềm nhà, bậc đá); lội được ra sông/ao (mặt nước không có va chạm).
- **Va chạm lấy từ mesh tĩnh** dưới `World` (`_build_colliders`): mỗi `MeshInstance3D` dùng
  `StandardMaterial3D` thành một `ConcavePolygonShape3D` ở lớp 4 (`SOLID_LAYER`); bỏ mesh dùng
  `ShaderMaterial` (lá có gió, mặt nước), MultiMesh (lúa, cỏ, cá, sen), dân làng, mây, quả bóng.
  Chỉ dựng lần đầu bật nhập vai (~220 nghìn tam giác, ~0,6 s trên máy cloud). Vật mới thêm vào
  `World` tự có va chạm nếu dùng vật liệu thường; lá/vật mềm nên dùng shader gió để đi xuyên qua.
- **Tương tác bằng tâm ngắm** (tia dài `reach` 3,2 m, lớp 2 + 3 + 4): cửa → "E: vào · tên nhà";
  chỗ câu → "E: ngồi câu cá"; quả bóng → "E / chuột trái: sút bóng" (`Football.kick_from_player`,
  sút theo hướng nhìn, nhìn lên thì bóng bổng); dân làng → "E: xem tin". Đi vào bóng thì dẫn bóng
  (`Football.nudge`). Gợi ý hiện ở `Hud.set_hint`, tâm ngắm là chấm trắng giữa màn hình.
- **Nhường camera:** vào nhà → `HouseEntry` dùng camera trong nhà như cũ, ra sân
  (`inside_changed`) thì nhập vai tiếp. Ngồi câu → `Fishing` dùng camera ngắm cảnh, thôi câu
  (signal `Fishing.stopped`) thì nhập vai tiếp. Trong lúc đi lại `HouseEntry.locked = true`
  (không bắt chuột theo kiểu ngắm cảnh), `CameraRig` bị tắt nhưng tâm của nó bám theo người chơi
  để mưa, dân làng, cá nhảy vẫn diễn ra quanh chỗ đứng.
- Chụp ảnh: `--fp --focus=x,z --fp-yaw=độ --fp-pitch=độ`. `tools/fp_test.gd` (headless) thử đi
  vào tường nhà, nhìn cửa → vào → ra, dẫn bóng và sút, ngồi câu → thôi câu, thoát nhập vai.

## 19. Trò chuyện với dân làng (giai đoạn 3b)

- `scripts/dialogue.gd` (node `Dialogue`). Khi nhập vai, nhìn vào một người (gợi ý
  "E: trò chuyện · tên") và nhấn E: `Dialogue.start(v, player)`; người chơi đứng lại
  (`FirstPerson._suspend("talk")`, giữ camera, hiện chuột), camera quay dần về mặt người đó và hạ
  tầm mắt ngang mặt họ (nói với trẻ con thì như ngồi xuống). Thoại xong (`finished`) thì đi tiếp.
- **NPC đứng lại:** meta `talking` — `Villagers._process` chỉ diễn hoạt (dáng "chat"), không
  đi tiếp, không đổi việc; NPC quay mặt về người chơi, thoại xong thì làm tiếp việc dở.
  Người làng có mắt và lông mày (trong mesh thân) để biết họ đang nhìn về đâu.
- **Khung thoại** dưới màn hình: tên (vàng), lời chạy từng chữ (`chars_per_second`), tối đa 3 câu
  hỏi chưa hỏi + câu chào ra về; chọn bằng 1–4 hoặc bấm chuột, E / Space để hiện hết chữ, Esc để thôi.
- **Xưng hô** (`_kin`): người chơi gọi NPC theo chữ đầu tên hiển thị (cụ, ông, bà, bác, chú, cô,
  thím, anh, chị); cụ ông / cụ bà tự xưng ông / bà; người lớn gọi người chơi "cháu", anh / chị gọi
  "em"; trẻ con xưng "em" và gọi người chơi anh / chị (`player_female`). Lời thoại viết với chỗ
  trống `{self}` `{you}` `{npc}` `{me}` `{a}` (" ạ" khi nói với người lớn), viết hoa `{Self}`…
- **Nội dung theo ngữ cảnh:** chào theo giờ / vai trò / đồng phục / đã gặp chưa; "đang làm gì"
  theo `v.activity`; câu riêng từng vai (lúa – nông dân, chợ phiên – người gánh hàng, chuyện làng
  ngày xưa `LORE` – cụ già, đá bóng / đi học – trẻ con, con trâu – trẻ chăn trâu); thời tiết;
  nhà ở đâu (`v.home.name`); khoe giỏ cá (khi `Fishing._total > 0`); tỉ số trận bóng.
- **Câu ngắn trên đầu (bark):** con vật (gâu gâu, ò ọ, cục tác, cạp cạp) và người đang đá bóng
  chỉ nói một câu `Label3D` vài giây, không mở khung thoại.
- `tools/talk_test.gd -- --hour=17 --weather=cloudy` in hội thoại mẫu với mỗi loại người / con vật
  để đọc lại lời lẽ. Chụp ảnh: `--fp --talk --talk-pick=N` (bắt chuyện người gần nhất).

## 20. Dân làng nhờ việc (giai đoạn 3c)

- `scripts/quests.gd` (node `Quests`). Luôn có `max_offers` (5) người có việc muốn nhờ — dấu "!"
  vàng trên đầu (`Label3D` tên `QuestMark`, meta `quest_offer`), làm mới mỗi `offer_refresh` giây.
  Nói chuyện → "{Npc} có cần {me} giúp gì không{a}?" → họ kể việc → "Vâng / Được, để {me} giúp"
  hoặc "Để lúc khác". Tối đa `max_active` (3) việc cùng lúc.
- **5 loại việc** (`make_quest`, `KINDS_BY_ROLE`): `water` (múc nước ở giếng làng → gánh về
  `home.front` người nhờ, đi chậm `carry_speed`), `message` (nhắn một người lớn khác, `MESSAGES`),
  `fish` (câu đúng loài — lấy từ `Fishing.basket`, đưa cá thì bỏ khỏi giỏ), `lost` (đồ đánh rơi
  `LOST_ITEMS` nằm cách một chỗ quen 2–5 m: gốc đa, bờ ao, sân đình, giếng, sân bóng, bến sông;
  dấu chỉ đường chỉ khoanh vùng "quanh đây"), `goal` (trẻ con thách sút vào lưới — tín hiệu
  `Football.goal_scored(team, by_player)`, `_player_touch` = người nhập vai chạm bóng cuối).
  Bước cuối luôn là quay lại báo người nhờ → nhận quà (`GIFTS` theo vai) vào `gifts`.
- **Bước** (`steps`): `pickup` (vùng bấm lớp 2 + meta `activate`, nhập vai nhìn vào là "E: Múc
  nước / Nhặt …"), `goto` (tới gần `arrive_radius`, chỉ tính khi đang nhập vai), `talk` (Dialogue
  thêm câu riêng lên đầu danh sách — `Quests.dialog_options(v)`), `catch`, `goal`. Người cần gặp
  đang trong nhà: tới trước cổng thì họ ra (`Villagers.call_out`).
- **Chỉ đường:** hình thoi vàng xoay trên mục tiêu (vẽ đè, phóng to theo khoảng cách) + số mét
  (`Label3D` `fixed_size`); khung "Việc được nhờ" bên phải: từng việc, bước hiện tại, hướng
  (phía trước / bên trái / bên phải / phía sau) và khoảng cách; đồ đang cầm; quà đã nhận.
- Dialogue hỗ trợ lựa chọn có bước con: option có `next` (Callable trả về danh sách lựa chọn).
- `tools/quest_test.gd` chạy trọn 5 loại việc (nhận qua hội thoại → làm → báo → quà).
  Chụp ảnh: `--fp --quest=water,message,lost` nhận sẵn việc từ người gần nhất có vai hợp.

## 21. Đi bộ bên trong các công trình (giai đoạn 3d)

- Khi đang nhập vai, nhìn vào cửa (nhà mình, 41 nhà làng, đình, chùa, lớp học) và nhấn E: vẫn
  chuyển cảnh mờ đen như mục 10, nhưng `HouseEntry.walk_inside = true` → `Interior.walk_mode = true`
  và người chơi đứng ngay sau ô cửa (`Interior.entry_point`), đi bộ tự do bên trong.
- **Nội thất kiểu đi bộ** (`Interior.walk_mode`): tường trước đủ cao gồm phần dưới bậu, dải cửa sổ
  song gỗ (`window_sill` … `window_top`), phần trên và lanh tô trên ô cửa (`door_height`); cột hiên,
  cánh cửa bức bàn / cửa son đủ chiều cao (tạm đặt `front_wall_cut = _h`, `column_cut = _h - 0.14`
  lúc dựng rồi trả lại); trần mái (`_build_ceiling`: khối mái hai dốc úp trên đỉnh tường + xà, rui;
  lớp học là trần phẳng). Đèn phụ `DaylightFill` (nhóm `day_fill`, DayNight tắt dần khi tối / âm u)
  để trong nhà có mái không tối om ban ngày. Kiểu nhà búp bê (mục 10) giữ nguyên khi không nhập vai.
- **Va chạm trong nhà:** `FirstPerson._build_colliders_for(interior)` sau mỗi lần dựng nội thất
  (tường, cột, đồ đạc, nền); nội thất bị xoá thì va chạm đi theo.
- **Ra sân:** bước ra khỏi nền nhà (`Interior.is_outside`), `Esc`, hoặc nhìn ô cửa "E: Ra sân" →
  chuyển cảnh, về đúng chỗ đứng trước cửa lúc vào (`_outside_spot`), quay lưng lại cửa.
- **Phím V trong nhà:** đang đi bộ → xem kiểu nhà búp bê (`_to_dollhouse`, dựng lại nội thất bỏ
  mái); đang xem nhà búp bê → xuống đi bộ (`_dollhouse_to_walk`). HUD có dòng phím riêng
  (`SHORTCUTS_FP_IN`), nút "Ra sân" ẩn khi đi bộ (chuột bị giữ).
- `HouseEntry._apply_state` không bật camera nhà búp bê khi `walk_inside` — `FirstPerson` tự lấy
  camera ở `inside_changed(true)`.
- Chụp ảnh: `--enter=<khoá> --fp [--fp-pitch=…]`. `tools/fp_test.gd` bước 6: vào nhà mình bằng E,
  đi thẳng vào (đồ đạc chặn), V ↔ nhà búp bê, đi ra cửa về sân, vào lại rồi Esc.

## 22. Dân làng ở trong nhà (giai đoạn 3e)

- `scripts/indoor_folk.gd` (node `IndoorFolk`). Khi đang ở trong một toà (nhà búp bê hay đi bộ),
  những người theo lịch đang ở đó hiện ra ở các chỗ `Interior.seats` và làm việc của họ:
  - **nhà ở:** người nhà có `home.key` trùng toà và `state == INSIDE`;
  - **chùa:** việc `pagoda` đã tới nơi;
  - **đình:** việc `dinh` (người lớn);
  - **lớp học:** việc `school` (trẻ con ngồi bàn).
- **Bản sao:** mỗi người trong nhà là một `Villager` mới dựng từ `v._look` (bỏ nón lá, không cầm đồ;
  học sinh mặc đồng phục), meta `proxy_of` = người thật. Người thật vẫn theo lịch ngoài làng: rời nhà
  thì bản sao đứng dậy đi ra cửa rồi biến mất; về tới nhà thì bản sao bước vào cửa, đi tới chỗ trống.
  Vào nhà lần đầu thì mọi người đã ngồi sẵn. Đồng bộ mỗi `sync_interval` giây.
- **Chỗ** (`Interior._seat(pos, pose, act, tags, face)`): bàn trà (`tea`), thắp hương bàn thờ
  (`pray`, cụ già), mép giường / chõng (`sit`), giường / phản ban đêm (`sleep`, tag `night` —
  nằm ngửa bằng cách xoay node −90° quanh X), khung cửi (`weave`, phụ nữ), cối xay (`work`), góc học
  và bàn lớp học (`study`, trẻ con), bồ đoàn chùa / chiếu hội đình (`kneel`), hương án đình (`pray`).
  `_pick_seat` chấm điểm theo giờ (21h–5h30 ưu tiên chỗ ngủ ở nhà ở) và tag hợp vai.
- **Dáng mới** trong `Villager._animate`: `tea` (thỉnh thoảng nâng chén), `weave` (đưa thoi),
  `study` (cúi viết), `kneel` (quỳ: đùi thẳng, ống chân sát nền, chắp tay cúi lạy), `pray` (đứng
  chắp tay vái), `work` (đẩy tay cối xay), `sleep` (nằm thẳng, thở chậm).
- **Người trông giữ thường trực** (5h–21h): **sư cụ** ở chùa (áo nâu sồng, đầu cạo — look `bald`,
  `soft_head(..., bald)`), quỳ tụng kinh ở bồ đoàn chính giữa; **ông thủ từ** đứng vái hương án đình.
  Không có người thật tương ứng. Sư cụ xưng "thầy", gọi người chơi "con" (`Dialogue._kin`, chữ "sư").
- **Hội thoại:** `Dialogue._real(v)` đổi bản sao → người thật để nhớ đã gặp và tính việc nhờ.
  Ở nhà: chào "Ơ, cháu sang chơi đấy à? Vào đây ngồi uống nước chè."; trả lời theo việc `home_*`,
  `pagoda_pray`, `dinh_meet`, `class`, `monk_chant`, `dinh_keep`. Người đang ngủ chỉ lầm bầm (bark).
- `Interior.entry_point` lùi sát ngưỡng cửa (`exit_z - 0.48`) để không đứng chồng lên bàn trà.
  Công cụ chụp ảnh giờ lên lại lịch (`replan`) TRƯỚC khi vào nhà để người trong nhà khớp giờ chụp.
- `tools/indoor_test.gd -- --enter=house_9 --hour=12 --seconds=45` chạy thời gian thật, in ai đang
  ở trong, tư thế, ai vào / ra, rồi thử nói chuyện với một người.

## 23. Bản đồ nhỏ (giai đoạn 3f)

- `scripts/minimap.gd` (`MiniMap`, node `Control` con của `HUD` — `H` ẩn HUD thì ẩn luôn bản đồ).
  Vẽ bằng `_draw()` từ dữ liệu thật, không chụp ảnh từ trên: ruộng (`Terrain.outer_fields`,
  `field_rect`), sân + đường đất + ao nhà mình, sông (`River._pts`, vẽ đê rồi nước), nền làng + lũy tre
  (elip `Village.center/radii`), lô đất (`Village._occupied`), đường trục / ngõ / lối ra sông, nhà làng
  (khối mái sau cửa `homes[i].door`, xoay theo `forward`), đình, chùa, ao làng, giếng, cây đa,
  sân bóng (`pitch_rect`), trường (`School.site`), nhà mình (`House`), bến sông. Hướng bắc ở trên (−z).
- **Ký hiệu:** mũi tên đỏ = người nhập vai (theo `rotation.y`); hình quạt + chấm đỏ = vùng camera
  ngắm cảnh (theo `yaw_deg`); trong nhà thì chấm ở cửa toà đang vào. Chấm trắng người lớn, vàng trẻ
  con, xám trâu; "!" người có việc nhờ; hình thoi vàng mục tiêu việc đang làm (`Quests._target_pos`),
  ra ngoài khung thì ghim ở mép theo hướng. La bàn "B", thước tỉ lệ.
- **Phím M:** nhỏ (`small_size` 230 px, bán kính `small_radius` 75 m quanh người chơi, góc dưới
  phải trên dải phím tắt) → lớn (giữa màn hình, cả làng `large_center` / `large_radius`, có tên chỗ)
  → ẩn. Bấm vào bản đồ ở chế độ ngắm cảnh: camera bay tới đó. Vẽ lại mỗi `redraw_interval` giây.
- Chụp ảnh: `--map=small|large|hidden`.

## 24. Đò trên sông (giai đoạn 3g, 3h)

- `scripts/boat_ride.gd` (node `BoatRide`, con cuối của `Main` để nhận phím trước `FirstPerson`).
  3 con đò của `River` là node riêng (`River.boat_nodes`, nhóm `boat`, mũi đò hướng +z cục bộ).
- **Đò to, đi bộ lên được:** dài ~9,6 m, rộng `boat_beam` 2,2 m; sàn ván ở `River.BOAT_DECK`
  (0,52 cục bộ, mặt nước 0,15); mạn đò có khe ở `BOAT_GAP_Z` hai bên, ngoài khe có bậc gỗ
  (`BOAT_STEP`) để từ dưới nước trèo lên (mỗi bậc ≤ `step_height`); mui tre đan `BOAT_CABIN`
  (z −0,6…2,6) có vách, ô cửa sổ, vòm cong hai mặt (ngoài sẫm, trong sáng), cao ~1,9 m đứng thẳng
  được; trong mui có chiếu, gối, bếp lò + nồi, chum, giỏ, lưới; cọc chèo ở đuôi.
  Con của mỗi đò: `Hull`, `Pole` (mái chèo dựa cọc — ẩn khi đang chèo), `Solid` (StaticBody lớp 4:
  hộp sàn, hai đầu, mạn chừa khe, vách + mái mui, bếp, chum, cọc), `ClickTarget` (hộp cả con đò,
  "Lên đò"; viền sáng là khung phẳng trên mặt nước), `OarTarget` ("Cầm chèo"), `Plank` (ván cầu),
  `Lantern` + `BoatLantern` (đèn bão đầu mui, `night_light`). `FirstPerson` không dựng va chạm từ
  mesh đò (bỏ qua nhóm `boat`) vì đã có `Solid` đi theo đò.
- **Ván cầu** (`BoatRide.deploy_plank`): khi neo, nếu mạn đò (chỗ khe) cách mép nước dưới
  `plank_reach` thì bắc ván từ khe lên mặt đê (cách mép 2 m) phía bờ gần hơn; xa bờ thì cất ván.
  Ván là mesh + hộp va chạm dựng lại mỗi lần neo.
- **Nhập vai:** đi qua ván lên đò, hoặc nhìn đò từ bờ "E: Lên đò" (`step_aboard` — đặt ngay lên
  sàn chỗ khe). Đứng trên đò thì mắt nằm trong hộp `ClickTarget` nên tia nhìn bỏ qua nó (không
  hit_from_inside). Tới đuôi nhìn cọc chèo "E: Cầm chèo" → `board(i)` (`FirstPerson._suspend("boat")`).
  Ngắm cảnh: bấm vào đò là chèo luôn.
- Khi chèo: người chèo (Villager dựng riêng, nón lá, dáng `work`) đứng ở đuôi, mái chèo quạt theo
  nhịp; ván cất đi. `HouseEntry.locked`, `CameraRig.active = false`; tâm `CameraRig` bám theo đò để
  mưa, cá nhảy, dân làng vẫn diễn ra quanh đò. V / F / P bị chặn khi đang chèo.
- **Chèo:** W / S tới / lùi (`max_speed`, `reverse_speed`, `accel`, `drag`), A / D rẽ (đứng yên
  vẫn xoay được — `turn_still`, đang đi — `turn_moving`), Shift chèo nhanh (`fast_speed`). Dòng sông
  trôi nhẹ theo tiếp tuyến (`current`). Đò nhấp nhô, nghiêng khi rẽ, gợn nước (`River.splash`) sau đuôi.
  Hàm `step(delta, throttle, steer, fast)` tách riêng để bài thử / công cụ chụp ảnh gọi.
- **Giữ trong sông:** chiếu vị trí lên tim sông (`nearest_s` / `sample` / `half_width`), ra quá
  `half_width - bank_margin` thì đẩy về; chỉ mất đà theo mức mũi đò đâm vào bờ (chạy dọc bờ thì
  trượt tiếp — đò neo sát bờ hơn `bank_margin`, nếu giảm tốc mỗi khung thì không chèo đi được).
  Hai đầu sông: triệt phần đi quá điểm cuối, KHÔNG giảm tốc (dòng chảy luôn đẩy về đầu sông).
- **Camera:** `Camera3D` riêng bám sau đò; chuột phải kéo để xoay, lăn chuột zoom (`cam_min`…`cam_max`).
- **Thôi chèo:** E / Esc → đò neo tại chỗ, bắc ván nếu sát bờ. Từ nhập vai thì đứng ở đuôi đò nhìn
  về mũi, đi lại tiếp (xa bờ thì lội xuống sông, trèo lên lại bằng bậc mạn). Từ ngắm cảnh thì camera
  ngắm cảnh đặt tâm vào đò.
- HUD: `Hud.set_boat(on)` — dòng phím `SHORTCUTS_BOAT`, chỗ "Trên đò". Bản đồ nhỏ vẽ các đò (thoi
  gỗ theo hướng mũi) và mũi tên đỏ theo đò khi đang chèo (`BoatRide.heading_for_map`).
- `tools/boat_test.gd` (headless): đi qua ván lên đò, vào mui, cầm chèo, chèo tới / rẽ / lùi (luôn
  cách mép ≥ `bank_margin`), thôi chèo giữa sông (không ván), lội xuống rồi trèo bậc mạn, chèo sát bờ
  (có ván), nhìn đò từ bờ "E: Lên đò", bấm đò từ ngắm cảnh.
  Chụp ảnh: `--boat=N [--boat-drive=giây] [--boat-cam=độ]`; đứng trên đò:
  `--fp --fp-board=N [--fp-at=x,z] [--fp-yaw=độ]` (toạ độ, hướng tính theo đò).
