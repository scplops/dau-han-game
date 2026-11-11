# Làng Quê Việt — Demo cảnh quan 2.5D low-poly

> File hướng dẫn cho Claude Code. Đặt file này ở thư mục gốc của dự án Godot.
> Mục tiêu giai đoạn này: **chỉ dựng cảnh quan để ngắm**, CHƯA có gameplay
> (không di chuyển nhân vật, không túi đồ, không nhiệm vụ).
> Ngoại lệ: **vào/ra các toà nhà bằng cách bấm cửa** (mục 10), **dân làng tự đi lại** (mục 13),
> mini-game câu cá (mục 16), sân bóng — người chơi vào đá được (mục 17), **nhập vai góc nhìn thứ nhất** (mục 18, phím `V`)
> **trò chuyện với dân làng** (mục 19), **dân làng nhờ việc** (mục 20), **lên đò, chèo đò trên sông** (mục 24)
> và **trò chơi dân gian** (mục 27: ô ăn quan, mục 28: trốn tìm, mục 29: đua thuyền rồng / thuyền đơn có chướng ngại, mục 30: thả diều, mục 31: nhảy dây, mục 32: đánh khăng, mục 43: kéo co, mục 44: đá cầu / bắn bi / chơi chuyền / bịt mắt bắt dê / rồng rắn lên mây), **mùa vụ lúa** (mục 33: cày → cấy → gặt, ~3 tháng một vụ), nhà 2 tầng có cầu thang lên gác (mục 35), dân làng tự chơi trò dân gian (mục 36), lưu game (mục 37), âm thanh tổng hợp bằng code (mục 38), sổ tay người chơi (mục 39), chợ phiên mua bán (mục 40), lễ hội theo lịch âm (mục 41), bốn mùa (mục 42), **túi đồ + tiền** (mục 48, phím `I`).

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
     (1 ngày = 15 phút, `day_length_seconds`). Mặc định khởi động lúc **17:00**.
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
   `toggle_minimap` (M), `day_back` / `day_forward` (`,` / `.` — lùi / tiến một ngày),
   `fb_shoot` (chuột trái / J), `fb_pass` (chuột phải / K), `fb_call` (Q) — khi đang đá bóng),
   `save_game` (F5), `new_game` (Ctrl+F5), `toggle_sound` (N), `toggle_notebook` (B), `cycle_quality` (G — mức đồ hoạ),
   `toggle_inventory` (I — túi đồ),
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
    market.gd          # chợ phiên ngoài cổng làng: lều, hàng, người bán, mua bán, biếu quà (mục 40)
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
  lunar_calendar.gd    # lịch Việt Nam: dương lịch, thứ, âm lịch, can chi, ngày lễ (mục 25)
  school_day.gd        # thời khoá biểu, học sinh làng bên, vào lớp / ra chơi / chào cờ (mục 26)
  o_an_quan.gd         # trò chơi dân gian ô ăn quan với dân làng (mục 27)
  hide_seek.gd         # trò chơi dân gian trốn tìm với trẻ con trong làng (mục 28)
  boat_race.gd         # trò chơi dân gian đua thuyền trên sông (mục 29)
  kite.gd              # trò chơi dân gian thả diều, mượn diều của trẻ con (mục 30)
  jump_rope.gd         # trò chơi dân gian nhảy dây: trẻ con tự chơi, người chơi vào nhảy (mục 31)
  tip_cat.gd           # trò chơi dân gian đánh khăng: trẻ con tự chơi, người chơi vào đánh (mục 32)
  tug_war.gd           # trò chơi dân gian kéo co: dân làng tự kéo, người chơi vào kéo theo nhịp hò (mục 43)
  folk_games.gd        # năm trò dân gian nhỏ: đá cầu, bắn bi, chơi chuyền, bịt mắt bắt dê, rồng rắn lên mây (mục 44)
  graphics.gd          # chất lượng đồ hoạ: trời, SSAO, glow, sương thể tích, vân bề mặt; 3 mức, phím G (mục 47)
  game_kit.gd          # đồ dùng chung của các trò chơi: hình nhân, khung giao diện, nhãn chữ (mục 46)
  soundscape.gd        # âm thanh tổng hợp bằng code: gió, mưa, dế, ếch, sông, gà, trống, chuông, sấm (mục 38)
  notebook.gd          # sổ tay người chơi: kỷ lục, sổ câu, người quen, quà & việc, làng hôm nay (mục 39)
  inventory.gd         # túi đồ + tiền: danh mục vật phẩm, ăn / mồi / diều / sáo, biếu quà, màn hình phím I (mục 48)
  festival.gd          # lễ hội theo lịch âm: Tết, rằm tháng Giêng, Trung thu rước đèn (mục 41)
  seasons.gd           # bốn mùa: màu lá, hoa phượng, thời tiết theo mùa, lá rụng, ve kêu (mục 42)
  save_game.gd         # lưu / mở lại game: ngày giờ, sổ câu, quà, người quen, kỷ lục (mục 37)
  farming.gd           # mùa vụ lúa theo lịch: cày bừa, cấy, lúa lên, trổ, chín, gặt, phơi thóc (mục 33)
                       # (interior.gd có thêm kiểu đi bộ bên trong cho nhập vai — mục 21)
shaders/
  wind_sway.gdshader
  water.gdshader       # nước low-poly, viền sáng bằng màu đỉnh (không cần depth texture)
  sky.gdshader         # bầu trời: dải màu theo giờ, quầng + đĩa mặt trời / trăng, sao, mây ti (mục 47)
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
  việc nhờ, chèo đò, trò chơi dân gian, chợ phiên, lễ hội, túi đồ + tiền); chế tạo / nấu ăn để giai đoạn sau.
- Dùng Git: commit sau mỗi bước hoàn thành, message rõ ràng
  (ví dụ: `step 4: add tiled-roof house`).

## 9. Ngoài phạm vi (để giai đoạn sau)

Người chơi tự trồng trọt (mùa vụ của làng đã có — mục 33), làm thuê mùa vụ lấy tiền công, nấu ăn / chế tạo đồ, nhạc nền (tiếng động, mưa, sấm đã có — mục 38),
thay mesh procedural bằng model Blender.

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
- **Mọi toà đều vào được** (nhà mình, 60 nhà làng, đình, chùa): cửa tạo bằng
  `HouseEntry.make_entry_target(parent, xform, size, hint, spec, key)`. `spec` là thông số
  nội thất; `Interior.load_spec(spec)` xoá nội thất cũ và dựng lại lúc màn hình tối, nên chỉ
  có MỘT nội thất tồn tại tại một thời điểm (không tốn FPS ngoài làng). Khoá: `main`, `dinh`,
  `pagoda`, `house_0`…`house_59`; chụp ảnh bằng `--enter=<khoá>`.
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
  trong elip `Village.center` (0, −115), bán kính (122, 80) — mép nam vẫn ở z −35 (cổng làng), 6 ngõ
  (`alley_z` −52…−152), 60 nhà (mục 34). Đất làng phẳng (y = 0) do
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
- **Lối đi trước cửa chính** (`VillageHouse.door_lane_half`, `build_house` trả về `door_x`): nhà phụ
  (chữ L / U) và bếp riêng không được lấn vào dải ±1 m thẳng trước cửa — đẩy ra ngoài, chạm rào thì
  thu hẹp, hẹp quá thì bỏ nếp đó. (Đã gặp: nhà 2 gian bố cục chữ L / U, nhà ngang đứng chắn ngay cửa,
  nhập vai không đi tới cửa được.)
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
  Dân làng sinh theo **hộ** (mục 34): mỗi nhà làng 3–4 người — 60 hộ ≈ 207 người (bố nông dân vác cuốc,
  mẹ làm ruộng / gánh hàng, ông / bà chống gậy, con: trẻ con / trẻ chăn trâu) — và ~75 con vật (trâu theo
  trẻ chăn, 10 chó theo chủ, 12 sân gà × 4, 6 vịt bơi nối đuôi ở ao làng). Số lượng chỉnh bằng `@export`. Dân số sinh theo `random_seed` cố định.
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
- **Người đã vào nhà (ẩn) không có vùng bấm:** `Villager._sync_click_body` theo `visibility_changed`
  tắt lớp va chạm 3 khi ẩn (không thì người vô hình đứng ở cửa chặn tia nhìn, không vào nhà được).
- **Xem tin:** bấm chuột trái vào người/vật (lớp va chạm 3) → vòng sáng dưới chân + khung
  thông tin góc trên phải (tên, vai trò, nhà, việc đang làm); `F` cho camera đi theo.
- **Hình người "mềm"** (`Villager._build_person_rig`): hông → đùi → khớp gối (`knees`) → ống chân
  + bàn chân; vai → bắp tay → khớp khuỷu (`elbows`) → cẳng tay + bàn tay; hông, thân dẹt, cổ, đầu
  dùng chung `Villager.soft_head()` (tai, chỏm tóc, búi tóc cho phụ nữ, mắt, lông mày, má hồng) —
  người câu cá (`Fishing`) và tượng nông dân (`Characters`) cũng dùng hàm này. Dáng đi: gối co khi
  chân đưa lên, thân lắc / xoay nhẹ theo bước, khuỷu hơi gập (tay cầm đồ thì thẳng), thở khi đứng
  yên, ngồi thì gập gối (hông hạ đúng một đoạn đùi). Mỗi người ~2.100 tam giác (207 người ~430 nghìn, phần lớn khuất / ở trong nhà / quá `visibility_range_end`).
  Bộ đồ (`_outfits`) lưu cả `knees` / `elbows`.
- **Hiệu năng:** mesh từng bộ phận dùng chung qua bộ đệm; chỉ diễn hoạt NPC trong
  `animate_distance` quanh camera; mỗi phần có `visibility_range_end`.
- Chụp ảnh: `--npc=<chỉ số|vai trò>` chọn NPC và cho camera đi theo.

## 14. Sông quanh làng (giai đoạn 1f)

- `scripts/builders/river.gd` (node `World/River`, dựng sau `Village`). Sông hình móng ngựa
  ôm ba mặt làng (tây → bắc → đông) theo elip của làng nới ra `offset_radii` (152, 108), uốn
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
- Trẻ con trong làng đi học theo thời khoá biểu của `SchoolDay` (mục 26): đi theo đường đất vào cổng,
  giờ học vào lớp, giờ ra chơi ra sân. Cửa sổ trường sáng nhẹ ban đêm (`night_glow`).
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
  sinh lại ở đoạn xa. Sổ câu (số con, con nặng nhất từng loài) được lưu lại (mục 37).
- **Giờ & thời tiết:** cá ăn mạnh lúc sáng sớm và chiều muộn, kém buổi trưa, rất kém ban đêm;
  mưa phùn cá ăn hơn; mưa giông thì không câu được (đang câu thì tự thu cần về).
  Ban đêm đèn bão cạnh chỗ ngồi tự sáng (nhóm `night_light`).
- **Câu trên đò** (giai đoạn 3i): mỗi đò có một chỗ câu ở mũi, sau mui (`Fishing._make_boat_spot`,
  node `FishSpot` là con của đò, toạ độ `BOAT_SEAT_X/Z`): ghế đẩu, cần tre dựng sẵn, giỏ cá, vùng bấm
  `FishTarget` ("Ngồi câu cá · Đò N"). Chỉ số chỗ câu: 0…2 là bến, 3 trở đi là đò. Lúc ngồi xuống
  `_orient_boat_spot` xoay chỗ câu về mạn phía lòng sông. Hướng ngồi lấy từ node (`_face(i)` =
  `global_rotation.y`), nên đò đã chèo đi chỗ khác vẫn câu đúng hướng. Đang chèo thì không ngồi câu
  (BoatRide tắt `FishSpot/FishTarget`). Nhập vai: đứng ở mũi đò nhìn cần câu "E: ngồi câu cá";
  thôi câu thì đứng lại trên đò.
- Chụp ảnh: `--fish=<chỉ số bến>` vào câu, `--fish-state=charge|wait|nibble|bite|reel|caught`
  dựng sẵn trạng thái để kiểm tra giao diện. `tools/fish_test.gd` chơi thử tự động (headless), in
  diễn biến từng lượt câu.
- **Cá giữ vị trí riêng** (`_fish[i].pos`): renderer headless không lưu transform MultiMesh,
  nên không đọc ngược vị trí cá từ MultiMesh.

## 17. Sân bóng làng (giai đoạn 2b)

- `scripts/builders/football.gd` (node `World/Football`, đứng SAU `Villagers` để điều khiển
  cầu thủ sau khi Villagers tick xong mỗi khung). Sân 30 × 18 m ở `Village.pitch_rect`
  (x −64…−34, z −176…−158): góc tây bắc làng, sau ngõ cuối, cạnh lối ra sông phía bắc.
  `Village._reserved` và vườn tạp né vùng này.
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
- **Luật** (giai đoạn 5e, `Phase`: KICKOFF, PLAY, GOAL, RESTART, HALFTIME, FULLTIME): trận `match_length` chia
  **2 hiệp**, nghỉ `halftime_seconds` rồi **đổi sân** (`half`, `_attack_dir` đảo dấu ở hiệp 2 — bàn thắng tính theo
  đội tấn công về phía khung thành đó, không theo đầu sân); hiệp 2 đội kia giao bóng. Giao bóng: đội không giao đứng
  ngoài vòng tròn giữa sân. Bóng ra ngoài (`_ball_out`, theo `_last_team` — đội chạm cuối): qua biên dọc → **ném
  biên** cho đội kia tại chỗ bóng ra; qua vạch cuối → đội nhà chạm cuối thì **phạt góc**, đội tấn công chạm cuối
  thì **phát bóng lên** (thủ môn đá). Tranh bóng khi đối phương đang giữ bóng (trong 1 m) có `foul_chance` thành
  **phạm lỗi** → **đá phạt** tại chỗ; phạm lỗi trong vòng cấm nhà (3 × 7 m) → **phạt đền** ở chấm 5 m: thủ môn về
  giữa khung, mọi người ra sau vạch chờ cách chấm 4 m (`_line_up_penalty`), cản hay không quyết định lúc sút
  (`_decide_penalty_save`: `penalty_save`, sút càng sát cột càng khó cản, không có thủ môn thì rất khó cản) và 0,7 s
  sau cú sút không ai được chạm bóng (không thì thủ môn chạy ra đá bóng như lúc chơi thường — đã gặp: 4/6 quả
  "bị cản" ngoài ý muốn). **Đá lại** (`_restart`: kind, team, pos, taker, placed): chờ `restart_delay`, đặt bóng,
  bóng nằm yên; người đá (`_pick_taker`, chọn SAU khi đã có `pos`) chạy tới rồi đá; đối phương cách 3 m (đá phạt 4 m),
  ai ở xa chỗ đứng > 1 m thì chạy. Hết giờ: bảng "Hết giờ! … thắng / Hoà" 6 s rồi tản đi. Trọng tài hô bằng chữ
  trên sân (`_call_label`) + dòng vàng trên bảng tỉ số. Đá làng không có việt vị. `stats` đếm từng loại.
