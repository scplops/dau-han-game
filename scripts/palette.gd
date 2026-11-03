class_name Palette
## Bảng màu của toàn cảnh. Mọi script lấy màu từ đây, không viết mã hex ở nơi khác.

# Bầu trời & ánh sáng
const SKY := Color("#f6e7c8")
const SKY_TOP := Color("#dfe3cf")        # đỉnh trời chiều, kem ngả xanh rất nhạt
const SUN := Color("#f7c873")
const AMBIENT := Color("#e9dcc0")        # ánh sáng môi trường ấm
const FOG := Color("#f2e4c6")            # sương màu kem

# Chu kỳ ngày đêm (bổ sung). Màu chiều 17:00 là SUN / SKY / SKY_TOP / AMBIENT / FOG ở trên.
const SUN_DAWN := Color("#ffb08a")       # sáng sớm: hồng nhạt
const SKY_DAWN := Color("#f3c6b8")
const SKY_DAWN_TOP := Color("#b7c3d9")
const AMBIENT_DAWN := Color("#dcc3c6")
const FOG_DAWN := Color("#eccdc4")
const SUN_NOON := Color("#fff4e0")       # trưa: trắng ấm
const SKY_NOON := Color("#eef1e2")
const SKY_NOON_TOP := Color("#a9cde0")
const AMBIENT_NOON := Color("#e6e8dc")
const FOG_NOON := Color("#e9ecdf")
const SUN_SUNSET := Color("#f2955a")     # hoàng hôn: cam
const SKY_SUNSET := Color("#f2b385")
const SKY_SUNSET_TOP := Color("#c4b3c6")
const AMBIENT_SUNSET := Color("#d9b5a3")
const FOG_SUNSET := Color("#e9c19f")
const MOON_DUSK := Color("#9aa6e0")      # chạng vạng: tím
const SKY_DUSK := Color("#6a6797")
const SKY_DUSK_TOP := Color("#343a6a")
const AMBIENT_DUSK := Color("#6c6fa8")
const FOG_DUSK := Color("#55577f")
const MOON := Color("#a9b6ea")           # đêm: xanh tím đậm
const SKY_NIGHT := Color("#2f3768")
const SKY_NIGHT_TOP := Color("#151b3c")
const AMBIENT_NIGHT := Color("#56609c")
const FOG_NIGHT := Color("#283058")
const FIREFLY := Color("#d8f27a")
const SMOKE := Color("#ece6da")

# Núi xa
const MOUNTAIN := Color("#9bb3a4")
const MOUNTAIN_DARK := Color("#87a291")

# Nền & ruộng
const GRASS := Color("#8fbf5a")
const RICE_1 := Color("#b5d66b")
const RICE_2 := Color("#a6cc5f")
const RICE_3 := Color("#c9dd74")
const RICE_FURROW := Color("#7fa84a")
const DIKE := Color("#8a9a4a")           # bờ ruộng phủ cỏ (bổ sung)
const EARTH := Color("#a98b66")          # đất đường đi, bờ ao (bổ sung)

# Nước
const WATER := Color("#6fb0c2")
const WATER_LIGHT := Color("#84c3d2")

# Nhà
const WALL := Color("#e8d6b0")
const WALL_DARK := Color("#d4bd92")
const YARD := Color("#c9a77a")
const ROOF := Color("#c4563f")
const ROOF_DARK := Color("#a8432f")
const WOOD := Color("#7a5233")
const WOOD_LIGHT := Color("#8f6540")     # cánh cửa (bổ sung)
const PLINTH := Color("#b8a888")         # nền nhà, bậc thềm (bổ sung)
const GROUT := Color("#9c8466")          # mạch vữa sân gạch (bổ sung)
const WINDOW_DARK := Color("#3a2c22")    # ô cửa ban ngày (bổ sung)
const WINDOW_GLOW := Color("#ffc56b")    # ánh đèn trong nhà ban đêm (bổ sung)
const FIRE_GLOW := Color("#ff9a4a")      # ánh lửa bếp (bổ sung)

# Tre
const BAMBOO_STEM := Color("#7d8f3a")
const BAMBOO_NODE := Color("#677730")     # đốt tre (bổ sung)
const BAMBOO_LEAF := Color("#6e9a3c")
const BAMBOO_LEAF_DARK := Color("#5d8a32")

# Cây đa
const BANYAN_LEAF_1 := Color("#4f7d38")
const BANYAN_LEAF_2 := Color("#5c8f40")
const BANYAN_LEAF_DARK := Color("#426b2f")
const BANYAN_TRUNK := Color("#6b4a2e")

# Trâu
const BUFFALO := Color("#5a5552")
const BUFFALO_DARK := Color("#4a4543")
const BUFFALO_HORN := Color("#d9cfc0")

# Người nông dân
const FARMER_SHIRT := Color("#3f6f8f")
const FARMER_SKIN := Color("#e3b58c")
const FARMER_PANTS := Color("#5a3d28")
const HAT := Color("#efd9a0")
const HAT_DARK := Color("#d8c084")

# Chi tiết nhỏ (bổ sung)
const ROCK := Color("#a29d8c")
const ROCK_DARK := Color("#87836f")
const JAR := Color("#8a5a3b")            # chum nước
const STRAW := Color("#d9b862")          # đống rơm
const LILY := Color("#5f9a45")           # lá súng
const LOTUS := Color("#f2a7b8")          # hoa sen
const FLOWER_WHITE := Color("#f4f0e2")
const FLOWER_YELLOW := Color("#f2d25a")
const FLOWER_PINK := Color("#eba3c0")
const DUCK := Color("#f3efe4")
const BEAK := Color("#e59a3a")
const CLOUD := Color("#fbf7ee")

# HUD (bổ sung)
const HUD_TEXT := Color("#fdf8ec")
const HUD_SUBTEXT := Color("#e9dfc8")
const HUD_BG := Color(0.17, 0.14, 0.11, 0.55)

# Trong nhà (bổ sung)
const FLOOR := Color("#b4704e")          # gạch đỏ lát nền
const ALTAR_RED := Color("#8e2f22")      # sơn son bàn thờ, hoành phi
const GOLD := Color("#d8a942")           # thếp vàng, đồ đồng
const CERAMIC := Color("#ebe6da")        # gốm sứ: bát hương, ấm chén
const MAT := Color("#d9c58f")            # chiếu cói
const BLANKET := Color("#7b9bb6")
const PILLOW := Color("#f1ece0")
const SACK := Color("#e6dbbd")           # bao gạo
const FADE := Color("#000000")           # màn chuyển cảnh

# Làng (bổ sung)
const WALL_WHITE := Color("#ece6d6")     # tường vôi trắng
const BRICK := Color("#a95a40")          # gạch trần
const BRICK_DARK := Color("#8e4733")
const MUD := Color("#b39370")            # vách đất
const THATCH := Color("#c7a564")         # mái rơm rạ
const THATCH_DARK := Color("#a78748")
const ROOF_BROWN := Color("#8f4a36")     # ngói cũ màu nâu
const ROOF_BROWN_DARK := Color("#743a2b")
const LANE_BRICK := Color("#b0654a")     # gạch lát đường làng
const LANE_BRICK_DARK := Color("#9a5640")
const HEDGE := Color("#4f7f36")          # dậu cây
const HIBISCUS := Color("#d9473e")       # hoa dâm bụt
const ARECA_TRUNK := Color("#9a9580")    # thân cau
const BANANA := Color("#86b84e")         # lá chuối
const VEGETABLE := Color("#5f9e3e")      # luống rau
