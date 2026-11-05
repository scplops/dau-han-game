class_name VillageHouse
extends RefCounted
## Sinh và dựng nhà trong làng. Mỗi nhà là một tổ hợp KHÔNG TRÙNG của:
##   số gian · loại mái · kiểu mái · tường · mặt tiền · bố cục lô
## cộng thêm tỉ lệ, rào, sân, vườn ngẫu nhiên theo seed.
## Toạ độ lô: gốc ở giữa mép trước (giáp ngõ), +z hướng ra ngõ (hướng nam), lô nằm ở z âm.

const BAYS: Array[int] = [2, 3, 4, 5]
const ROOFS: Array[String] = ["tile_red", "tile_brown", "thatch"]
const FORMS: Array[String] = ["gable", "hip", "gable_wall"]
const WALLS: Array[String] = ["lime_yellow", "lime_white", "brick", "mud"]
const FRONTS: Array[String] = ["veranda_wood", "veranda_brick", "panel_doors"]
const LAYOUTS: Array[String] = ["single", "L_left", "L_right", "U", "kitchen"]
## Nửa bề rộng lối đi để trống thẳng trước cửa chính (nhà phụ không được lấn vào).
const door_lane_half := 1.0
const FENCES: Array[String] = ["brick_wall", "bamboo_fence", "hibiscus_hedge", "low_edge"]
const GARDEN: Array[String] = ["areca", "banana", "fruit_tree", "vegetables", "haystack", "water_tank", "trellis"]


# --- Chọn kiểu ------------------------------------------------------------------------

static func _valid(roof: String, form: String, wall: String, front: String) -> bool:
	if roof == "thatch":
		return wall in ["mud", "lime_yellow"] and form != "gable_wall" and front != "veranda_brick"
	return wall != "mud"