- **Người nhập vai vào đá** (`user_team`, không nằm trong `players`): đứng trên sân / mép sân (không nhìn vào gì) →
  "E: Xin vào đá bóng" (`join_hint`, `FirstPerson._update_look` / `_act` → `join_user`) → vào đội ít người hơn; ít
  hơn 5 người máy thì gọi trẻ con / đàn ông đang rảnh trong 170 m ra sân (`_gather` → `Villagers._next_activity(v,
  "football")`; tối / giông thì không gọi được — tập sút một mình). Phím mới trong Input Map: `fb_shoot` (chuột trái
  / J — giữ lấy lực `user_charge_time`, thả để sút `user_shot_speed`, nhìn lên thì bóng bổng; ném biên thì ném bằng
  tay), `fb_pass` (chuột phải / K — chuyền cho đồng đội gần hướng nhìn nhất), `fb_call` (Q — "Chuyền đây!": đồng đội
  có bóng chuyền tới trước chân người chơi nếu người chơi không bị kèm). Chỉ chạm bóng trong `user_reach`; lúc chờ
  đá lại chỉ người được giao (người chơi được ưu tiên nếu gần ngang người máy, phạt đền thì luôn là người chơi).
  Máy coi người chơi như cầu thủ: đồng đội không tranh bóng khi người chơi gần bóng hơn, chuyền cho người chơi, đối
  phương lách / tranh bóng / phạm lỗi với người chơi. Người chơi chạy (> 4,2 m/s) xô vào đối phương đang giữ bóng là
  phạm lỗi. Rời đội: thôi nhập vai, làm việc khác, ra xa sân 8 m. Bảng tỉ số riêng (trên giữa màn hình): tỉ số,
  hiệp, đồng hồ, đội của bạn, khung thành đối phương ở phía nào (so với hướng nhìn), việc cần làm, thanh lực sút.
- `tools/football_join_test.gd`: 7 tình huống luật (ném biên, phạt góc, phát bóng lên do thủ môn, đá phạt, phạt
  đền ở chấm 5 m, bàn hiệp 2 đúng đội); một trận máy đấu máy (thường 4–9 bàn, ~5 ném biên, 2–4 phát bóng lên, 1–5
  phạt góc, 1–5 phạm lỗi, có nghỉ giữa hiệp, hết giờ, tản đi); người nhập vai xin vào → gọi người → sút (~20 lần
  chạm, vài bàn) → gọi chuyền → ném biên → 6 quả phạt đền → thôi nhập vai thì rời đội.
- Chụp ảnh: `--football=<số người>` đưa người ra sân đá ngay (chạy trước 6 s), camera nhìn vào
  sân; `--fp --focus=-47,-145 --fb-join=N [--fb-restart=throw|corner|free|penalty]` vào đá cùng N người. `tools/football_test.gd -- --players=12 --seconds=240` mô phỏng một trận không giao diện,
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
- **Rủ chơi trò dân gian** (`game_options(v)`: thả diều, nhảy dây, đánh khăng, trốn tìm — trẻ con; ô ăn quan — cả người lớn): khung
  chỉ hiện 3 câu, nên người rủ được từ 2 trò trở lên thì gom thành MỘT câu "Chơi gì không em?" (key `games`,
  `repeat` — không đánh dấu đã hỏi) → chọn trò ở bước sau. (Đẩy từng câu rủ lên đầu danh sách thì trò thêm sau
  đẩy trò trước ra ngoài — đã gặp: câu rủ ô ăn quan biến mất khi có nhảy dây.) Bài thử tìm câu rủ qua
  `_game_option(dlg, key)`.
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

- Khi đang nhập vai, nhìn vào cửa (nhà mình, 60 nhà làng, đình, chùa, lớp học) và nhấn E: vẫn
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
- **Lớp học:** cửa trong mở vào lối đi giữa dãy bàn bên phải và tường hồi; dãy bàn chừa ~1,5 m
  trước cửa (đặt cửa giữa dãy bàn thì vào là kẹt trong bàn ghế).
- `tools/building_walk_test.gd [-- --only=house_3,dinh]`: kiểm tra MỌI toà (64) — đứng ngoài sân đi
  thẳng tới cửa → "E: vào" → vào; đứng trên nền, không kẹt; đi sâu / trái / phải (quãng đi được, xuyên
  tường, rơi khỏi nền); đi ra cửa về sân. In một dòng mỗi toà + tổng kết. Dò mặt đất trước cửa từ
  ngang tầm người (dò từ trên cao thì trúng mái hiên).
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
  `Lantern` + `BoatLantern` (đèn bão đầu mui, treo lệch một bên, `night_light`), `FishSpot` (chỗ câu,
  mục 16). `FirstPerson` không dựng va chạm từ
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
  (có ván), nhìn đò từ bờ "E: Lên đò", bấm đò từ ngắm cảnh, ngồi câu trên đò (quay ra lòng sông,
  phao rơi xuống nước), đang chèo thì không câu, rê chuột vào cần câu trên đò.
  `tools/fish_test.gd -- --spot=4` chơi trọn một ván câu trên đò 2.
  Chụp ảnh: `--boat=N [--boat-drive=giây] [--boat-cam=độ]`; đứng trên đò:
  `--fp --fp-board=N [--fp-at=x,z] [--fp-yaw=độ]` (toạ độ, hướng tính theo đò).

## 25. Lịch Việt Nam, lễ đình mùng 1 / rằm (giai đoạn 4a)

- `scripts/lunar_calendar.gd` (`LunarCalendar`, node `Calendar` con của `Main`). Ngày lưu bằng số ngày
  Julius `jd`; mặc định lấy ngày hôm nay của máy (`use_system_date`, tắt thì dùng `start_date`).
  Đặt ngày trong `_enter_tree` (trước `_ready` của `World`) để Villagers lên lịch đã có ngày.
- **Âm lịch** theo thuật toán của Hồ Ngọc Đức (`solar_to_lunar`, `new_moon_day`, `sun_longitude`,
  `lunar_month11`, `leap_month_offset`), múi giờ +7, có tháng nhuận; năm can chi `can_chi_year`.
  `tools/calendar_test.gd` đối chiếu 12 ngày đã biết (Tết 2024–2027, Trung thu, tháng 2 nhuận 2023,
  tháng 6 nhuận 2025…).
- **Sang ngày:** `DayNight.day_rolled(days)` phát khi `time_of_day` qua nửa đêm (tiến hoặc lùi) →
  `add_days`. Phím `,` / `.` lùi / tiến một ngày. HUD có dòng ngày dưới giờ (`date_text`: "Thứ Năm
  5/11/2026 · Âm lịch 27/9 Bính Ngọ"), ngày lễ (`holiday_name`: Tết, rằm tháng Giêng, Giỗ Tổ, Đoan
  ngọ, rằm tháng Bảy, Trung thu, ông Táo, mùng một, rằm) tô vàng.
- **Đi lễ đình** (`is_worship_day`: mùng 1, rằm): `Villagers.worship_weight` — người lớn (cụ già nhiều
  nhất) đi lễ trong `worship_morning` (5:30–9:30) và `worship_evening` (16:30–19:00), mỗi buổi một lần
  (meta `worship_done`). Việc `worship`: đi tới chân thềm đình (`Village.dinh_door`), vào trong (ẩn,
  meta `at_dinh`, `worship_minutes` giây thật) rồi bước ra. IndoorFolk cho người `at_dinh` đứng vái
  ở 7 chỗ trước hương án (tag `worship`, act `dinh_worship`).
- **Sân đình ngày lễ** (`Village._build_worship_decor`, nhóm `worship_decor` — Calendar bật / tắt):
  hai hàng cờ hội ngũ sắc (shader gió), đỉnh hương đồng ba chân trước thềm có khói (CPUParticles3D).
- Đường vào sân đình đi vòng hồ bán nguyệt (`Villagers._around_dinh_pond`, `Village.dinh_pond_center/
  radii`) — trước đây người ra đình lội thẳng qua hồ.
- **Hội thoại:** câu hỏi "Hôm nay là ngày bao nhiêu âm lịch?" (`_ans_date`: "rằm tháng Chín năm Bính
  Ngọ", nhắc sắp rằm / mùng một), chào và trả lời "đang làm gì" theo việc `worship`.
- Chụp ảnh: `--date=YYYY-MM-DD`, `--lunar-day=N` (nhảy tới ngày gần nhất có ngày âm N), `--settle=giây`
  (tua nhanh cho dân làng kịp tới nơi).

## 26. Học sinh, thời khoá biểu trường (giai đoạn 4b)

- `scripts/school_day.gd` (`SchoolDay`, node con của `Main`). `phase(h)`: `arrive` 6:24–7:00 /
  13:00–13:30, `class`, `recess` 9:12–9:36 / 14:54–15:15, `leave` 11:00–11:24 / 16:30–16:54,
  thứ Hai 7:00–7:30 `flag` (chào cờ); thứ Bảy chỉ học sáng; `off` ngoài giờ, Chủ nhật, từ 23 tháng
  Chạp tới mùng 7 Tết (`LunarCalendar.is_school_day`).
- **Học sinh làng bên** (`pupil_count` 16 — làng đã đông trẻ con, `pupils`): Villager trẻ con mặc đồng phục, meta `pupil`,
  `class` (0…4 = 5 lớp tầng 1), `spawn` (đầu đường đất phía nam cổng). Đến trường: đi đường đất →
  cổng (`School.gate_out/gate_in`) → sân; tan học thì đi ngược ra và ẩn ở đầu đường.
- **Trẻ con trong làng** (Villagers, việc `school` khi `wants_pupils`): tới trường thì
  `Villagers._arrive` gọi `SchoolDay.on_arrive` — meta `at_school`, dwell rất lớn để Villagers không
  đổi việc; SchoolDay điều khiển tới khi tan học (`_release` trả về Villagers chọn việc tiếp).
- **Giờ học:** đi tới mép sân trước lớp (`School.classroom_fronts`) → cửa lớp (`classroom_doors`) → ẩn,
  meta `in_class`. IndoorFolk (khoá `school`) cho người `in_class` ngồi bàn (12 chỗ) + **cô giáo**
  (người trông giữ, dáng `teach` — tay chỉ lên bảng) đứng ở bục giảng (seat tag `teacher`).
  **Ra chơi:** ùa ra sân, chạy từ chỗ này sang chỗ khác (`_wander`, `School.yard_spots` 26 chỗ).
  **Chào cờ thứ Hai:** mỗi lớp một hàng dọc trước cột cờ (`School.flag_pos`), quay mặt về cột cờ.
- Đổi giờ / ngày đột ngột: `SchoolDay.replan()` đặt ngay mọi học sinh đúng chỗ (công cụ chụp ảnh gọi).
- Hội thoại: học sinh trả lời theo giai đoạn (ra chơi, chào cờ, tan học, được nghỉ); nhà ở "làng bên".
  Bản đồ nhỏ vẽ học sinh làng bên (chấm vàng).
- `tools/school_calendar_test.gd`: thứ Hai 6:12 → 12:00 (đếm học sinh hiện / trong lớp / quanh cột
  cờ, trẻ trong làng ở trường), vào lớp lúc 8:00 (số em ngồi học + cô giáo), Chủ nhật (vắng),
  ngày thường và ngày rằm lúc 7:00 (số người đi lễ, cờ hội, người vái trong đình).

## 27. Trò chơi dân gian: Ô ăn quan (giai đoạn 5a)

- `scripts/o_an_quan.gd` (`OAnQuan`, node con CUỐI của `Main` — nhận Esc trước các phần khác).
  Vào ván qua hội thoại (nhập vai): câu "{Npc} chơi ô ăn quan với {me} không?" (trẻ con, trẻ chăn
  trâu, cụ già, nông dân, người gánh hàng — không phải bản sao trong nhà). `OAnQuan.refusal(v)` cho lời
  từ chối khi người đó đang học, đang dở việc (ra đồng, đi lễ…). Đồng ý → lựa chọn "(Ngồi xuống chơi)"
  (option `end` + `then` Callable — Dialogue gọi sau khi khép khung thoại) → `start(v)`.
- **Bày bàn:** bàn kẻ phấn trên mảnh đất nện (`Board`, top_level) ở giữa người chơi và đối thủ, mặt đất
  dò bằng tia lớp 4; đối thủ ngồi xổm (dáng mới `squat` — gối gập sâu, hông sát đất, tay với ra bàn)
  phía bên kia, meta `talking` + `playing_oaq` (Villagers / SchoolDay đứng yên). Người chơi nhường
  camera (`FirstPerson._suspend("game")`); camera riêng nhìn chéo từ sau lưng người chơi; HUD ẩn, giao
  diện riêng: tên + điểm hai bên, lượt, nút "◀ Rải sang trái (A)" / "Rải sang phải (D) ▶".
- **Luật** (hàm tĩnh thuần dữ liệu: `play`, `refill`, `collect`, `is_over`, `amount`): vòng 12 ô —
  0 quan trái, 1…5 người chơi (trái → phải), 6 quan phải, 7…11 đối thủ. Mỗi ô dân `stones_per_square`
  (5) sỏi, quan `quan_value` (10) điểm. Rải từng viên (qua cả ô quan); ô kế có sỏi → bốc rải tiếp; ô kế
  trống mà ô sau có → ăn, cách một ô trống ăn tiếp; ô kế là ô quan → mất lượt. Luật **quan non**
  (`quan_non` 5): ô quan còn viên quan mà ít hơn 5 sỏi dân thì chưa được ăn. Hàng mình hết sỏi → lấy
  5 viên đã ăn rải lại (`refill`), không đủ thì thua (bên kia thu hết). Hết hai quan → thu quân.
  **Trạng thái dùng `Array` (kiểu tham chiếu), KHÔNG dùng `PackedInt32Array`**: gán packed array sang
  biến khác rồi sửa là sửa bản sao (đã gặp: rải không đổi số sỏi, tổng điểm lệch).
- **Máy** (`ai_move`): chọn nước ăn nhiều nhất; chơi khó (cụ già, nửa số người lớn) trừ 0,9 × nước đáp
  trả tốt nhất của người chơi; chơi dễ (trẻ con) cộng nhiễu lớn.
- **Diễn hoạt:** mỗi nước sinh chuỗi sự kiện `pick` / `drop` / `take` / `give` / `end_turn` / `over`,
  chạy lần lượt mỗi `sow_step` giây: sỏi bay lên tay, rơi từng viên vào ô, ô bị ăn bay về đống sỏi
  của bên ăn; số sỏi mỗi ô (`Label3D`, ô quan "Q+n"), ô đang chọn tô vàng. Đối thủ nói câu ngắn (bark,
  `Dialogue.fill_for` điền xưng hô) khi ăn quan / thắng / thua.
- **Điều khiển:** bấm ô (hoặc W / S) chọn ô, A / D hoặc nút để rải, Esc thôi chơi; hết ván: E chơi
  ván nữa.
- `tools/oaq_test.gd`: 7 thế cờ dựng sẵn (ăn, ăn liên tiếp tới quan, quan non, gặp ô quan mất lượt, bốc
  rải tiếp, rải qua ô quan, rải lại khi hết hàng); 200 ván máy dễ đấu máy khó (bảo toàn tổng điểm,
  ván nào cũng dứt — thường khó thắng ~85 %, ~16 nước một ván); rủ một đứa trẻ chơi qua hội thoại →
  đi vài nước → Esc. Chụp ảnh: `--fp --focus=x,z --oaq=N [--oaq-side]` (rủ người gần nhất, đi trước
  N lượt; `--oaq-side` nhìn ngang để xem dáng ngồi).

## 28. Trò chơi dân gian: Trốn tìm (giai đoạn 5b)

- `scripts/hide_seek.gd` (`HideSeek`, node con CUỐI của `Main`, sau `OAnQuan` — nhận Esc trước). Người
  chơi đi tìm, bọn trẻ đi trốn. Rủ qua hội thoại với trẻ con / trẻ chăn trâu: "Chơi trốn tìm không em?
  {Me} đi tìm cho!" → "(Bịt mắt đếm)". `refusal(v)`: người lớn, đang học, sau 19h / trước 6h, giông,
  đang trên đường đi học / chăn trâu thì từ chối.
- **Người trốn** (`hider_count` 4): đứa được rủ + trẻ con rảnh trong vòng 45 m; thiếu thì "trẻ nhà bên"
  (Villager tạm `_make_temp`, hình như trẻ con làng, chơi xong thì xoá). Chỗ người chơi đứng là cột
  (vòng phấn `BaseMark`).
- **Chỗ trốn** (`_find_spots`): rải ngẫu nhiên trong `spot_range` (9–28 m) quanh cột; giữ chỗ mặt đất
  (tia lớp 4 dò từ ngang tầm người) cao ngang cột ±0,6 m (bỏ bậc cao, lòng ao / sông), không kẹt trong
  vật (cầu 0,32 m), tia nhìn từ mắt người ở cột tới đầu người ngồi thụp (0,7 m) BỊ CHẮN, sát một vật
  che trong 1,4 m; cách nhau ≥ 5 m. Thiếu thì lấy chỗ chỉ thoả điều kiện khuất.
- **Đếm** (`count_seconds` 10): màn hình tối, chữ "Bịt mắt đếm… Một … Mười"; người chơi đứng yên
  (`FirstPerson._suspend("count")`, vẫn giữ camera). Trẻ con trong làng chạy đi trốn bằng việc
  `hideseek` (Villagers đi theo đồ thị đường, tới nơi gọi `HideSeek.on_arrive`), trẻ tạm do HideSeek
  điều khiển. Hết đếm ai chưa tới thì đặt luôn vào chỗ. Trốn: dáng `squat`, meta `hiding` + `talking`.
- **Tìm** (`seek_seconds` 150): đứa nào trong `spot_distance` (7 m), gần giữa tầm nhìn (cos > 0,82) và tia
  nhìn không bị chắn là bị bắt; hoặc nhìn vào "E: Thấy rồi!" (`FirstPerson._act` → `spot`). Bị bắt thì
  nói một câu và chạy về cột đứng reo. Cứ `hint_interval` giây có "tiếng cười khúc khích ở phía …"
  (hướng so với chỗ đang nhìn). Người chơi xa cột hơn `escape_distance` (16 m) thì đứa đang trốn (không
  nằm trong tầm nhìn) có thể lén chạy về **đập cột** (`escaped`); bắt được giữa đường vẫn tính.
  Bản đồ nhỏ không vẽ người đang trốn.
- **Hết ván** (hết giờ / bắt hết / còn lại đều đã về cột): bảng kết quả 5 s, đứa chưa tìm ra đứng dậy
  "ở đây này!"; `stop()` gỡ meta, trả trẻ trong làng về Villagers (dwell 0), xoá trẻ tạm. Esc: thôi chơi.
- `tools/hideseek_test.gd`: Chủ nhật 15:00 rủ một đứa trẻ → đếm → 4/4 đang trốn, khuất tầm nhìn từ cột
  → đi tới từng đứa → bắt hết → dọn dẹp; ván hai đứng xa cột quay lưng → có đứa về đập cột → Esc.
  Chụp ảnh: `--fp --focus=x,z --hs [--hs-count] [--hs-look=N]` (đang đếm / đứng nhìn đứa thứ N).

## 29. Trò chơi dân gian: Đua thuyền (giai đoạn 5c)

- `scripts/boat_race.gd` (`BoatRace`, node con CUỐI của `Main`, sau `HideSeek`). **Bến đua** trên đê cạnh bến
  sông `station_landing` (2 = bến bắc): cột tre cắm cờ ba màu, trống cái trên giá, biển "ĐUA THUYỀN"; vùng bấm
  "Đua thuyền" (lớp 2, meta `activate` — ngắm cảnh bấm chuột, nhập vai nhìn vào + E). Nhập vai thì
  `FirstPerson._suspend("race")`; thôi đua thì đứng lại trước bến (hoặc camera ngắm cảnh đặt tâm vào bến).
- **Đường đua** `course_length` (300 m) dọc sông, bắt đầu cách bến 25 m, đi về phía đầu sông còn đủ dài
  (`dir` ±1). Cổng "XUẤT PHÁT" / "ĐÍCH" (cột tre, dây, băng rôn đỏ, chữ hai mặt nhô khỏi băng rôn) và phao
  báo khoảng cách mỗi 50 m; chỉ hiện khi đang đua (`Course`).
- **Thuyền đua:** 4 thuyền dài 6,4 m sơn màu đội (`TEAM_COLORS`: Đỏ — người chơi, Xanh xóm Đông, Vàng xóm
  Đoài, Lục xóm Chợ), mũi rồng thếp vàng, 4 tay chèo (mái chèo là node `Paddle*` quạt theo tốc độ, gợn nước
  `River.splash` ở đuôi). Lúc chưa đua thì neo ở vạch xuất phát. Không có va chạm với nhập vai.
- **Toạ độ đua:** `s` (dọc tim sông, `River.sample`), `lat` (lệch ngang), `head` (góc mũi so với chiều
  đua) — khúc cong tự theo sông, người chơi chỉ lái giữ làn (`_lane(i)`). Chạm bờ: kẹp trong
  `half_width - 1.4`, mất đà theo mức mũi đâm vào bờ, chỉ tính một lần mỗi lần va (meta `touch`) — trừ đà
  mỗi khung thì thuyền dính bờ đứng im. Hai thuyền chồng nhau thì đẩy ra hai bên, cùng chậm lại.
- **Chèo:** giữ W (`cam_forward`) → `row_speed` 6,4 m/s, tốn sức `stamina_drain`/s, thả ra hồi
  `stamina_regen`; hết sức chỉ còn `tired_speed`. Space / chuột trái (`fish_reel`) đúng nhịp trống
  (`beat_period` 0,72 s, ±`beat_window`) → "Đều tay! ×n": cộng `beat_boost` (tăng theo chuỗi, trần
  `boost_cap`, giảm dần), hồi chút sức; lệch nhịp → "Lệch nhịp!", mất đà, mất chuỗi. A / D lái.
  Máy: tốc độ `ai_speed` ngẫu nhiên + dao động, nước rút 60 m cuối, tự giữ làn.
- **Diễn biến:** đếm ngược 3-2-1 "Bắt đầu!" → đua (thanh trên: m đã đi, hạng, giờ; góc dưới trái: thanh sức,
  thước nhịp có chấm chạy và vùng vàng) → về đích: bảng xếp hạng (thời gian / "còn N m") → E / Esc về bến.
  Esc giữa chừng là bỏ cuộc. Camera riêng `RaceCam` bám sau đuôi (mũi thuyền hướng +z cục bộ).
- **Bảng chọn** (bấm bến → `Phase.SETUP`): 1 thuyền rồng / 2 thuyền đơn, A / D số thuyền đơn (2…`max_solo_boats` 10),
  3 bật / tắt chướng ngại, E bắt đầu (`begin(mode, count, obstacles)`), Esc thôi; có cả nút bấm chuột.
- **Thuyền đơn** (`_make_solo_boat`, `solo_boats`): thuyền nhỏ 3,4 m, một người chèo mái đơn đổi bên theo nhịp,
  10 màu (`SOLO_COLORS`), tên `SOLO_NAMES` ("Bạn", "Anh Tú"…). Mọi tốc độ × `solo_speed_scale` (0,8); máy chênh
  nhau nhiều hơn thuyền rồng (có người sát nút). Mỗi thuyền một từ điển trạng thái (`_boat_state`: `half_len`,
  `beam`, `scale`, `solo`, `hits`…); `boats` trỏ tới bộ đang đua, thuyền không dùng thì ẩn.
- **Làn** `_lane(i, s)`: dàn đều theo số thuyền và CO LẠI theo bề rộng sông tại `s` — làn cố định theo chỗ rộng
  thì tới khúc hẹp làn ngoài cùng sát bờ, thuyền va bờ mãi (đã gặp: thuyền đơn chậm hẳn ở mét 240).
- **Chướng ngại vật** (`_build_obstacles`, `obstacle_count` 12, rải lại mỗi cuộc đua từ mét 40 tới cách đích 20 m,
  toạ độ đua `d` + `lat`, hộp `hs` × `hl`): **khúc gỗ trôi** dạt qua lại (`base` + `amp`·sin) — va mất đà còn
  `log_hit_keep`; **đám bèo tây** — trong bèo chỉ còn `weed_slow` tốc độ ("Vướng bèo!"); **hàng cọc đăng** có lưới,
  cờ đỏ ở đầu phía lòng sông, chắn 35–50 % bề ngang từ một bờ (hai hàng liền nhau đổi bờ) — va gần như đứng lại
  (`stakes_hit_keep`) và bị chặn như tường, phải lái vòng. Va cứng tính một lần mỗi lần chạm (`touching`), đẩy ra
  theo phía chồng ít hơn. Dòng đỏ "Phía trước: … (A / D để né)" khi có chướng ngại trên đường trong 30 m.
- **Máy né** (`ai_target_lat`): mọi chướng ngại trong `ai_look_ahead` m chặn một khoảng ngang; chọn điểm trống gần
  làn mình + chỗ đang đi nhất, hết chỗ thì bỏ cái xa nhất. (Né từng cái một thì né cái sau lại lao vào hàng cọc
  vừa né — đã gặp kẹt.) Mỗi chướng ngại có `ai_miss_chance` máy "không kịp né": chỉ thấy khi còn ~2,5 m, va rồi
  lách ra (bỏ qua hẳn thì kẹt sau hàng cọc mãi).
- `step(delta, rowing, steer)` tách riêng cho bài thử. `tools/boat_race_test.gd` mô phỏng cả cuộc đua với
  từng cách chơi: không chèo (không về), giữ W suốt (~62 s, hạng 4), gõ trúng mọi nhịp (~48 s, nhất),
  trúng 70 % nhịp (~49 s), gõ bừa (~56 s, hạng 4); máy về 51–56 s. Thử lái đâm bờ (không vượt mép, vẫn đi
  được), vào từ nhập vai → Esc. Thêm: thuyền rồng có chướng ngại × 5 lần rải (trúng nhịp + né: nhất, ~49 s, va
  ~0,4 lần; chỉ giữ làn: kẹt sau cọc đăng), thuyền đơn 10 thuyền (làn khe ≥ 1,9 m; trúng nhịp + né: hạng 1–5,
  ~64 s; giữ W: bét; máy va ~0,7 lần / thuyền, thuyền máy nào cũng về đích), 2 thuyền, bảng chọn qua phím.
- Chụp ảnh: `--race=giây` (0 = đếm ngược; chèo đúng nhịp tới giây đó), `--race-result`, `--race-setup`,
  `--race-mode=team|solo`, `--race-boats=N`, `--race-obstacles=0|1`, `--race-seed=N`.

## 30. Trò chơi dân gian: Thả diều (giai đoạn 5d)

- `scripts/kite.gd` (`KiteFlying`, node con CUỐI của `Main`, sau `BoatRace`). Rủ qua hội thoại (nhập vai) với
  trẻ con / trẻ chăn trâu: "Cho {me} mượn con diều thả với!" → "(Thả diều)". `refusal(v, chỗ đứng)`: người
  lớn, đang học, sau 18:30 / trước 6h, mưa phùn / giông (ướt giấy diều), sương mù (lặng gió), chỗ không thoáng.
- **Chỗ thoáng** (`open_area`): tia lớp 4 lên trời không vướng; 8 tia xiên ở tầm 4–6 m vướng ≤ 2; phía xuôi gió
  18 m trống; và không nằm dưới khối bao (nới 2 m) của mesh lá dùng shader gió (`_leaf_boxes` — tán lá không
  có va chạm nên tia bay xuyên qua). Bờ ruộng, sân trước nhà mình được; dưới gốc đa, giữa làng thì không.
- **Mô hình bay:** diều trên mặt cầu bán kính `line` quanh tay (`_hand`), xuôi gió (`wind_dir_deg` 145° — gió
  nồm đông nam), góc ngẩng `el`, góc lệch `az`. Gió = `wind_base` × √`Weather.wind` × (0,75 + mạnh dần theo độ
  cao) × (dao động chậm + cơn giật / lặng gió ngẫu nhiên mỗi `gust_every` giây). Gió biểu kiến: giật dây
  (giữ Space / chuột trái) +`pull_boost` và dây ngắn lại; thả dây (W) trừ đi (diều trôi theo gió), dây dài ra
  tới `max_line`; thu dây (S). Gió biểu kiến × "cửa sổ gió" (cos `az`, ngẩng quá cao kém gió) so với
  `lift_need`: hơn thì lên, kém thì chúc xuống. A / D lái `az`.
- **Sức căng** `tension = (gió biểu kiến / tension_ref)²`; quá 1 thì dây "mỏi" (`strain`) dần, mỏi hết là
  **đứt dây** — diều bay mất theo gió. Diều chạm đất là **rơi**. Esc thu diều. Kết quả: cao nhất, số giây bay,
  lời khen; E thả lại (diều màu khác), Esc trả diều (nhập vai đi tiếp).
- **Hình:** diều sáo hình thoi hai màu (`KITE_COLORS`), khung tre chữ thập, ống sáo, cỡ `kite_scale`; đuôi dải vải
  10 đốt bám theo nhau, gió thổi lượn sóng; dây là dải mỏng quay về camera, võng nhiều khi chùng (ImmediateMesh,
  vẽ lại mỗi khung). Camera riêng `KiteCam` sau lưng người thả, ngước theo diều nhưng giữ chân trời ở mép dưới
  (pitch 6°–36°). Đứa trẻ đứng cạnh (meta `talking`) quay mặt theo diều, reo khi diều lên 20 / 40 / 60 m, nhắc
  "Gió giật đấy! Thả dây ra" / "Lặng gió rồi, giật dây đi".
- **Giao diện:** dòng trên: cao, dây, giây + nhắc ("Dây căng quá! Thả dây ra (W)!", "Diều sắp rơi!"); góc dưới
  trái: thanh sức căng (vùng đỏ > 1), sức gió (lặng / nhẹ / vừa / mạnh, giật), phím.
- `step(delta, pulling, reel, steer)` tách riêng. `tools/kite_test.gd`: 90 s bay × cách chơi × thời tiết (6 lần
  gieo gió): để mặc lơ lửng ~9 m; giật suốt ~7 m (trời nhiều mây có khi đứt); thả suốt thì rơi; "khéo" (thả khi
  căng, giật khi chúc) lên 66–115 m; khéo tới 60 m dây rồi để mặc: nắng giữ được, nhiều mây đứt 5/6. Kiểm tra
  chỗ thoáng / gốc đa / sân đình / sương mù, rủ qua hội thoại → thả → Esc → kết quả → Esc.
- Chụp ảnh: `--fp --focus=x,z --kite=giây` (ví dụ `--focus=-8,14`: bờ ruộng trước nhà).

## 31. Trò chơi dân gian: Nhảy dây (giai đoạn 5f)

- `scripts/jump_rope.gd` (`JumpRope`, node con CUỐI của `Main`, sau `KiteFlying`). Nhảy dây dài: hai đứa hai đầu
  quay dây, những đứa khác xếp hàng (`queue`) lần lượt vào giữa nhảy; đứa nào vướng thì ra thay người quay
  (`turners[0]` vào cuối hàng). Mỗi cuộc chơi là một từ điển (`games`): `center`, `axis` (hướng nối hai người quay),
  `turners`, `queue`, `jumper`, `phi` (pha dây, 0 = đáy dây chạm đất giữa sân), `rev` (vòng/giây), `count`, `best`.
- **Trẻ con tự chơi:** việc mới `jumprope` của Villagers (trẻ con, 7:00–17:30 trừ trưa, không mưa, không giờ học —
  `ambient_ok`), đích ở bãi gần nhất trong `sites`: sân đình (`dinh_spot` − 9 m) và bãi cỏ phía tây cổng làng
  (`center.x − 30`; phía đông cổng là chợ phiên — mục 40; dưới gốc đa thì tán lá che hết, đã thử). Tới nơi `on_arrive` → meta `jumprope` + `talking` (Villagers chỉ
  diễn hoạt, JumpRope tự dắt tới chỗ đứng `_walk_to`, gỡ meta khi tan). Đủ 3 đứa mới nhảy; máy nhảy đúng lúc tới
  "số phận" `kid_skill` lần thì nhảy sớm / muộn → vướng. Tan cuộc sau `game_seconds` giây thật (1 ngày = 15 phút
  nên ~1–2 giờ trong game), hoặc ≥ 18:00, mưa, tới giờ học → dwell 0 cho Villagers chọn việc khác. Số lần nhảy
  hiện bằng `Label3D` trên bãi; các đứa đứng quay reo (`CHANTS`) mỗi 10 lần.
- **Người chơi:** nhập vai nhìn một đứa đang chơi "E: Xin nhảy dây cùng" (`FirstPerson` → `join_at`), hoặc rủ qua
  hội thoại "Chơi nhảy dây không em?" → "(Vào nhảy)" (`start_with`: bày cuộc chơi 2,5 m trước mặt, dây quay ngang
  tầm nhìn, gọi thêm ≤ 3 trẻ rảnh trong 30 m, thiếu người quay thì trẻ nhà bên chạy sang — `_make_temp`).
  `refusal`: người lớn, đang học, tối, mưa, đang đi học / chăn trâu, chỗ chật (`open_ground`: 8 hướng × tầm 0,5 và
  1,8 m không vướng gì trong nửa dây + 0,8 m). Dialogue không mở khung thoại với đứa đang nhảy dây (chỉ bark).
- **Nhảy:** người chơi luôn là người nhảy (khách, không phải quay dây), hình nhân `_avatar` (dáng người lớn, không
  nón), camera riêng `RopeCam` nhìn ngang. Space / chuột trái (`fish_reel`) nhảy khi chân chạm đất: lơ lửng
  `jump_air` 0,32 s, cao `jump_height`; lúc dây quét qua đáy (pha qua bội 2π) chân phải cao hơn `need_clearance`
  = `clearance` + `clearance_per_rev` × (dây nhanh hơn lúc đầu) → dây càng nhanh càng phải nhảy chuẩn. Dây quay
  `start_rev` → `max_rev`, +`speed_step` mỗi `speed_every` lần. Vướng → lượt các đứa trong hàng → lại tới bạn;
  bảng kỷ lục, hàng chờ, thước nhịp (chấm đỏ chạy theo pha dây, vạch vàng = dây chạm đất), số to giữa màn hình.
  Esc: thôi (cuộc chơi người chơi bày thì tan, cuộc chơi ở bãi thì bọn trẻ chơi tiếp thêm 20–40 s).
- **Dây:** cung tròn giữa hai bàn tay (`hand_height`, bán kính bằng tầm tay nên đáy sát đất, đỉnh ~2 m trên đầu),
  ImmediateMesh dải mỏng quay về camera, chỉ vẽ trong 70 m. Người quay: tay phải đưa ra trước quay vòng theo
  `phi`; người nhảy: nâng người theo cú nhảy, co gối, dang tay (ghi đè sau khi Villagers diễn hoạt — JumpRope
  đứng sau World trong cây scene).
- `step(g, dt)` tách riêng. `tools/jump_rope_test.gd`: 4 đứa ở bãi sân đình 60 s (lượt nhảy, đổi người quay, kỷ lục,
  tan sạch meta); rủ qua hội thoại ở bờ ruộng; bot nhảy mỗi vòng một lần với độ lệch tay: lệch ≤ ±0,08 s trụ hết
  45 s (~60 lần, dây lên ~2 vòng/s), ±0,1 s được 18–58 lần, ±0,14 s 0–11 lần, nhảy sớm / không nhảy vướng ngay;
  Esc dọn sạch; từ chối khi chật / mưa / người lớn.
- Chụp ảnh: `--rope=N` (bãi thứ N có 4 đứa đang chơi; kèm `--distance --pitch --yaw=20`), `--fp --focus=x,z
  --rope-play[=số lần]` (bạn đang nhảy, chụp lúc lơ lửng; ví dụ `--focus=-10,-3 --fp-yaw=90`: sân gạch nhà mình).

## 32. Trò chơi dân gian: Đánh khăng (giai đoạn 5g)

- `scripts/tip_cat.gd` (`TipCat`, node con CUỐI của `Main`, sau `JumpRope`). Mỗi đứa cầm **khăng cái** (que dài
  `khang_len` 0,6 m, gắn vào cẳng tay phải — `_give_bat`, gỡ ngay khi tan bằng `remove_child`), **khăng con** (que
  ngắn vót hai đầu, làm to hơn thật cho dễ nhìn) đặt ngang **lỗ khăng** (rãnh đất sẫm). Người đánh lần lượt
  (`order`), những đứa còn lại là bên đỡ toả ra trước mặt 7–15 m (meta `khang_home`):
  1) **Hất khăng** (`_flick`, lực 0…1 → `flick_speed`, A / D ngắm `aim`). Bên đỡ đoán điểm rơi (`_predict`) và chạy tới
     (trong 9 m); khăng đang rơi qua tầm tay (cao 0,3–1,8 m, trong `catch_radius`) → thử bắt, dính với xác suất
     kỹ năng × `catch_skill` → **chết**; tuột tay thì đứa đó không bắt lại lần nữa (`tried`).
  2) **Ném vào lỗ**: đứa gần nhất chạy tới nhặt (0,5 s) rồi ném về lỗ (lệch theo kỹ năng). Người đánh **vụt đỡ** một
     lần (`_try_bat`: khăng trong 0,15–2,2 m quanh lỗ) → khăng bay ra (bên đỡ lại có thể bắt). Rơi cách lỗ
     ≤ `khang_len` → **chết**.
  3) **Đánh khăng** (`strikes` 3 lần): người đánh ra chỗ khăng nằm, gõ cho nảy (`_tap`, `hop_speed`), vụt khi khăng
     lên cao nhất (`_strike`: lệch đỉnh nảy quá `strike_window` 0,22 s là hụt — mất một lần; đúng đỉnh thì bay xa
     nhất `strike_speed`). Mỗi chuyến bay đều có thể bị bắt. Hết lần đánh: **được N khăng** = khoảng cách lỗ →
     khăng con / `khang_len`. `turn_done(who, points, out)`.