## Tất cả tổ hợp hợp lệ, xáo trộn theo seed.
static func all_styles(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in BAYS:
		for r in ROOFS:
			for f in FORMS:
				for w in WALLS:
					for fr in FRONTS:
						if not _valid(r, f, w, fr):
							continue
						for l in LAYOUTS:
							out.append({"bays": b, "roof": r, "form": f, "wall": w, "front": fr, "layout": l})
	# Xáo trộn theo seed; nhà tranh được ưu tiên lên trước để chiếm khoảng 1/3 làng
	# (tổ hợp mái rạ ít hơn mái ngói nên nếu xáo đều sẽ rất hiếm)
	var keyed: Array = []
	for st in out:
		var k := rng.randf() * (0.35 if st.roof == "thatch" else 1.0)
		keyed.append([k, st])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var sorted: Array[Dictionary] = []
	for item in keyed:
		sorted.append(item[1])
	return sorted


static func signature(style: Dictionary) -> String:
	return "%d|%s|%s|%s|%s|%s" % [style.bays, style.roof, style.form, style.wall, style.front, style.layout]


## Bề rộng lô tối thiểu cho kiểu nhà (nhà + lối hai bên).
static func min_plot_width(style: Dictionary) -> float:
	var w: float = style.bays * 2.9 + 2.4
	if style.layout == "U":
		w = maxf(w, 12.5)
	return w


## Chọn kiểu cho lô rộng `width`: chưa dùng, vừa lô, và khác nhà bên cạnh về mái + tường.
static func pick_style(pool: Array[Dictionary], used: Dictionary, width: float,
		prev: Dictionary) -> Dictionary:
	var fallback: Dictionary = {}
	for st in pool:
		if used.has(signature(st)) or min_plot_width(st) > width:
			continue
		if prev.is_empty() or (st.roof != prev.roof and st.wall != prev.wall):
			return st
		if fallback.is_empty():
			fallback = st
	return fallback


# --- Màu ------------------------------------------------------------------------------

static func wall_color(wall: String) -> Color:
	match wall:
		"lime_white": return Palette.WALL_WHITE
		"brick": return Palette.BRICK
		"mud": return Palette.MUD
	return Palette.WALL


static func wall_dark(wall: String) -> Color:
	match wall:
		"lime_white": return Palette.WALL_WHITE.darkened(0.14)
		"brick": return Palette.BRICK_DARK
		"mud": return Palette.MUD.darkened(0.16)
	return Palette.WALL_DARK


static func roof_colors(roof: String) -> Array[Color]:
	match roof:
		"tile_brown": return [Palette.ROOF_BROWN, Palette.ROOF_BROWN_DARK]
		"thatch": return [Palette.THATCH, Palette.THATCH_DARK]
	return [Palette.ROOF, Palette.ROOF_DARK]


static func _t(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


# --- Mái --------------------------------------------------------------------------------

## Mái trên tường cao `top_y`, nhà dài `len_` (trục x), sâu `dep` (trục z).
## form: "gable" (hai mái), "hip" (bốn mái, có đầu đao nếu lợp ngói), "gable_wall" (tường hồi bít đốc).
static func roof(mb: MeshBuilder, xf: Transform3D, len_: float, dep: float, top_y: float,
		rise: float, over: float, gover: float, roof_kind: String, form: String,
		wall_col: Color, wall_dk: Color) -> void:
	var cols := roof_colors(roof_kind)
	var thatch := roof_kind == "thatch"
	var thick := 0.34 if thatch else 0.14
	# Khối hồi lấp gầm mái
	mb.add_wedge(Vector3(len_, rise, dep), wall_dk, xf * _t(0.0, top_y, 0.0), wall_col)
	var half := dep * 0.5
	var tan_a := rise / half
	var run := half + over
	var eave_y := top_y - over * tan_a
	var ridge_y := top_y + rise

	if form == "hip":
		var ex := len_ * 0.5 + gover
		var rl := maxf(ex - run, 0.4)
		var ey := eave_y
		var ry := ridge_y + thick
		var c := [Vector3(-ex, ey, run), Vector3(ex, ey, run), Vector3(ex, ey, -run), Vector3(-ex, ey, -run)]
		var r0 := Vector3(-rl, ry, 0.0)
		var r1 := Vector3(rl, ry, 0.0)
		var inside := Vector3(0.0, ey + (ry - ey) * 0.3, 0.0)
		mb.add_quad(c[0], c[1], r1, r0, cols[0], inside, xf)   # mái trước
		mb.add_quad(c[3], c[2], r1, r0, cols[0], inside, xf)   # mái sau
		mb.add_triangle(c[0], c[3], r0, cols[0], inside, xf)   # mái đầu hồi trái
		mb.add_triangle(c[1], c[2], r1, cols[0], inside, xf)   # mái đầu hồi phải
		mb.add_quad(c[0], c[1], c[2], c[3], cols[1], inside, xf)
		if not thatch:
			# Hàng ngói ống trên hai mái chính (ngắn dần ở phần đầu hồi)
			var slope_len := Vector2(run, ry - ey).length()
			var a := atan2(ry - ey, run)
			var x := -ex + 0.2
			var k := 0
			while x < ex - 0.1:
				var l := slope_len
				if absf(x) > rl:
					l = slope_len * clampf((ex - absf(x)) / (ex - rl), 0.0, 1.0)
				if l > 0.3:
					for s in [1.0, -1.0]:
						var b := Basis(Vector3.RIGHT, s * a)
						var start := Vector3(x, ey, s * run)
						var dir := b * Vector3(0.0, 0.0, -s)  # từ diềm lên nóc
						var mid := start + dir * (l * 0.5)
						mb.add_box(Vector3(0.13, 0.06, l), cols[1] if k % 2 == 0 else cols[0],
								xf * Transform3D(b, mid + b * Vector3(0.0, 0.0, 0.0)))
				x += 0.4
				k += 1
			# Bờ nóc, bờ dải, đầu đao cong vút ở 4 góc
			mb.add_box(Vector3(rl * 2.0 + 0.3, 0.3, 0.36), cols[1], xf * _t(0.0, ry - 0.08, 0.0))
			for i in 4:
				var corner: Vector3 = c[i]
				var top := r0 if corner.x < 0.0 else r1
				mb.add_limb(corner, top, 0.1, 0.09, 4, cols[1], xf)
				var out := Vector3(signf(corner.x), 0.0, signf(corner.z)).normalized()
				mb.add_limb(corner, corner + out * 0.55 + Vector3(0, 0.75, 0), 0.13, 0.02, 4, cols[1], xf)
			for s in [-1.0, 1.0]:
				mb.add_limb(Vector3(s * rl, ry, 0), Vector3(s * (rl + 0.35), ry + 0.55, 0), 0.12, 0.03, 4, cols[1], xf)
		else:
			mb.add_prism(0.28, 0.28, rl * 2.0 + 0.4, 6, cols[1],
					xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(rl + 0.2, ry - 0.1, 0.0)))
		return

	# Hai mái (gable / gable_wall)
	var go := 0.04 if form == "gable_wall" else gover
	var a2 := atan(tan_a)
	var slope_len2 := run / cos(a2)
	var roof_len := len_ + go * 2.0
	for s in [1.0, -1.0]:
		var basis := Basis(Vector3.RIGHT, s * a2)
		var mid := Vector3(0.0, ridge_y - run * 0.5 * tan_a, s * run * 0.5)
		var sx := xf * Transform3D(basis, mid)
		mb.add_box(Vector3(roof_len, thick, slope_len2), cols[0], sx)
		if thatch:
			# Mép rạ dày và sẫm ở diềm
			mb.add_box(Vector3(roof_len + 0.1, thick + 0.08, 0.35), cols[1], sx * _t(0.0, -0.04, slope_len2 * 0.5 - 0.17))
		else:
			var x := -roof_len * 0.5 + 0.2
			var k := 0
			while x < roof_len * 0.5:
				mb.add_box(Vector3(0.13, 0.06, slope_len2), cols[1] if k % 2 == 0 else cols[0], sx * _t(x, thick, 0.0))
				x += 0.4
				k += 1
	if thatch:
		mb.add_prism(0.3, 0.3, roof_len + 0.2, 6, cols[1],
				xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(roof_len * 0.5 + 0.1, ridge_y + 0.05, 0.0)))
	else:
		mb.add_box(Vector3(roof_len + 0.15, 0.3, 0.38), cols[1], xf * _t(0.0, ridge_y - 0.04, 0.0))
	if form == "gable_wall":
		# Tường hồi xây cao hơn mái + "tay ngai" hai bên
		for s in [-1.0, 1.0]:
			var gx: float = s * (len_ * 0.5 + 0.05)
			mb.add_wedge(Vector3(0.3, ridge_y - eave_y + 0.32, dep + over * 2.0 + 0.2), wall_col,
					xf * _t(gx, eave_y - 0.02, 0.0))
			for z in [-1.0, 1.0]:
				mb.add_box(Vector3(0.42, 0.8, 0.42), wall_col, xf * _t(gx, eave_y - 0.55, z * (run + 0.05)))
				mb.add_pyramid(0.3, 0.3, 4, wall_dk, xf * _t(gx, eave_y + 0.25, z * (run + 0.05)))
	elif not thatch:
		for s in [-1.0, 1.0]:
			mb.add_limb(Vector3(s * roof_len * 0.5, ridge_y + 0.15, 0.0),
					Vector3(s * (roof_len * 0.5 + 0.3), ridge_y + 0.7, 0.0), 0.14, 0.03, 4, cols[1], xf)


# --- Nhà chính ------------------------------------------------------------------------

## Dựng nhà chính theo kiểu `st`, gốc toạ độ ở giữa nền nhà, mặt trước hướng +z.
## Trả về thông số nội thất (Interior.load_spec) kèm "door": vị trí ô cửa chính (world).
static func build_house(mb: MeshBuilder, glow: MeshBuilder, xf: Transform3D, st: Dictionary,
		dims: Dictionary) -> Dictionary:
	var bays: int = st.bays
	var bw: float = dims.bay
	var L := bays * bw
	var D: float = dims.depth
	var H: float = dims.height
	var P: float = dims.plinth
	var wc := wall_color(st.wall)
	var wd := wall_dark(st.wall)
	var veranda: float = 1.4 if st.front != "panel_doors" else 0.0
	var core := D - veranda
	var front_z := -D * 0.5 + core

	mb.add_box(Vector3(L + 0.7, P, D + 0.7), Palette.PLINTH, xf)
	mb.add_box(Vector3(minf(2.6, L * 0.5), P * 0.5, 0.45), Palette.PLINTH, xf * _t(0.0, 0.0, (D + 0.7) * 0.5 + 0.22))
	mb.add_box(Vector3(L, H, core), wc, xf * _t(0.0, P, -D * 0.5 + core * 0.5))
	mb.add_box(Vector3(L + 0.05, 0.32, core + 0.05), wd, xf * _t(0.0, P, -D * 0.5 + core * 0.5))
	if st.wall == "brick":
		# Mạch vữa ngang trên tường gạch
		var y := P + 0.5
		while y < P + H - 0.1:
			mb.add_box(Vector3(L + 0.02, 0.03, core + 0.02), wd, xf * _t(0.0, y, -D * 0.5 + core * 0.5))
			y += 0.42

	match st.front:
		"veranda_wood":
			for i in bays + 1:
				var x := -L * 0.5 + 0.2 + (L - 0.4) * i / bays
				mb.add_box(Vector3(0.32, 0.12, 0.32), Palette.PLINTH, xf * _t(x, P, D * 0.5 - 0.22))
				mb.add_prism(0.11, 0.1, H - 0.12, 6, Palette.WOOD, xf * _t(x, P + 0.12, D * 0.5 - 0.22))
			mb.add_box(Vector3(L, 0.2, 0.22), Palette.WOOD, xf * _t(0.0, P + H - 0.2, D * 0.5 - 0.22))
		"veranda_brick":
			var col_c := wc if st.wall != "lime_yellow" else Palette.WALL_WHITE
			for i in bays + 1:
				var x := -L * 0.5 + 0.2 + (L - 0.4) * i / bays
				mb.add_box(Vector3(0.34, H, 0.34), col_c, xf * _t(x, P, D * 0.5 - 0.22))
			mb.add_box(Vector3(L + 0.1, 0.32, 0.3), wd, xf * _t(0.0, P + H - 0.32, D * 0.5 - 0.22))

	if st.front == "panel_doors":
		# Cửa bức bàn: cả mặt tiền là ván gỗ, khe thông gió phía trên phát sáng ban đêm
		for i in bays:
			var cx := -L * 0.5 + bw * (i + 0.5)
			mb.add_box(Vector3(bw - 0.22, H - 0.3, 0.08), Palette.WOOD_LIGHT, xf * _t(cx, P + 0.05, front_z))
			for k in 4:
				var sx := cx - (bw - 0.4) * 0.5 + (bw - 0.4) * k / 3.0
				mb.add_box(Vector3(0.05, H - 0.3, 0.05), Palette.WOOD, xf * _t(sx, P + 0.05, front_z + 0.06))
			glow.add_box(Vector3(bw * 0.55, 0.22, 0.04), Palette.WINDOW_DARK, xf * _t(cx, P + H - 0.55, front_z + 0.07))
		for i in bays + 1:
			mb.add_box(Vector3(0.2, H, 0.2), Palette.WOOD, xf * _t(-L * 0.5 + bw * i, P, front_z))
	else:
		# Cửa giữa + cửa sổ có song ở các gian bên
		var mid := bays >> 1
		for i in bays:
			var cx := -L * 0.5 + bw * (i + 0.5)
			if i == mid:
				mb.add_box(Vector3(1.4, 2.0, 0.1), Palette.WOOD, xf * _t(cx, P, front_z))
				mb.add_box(Vector3(1.2, 1.85, 0.06), Palette.WOOD_LIGHT, xf * _t(cx, P + 0.05, front_z + 0.06))
				mb.add_box(Vector3(0.04, 1.85, 0.04), Palette.WOOD, xf * _t(cx, P + 0.05, front_z + 0.1))
			else:
				mb.add_box(Vector3(1.15, 1.0, 0.1), Palette.WOOD, xf * _t(cx, P + 0.85, front_z))
				glow.add_box(Vector3(0.95, 0.8, 0.04), Palette.WINDOW_DARK, xf * _t(cx, P + 0.95, front_z + 0.07))
				for k in 4:
					mb.add_box(Vector3(0.05, 0.8, 0.05), Palette.WOOD, xf * _t(cx - 0.36 + k * 0.24, P + 0.95, front_z + 0.11))
	# Cửa sổ tròn trên tường hồi (một số nhà)
	if dims.round_window:
		for s in [-1.0, 1.0]:
			var rw := Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(s * (L * 0.5 + 0.02), P + H * 0.62, -D * 0.5 + core * 0.5))
			glow.add_prism(0.32, 0.32, 0.04, 10, Palette.WINDOW_DARK, xf * rw)

	roof(mb, xf, L, D, P + H, dims.rise, dims.over, dims.gover, st.roof, st.form, wc, wd)

	var door_x := -L * 0.5 + bw * ((bays >> 1) + 0.5)
	return {
		"kind": "home", "bays": bays, "bay": bw, "depth": D, "veranda": veranda,
		"height": H, "plinth": P, "wall": st.wall, "front": st.front, "roof": st.roof,
		"door": xf * _t(door_x, P + 1.05, front_z + 0.14),
		"door_x": door_x,
	}