- **Trẻ con tự chơi:** việc `khang` của Villagers (trẻ con và trẻ chăn trâu, con trai nhiều hơn — con gái thích
  nhảy dây hơn), giờ như nhảy dây (`ambient_ok`); `sites` + hướng đánh `site_dirs`: sân đình phía đông (bãi nhảy
  dây ở phía tây) đánh về phía nam, bãi cỏ phía tây cổng làng đánh chếch tây nam. Meta `khang` + `talking`; đủ 2
  đứa là chơi, chờ bạn tối đa 30 s; tan sau `game_seconds`, ≥ 18:00, mưa, giờ học.
- **Người chơi:** nhìn đứa đang chơi "E: Xin đánh khăng cùng" (`join_at`) hoặc rủ qua hội thoại "Chơi đánh khăng
  không em?" → "(Đào lỗ khăng ngay đây)" (`start_with`: lỗ 1,2 m trước mặt, đánh theo hướng nhìn, gọi ≤ 2 trẻ rảnh
  trong 30 m, thiếu thì trẻ nhà bên). `refusal`: người lớn, đang học, tối, mưa, đang đi học / chăn trâu, phía trước
  hẹp (`open_field`: 3 tia toả quạt ±20° tầm 1 m dài 14 m không vướng). Hình nhân `_avatar`, camera `KhangCam` sau
  lưng người đánh lệch sang phía khăng con (đứng cùng phía người đánh thì người che mất khăng đang nảy), khi khăng
  bay thì lùi cao nhìn theo. Space / chuột trái (`fish_reel`): giữ lấy lực rồi thả (hất) / bấm vụt đỡ / bấm gõ
  rồi bấm vụt; A / D ngắm. Lượt bọn trẻ: E tua nhanh (time_scale 3). Chơi `rounds` vòng → "Hết 3 vòng! … thắng";
  E / Esc thôi (cuộc chơi ở bãi thì bọn trẻ chơi tiếp, người chơi bày thì tan).
- `step(g, dt)` tách riêng. `tools/tip_cat_test.gd`: bãi sân đình 4 đứa 89 s (~6 lượt, khoảng nửa số lượt chết, ~47
  khăng / lượt sống; tan sạch meta + khăng cái); rủ qua hội thoại ở sân nhà mình; bot "chuẩn" (lực 0,8, đỡ khi
  khăng còn ~1 m, vụt lệch ±0,03 s) 49–73 khăng / lượt, hiếm chết; "vụng" (lệch ±0,25 s) nửa số lượt chết; trọn
  3 vòng có người thắng; Esc dọn sạch; từ chối người lớn / sát gốc đa / mưa.
- Chụp ảnh: `--khang=N` (bãi thứ N, chụp lúc khăng đang bay; `--distance=14 --pitch=-26 --yaw=20`),
  `--fp --focus=-14,-1 --fp-yaw=-90 --khang-play[=flick_ready|hop|throw_flight]` (bạn đang đánh).

## 33. Mùa vụ lúa (giai đoạn 6a)

- `scripts/farming.gd` (`Farming`, node con của `Main` ngay sau `Calendar` — NGOÀI `World` nên nhập vai không dựng
  va chạm cho nước ruộng, bó lúa…). Một vụ `cycle_days` 90 ngày theo lịch trong game (≈ 3 tháng; 1 ngày = 15 phút
  thật nên cả vụ ≈ 22,5 giờ thật — phím `,` / `.` để lướt ngày). Ngày trong vụ = (ngày Julius + giờ / 24 − mốc
  `epoch_date` 24/08/2026) mod 90 + độ lệch thửa (`home_offsets` 0 / −1,5 / −3; ô ngoài đồng `outer_offset_range`
  −6…+2) → đồng không chín đều tăm tắp. Mốc chọn để 8/11/2026 là ngày 77: lúa chín vàng, sắp gặt (vụ mùa ngoài Bắc).
- **Giai đoạn** (`STAGES`, `stage_of(d)`, `state_of(d)` → nước, bùn, đã cấy, cao, chín, bông, đã gặt):
  cày bừa 0 (ruộng ngập nước đục, chưa có lúa) → cấy 5 (cấy dần theo luống, nước trong) → lúa non 11 (cao dần,
  xanh non) → thì con gái 30 (xanh đậm, nước rút dần từ ngày 44) → trổ bông 55 (bông lúa mọc) → chín 65 (xanh →
  vàng) → gặt 80 (gặt dần theo luống thành gốc rạ) → ruộng nghỉ 87 (gốc rạ, rơm).
- **Ruộng nhà mình:** `RiceField` giữ dữ liệu từng khóm (`base_xforms`, `base_colors`, `paddy_of`, `order01` — thứ
  tự cấy / gặt theo luống từ bờ tây sang bờ đông) và MultiMesh bông lúa `ears_mm` (ẩn tới khi trổ). Farming đặt lại
  transform / màu từng khóm (chưa cấy → co về 0, đã gặt → gốc rạ thấp màu rơm), nước ruộng (`PaddyWater*`, đục khi
  cày, trong khi cấy), bó lúa nằm (`Sheaves`) chỗ đã gặt tới khi gánh về. **Trâu kéo cày** (`PlowTeam`: trâu, bác
  nông dân dáng `plow`, cái cày gỗ) đi luống đi luống về trên thửa đang cày, ban ngày, trời không mưa.
- **Đồng ngoài làng:** mỗi ô ruộng của `Terrain.outer_fields` một tấm phủ có luống (`OuterCrop`, MultiMesh, màu
  instance theo giai đoạn: bùn → mạ lấm tấm → xanh → vàng → gốc rạ), nước ruộng (`OuterWater`, khuất dần khi lúa
  lên), đống rơm (`StrawStacks`) chất dần khi gặt. **Trong làng:** sân phơi thóc vàng (`DryingGrain`) trước một nửa
  số nhà và sân nhà mình từ ngày 81 tới 89,5.
- Chỉ vẽ lại khi trạng thái đổi đáng kể (`_sig` lượng tử hoá, kiểm mỗi `update_interval`); vẽ lại toàn bộ ~2 ms.
  **Renderer headless không giữ transform MultiMesh** → bài thử đọc số đếm `counts` (khóm đang hiện, gốc rạ, bông,
  bó lúa, ô có nước, đống rơm, sân phơi) do Farming tự đếm lúc vẽ.
- **Dân làng:** trọng số việc `field` × `busy()` (cấy / gặt ×2,2, cày ×1,4, lúa đang lên ×0,9, ruộng nghỉ ×0,6);
  tới ruộng thì `field_work(pos)` theo ô ruộng gần nhất: cuốc đất / đắp bờ (`hoe`), cấy và làm cỏ (dáng mới
  `plant` — cúi sâu, tay cắm mạ), gặt (dáng mới `reap` — cúi, tay quẹt liềm), đứng xem lúa chín; cất cuốc khi cấy /
  gặt. Dáng cúi: thân xoay về trước, hông xoay ngược để chân vẫn thẳng. Hội thoại "Lúa năm nay thế nào?" và "đang
  làm gì" nói theo giai đoạn (`rice_talk`). HUD có dòng "Đồng: … (ngày N/90 của vụ)" dưới dòng ngày (`stage_text`).