## Mô tả ngắn cho gợi ý khi rê chuột, ví dụ "Nhà 3 gian · mái rạ · tường đất".
static func describe(st: Dictionary) -> String:
	var roofs := {"tile_red": "mái ngói đỏ", "tile_brown": "mái ngói nâu", "thatch": "mái rạ"}
	var walls := {"lime_yellow": "tường vôi vàng", "lime_white": "tường vôi trắng", "brick": "tường gạch", "mud": "vách đất"}
	return "Nhà %d gian · %s · %s" % [st.bays, roofs.get(st.roof, ""), walls.get(st.wall, "")]


## Nhà phụ (nhà ngang, bếp): tường, cửa tối, mái hai mái cùng loại.
static func build_small(mb: MeshBuilder, glow: MeshBuilder, xf: Transform3D, len_: float,
		dep: float, h: float, st: Dictionary) -> void:
	var wall := st.wall as String
	if st.roof == "thatch":
		wall = "mud"
	var wc := wall_color(wall)
	var wd := wall_dark(wall)
	mb.add_box(Vector3(len_ + 0.4, 0.2, dep + 0.4), Palette.PLINTH, xf)
	mb.add_box(Vector3(len_, h, dep), wc, xf * _t(0.0, 0.2, 0.0))
	mb.add_box(Vector3(len_ + 0.04, 0.26, dep + 0.04), wd, xf * _t(0.0, 0.2, 0.0))
	mb.add_box(Vector3(0.95, 1.7, 0.08), Palette.WOOD, xf * _t(0.0, 0.2, dep * 0.5))
	glow.add_box(Vector3(0.78, 1.55, 0.04), Palette.WINDOW_DARK, xf * _t(0.0, 0.25, dep * 0.5 + 0.05))
	var form := "gable" if st.form == "hip" else (st.form as String)
	roof(mb, xf, len_, dep, 0.2 + h, dep * 0.42, 0.45, 0.2, st.roof, form, wc, wd)


# --- Cả lô đất -------------------------------------------------------------------------

## Dựng một lô: rào + cổng, nhà chính, nhà phụ theo bố cục, sân, lối vào, vườn.
## `xf` đặt gốc lô ở giữa mép trước, +z hướng ra ngõ. Trả về thông số nội thất nhà chính.
static func build_plot(mb: MeshBuilder, glow: MeshBuilder, leaves: MeshBuilder, ground: MeshBuilder,
		xf: Transform3D, width: float, depth: float, st: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var dims := {
		"bay": rng.randf_range(2.75, 3.3),
		"depth": rng.randf_range(4.8, 6.2),
		"height": rng.randf_range(2.3, 2.85),
		"plinth": rng.randf_range(0.2, 0.55),
		"rise": rng.randf_range(1.7, 2.5),
		"over": rng.randf_range(0.45, 0.8),
		"gover": rng.randf_range(0.2, 0.45),
		"round_window": rng.randf() < 0.3,
	}
	if st.roof == "thatch":
		dims.rise = rng.randf_range(2.2, 2.8)
		dims.over = rng.randf_range(0.7, 1.0)
	var L: float = st.bays * dims.bay
	# Co gian cho vừa lô
	if L > width - 2.2:
		dims.bay = (width - 2.2) / st.bays
		L = width - 2.2
	var D: float = dims.depth
	var back := rng.randf_range(2.6, 4.0)
	var hx := rng.randf_range(-1.0, 1.0) * maxf(0.0, (width - L - 2.2) * 0.5)
	var hz := -depth + back + D * 0.5
	var hxf := xf * Transform3D(Basis(Vector3.UP, deg_to_rad(rng.randf_range(-2.5, 2.5))), Vector3(hx, 0.0, hz))
	var info := build_house(mb, glow, hxf, st, dims)

	var house_front := hz + D * 0.5 + 0.35
	var yard_z0 := house_front + 0.4
	var yard_z1 := -2.2
	var yard_x0 := hx - L * 0.5 - 0.3
	var yard_x1 := hx + L * 0.5 + 0.3

	# Nhà phụ theo bố cục
	var wing_len := clampf(yard_z1 - yard_z0 - 0.6, 3.0, 6.0)
	var wing_dep := rng.randf_range(2.8, 3.4)
	var wing_h := rng.randf_range(2.0, 2.4)
	var sides: Array[float] = []
	match st.layout:
		"L_left": sides = [-1.0]
		"L_right": sides = [1.0]
		"U": sides = [-1.0, 1.0]
	# Lối đi thẳng từ cửa chính ra sân phải để trống (nhập vai đi vào được): nhà phụ lấn vào
	# lối này thì đẩy ra ngoài, chạm rào thì thu hẹp lại, vẫn không vừa thì bỏ nếp đó.
	var door_cx: float = hx + float(info.door_x)
	var lane := door_lane_half
	var fence_x := width * 0.5 - 0.35
	for s in sides:
		var wd := wing_dep
		var wx: float = hx + s * (L * 0.5 - wd * 0.5 + 0.2)
		var inner: float = s * (wx - door_cx) - wd * 0.5
		if inner < lane:
			wx = door_cx + s * (lane + wd * 0.5)
		var outer: float = s * wx + wd * 0.5
		if outer > fence_x:
			wd -= outer - fence_x
			wx = door_cx + s * (lane + wd * 0.5)
		if wd < 2.2:
			continue
		var wz: float = yard_z0 + wing_len * 0.5 + 0.2
		var wxf := xf * Transform3D(Basis(Vector3.UP, -s * PI * 0.5), Vector3(wx, 0.0, wz))
		build_small(mb, glow, wxf, wing_len, wd, wing_h, st)
	if st.layout == "kitchen":
		var side := -1.0 if hx > 0.0 else 1.0
		var room := width * 0.5 - absf(hx) - L * 0.5
		var kx := hx + side * (L * 0.5 + room * 0.5)
		var kz := house_front + 2.2
		if room < 3.4:
			# Không đủ chỗ cạnh nhà: đặt bếp ở sân, bên cạnh lối đi từ cửa
			kx = door_cx + side * (lane + 1.4)
			if side * kx + 1.4 > fence_x:
				kx = door_cx - side * (lane + 1.4)
		if absf(kx - door_cx) >= lane + 1.4 - 0.01 or room >= 3.4:
			var kxf := xf * Transform3D(Basis(Vector3.UP, side * PI * 0.5), Vector3(kx, 0.0, kz))
			build_small(mb, glow, kxf, 3.2, 2.8, 2.0, st)

	# Sân: gạch hoặc đất nện
	var brick_yard: bool = st.wall != "mud" and rng.randf() < 0.7
	if brick_yard:
		var ts := 0.5
		var z := yard_z0
		var row := 0
		while z < yard_z1 - 0.05:
			var x := yard_x0 - (ts * 0.5 if row % 2 == 1 else 0.0)
			while x < yard_x1 - 0.05:
				var xa := maxf(x, yard_x0) + 0.025
				var xb := minf(x + ts, yard_x1) - 0.025
				if xb > xa:
					ground.add_quad(Vector3(xa, 0.035, z + 0.025), Vector3(xb, 0.035, z + 0.025),
							Vector3(xb, 0.035, z + ts - 0.025), Vector3(xa, 0.035, z + ts - 0.025),
							Palette.YARD, Vector3(xa, -1.0, z), xf)
				x += ts
			z += ts
			row += 1
		ground.add_quad(Vector3(yard_x0, 0.02, yard_z0), Vector3(yard_x1, 0.02, yard_z0),
				Vector3(yard_x1, 0.02, z), Vector3(yard_x0, 0.02, z), Palette.GROUT, Vector3(0, -1, -5), xf)
	else:
		ground.add_quad(Vector3(yard_x0, 0.03, yard_z0), Vector3(yard_x1, 0.03, yard_z0),
				Vector3(yard_x1, 0.03, yard_z1), Vector3(yard_x0, 0.03, yard_z1), Palette.EARTH, Vector3(0, -1, -5), xf)

	# Rào trước + cổng, rào bên trái
	var gate_x := clampf(hx + rng.randf_range(-1.0, 1.0), -width * 0.5 + 1.6, width * 0.5 - 1.6)
	info["gate"] = xf * Vector3(gate_x, 0.0, 0.7)   # ngay ngoài cổng, phía ngõ (cho NPC đi)
	var fence: String = FENCES[rng.randi_range(0, FENCES.size() - 1)]
	_fence(mb, leaves, xf, Vector3(-width * 0.5, 0, -0.4), Vector3(gate_x - 0.95, 0, -0.4), fence, rng)
	_fence(mb, leaves, xf, Vector3(gate_x + 0.95, 0, -0.4), Vector3(width * 0.5, 0, -0.4), fence, rng)
	_fence(mb, leaves, xf, Vector3(-width * 0.5, 0, -0.4), Vector3(-width * 0.5, 0, -depth + 0.3),
			"hibiscus_hedge" if fence == "brick_wall" else fence, rng)
	_gate(mb, xf, gate_x, fence)
	# Lối từ cổng vào sân
	var path_col := Palette.YARD if brick_yard else Palette.EARTH
	ground.add_quad(Vector3(gate_x - 0.6, 0.03, yard_z1), Vector3(gate_x + 0.6, 0.03, yard_z1),
			Vector3(gate_x + 0.6, 0.03, -0.3), Vector3(gate_x - 0.6, 0.03, -0.3), path_col, Vector3(0, -1, -1), xf)

	# Vườn: 2–4 thứ khác nhau, đặt ở các khoảng trống
	var picks: Array[String] = []
	var pool := GARDEN.duplicate()
	for i in rng.randi_range(2, 4):
		var idx := rng.randi_range(0, pool.size() - 1)
		picks.append(pool[idx])
		pool.remove_at(idx)
	var spots := _garden_spots(width, depth, hx, L, hz, D, yard_z1, st.layout)
	for i in picks.size():
		if i >= spots.size():
			break
		_garden(mb, leaves, ground, xf, spots[i], picks[i], rng)
	# Cây ăn quả phía sau nhà luôn có
	var bx := hx + rng.randf_range(-L * 0.4, L * 0.4)
	_fruit_tree(mb, leaves, xf * _t(bx, 0.0, -depth + 1.4), rng)
	return info


## Các khoảng trống trong lô (toạ độ lô): [tâm, kích thước].
static func _garden_spots(width: float, depth: float, hx: float, L: float, hz: float, D: float,
		yard_z1: float, layout: String) -> Array:
	var out: Array = []
	var left := -width * 0.5 + 0.8
	var right := width * 0.5 - 0.8
	var gap_l := (hx - L * 0.5) - left
	var gap_r := right - (hx + L * 0.5)
	if gap_l > 1.6:
		out.append([Vector2(left + gap_l * 0.5, hz), Vector2(gap_l - 0.4, D)])
	if gap_r > 1.6:
		out.append([Vector2(right - gap_r * 0.5, hz), Vector2(gap_r - 0.4, D)])
	# Hai góc trước, cạnh rào (chỉ khi không có nhà ngang chiếm chỗ)
	if layout != "L_left" and layout != "U":
		out.append([Vector2(left + 1.2, -1.4), Vector2(2.0, 1.6)])
	if layout != "L_right" and layout != "U":
		out.append([Vector2(right - 1.2, -1.4), Vector2(2.0, 1.6)])
	out.append([Vector2(hx + L * 0.25, -depth + 1.0), Vector2(L * 0.4, 1.4)])
	return out


# --- Rào, cổng ------------------------------------------------------------------------

static func _fence(mb: MeshBuilder, leaves: MeshBuilder, xf: Transform3D, a: Vector3, b: Vector3,
		kind: String, rng: RandomNumberGenerator) -> void:
	var len_ := a.distance_to(b)
	if len_ < 0.3:
		return
	var dir := (b - a).normalized()
	var yaw := atan2(dir.x, dir.z)
	var mid := (a + b) * 0.5
	var seg := xf * Transform3D(Basis(Vector3.UP, yaw), mid)
	match kind:
		"brick_wall":
			mb.add_box(Vector3(0.24, 1.15, len_), Palette.BRICK if rng.randf() < 0.5 else Palette.WALL_WHITE, seg)
			mb.add_box(Vector3(0.32, 0.08, len_ + 0.04), Palette.BRICK_DARK, seg * _t(0.0, 1.15, 0.0))
		"bamboo_fence":
			var n := int(len_ / 0.16)
			for i in n:
				var z := -len_ * 0.5 + (i + 0.5) * len_ / n
				mb.add_box(Vector3(0.04, rng.randf_range(1.0, 1.2), 0.04), Palette.BAMBOO_STEM, seg * _t(0.0, 0.0, z))
			for y in [0.35, 0.85]:
				mb.add_box(Vector3(0.06, 0.05, len_), Palette.BAMBOO_NODE, seg * _t(0.06, y, 0.0))
		"hibiscus_hedge":
			leaves.add_box(Vector3(0.7, 1.0, len_), Palette.HEDGE, seg)
			var n2 := int(len_ / 1.2)
			for i in n2:
				var z2 := -len_ * 0.5 + (i + rng.randf()) * len_ / maxf(n2, 1)
				leaves.add_box(Vector3(0.12, 0.1, 0.12), Palette.HIBISCUS,
						seg * _t(rng.randf_range(-0.36, 0.36), rng.randf_range(0.6, 1.0), z2))
		_:
			mb.add_box(Vector3(0.22, 0.25, len_), Palette.BRICK_DARK, seg)


static func _gate(mb: MeshBuilder, xf: Transform3D, gx: float, kind: String) -> void:
	for s in [-1.0, 1.0]:
		var px: float = gx + s * 0.95
		if kind == "brick_wall":
			mb.add_box(Vector3(0.42, 1.7, 0.42), Palette.WALL_WHITE, xf * _t(px, 0.0, -0.4))
			mb.add_pyramid(0.34, 0.35, 4, Palette.ROOF_BROWN, xf * Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(px, 1.7, -0.4)))
		else:
			mb.add_prism(0.08, 0.07, 1.45, 5, Palette.WOOD, xf * _t(px, 0.0, -0.4))
	if kind == "brick_wall":
		# Cổng có mái ngói nhỏ
		mb.add_box(Vector3(2.3, 0.14, 0.5), Palette.WOOD, xf * _t(gx, 1.7, -0.4))
		mb.add_wedge(Vector3(2.5, 0.45, 0.9), Palette.ROOF_BROWN, xf * _t(gx, 1.84, -0.4))