- `tools/farming_test.gd`: đi qua 10 ngày trong vụ (số khóm / gốc rạ / bông / bó lúa / nước / rơm / sân phơi / trâu
  cày / mức bận / việc ngoài đồng), thời gian vẽ lại, dân làng ra đồng mùa cấy (dáng `plant`) và mùa gặt (`reap`).
  Chụp ảnh: `--crop-day=N` (2 cày, 8 cấy, 40 xanh, 60 trổ, 76 chín, 84 gặt, 89 rạ), kèm `--hour=10`.

## 34. Làng 60 hộ (giai đoạn 6b)

- **Làng nới rộng** để đủ 60 nhà không trùng kiểu (thu hẹp lô thì gần hết là nhà 2 gian — mất đa dạng):
  `Village.center` (0, −115), `radii` (122, 80), thêm ngõ thứ 6 ở z −152, `max_houses` 60. Đình (luôn sau ngõ cuối)
  lùi lên bắc 20 m, sân bóng dời tới `pitch_rect` (−64, −176, 30, 18). Kéo theo: `Terrain.village_rect`
  (−136, −208, 272, 176 — bội của ô 8 m), sông `offset_radii` (152, 108) + hai đuôi (nối vào (±152, −82)),
  đồi / núi lùi ra sau (`hill_z_range` −284…−312, `peak_z_range` −325…−385), bản đồ lớn `large_center` (−15, −100),
  `large_radius` 185. Mép nam (cổng, ao làng, cây đa, giếng, bãi chơi ngoài cổng) giữ nguyên.
- **Hộ dân** (`Villagers._household(size)`, `household_size` (3, 4), `elder_chance` 0,45, `herder_chance` 0,16,
  `carrier_chance` 0,35, `max_households` 0 = mọi nhà): bố (nông dân) + mẹ (làm ruộng / gánh hàng) + có khi ông
  hoặc bà + các con (trẻ con / trẻ chăn trâu); hộ 3 người có ông / bà thì chỉ một bố hoặc mẹ. Nhà mình (`main`) không có
  người máy ở. Mỗi người có meta `household` (chỉ số nhà), `relation` (bố / mẹ / ông / bà / con); `home.family` là
  danh sách người trong hộ (`Villagers.family_of(v)`). Thường ra ~89 nông dân, 17 gánh hàng, 27 cụ, 63 trẻ con,
  11 trẻ chăn trâu. Tên: kho tên `MALE` / `FEMALE` / `KID` ~45 mỗi loại, `_unique_name` hết chỗ ngẫu nhiên thì duyệt
  lần lượt — không ai trùng tên.
- **Hội thoại** "Nhà … ở đâu?" kể thêm người trong nhà theo quan hệ với người nói (`Dialogue._family_text`,
  `_relation_word`): "Nhà có bốn người: vợ Duyên, bà cụ Mơ, cu Mít với bác."
- **Trong nhà ban đêm:** nhà chỉ có 1–3 chỗ ngủ, người không có giường / phản vẫn hiện, ngồi thức ở chỗ khác
  (`IndoorFolk._pick_seat`: đêm mà chỗ không có tag `night` chỉ trừ 4 điểm; ngày mà chỗ ngủ thì trừ 10).
- `tools/building_walk_test.gd` thử mọi nhà theo `Village.house_count` (64 toà).
- **Hiệu năng:** Villagers._process ~1,5–2 ms / khung lúc ~200 người ngoài đường (đo headless), ~12 MeshInstance mỗi
  người (chỉ bộ đồ đang mặc hiện). Ban đêm hầu hết ẩn trong nhà.

## 35. Nhà rộng hơn, nhà 2 tầng có cầu thang (giai đoạn 6c)

- **Nhà rộng hơn ~15 %** (nội thất lấy kích thước từ nhà bên ngoài nên rộng theo): nhà làng gian 3,1–3,75 m, sâu
  5,8–7,2 m, tường cao 2,6–3,0 m (`VillageHouse.build_plot` → `dims`; số lần rút số ngẫu nhiên giữ nguyên nên vị trí
  lô không đổi); nhà mình `House.length` 11, `depth` 6,4, `wall_height` 2,8.
- **Nhà 2 tầng** (`VillageHouse.floors_of(st)`: mái ngói, tường vôi / gạch, `signature().hash() % 3 == 0` — không rút
  số ngẫu nhiên; thường 13/60 nhà, thống kê `floors` khi chạy). Bên ngoài (`_upper_floor`): sàn bê tông viền trắng
  `SLAB` 0,2 m đua ra thành ban công trên hiên, tường tầng 2 cao `height2` = 0,92 × tầng 1, cửa sổ có cánh chớp xanh
  `SHUTTER`, cửa giữa ra ban công, lan can con tiện, gờ chỉ trắng dưới mái; mái đặt trên đỉnh tầng 2. Sâu tối thiểu
  6,6 m. Tên: "Nhà 2 tầng 3 gian · …". Spec nội thất có `floors`, `height2`, `slab`.
- **Nội thất** (`Interior`): gian đầu hồi trái là chân cầu thang (`rooms[0] = "stairs"`, `_room_stairs`): cầu thang
  xây dọc tường hồi, lên từ phía trước ra phía sau, bậc cao ≤ 0,235 m, mặt bậc 0,24 m, mặt bậc gỗ, tay vịn phía
  trong; gầm thang có bao thóc, cạnh đó tủ, chum, ghế. `Interior.stair` = {x, w, z_bottom, z_top, hole_x1, bottom,
  top}; `upper_y()` = mặt sàn gác. Kiểu đi bộ: `_build_slab` (sàn chừa lỗ thang — `_slab_rects`, mặt dưới là trần
  tầng 1, dầm gỗ) + `_build_upper` (sàn gỗ, tường, cửa sổ song gỗ, cửa ra ban công, lan can quanh lỗ thang — để trống
  phía sau là chỗ bước lên, buồng ngủ / phản / góc học ở các gian còn lại — dùng lại hàm bày gian với `_p` tạm nâng lên
  mặt sàn gác), trần mái trên đỉnh tầng 2, đèn phụ `DaylightFillUpper`. Kiểu nhà búp bê chỉ dựng tầng 1 (thang lên
  tới trần).
- **Người trong nhà** (IndoorFolk): chỗ trên gác có tag `upstairs` và `via` (chân thang → bậc đầu → đầu thang); bản
  sao đi theo `via` lên gác, ra về thì đi ngược xuống. Ban đêm cả nhà lên gác ngủ.
- `tools/stairs_test.gd [-- --only=house_0]`: mỗi nhà 2 tầng: đi lên thang (tới đúng sàn gác), sang gian bên, đẩy vào
  lỗ thang từ bên hông (lan can chặn), ra ban công (không rơi), đi xuống tới nền; ban đêm người nhà lên gác ngủ.
  Chụp ảnh: `--enter=house_0 --fp --fp-in=stair|up|x,y,z --fp-yaw=… --fp-pitch=…`.

## 36. Dân làng tự chơi trò dân gian; người chơi vào thì chơi lại từ đầu (giai đoạn 6d)

- **Không có người chơi, làng vẫn chơi** cả sáu trò; người chơi vào trò đang diễn ra thì trò đó **bắt đầu lại từ đầu**:
  - **Nhảy dây / đánh khăng** (đã tự chơi từ mục 31, 32): `JumpRope._start_player` — đứa đang nhảy ra cuối hàng, dây
    quay chậm lại, đếm lại 0, xoá kỷ lục, người chơi nhảy trước; `TipCat._start_player` — điểm về 0, vòng 1, người
    chơi đánh trước (`turn_i = -1` → `_next_turn`). Bọn trẻ reo "Chơi lại từ đầu…".
  - **Ô ăn quan** (`OAnQuan.ambient`, `sites`: gốc đa đầu làng, sân chùa): việc `oaq` của Villagers (cụ già, trẻ con,
    trẻ chăn trâu; 7:00–18:18, không mưa) → `on_arrive`: đủ 2 người thì ngồi xổm hai bên bàn kẻ phấn (`_chalk` dùng
    chung với bàn của người chơi), máy đi cho cả hai bên mỗi `ambient_move_time` giây (đủ luật: `play`, `refill`,
    `collect`; người già / nửa số người lớn chơi khó), sỏi vẽ bằng một MultiMesh mỗi bàn (`_ambient_draw`), hết ván
    thì người thắng reo rồi ván mới (đổi người đi trước); tan sau `ambient_seconds`. Nhập vai nhìn người đang chơi
    "E: Xin chơi ô ăn quan (ván mới)" → `join_ambient` → `start(v)` (bàn dân làng tan, người kia đi việc khác, ván mới 0–0).
  - **Trốn tìm** (`HideSeek.ambient`): việc `hs_play` (trẻ con, trừ trưa, không mưa) → tụ ở cột (`ambient_bases`: giữa
    đường trục chỗ ngõ 2 và ngõ 4 rẽ); đủ 3 đứa: một đứa đứng chắp tay đếm, những đứa khác chạy (theo đồ thị đường)
    tới chỗ trốn `_amb_spots` (nấp sau rào ngay cạnh cổng các nhà, sau gốc đa, cạnh giếng — KHÔNG dò bằng tia va chạm
    vì va chạm chỉ có sau khi bật nhập vai), ngồi thụp; người đi tìm đi lần lượt các chỗ (chỗ thật + vài chỗ trống,
    gần trước), tới nơi thì bắt; đi xa cột > 14 m thì đứa đang trốn có thể lén về đập cột (`ambient_escape_rate`);
    hết vòng thì đứa bị bắt đầu tiên đi tìm vòng sau. Nhập vai nhìn một đứa "E: Xin chơi trốn tìm (chơi lại từ đầu)" →
    nhóm tan, cả nhóm (dù đang nấp xa) thành người trốn trong ván mới, người chơi đi tìm (`start`).
  - **Thả diều** (`KiteFlying.ambient`, `sites`: trên hai đường đất giữa đồng, z 26 / 64): việc `kite` (trẻ con, trẻ
    chăn trâu; nắng / nhiều mây) → mỗi chỗ tối đa `ambient_per_site` đứa, diều nhẹ (mesh diều + dây + đuôi
    ImmediateMesh, dưới node `AmbientKites` ở `Main` — node `KiteFlying` ẩn khi người chơi không thả), lên dần trong
    ~10 s rồi chao lượn xuôi gió, chỉ vẽ trong 260 m. "E: Mượn diều thả" → đứa trẻ thu diều đưa người chơi thả lại từ đầu
    (`start` bỏ diều của đứa đó, meta `kite_lent`; trả diều thì đứa trẻ đi việc khác).
  - **Đua thuyền** (`BoatRace.ambient`, `begin_ambient`): ban ngày (`ambient_hours`), không mưa / sương, cứ
    `ambient_interval` giây bốn thuyền rồng bốn xóm đua với nhau (thuyền Đỏ cũng do máy chèo, không chướng ngại, không
    camera / giao diện), về đích hết thì nghỉ 10 s rồi về lại vạch xuất phát. Người chơi bấm bến đua giữa chừng →
    `_end_ambient` (các thuyền về vạch xuất phát) → bảng chọn như cũ.
- Meta của người đang tự chơi: `oaq_ambient`, `hs_amb` (+ `hs_hidden`, `hs_back`), `kite_amb`; Dialogue chỉ nói câu ngắn
  (bark) với họ, FirstPerson hiện gợi ý vào chơi. Villagers gọi đi (tối, mưa, đi học…) thì tự rời trò.
- `tools/folk_ambient_test.gd`: Chủ nhật 14:30 để làng tự chạy 160 s (tua ×4): ô ăn quan ~8 ván, trốn tìm ~6 vòng (bắt,
  đập cột), 5–7 diều cùng bay, một cuộc đua thuyền đủ 4 thuyền về đích, nhảy dây, đánh khăng; rồi người chơi vào từng trò →
  ô ăn quan ván mới 0–0, trốn tìm ván mới (người chơi đếm), mượn diều thả lại từ dây 9 m, đua thuyền về vạch xuất phát,
  nhảy dây đếm lại 0, đánh khăng điểm về 0.

## 37. Lưu game (giai đoạn 7a) — lộ trình giai đoạn 7

- **Lộ trình giai đoạn 7 — ĐÃ XONG cả 9 bước** (7a…7i, mục 37–45): 7a lưu game → 7b âm thanh
  → 7c sổ tay người chơi → 7d chợ phiên → 7e lễ hội theo lịch âm (Tết, rằm tháng Giêng, Trung thu) → 7f các mùa trong
  năm → 7g kéo co → 7h trò dân gian khác (bịt mắt bắt dê, rồng rắn lên mây, chơi chuyền, bắn bi, đá cầu) → 7i hiệu năng.
- `scripts/save_game.gd` (`SaveGame`, node con cuối của `Main`). File JSON `save_path` (`user://lang_que_save.json`):
  `version`, `saved_at`, `jd` (ngày), `hour`, `auto_run`, `weather`, `camera` (tâm, yaw, khoảng cách camera ngắm cảnh),
  `fish_log` / `fish_total` / `basket` (Fishing), `gifts` (Quests), `met` (Dialogue `_met` — lưu theo `display_name`,
  nạp lại khớp tên vì dân làng sinh theo seed cố định), `records` (kỷ lục người chơi).
- **Kỷ lục** (`records`) lấy từ tín hiệu sẵn có: `JumpRope.turn_over` ("Bạn" → `rope_best`), `TipCat.turn_done`
  (`khang_best` lượt không chết), `BoatRace.finished` (`race_best_team` / `race_best_solo`, `race_wins`),
  `KiteFlying.finished` (`kite_best`), `OAnQuan.finished` (thắng / thua / hoà — chỉ ván chơi hết), `HideSeek.finished`,
  `Football.goal_scored` (`goals` của người chơi).
- **Khi nào lưu:** mỗi `autosave_seconds` (60) giây thật, khi đóng cửa sổ (`NOTIFICATION_WM_CLOSE_REQUEST`), F5
  (`save_game`, hiện chữ "Đã lưu game"). Mở game có file thì nạp (`_load` gọi trễ một nhịp, sau khi mọi phần đã
  dựng; ngày lưu thay cho ngày hôm nay của máy) rồi `Villagers.replan()`. Ctrl+F5 (`new_game`): xoá file, lần mở
  sau chơi lại từ đầu. File hỏng thì bỏ qua (cảnh báo).
- Chạy bằng `-s` (bài thử, `tools/screenshot.gd`) thì `SaveGame` không đọc / ghi file (`_disabled`) — ảnh chụp và bài
  thử không bị file lưu của người chơi làm lệch.