# --- Vườn -------------------------------------------------------------------------------

static func _garden(mb: MeshBuilder, leaves: MeshBuilder, ground: MeshBuilder, xf: Transform3D,
		spot: Array, kind: String, rng: RandomNumberGenerator) -> void:
	var c: Vector2 = spot[0]
	var size: Vector2 = spot[1]
	match kind:
		"areca":
			var n := clampi(int(maxf(size.x, size.y) / 1.6), 1, 4)
			for i in n:
				var t := (i + 0.5) / n
				var p := c + (Vector2(0, (t - 0.5) * size.y) if size.y > size.x else Vector2((t - 0.5) * size.x, 0))
				areca(mb, leaves, xf * _t(p.x, 0.0, p.y), rng)
		"banana":
			for i in rng.randi_range(2, 3):
				var p := c + Vector2(rng.randf_range(-0.4, 0.4) * size.x, rng.randf_range(-0.4, 0.4) * size.y)
				banana(mb, leaves, xf * _t(p.x, 0.0, p.y), rng)
		"fruit_tree":
			_fruit_tree(mb, leaves, xf * _t(c.x, 0.0, c.y), rng)
		"vegetables":
			var w := minf(size.x, 3.0)
			var d := minf(size.y, 3.0)
			var rows := maxi(2, int(d / 0.7))
			for r in rows:
				var z := c.y - d * 0.5 + (r + 0.5) * d / rows
				mb.add_box(Vector3(w, 0.12, d / rows - 0.2), Palette.EARTH.darkened(0.15), xf * _t(c.x, 0.0, z))
				for k in int(w / 0.35):
					leaves.add_blob(Vector3(0.13, 0.1, 0.13), Palette.VEGETABLE, rng, 0.25,
							xf * _t(c.x - w * 0.5 + 0.2 + k * 0.35, 0.1, z))
		"haystack":
			var s := minf(1.0, minf(size.x, size.y) * 0.4)
			mb.add_prism(0.95 * s, 0.15, 1.8 * s, 9, Palette.STRAW, xf * _t(c.x, 0.0, c.y), 0.2)
		"water_tank":
			if rng.randf() < 0.5:
				mb.add_prism(0.6, 0.6, 1.0, 10, Palette.WALL_WHITE, xf * _t(c.x, 0.0, c.y))
				mb.add_prism(0.5, 0.5, 1.02, 10, Palette.WATER.darkened(0.3), xf * _t(c.x, 0.0, c.y))
			else:
				mb.add_box(Vector3(1.2, 1.0, 1.0), Palette.WALL_WHITE.darkened(0.08), xf * _t(c.x, 0.0, c.y))
				mb.add_box(Vector3(1.0, 0.03, 0.8), Palette.WATER.darkened(0.3), xf * _t(c.x, 1.0, c.y))
		"trellis":
			var w2 := minf(size.x, 2.6)
			var d2 := minf(size.y, 2.6)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					mb.add_box(Vector3(0.06, 1.9, 0.06), Palette.BAMBOO_STEM, xf * _t(c.x + sx * w2 * 0.45, 0.0, c.y + sz * d2 * 0.45))
			for k in 4:
				mb.add_box(Vector3(w2, 0.04, 0.04), Palette.BAMBOO_STEM, xf * _t(c.x, 1.9, c.y - d2 * 0.45 + k * d2 * 0.3))
			for k in 6:
				leaves.add_blob(Vector3(0.45, 0.12, 0.4), Palette.VEGETABLE, rng, 0.3,
						xf * _t(c.x + rng.randf_range(-0.4, 0.4) * w2, 1.86, c.y + rng.randf_range(-0.4, 0.4) * d2))