- `tools/save_test.gd`: đặt trạng thái (kỷ lục qua tín hiệu thật) → lưu file tạm → xáo trộn → nạp lại: 12/12 mục đúng;
  file hỏng thì bỏ qua.

## 38. Âm thanh (giai đoạn 7b)

- `scripts/soundscape.gd` (`Soundscape`, node con của `Main`). **Mọi tiếng tổng hợp bằng code** lúc mở game (giống mesh
  procedural, không file âm thanh ngoài): mảng mẫu −1…1 → `AudioStreamWAV` 16 bit mono `SAMPLE_RATE` 16 kHz (`_wav`);
  tiếng lặp trộn đuôi vào đầu cho liền (`_seamless`). Mỗi khung chỉ tạo một tiếng (17 tiếng ~18 khung, khung lâu nhất
  ~110 ms lúc mở game). Kỹ thuật: ồn trắng qua lọc thấp / cao một cực (gió, mưa, sông, bước chân, sấm = ồn nâu),
  sóng sin trượt tần (chim, bọt nước), hoạ âm có trọng số (gà gáy "ò ó o o" — bốn nốt trượt, rung), sin tụt giọng +
  tiếng gõ (trống), hoạ âm lệch ngân dài (chuông đồng), xung điều biên (dế "ri ri", ếch "ộp", gà cục tác), nhiều giọng
  răng cưa lọc (reo hò).
- **Nền lặp** (`_loops`, bus `Ambient`): gió theo `Weather.wind` (`wind_db`), mưa theo `Weather.rain` (`rain_db`), dế +
  ếch nhái ban đêm 18:48–5:00 (mưa thì dế im, ếch to hơn), âm lượng chuyển dần 30 dB/s. Tiếng sông: `AudioStreamPlayer3D`
  đặt ở điểm tim sông gần camera nhất (`River.nearest_s` / `sample`).
- **Tiếng lẻ định vị** (bể 14 `AudioStreamPlayer3D`, bus `Effects`, `play_at`): chim hót ban ngày quanh người nghe,
  gà gáy 4:18–7:12 ở một nhà ngẫu nhiên, chó sủa / gà cục tác khi có con gần (`Villagers.animals`), trống trường khi
  `SchoolDay.phase` đổi (3 tiếng, tan học 5 tiếng, ở cột cờ), chuông chùa 3 tiếng lúc 5:00 và 18:00, trống đua thuyền
  theo nhịp `beat_period` (cả khi dân làng tự đua), nước té khi mặt sông gợn (tín hiệu mới `River.rippled`, tối đa
  4 lần / s), sấm 0,6–3,2 s sau chớp (tín hiệu mới `Weather.lightning`), reo hò khi có bàn thắng / về nhất đua thuyền,
  bước chân khi nhập vai (nhịp theo tốc độ).
- **Trong nhà:** bus `Ambient` bật `AudioEffectLowPassFilter` (900 Hz) và bớt 8 dB — nghe như cách tường; chỉ tiếng nền.
- Phím N (`toggle_sound`): tắt / bật cả bus Master. `played` đếm số lần phát từng tiếng (cho bài thử).
- `tools/sound_test.gd`: thời gian tổng hợp, độ dài / đỉnh / RMS từng tiếng (không tiếng nào câm), âm lượng nền
  14:00 nắng / 21:00 nắng / 21:00 giông / trong nhà, các tiếng theo sự kiện; lưu `screenshots/sounds/*.wav` để nghe thử.

## 39. Sổ tay người chơi (giai đoạn 7c)

- `scripts/notebook.gd` (`Notebook`, `CanvasLayer` con cuối của `Main`, `layer` 18). Phím B (`toggle_notebook`) mở /
  gấp; A / D hoặc bấm mục để lật trang; Esc gấp. Cuốn sổ giấy giữa màn hình (`PAPER`, gáy nâu, chữ mực `INK`, tiêu đề
  đỏ `ACCENT`), nội dung là `RichTextLabel` BBCode, trang đang mở tự làm mới 2 lần / s.
- **5 trang** (`PAGES`, `page_text(i)`): **Kỷ lục** (`SaveGame.records`: nhảy dây, đánh khăng, đua thuyền rồng / đơn,
  thả diều, ô ăn quan thắng / thua / hoà, trốn tìm, bàn thắng); **Câu cá** (mọi loài trong `Fishing.SPECIES` — đã câu:
  số con + to nhất, chưa câu: "chưa câu được"; x / 6 loài; cá trong giỏ + tổng cân); **Người quen** (`Dialogue._met`,
  xếp theo số lần trò chuyện: tên, vai, quan hệ trong nhà, nhà nào; x / số dân); **Quà & việc** (`Quests.done_count`,
  việc đang làm `active[].title`, quà gộp theo món); **Làng hôm nay** (ngày dương / âm, lễ, giờ, thời tiết, mùa vụ,
  số hộ / người / con vật, thời gian đã chơi `records.play_seconds`, lần lưu cuối).
- Lưu thêm `records.play_seconds` (đếm cả khi không lưu file) và `quests_done` (`Quests.done_count`).
- **Mở khi:** không đang trò chuyện; nhập vai thì chỉ khi không đang chơi trò gì (`FirstPerson._suspended` rỗng) →
  `_suspend("notebook")` (đứng lại, hiện chuột), gấp sổ thì `_resume()`. Ngắm cảnh thì tạm tắt `CameraRig.active`
  (camera đọc phím trực tiếp nên chặn sự kiện không đủ). Khi sổ mở, mọi phím khác bị chặn (`set_input_as_handled`).
- Chụp ảnh: `--notebook=0..4` (mở trang đó, kèm dữ liệu mẫu). `tools/notebook_test.gd`: mở / gấp ở ngắm cảnh và nhập
  vai, lật trang, W không làm camera chạy, số liệu thật hiện trên các trang, không mở khi đang trò chuyện. Bài thử gửi
  phím bằng `Input.parse_input_event` phải chờ `process_frame` (khi nhập vai, sự kiện vào trễ một khung).

## 40. Chợ phiên (giai đoạn 7d)

- `scripts/builders/market.gd` (`Market`, node `World/Market`, dựng TRƯỚC `Villagers` để nối lối chợ vào đồ thị đường).
  Bãi cỏ ngoài cổng làng phía đông nam (giữa đường đất `roads[1]` và cây đa nhà mình): lối giữa (`origin` (7,2; −20,5),
  nền đất nện), hai dãy 4 lều tre (`stall_spacing` 3,8 m, `row_offset` 3,6 m) quay mặt vào lối giữa; mỗi lều: 4 cột tre,
  sạp nan tre cao 0,72 m, mái lá (shader gió) hoặc bạt xanh dốc ra lối, ghế đẩu sau sạp. Cổng tre + biển "CHỢ PHIÊN"
  (`Label3D` `BILLBOARD_FIXED_Y` — đọc được cả hai phía). Lều dựng sẵn; **hàng hoá** (`Goods`) chỉ hiện trong phiên: rau,
  chuối + bưởi, chậu cá, lồng gà + trứng, thúng gạo, nồi đất / chum, chồng nón + quạt nan, mẹt bánh đa + kẹo lạc.
- **Phiên chợ:** ngày âm lịch chia 5 dư 1 (mùng 1, 6, 11, 16, 21, 26 — `is_market_day`), `market_hours` 5:30–11:30, không
  họp khi giông. Bãi nhảy dây ngoài cổng dời sang phía tây cổng (`JumpRope.sites[1]`).
- **Người bán:** từ `prep_hours` (1,25 h) trước giờ họp, `_call_sellers` gọi người gánh hàng (thiếu thì phụ nữ làm ruộng)
  — meta `market_stall`, việc `market_sell` (`Villagers._choices` trả về `market_sell` khi đã nhận sạp, kể cả khi lịch bị
  lên lại) → tới ghế đẩu `on_seller_arrive`: ngồi (`sit`) mặt ra lối, meta `market_seller`, dwell rất lớn. Giờ bị nhảy
  thẳng vào giữa phiên (chỉnh giờ, mở game đã lưu) thì người bán ngồi sẵn (`instant`). Tan chợ: `_release_sellers`.
  (Đã gặp: gọi đúng giờ mở chợ thì người gánh hàng 1,15 m/s đi từ trong làng ra mất ~2 phút thật = 3 giờ trong game.)
- **Người đi chợ:** việc `market` (phụ nữ làm ruộng / gánh hàng 4, cụ già 2,5, trẻ con 1,5, đàn ông 0,6) → đứng trước một
  sạp (`shopper_target`), quay vào sạp, dáng `chat`.
- **Mua bán với người chơi** (qua `Dialogue` — `market.dialog_options(v, dlg)` thêm lên đầu, tối đa 3 câu): nói chuyện với
  người bán (nhập vai nhìn vào: "E: Mua bán · tên (hàng…)") → "Cho {me} xem hàng" → mua món (`STALLS[].items`, giá nghìn
  đồng; thiếu tiền thì không bán) → đồ vào `bag`; hàng cá mua hết cá trong giỏ (`sell_fish`: cân × `FISH_PRICE`). Người
  chơi có `money` (bắt đầu `start_money` 20 nghìn). Ai cũng nhận quà: "{Me} biếu {npc} chút quà" → chọn món trong `bag` →
  người nhận cảm ơn, `Dialogue._met` +2 (quen thân hơn). Tín hiệu `traded(text)`.
- Lưu `money`, `bag` (SaveGame); sổ tay trang "Quà & đồ" (túi tiền, đồ đã mua) và dòng "Chợ" ở "Làng hôm nay"
  (`status_text`: "hôm nay có phiên…" / "phiên tới ngày N âm lịch (còn N ngày)"); bản đồ vẽ các lều (đỏ khi đang họp) và
  nhãn "Chợ"; Soundscape thêm tiếng chợ ồn ào (`_murmur`: 7 giọng răng cưa lọc nói ngắt quãng, nguồn 3D ở giữa chợ, chỉ khi
  họp). Câu "Chợ phiên có gì vui không?" của người gánh hàng nói đúng lịch phiên.
- `tools/market_test.gd`: ngày phiên 6:30 (8/8 người bán ngồi sạp, ~10 người đi chợ, hàng bày) → mua (trừ tiền, vào giỏ đồ),
  hết tiền không mua được, bán cá (1,5 kg chép + 0,3 kg diếc = 44 nghìn), biếu quà (giỏ đồ bớt, quen thêm) → lưu / nạp tiền +
  giỏ đồ → 11:36 tan chợ (cất hàng, người bán về) → hôm sau đóng, báo phiên tới. Chụp ảnh: `--hour=8 --settle=40 --fp
  --focus=1.5,-20.5 --fp-yaw=-70` (đứng ở lối giữa chợ; nhìn từ trên cao thì mái lều che người bán).

## 41. Lễ hội theo lịch âm (giai đoạn 7e)

- `scripts/festival.gd` (`Festival`, node con của `Main` — ngoài `World` nên không sinh va chạm). Đồ trang trí dựng một
  lần (`_build`, gọi trễ sau khi làng dựng xong), bật / tắt theo `mode_now()` (kiểm mỗi giây): `tet` (25 Chạp → mùng 7
  Giêng), `gieng` (13–15 tháng Giêng), `trungthu` (13–15 tháng Tám); tháng nhuận không tính.
- **Dây cờ đuôi nheo** (`Bunting`, mọi kỳ lễ): căng ngang đường trục mỗi 9 m giữa hai cột tre, cờ 5 màu dùng shader gió.
- **Tết** (`Tet`): 2 cây nêu (sân đình, ngoài cổng làng — tre 9 m, túm lá ngọn, dải đỏ, đèn lồng), câu đối đỏ trên trụ cổng,
  băng rôn "CHÚC MỪNG NĂM MỚI" (`BILLBOARD_FIXED_Y`), cành đào trong chậu trước cổng mỗi nhà (một MultiMesh 60 cây).
  **Pháo:** vừa sang mùng 1 tháng Giêng (giờ qua nửa đêm) và 6:00 sáng mùng 1 → `light_firecrackers()`: 9 s tiếng `pop`
  (Soundscape, tiếng mới) lách tách quanh cây nêu sân đình + xác pháo đỏ (CPUParticles3D). `firecrackers` đếm số đợt.
- **Chúc Tết** (mùng 1–7, `dialog_options` thêm vào khung thoại trước câu của chợ): "Chúc mừng năm mới …!" → người lớn
  mừng tuổi `lixi_range` (2–5 nghìn, cộng `Market.money`); trẻ con chúc lại, người chơi mừng tuổi 1 nghìn (nếu còn tiền).
  Mỗi người một lần mỗi năm (`lixi` theo tên, `lixi_year`; lưu cùng game).
- **Trung thu** (`MidAutumn`): đèn ông sao to ở cổng làng, mâm cỗ (ngũ quả, bánh nướng bánh dẻo, đèn kéo quân có đèn
  `night_light`) ở sân đình. **Rước đèn** tối rằm `parade_hours` (18:24–20:48, không mưa): `Villagers._choices` cho trẻ con /
  trẻ chăn trâu việc `trungthu` (đặt TRƯỚC nhánh ban đêm; việc này cũng được miễn lệnh "tối về nhà") → đi tới một đầu đường
  trục (`parade_target`, meta `parade_to_gate` đổi đầu) → `on_parade_arrive`: cầm đèn ông sao (`StarLantern` gắn vào node
  người — sao 5 cánh không đổ bóng, tự sáng; cứ 3 đứa một đèn `OmniLight3D`) rồi quay đầu đi tiếp; hết giờ thì cất đèn về
  nhà. Trống ếch "tùng rinh rinh" (tiếng `drum` cao giọng) đi theo đoàn. Thường ~65 đứa cùng rước (trâu vẫn theo trẻ chăn).
- Sổ tay "Làng hôm nay" có dòng "Lễ hội" (`status_text`).
- `tools/festival_test.gd`: ngày thường (tắt hết) → 28 Chạp (nêu, đào, cờ) → giao thừa + 6:00 mùng 1 (2 đợt pháo) → chúc
  Tết người lớn (+2…5 nghìn, một lần) và trẻ con (−1 nghìn) → rằm tháng Giêng (cờ, không nêu) → rằm tháng Tám 18:36 (75 đứa
  đi rước, 65 đèn sáng, đi suốt z −41…−149) → 21:00 cất đèn. Chụp ảnh: `--date=2027-02-06 --hour=9 --focus=0,-44 --yaw=180`
  (Tết), `--date=2027-09-15 --hour=19.2 --settle=45 --focus=0,-75` (rước đèn).

## 42. Bốn mùa trong năm (giai đoạn 7f)

- `scripts/seasons.gd` (`Seasons`, node con của `Main`). Mùa tính theo ngày dương lịch của `Calendar`: xuân (tháng 2–4),
  hạ (5–7), thu (8–10), đông (11–1) — `CENTERS` là ngày giữa mùa; `weights_at(ngày trong năm, blend_days)` cho trọng số
  bốn mùa (tổng 1), quanh ngày giáp ranh chuyển tuyến tính trong `blend_days` (30) nên cảnh không đổi màu đột ngột.
  Chỉ tính lại khi sang ngày khác (`refresh`), rồi ĐẨY giá trị sang các phần khác (các phần đó không cần biết Seasons).
- **Màu lá:** biến toàn cục shader `season_leaf` (màu ngả tới) + `season_mix` (mức ngả) trong `[shader_globals]`;
  `wind_sway.gdshader` chỉ đổi những mặt "xanh lá" (g trội hơn r, b), giữ độ sáng từng mặt — cờ, hoa, mái lá không đổi.
  Xuân xanh non, hạ giữ màu gốc, thu ngả vàng, đông úa xám. Vật liệu có `season_scale = 0` thì không đổi (lúa — màu do mùa
  vụ quyết định). **Hoa phượng** (`flower_season = 1` trên `SchoolTrees`): mặt đỏ chỉ đỏ khi `season_bloom` > 0 (mùa hạ),
  ngoài mùa thành lá xanh. Nền cỏ nhà mình + đồng (`Terrain/Ground`, `FlatGround`) dùng vật liệu riêng nhân màu `GROUND`.
- **Thời tiết theo mùa:** `Weather.season_weights` nhân vào `AUTO_WEIGHTS` (`weight_of`): xuân mưa phùn ~37 %, hạ giông ~22 %
  (gần như không sương mù), thu nắng ~51 %, đông nhiều mây + sương mù + mưa phùn, hầu như không giông.
- **Hạt bay** (`SeasonDrift`, CPUParticles3D quanh tâm camera, tắt khi mưa / trong nhà): cánh hoa hồng mùa xuân, lá vàng mùa
  thu (dày nhất), lá nâu mùa đông. CPUParticles3D không có `amount_ratio` — đổi `amount` (chỉ khi sang ngày khác).
- **Ve kêu** mùa hạ (`Soundscape.cicada_level`, tiếng lặp mới `cicada`: 5 con, sóng cao điều biên nhanh, từng đợt to dần rồi
  lịm; 8:00–18:00, tạnh ráo). **Dân làng:** `Villagers.season` — mùa đông trẻ con không tắm sông, mùa hạ tắm nhiều hơn.
- HUD: tên mùa cuối dòng ngày (`Hud.season_text`); sổ tay "Làng hôm nay" có dòng "Mùa"; hỏi chuyện thời tiết thì người làng
  nói thêm một câu về mùa (`Seasons.TALK`, đọc `Weather.season`).
- `tools/seasons_test.gd`: 6 ngày (giữa mùa + giáp ranh): mùa, mức ngả màu lá, hoa phượng, số hạt bay, mức ve, phân bố thời
  tiết qua 2000 lần chọn, số trẻ muốn tắm sông (đông = 0). Chụp ảnh: `--date=2027-06-20 --hour=10 --focus=-66,-22
  --distance=30 --pitch=-28 --yaw=200` (sân trường, phượng nở), đổi ngày để so bốn mùa.

## 43. Trò chơi dân gian: Kéo co (giai đoạn 7g)

- `scripts/tug_war.gd` (`TugOfWar`, node con CUỐI của `Main`). Mỗi lúc chỉ có MỘT cuộc kéo co (từ điển `g`: `center`,
  `axis`, `teams` [đội 0 phía −axis, đội 1 phía +axis], `x` — độ lệch dải vải đỏ, `score`, `round`, `phase`:
  `gather` → `ready` (2,5 s) → `pull` → `win` (3 s) → hiệp sau / `done`). Dải đỏ qua vạch `win_dist` (2,2 m) của đội nào
  thì đội đó thắng hiệp; hết `round_seconds` (40) thì đội đang kéo được hơn thắng; thắng `rounds_to_win` (2) hiệp là thắng.
- **Hình:** vạch vôi giữa + hai vạch thắng đỏ nhạt, dây thừng (ImmediateMesh quay về camera) có dải vải đỏ rủ ở giữa,
  bảng tỉ số `Label3D`. Người kéo đứng so le hai bên dây (`_slot(đội, k)` — trượt theo `x`), dáng kéo ghi đè sau khi
  Villagers diễn hoạt: thân ngả ra sau (`body.rotation.x` âm), chân choãi, hai tay nắm dây phía trước, nhún theo nhịp;
  đội thắng giơ hai tay reo.
- **Dân làng tự chơi:** việc `tug` của Villagers (trẻ con, trẻ chăn trâu, đàn ông; `ambient_hours` 15:30–17:42, ngày lễ
  hội thêm 8:00–11:00; không mưa) → bãi `site` (−34; −10,5: dải cỏ giữa tường trường và đường đất, phía tây cổng làng,
  dây căng theo hướng bắc – nam) → `on_arrive`: vào đội ít người hơn (tối đa `team_size` 4 mỗi bên); mỗi bên đủ 3 người
  (hoặc chờ quá `gather_wait` mà mỗi bên có 2) là kéo; lực hai đội dao động ngẫu nhiên + cơn rướn; xong cuộc thì tan
  (dwell 0). Meta `tug` + `talking`.
- **Người chơi** (luôn ở đội 0, đứng đầu dây): nhìn người đang kéo "E: Xin kéo co cùng (chơi lại từ đầu)" (`join_at` — tỉ số
  về 0–0, hai đội chia lại cho cân) hoặc rủ qua hội thoại "… chơi kéo co với … không?" (trẻ con, trẻ chăn trâu, nông dân) →
  "(Căng dây ra kéo)" (`start_with`: dây căng ngang trước mặt 3 m, gọi ≤ 5 người rảnh trong 35 m, thiếu thì người làng bên
  — `_make_temp`). `refusal`: cụ già / người gánh hàng, đang học, tối, mưa, dở việc, chỗ chật (`open_ground`: hai phía 6,5 m
  không vướng). **Cách kéo:** Space / chuột trái (`fish_reel`) ĐÚNG NHỊP hò (`beat_period` 0,9 s, ±`beat_window`) → `power`
  +`hit_gain` ("Hò dô ta! ×n"), bấm lệch / bấm hai lần một nhịp → −`miss_loss` ("Lệch nhịp!"); `power` tự giảm
  `power_decay`/s. Lực đội mình = `my_base` + `my_gain` × power; đội kia = `their_base` + dao động + cơn rướn 2 s mỗi 6–10 s.
  Giao diện: tỉ số, thước dây (chấm đỏ), thước nhịp (chấm trắng vào vùng vàng), thanh sức; hết cuộc: E kéo lại, Esc thôi
  (cuộc ở bãi thì dân làng kéo tiếp, cuộc người chơi bày thì tan). Camera `TugCam` nhìn ngang. Tín hiệu
  `finished(won, mine, theirs)` → kỷ lục `tug_wins` / `tug_games` (sổ tay trang Kỷ lục).
- `step(dt)` tách riêng. `tools/tug_test.gd`: 8 người ở bãi tự kéo trọn một cuộc (2 hiệp, ~40 s) rồi tan; người chơi rủ ở
  sân nhà mình: trúng 100 % nhịp thắng 2–0 (~31 s), 80 % thắng 2–0, 60 % thắng sát nút 2–1, không bấm / bấm bừa thua 0–2;
  xin vào cuộc ở bãi (0–0, hiệp 1), Esc; từ chối cụ già / trời giông. Bài thử phải chạy với `timeout` (lỗi script trong
  bài thử thì SceneTree không tự thoát). Chụp ảnh: `--date=2027-06-20 --hour=16 --tug=12 --distance=13 --pitch=-24 --yaw=75`
  (dân làng kéo), thêm `--fp --focus=-30,-9` (bạn vào kéo).

## 44. Năm trò dân gian nhỏ: đá cầu, bắn bi, chơi chuyền, bịt mắt bắt dê, rồng rắn lên mây (giai đoạn 7h)

- `scripts/folk_games.gd` (`FolkGames`, node con CUỐI của `Main`) — MỘT script cho cả năm trò (`KINDS`: tên, số người
  `min` / `max`, trọng số; `ORDER`). Mỗi nhóm đang chơi là một từ điển trong `groups`: `kind`, `center`, `members`
  (Villager; người chơi là hình nhân `_avatar`, chỉ số `pi`), `st` (trạng thái riêng từng trò), `root` (đạo cụ),
  `site` (nhóm ở bãi của làng), `player`. `step(g, dt)` tách riêng; `_restart(g)` bắt đầu lại từ đầu; `stats` đếm sự kiện.
- **Trẻ con tự chơi:** việc `folk` của Villagers (trẻ con 3,0; trẻ chăn trâu 1,2; 7:00–17:36 trừ trưa, không mưa) →
  `site_target(v)` chọn trò (ưu tiên nhóm đang thiếu người; chơi chuyền chủ yếu con gái, bắn bi chủ yếu con trai), ghi meta
  `folk_kind` → tới bãi `sites[kind]` → `on_arrive`: meta `folk` (= tên trò) + `talking`. Đủ `min` người thì chơi; tan sau
  `game_seconds`, hết giờ chơi, mưa. Bãi (cỏ trống, chọn theo ảnh chụp từ trên xuống): đá cầu (−6; −21,5) và bắn bi
  (−12,5; −22,5) giữa hai đường đất ngoài cổng làng, chơi chuyền (−36; −26,5) cạnh tường trường, bịt mắt bắt dê (0,5; −2)
  trước sân nhà mình, rồng rắn (21; −9) bãi cỏ phía đông cây đa.
- **Đá cầu:** đứng vòng tròn `cau_radius`, quả cầu lông gà bay cung parabol từ người này sang người khác (`cau_flight`
  giây); máy đá hụt `cau_miss`; đếm số chạm liên tiếp. Người chơi: Space / chuột trái đúng lúc cầu rơi tới chân
  (±`cau_window`), thanh vàng đầy = tới nơi.
- **Bắn bi:** vòng phấn `bi_ring` có 5 viên, lần lượt ngồi ở vạch `bi_line` bắn viên bi cái; vật lý 2D tự viết (ma sát
  `bi_friction`, va chạm đàn hồi cùng khối lượng, 4 bước con mỗi khung); bi ra khỏi vòng là ăn; hết bi là xong ván. Người
  chơi: A / D ngắm (vạch vàng), giữ Space lấy lực (thanh chạy lên xuống), thả để bắn; lượt người chơi thì chờ không giới hạn.
- **Chơi chuyền:** ngồi xổm quanh 10 que; tung quả chuyền (`chuyen_flight` giây), trong lúc quả trên không phải nhặt đủ số
  que của bàn (bàn k nhặt k que một lần, đủ 10 que là xong bàn, tới `chuyen_max_ban` 5 là thắng); hỏng thì mất lượt, nhặt
  lại từ đầu bàn đó. Người chơi: Space tung, rồi bấm Space ĐÚNG số lần cần nhặt trước khi quả rơi.
- **Bịt mắt bắt dê:** vòng phấn `goat_ring`; người bịt mắt (dải vải đỏ `Blindfold` trên đầu, hai tay quờ quạng) lần theo
  tiếng "Be… be…" (`heard` — chỗ nghe thấy gần nhất, có sai lệch), dê né khi bị tới gần 2 m, bị dồn ra mép thì chạy men
  vòng; bắt được thì đổi người (người bắt mới đứng 3 s cho dê chạy ra — không thì bắt lại ngay đứa vừa bắt mình, đã gặp:
  39 lần bắt trong 90 s). Người chơi: màn hình tối, chữ "Be… be…!" loé lên đúng hướng mỗi lần dê kêu, W A S D để đi,
  `blind_seconds` 60; điểm = số giây còn dư.
- **Rồng rắn lên mây:** một đứa làm thầy thuốc, cả hàng bám vai nhau (`dragon_gap`) đi vòng quanh hát bốn câu (`CHANT`),
  rồi "Xin khúc đuôi!" → thầy thuốc đuổi chạm đứa cuối hàng trong `chase_seconds`; đầu rồng dang tay chắn — xoay cả hàng
  quanh tâm hàng để luôn ở giữa thầy thuốc và đuôi (đầu chỉ lùi theo thầy thuốc thì hàng không xoay, chạy vòng là bắt
  được ngay); bắt được thì đứa đuôi làm thầy thuốc. Người chơi là thầy thuốc: W A S D chạy (`player_speed`), không chạy
  xuyên qua đầu rồng; điểm = số giây còn dư.
- **Người chơi vào:** nhìn một đứa đang chơi "E: Xin chơi … cùng (chơi lại từ đầu)" (`join_at`; nhóm đủ người thì một đứa
  nhường chỗ) hoặc hội thoại → "Chơi gì không em?" → "Chơi trò khác (đá cầu, bắn bi, chuyền, bắt dê, rồng rắn)…" → chọn trò
  (`start_with(v, kind)`: bày ngay trước mặt, gọi trẻ rảnh trong 30 m, thiếu thì trẻ nhà bên). Camera `FolkCam` đứng ở phía
  người chơi vừa đứng (`_cam_dir`), W A S D tính theo hướng camera. Esc thôi (`finished(kind, score)` → kỷ lục `cau_best`,
  `bi_best`, `chuyen_best`, `goat_best`, `dragon_best` trong sổ tay); nhóm ở bãi thì bọn trẻ chơi tiếp.
- `tools/folk_test.gd` (chạy với `timeout`): 71 trẻ có thể ra chơi; mỗi trò tự chơi 90 s (đá cầu ~63 chạm / 8 lần rơi, bắn
  bi ~25 phát ăn ~8 viên, chuyền ~43 lần nhặt được / 4 lần hỏng, bắt dê ~7 lần, rồng rắn ~5 lần bắt đuôi), tan sạch meta;
  người chơi rủ từng trò, bot chơi (cầu 20–40 chạm, bi xong ván, chuyền hết 5 bàn, bắt dê, bắt đuôi) so với đứng yên (thua).
  Chụp ảnh: `--folk=da_cau|ban_bi|chuyen|bit_mat|rong_ran [--folk-time=giây]` (+ `--fp --focus=x,z` để vào chơi).

## 45. Hiệu năng phần script (giai đoạn 7i)

- `tools/perf_test.gd` (headless, chạy với `timeout`): Chủ nhật 15:00 (≈ 210 người ngoài đường), tua cho làng vào nếp rồi
  GỌI THẲNG `_process` / `_physics_process` của từng node 60 lần và bấm giờ — in tổng và 14 node tốn nhất, riêng Villagers
  tách người / con vật và số lần lên lịch lại mỗi khung. (Cách "tắt từng node rồi so thời gian khung" nhiễu ±1 ms, không dùng.)
- **Kết quả đo:** trước 3,05 ms / khung (Villagers 2,3 ms, River 0,5 ms, mọi thứ khác < 0,1 ms) → sau 1,63 ms
  (Villagers ~1,3 ms, River ~0,2 ms). Các trò chơi, lễ hội, mùa, chợ… đều < 0,1 ms khi không ai chơi.