## Cây cau: thân mảnh cao, tàu lá rủ.
static func areca(mb: MeshBuilder, leaves: MeshBuilder, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(6.0, 8.5)
	var lean := Vector3(rng.randf_range(-0.3, 0.3), h, rng.randf_range(-0.3, 0.3))
	mb.add_limb(Vector3.ZERO, lean, 0.11, 0.08, 6, Palette.ARECA_TRUNK, xf)
	leaves.add_blob(Vector3(0.22, 0.3, 0.22), Palette.BAMBOO_LEAF, rng, 0.2, xf * _t(lean.x, h - 0.3, lean.z))
	for i in 7:
		var a := TAU * i / 7.0 + rng.randf_range(-0.2, 0.2)
		var out := Vector3(cos(a), 0.0, sin(a))
		var tip := lean + Vector3(0, 0.2, 0) + out * 1.6 + Vector3(0, -0.9, 0)
		leaves.add_limb(lean + Vector3(0, 0.2, 0), tip, 0.18, 0.02, 3, Palette.BAMBOO_LEAF if i % 2 == 0 else Palette.BAMBOO_LEAF_DARK, xf)


## Cây chuối: thân ngắn, lá to bản xoè.
static func banana(mb: MeshBuilder, leaves: MeshBuilder, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(1.4, 2.0)
	mb.add_prism(0.14, 0.11, h, 6, Palette.BAMBOO_STEM.lerp(Palette.BANANA, 0.4), xf)
	for i in 6:
		var a := TAU * i / 6.0 + rng.randf_range(-0.3, 0.3)
		var tilt := deg_to_rad(rng.randf_range(35.0, 70.0))
		var dir := Vector3(cos(a), 0.0, sin(a))
		var b := Basis(Vector3.UP.cross(dir).normalized(), tilt) * Basis(Vector3.UP, a)
		var lxf := xf * Transform3D(b, Vector3(0, h - 0.1, 0))
		leaves.add_box(Vector3(0.38, 1.4, 0.03), Palette.BANANA if i % 2 == 0 else Palette.BANANA.darkened(0.15), lxf)


static func _fruit_tree(mb: MeshBuilder, leaves: MeshBuilder, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(1.6, 2.6)
	mb.add_prism(0.16, 0.12, h + 0.4, 6, Palette.BANYAN_TRUNK, xf)
	var cols: Array[Color] = [Palette.BANYAN_LEAF_1, Palette.BANYAN_LEAF_2, Palette.BAMBOO_LEAF]
	var col := cols[rng.randi_range(0, 2)]
	var r := rng.randf_range(1.2, 1.9)
	leaves.add_blob(Vector3(r, r * 0.8, r), col, rng, 0.2, xf * _t(0.0, h, 0.0))
	leaves.add_blob(Vector3(r, r, r) * 0.6, col.darkened(0.1), rng, 0.2, xf * _t(r * 0.5, h + 0.3, r * 0.3))