- **Dân làng cập nhật theo khoảng cách** (`Villagers._process`): gần camera (< `close_distance` 45 m, không ở sau lưng
  camera) diễn hoạt mỗi khung; tới `animate_distance` 90 m diễn hoạt cách khung (`mid_tick_every` 2); ngoài tầm / sau lưng
  camera không diễn hoạt, bước đi cách khung; xa hơn `far_distance` 170 m hoặc đang trong nhà thì mỗi `far_tick_every` 4
  khung. Khung bị bỏ thì delta nhân lên tương ứng (đi vẫn đúng tốc độ), mỗi người lệch một nhịp (`_frame + chỉ số`) để chia
  đều. Con vật ngoài tầm cũng cách khung. `stat_next` / `stat_acts` đếm số lần `_next_activity` (người nào bị lên lịch lại
  mỗi khung là dấu hiệu lỗi — hiện ~0 lần / khung).
- **Một lần đặt vị trí mỗi bước đi** (`Villager._step_walk` + `_ground_y`): trước đây đặt `global_position` 2–3 lần mỗi bước
  (đi, rồi chỉnh độ cao), mỗi lần là cập nhật transform ~30 node con.
- **Cá sông** (`River._process`): camera cách tim sông hơn `fish_far_distance` 110 m thì 220 con cá chỉ bơi mỗi
  `far_fish_every` 4 khung (kiểm tra khoảng cách 2 lần / s).
- Đã chạy lại `market_test`, `festival_test`, `folk_test`, `tug_test` sau khi đổi: kết quả như cũ.

## 46. Tối ưu phần vẽ + dọn code trùng lặp (giai đoạn 8a)

- `tools/render_stats.gd` (chạy dưới xvfb với `timeout 290`): số vật thể / tam giác / draw call mỗi khung ở 4 góc nhìn (nhà mình,
  cổng làng, giữa làng, cả làng từ xa). `-- --breakdown` ẩn lần lượt từng nhóm dưới `World` để xem nhóm nào tốn (Villagers
  bị tạm dừng cho số liệu khỏi nhiễu); `--detail=Village` liệt kê từng node con của một nhóm. Số tam giác tính cả các lượt
  vẽ bóng. Lavapipe ~1 khung / giây nên chỉ đọc SỐ ĐẾM, không đọc ms.
- **Kết quả** (trước → sau): nhà mình 1.777 → 737 draw call, 4,45 → 1,80 triệu tam giác; cổng làng 1.817 → 957 / 4,28 → 1,72;
  giữa làng 1.286 → 636 / 4,20 → 1,67; cả làng từ xa 1.109 → 650 / 1,69 → 1,48.
- **Cây cỏ ven sông chia ô** (`River._multimesh`, `veg_cell` 48 m): trước đây mỗi loại (lau, bèo, cỏ đê, hoa dại, sen…) là MỘT
  MultiMesh cho cả con sông 1 km đặt ở gốc toạ độ → không bao giờ bị cắt, luôn vẽ ~2,2 triệu tam giác. Giờ mỗi ô một
  MultiMeshInstance đặt ở TÂM Ô (transform từng cây trừ đi tâm) với `visibility_range_end` riêng (lau 140, bèo / sen 120, cỏ 100,
  hoa 90 m) và không đổ bóng (chỉ chuối còn bóng). `veg_nodes` đếm số ô. **Bài học: visibility range tính từ gốc của node —
  MultiMesh trải rộng phải chia nhỏ và đặt node ở giữa vùng nó phủ.**
- **Người ở xa vẽ bằng hình đơn giản** (`Villager._build_lod`, `LOD_DISTANCE` 75 m ± `LOD_MARGIN`, `FAR_DISTANCE` 170 m): các
  mảnh có khớp (~12 mesh, ~2.100 tam giác) chỉ vẽ tới 75 m; xa hơn là MỘT mesh ~60 tam giác (quần, áo, đầu, nón / khăn / tóc
  theo màu của người đó, dùng chung qua bộ đệm mesh), không đổ bóng; đổi bộ đồ (`wear`) thì đổi màu theo. Trâu, chó giữ nguyên.
- **Bóng người chỉ ở gần** (`Villagers.shadow_distance` 42 m → `Villager.set_shadows`): mỗi mảnh đổ bóng là thêm một draw call
  cho từng tầng bóng.
- **Tầm bóng mặt trời theo độ cao camera** (`DayNight.shadow_distance_range` 70…140 m, `shadow_per_height` 2,2; chỉnh 4 lần / s):
  nhìn gần / nhập vai thì bóng chỉ phủ 70 m, zoom ra xa mới phủ 140 m (trước đây cố định 140 m).
- **Code dùng chung** `scripts/game_kit.gd` (`GameKit`, hàm tĩnh): `label`, `top_panel`, `big_label`, `bar`, `make_person`,
  `make_avatar`, `animate_owned`, `bark` — nhảy dây, đánh khăng, kéo co, năm trò nhỏ dùng chung thay cho bốn bản chép gần giống
  nhau (bớt ~210 dòng). Trò mới nên dùng thẳng `GameKit`.
- **Lỗi tìm ra khi chạy lại bài thử:** `HideSeek._process_ambient` — đứa đi tìm bị Villagers gọi đi giữa ván (tới giờ học) thì
  `g.seeker` rỗng → lỗi mỗi khung; giờ tan ván êm.
- Đã chạy lại: `jump_rope_test`, `tip_cat_test`, `tug_test`, `folk_test`, `school_calendar_test`, `perf_test` (script ~1,8 ms / khung).
- Đổi file script có `class_name` mới thì phải `--import` trước khi chạy công cụ `-s` khác (đã gặp: ảnh chụp chạy song song
  lúc đang thêm `GameKit` báo "Identifier not declared").

## 47. Đồ hoạ chân thật hơn (giai đoạn 8b)

- Người dùng muốn cảnh "chân thật hơn": GIỮ hình khối low-poly và bảng màu, nâng phần ánh sáng / khí quyển / bề mặt. Vì thế
  các quy tắc ở mục 3 được nới: có glow NHẸ, có một lớp vân bề mặt (texture nhiễu tạo bằng code), nước không còn phẳng từng mặt.
- `scripts/graphics.gd` (`Graphics`, node con của `Main`): ba mức `quality` — **0 Nhẹ** (như trước, cho máy yếu / Compatibility),
  **1 Vừa**, **2 Cao** (mặc định). Phím **G** (`cycle_quality`) đổi mức, hiện chữ báo; mức được lưu cùng game (`quality`).
  `apply()` bật / tắt theo mức; renderer Compatibility thì bỏ SSAO / SSIL / sương thể tích.
  - **Vừa:** đổ bóng tiếp xúc SSAO (`ssao_radius` 1,4, `ssao_intensity` 1,7 — gầm hiên, chân tường, kẽ nhà tối lại), glow nhẹ
    kiểu softlight (`glow_intensity` 0,42 — đèn lồng, cửa sổ đêm, mặt nước loé nắng), mây ti trên trời, vân bề mặt.
  - **Cao:** thêm ánh sáng dội SSIL, sương thể tích (`volumetric_density` 0,0035 → `volumetric_mist_density` 0,02 khi sương mù;
    tia nắng, quầng quanh đèn ban đêm), bóng mặt trời mềm dần khi xa vật (`sun_angular_distance` 0,55°).
- **Bầu trời** `shaders/sky.gdshader` (thay `ProceduralSkyMaterial`, dùng ở mọi mức): dải màu chân trời → đỉnh trời, quầng sáng rộng
  quanh mặt trời + vệt sáng sát chân trời, đĩa mặt trời / mặt trăng (cùng một đèn — ban đêm đèn là trăng), sao đêm (ẩn khi mây
  phủ), mây ti mỏng (fbm). KHÔNG dùng `TIME` trong shader trời (bản đồ phản chiếu sẽ phải vẽ lại mỗi khung) — mây trôi bằng
  `cloud_shift` do Graphics đẩy 2 lần / s. `DayNight._apply` đặt `horizon_color`, `top_color`, `ground_color`, `night`, `cover`
  (vẫn đặt được cho `ProceduralSkyMaterial` nếu ai đổi lại).
- **Mặt nước** `shaders/water.gdshader`: pháp tuyến pha giữa mặt phẳng từng tam giác và gợn sóng nhỏ mịn (`smoothness` 0,75,
  `ripple_strength`; gió to / mưa thì gợn mạnh), Fresnel — nhìn xiên thì ngả màu trời, đục và bóng hơn (phản chiếu trời + loé
  nắng), nhìn thẳng xuống thì trong. Vẫn không dùng depth texture.
- **Vân bề mặt** (`grain_strength` 0,16, `grain_scale`): `NoiseTexture2D` tạo bằng code, phủ ba chiều theo toạ độ thế giới
  (`uv1_world_triplanar`) lên vật liệu dùng chung `MeshBuilder.material()` và nền cỏ của Seasons → đất, tường, mái, đá hết phẳng
  lì; màu đỉnh × vân nên bảng màu chỉ sẫm đi vài phần trăm. Lá / lúa (shader gió) không đổi.
- Chụp ảnh: `--quality=0|1|2`. So sánh nhanh: `--hour=16 --focus=-10,-4 --distance=13 --pitch=-22 --yaw=20` (sân nhà: vân + bóng
  hiên), `--hour=17.6 --pitch=-12 --distance=24 --focus=6,2 --yaw=20` (trời + ao), `--hour=21 --pitch=-14` (sao).
- Chưa đo FPS thật (máy cloud vẽ bằng phần mềm). SSIL và sương thể tích là hai thứ nặng nhất — máy yếu bấm G về "Vừa".

## 48. Túi đồ và tiền (giai đoạn 9a)

- `scripts/inventory.gd` (`Inventory`, `CanvasLayer` con CUỐI của `Main`, `layer` 19). Gộp những thứ trước đây rải rác:
  tiền (`Market.money` cũ), đồ mua ở chợ (`Market.bag` cũ), quà của việc nhờ (giờ là vật phẩm thật; `Quests.gifts` chỉ còn là
  lịch sử tên quà), cá trong giỏ (vẫn ở `Fishing.basket`, hiện ở ngăn "Giỏ cá"). Đơn vị: nghìn đồng.
- **Danh mục** `ITEMS` (31 món): mã → `name`, `cat` (food / tool / goods), `price`, `stall` (sạp chợ mua lại, "" = không ai
  mua), `icon`, `use` (eat / drink / bait / kite / flute / ""), `energy` (giây no bụng), `desc`, `likes` (vai thích được biếu),
  `alias` (tên cũ). `Market.STALLS[].items` và `Quests.GIFTS` dùng MÃ vật phẩm; giá lấy từ danh mục. `items` (mã → số),
  `order` (thứ tự thêm vào); `add` / `remove` / `earn` / `spend` (false nếu không đủ) / `count`; tín hiệu `changed`, `used`.
- **Công dụng:** ăn / uống → `energy` giây thật (trần `energy_cap` 360): Inventory ĐẨY hệ số sang `FirstPerson.run_boost` (1,25),
  `BoatRace.stamina_scale` (0,6), `TugOfWar.decay_scale` (0,7) — các phần đó không cần biết Inventory. Hộp mồi giun →
  `Fishing.bait` += `bait_per_box` (5); mỗi lần quăng cần tốn một lượt (`_baited`): chờ cá × `bait_factor` 0,5, tầm dụ cá × 1,4.
  Diều giấy → `KiteFlying.start(null)` (thả diều của mình, không có đứa trẻ đứng cạnh; điều kiện `self_refusal`: giờ, thời
  tiết, chỗ thoáng); đứt dây thì mất diều (`flying_own_kite`). Sáo trúc → tiếng `flute` (Soundscape: câu nhạc ngũ cung, rung,
  hơi thổi), trẻ con / cụ già trong 14 m khen.
- **Kiếm tiền / đồ:** bán cá (hàng cá) và bán lại đồ cho sạp đúng loại (`Market.sellable`, `resell_ratio` nửa giá) — câu
  "{Npc} có mua lại đồ của {me} không?"; việc nhờ: quà vào túi + người lớn trả tiền công `Quests.PAY` (3–8 nghìn, trẻ con không
  trả); nhất đua thuyền `race_prize` 10 nghìn (thuyền đơn 2 nghìn mỗi thuyền thua); thắng kéo co → gói kẹo lạc; thắng ô ăn quan
  (ván chơi hết) → bánh đa; mừng tuổi Tết (Festival cộng / trừ qua `earn` / `spend`). `earned` / `spent` để sổ tay ghi.
- **Chợ** (`Market`): mua / bán theo trang (`_paged`: 3 món, hoặc 2 món + "Món khác…" + câu thôi — khung thoại tối đa 4 lựa chọn).
  Hàng mới: hộp mồi giun (hàng cá), diều giấy + sáo trúc (nón quạt), khoai (rau), ổi (hoa quả), xôi lạc (gạo), con quay + bi (bánh kẹo).
- **Biếu quà** (`Inventory.dialog_options` → Dialogue, sau câu của chợ): ai cũng nhận; đúng món thích (`likes`) thì `_met` +3 và
  lời cảm ơn riêng, không thì +2.
- **Màn hình túi đồ** (phím I, `toggle_inventory`): giấy như sổ tay, túi tiền góc trên phải; 5 ngăn (Tất cả, Đồ ăn, Đồ dùng, Đồ đạc,
  Giỏ cá); lưới 5 cột ô có **biểu tượng vẽ bằng code** (lớp trong `ItemIcon` — `_draw()` hình phẳng theo `icon`, màu `Palette.ICON_*`
  bổ sung); bên phải chi tiết món (mô tả, công dụng, giá bán lại, ai thích), nút Dùng / Bỏ đi 1; dòng trạng thái: no bụng còn bao
  lâu, mồi còn mấy lượt, đồ đang cầm cho việc nhờ, đã kiếm / tiêu. A / D đổi ngăn, W / S chọn, E dùng, I / Esc gấp. Mở như sổ tay:
  không khi đang trò chuyện / chơi trò gì / sổ tay đang mở; nhập vai thì `_suspend("inventory")`. HUD có tiền ở dòng thông tin
  (`Hud.money_text`). Chữ báo (`toast`) hiện cả khi túi gấp.
- **Lưu** (`SaveGame` VERSION 2): `inventory` = `snapshot()` (tiền, đồ + thứ tự, no bụng, đã kiếm / tiêu, mồi). File bản trước
  (`money`, `bag`, `gifts` dạng tên) → `load_legacy` đổi tên ra mã (`id_of`, có `alias`).
- `tools/inventory_test.gd` (chạy với `timeout`): danh mục đủ, mua / không đủ tiền / bán lại / bán cá, ăn → hệ số chạy / chèo / kéo co
  rồi hết, mồi giun, biếu quà (+3 / +2), việc nhờ (quà + tiền công), thưởng trò chơi, thả diều của mình + đứt dây mất diều, sáo,
  màn hình (ngăn, mở / gấp, không mở khi trò chuyện), nạp file cũ. Hiệu ứng đẩy trong `_process` — bài thử chờ `process_frame`
  (chờ `physics_frame` thì sau lúc dựng cảnh nặng nhiều bước vật lý dồn vào một khung, `_process` chưa chạy).
- Chụp ảnh: `--inventory[=0..4]` (mở túi ở ngăn đó, kèm đồ mẫu).
