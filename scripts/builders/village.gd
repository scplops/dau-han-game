class_name Village
extends Node3D
## Làng Bắc Bộ xưa ở phía bắc (z âm) khu nhà chính:
## - Lũy tre bao quanh hình bầu dục, cổng làng ở phía nam.
## - Đường trục lát gạch từ cổng chạy thẳng tới đình; các ngõ ngang toả hai bên (xương cá).
## - Lô đất nằm phía bắc mỗi ngõ, nhà quay hướng nam ra ngõ; mỗi nhà một kiểu không trùng.
## - Đình (sân, hồ bán nguyệt, nghi môn, tả mạc hữu mạc), chùa (tam quan, gác chuông),
##   ao làng, giếng làng, điếm canh, cây đa đầu làng.
## Mặt đất trong làng phẳng (y = 0), do Terrain dựng (vùng `village_rect`).

@export var terrain: Terrain
@export var random_seed: int = 2024

@export_group("Quy hoạch")
@export var center: Vector2 = Vector2(0.0, -115.0)
@export var radii: Vector2 = Vector2(122.0, 80.0)
@export var alley_z: PackedFloat32Array = PackedFloat32Array([-52.0, -72.0, -92.0, -112.0, -132.0, -152.0])
@export var main_lane_width: float = 3.6
@export var alley_width: float = 2.4
@export var plot_width_range: Vector2 = Vector2(11.0, 15.0)
@export var plot_depth: float = 17.4
@export_range(10, 90) var max_houses: int = 60
@export_range(0.5, 1.0) var plot_margin: float = 0.95   # lô phải nằm trong elip co lại

@export_group("Công trình")
@export var dinh_half_width: float = 19.0
@export var pagoda_rect: Rect2 = Rect2(57.0, -121.0, 27.0, 27.0)
@export var pond_center: Vector2 = Vector2(-25.0, -44.0)
@export var pond_radii: Vector2 = Vector2(7.5, 5.0)
@export var banyan_position: Vector3 = Vector3(16.0, 0.0, -44.0)
@export var well_position: Vector3 = Vector3(7.5, 0.0, -47.0)
## Sân bóng làng (x, z, dài, rộng) — không xây lô, không trồng vườn tạp lên đây (mục 17).
## Sân bóng 11 người (mục 51): bãi ngoài cổng làng phía đông, giữa đường đất và cánh đồng (trong làng không đủ chỗ).
@export var pitch_rect: Rect2 = Rect2(38.0, -26.0, 64.0, 40.0)
## Bãi cỏ góc tây bắc làng — chỗ sân bóng cũ; vẫn để trống (đổi thì bố cục lô đất, nhà trong làng đổi theo).
@export var old_pitch_rect: Rect2 = Rect2(-64.0, -176.0, 30.0, 18.0)

@export_group("Lối ra sông")
## Các ngõ được nối dài xuyên lũy tre ra sông (chỉ số trong alley_lines: ngõ thứ i có
## hai nửa 2i = tây, 2i + 1 = đông).
@export var river_access_alleys: PackedInt32Array = PackedInt32Array([4, 3])
## Lối ra sông phía bắc: rẽ từ ngõ cuối (phía tây) tại x này, đi thẳng lên bắc.
@export var north_access_x: float = -27.0
@export var access_width: float = 2.6

@export_group("Lũy tre")
@export var hedge_spacing: float = 3.0
@export var gate_gap: float = 6.5

@export_group("Gió")
@export var leaf_wind: float = 0.12
@export var hedge_wind: float = 0.28

## Lối ra sông: {points (x,z) từ ngõ tới khe lũy tre, exit (x,z) ngay ngoài lũy, out (hướng ra)}.
var access_paths: Array[Dictionary] = []

## Số nhà và số kiểu khác nhau (để kiểm tra), có sau build().
var house_count: int = 0
var unique_styles: int = 0
## Đếm theo từng đặc điểm, ví dụ {"roof": {"thatch": 12, ...}, ...}.
var style_stats: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _lane: PackedVector2Array
var _alleys: Array[PackedVector2Array] = []

## Các nhà có người ở (cho NPC): {door, forward, gate, name, key}. Có sau build().
var homes: Array[Dictionary] = []
## Chỗ đứng chơi trong sân đình / sân chùa (cho NPC).
var dinh_spot: Vector3
## Chân bậc thềm đình (người đi lễ vào / ra ở đây).
var dinh_door: Vector3
## Hồ bán nguyệt giữa sân đình (tâm, bán kính) — Villagers đi vòng, không lội qua.
var dinh_pond_center: Vector3
var dinh_pond_radii: Vector2
var pagoda_spot: Vector3
var _glow_mat: StandardMaterial3D
var _occupied: Array[Rect2] = []      # vùng đã có lô / công trình (để rải vườn tạp tránh)


func build() -> void:
	_rng.seed = random_seed
	_glow_mat = _make_glow_material()
	_plan_lanes()
	_plan_access()

	var ground := MeshBuilder.new(random_seed, 0.07)
	_build_lanes(ground)
	for a in access_paths:
		_paved_strip(ground, a.points, access_width, 0.045)
	var stat := MeshBuilder.new(random_seed + 1, 0.04)
	stat.contact_shade_height = 0.6
	stat.contact_shade_strength = 0.18
	var leaves := MeshBuilder.new(random_seed + 2, 0.06)
	var glow := MeshBuilder.new(random_seed + 3, 0.0)

	_build_gate(stat)
	_build_entrance(stat, leaves, ground, glow)
	_build_dinh(stat, leaves, ground, glow)
	_build_pagoda(stat, leaves, ground, glow)
	_commit(stat, leaves, ground, glow, "Public")

	_build_plots()
	_build_hedge()
	_build_wild_gardens()
	print("Village: %d nhà, %d kiểu khác nhau" % [house_count, unique_styles])
	for key in style_stats:
		print("  %s: %s" % [key, style_stats[key]])


func _commit(stat: MeshBuilder, leaves: MeshBuilder, ground: MeshBuilder, glow: MeshBuilder, tag: String) -> void:
	add_child(stat.commit_instance(tag + "Buildings"))
	if leaves.triangle_count() > 0:
		add_child(leaves.commit_instance(tag + "Leaves", MeshBuilder.wind_material(leaf_wind, 0.6, 6.0, 0.9)))
	if ground.triangle_count() > 0:
		var g := ground.commit_instance(tag + "Ground")
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g)
	if glow.triangle_count() > 0:
		var gl := glow.commit_instance(tag + "Glow", _glow_mat)
		gl.add_to_group("night_glow")
		add_child(gl)


static func _make_glow_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	mat.emission_enabled = true
	mat.emission = Palette.WINDOW_GLOW
	mat.emission_energy_multiplier = 0.0
	return mat


static func _t(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


## Nửa bề rộng elip làng tại độ sâu z.
## Đường trục (x, z) từ ngoài cổng vào tới đình.
func lane_points() -> PackedVector2Array:
	return _lane


## Các ngõ ngang, mỗi ngõ là một đường gấp khúc (x, z) bắt đầu từ mép đường trục.
func alley_lines() -> Array[PackedVector2Array]:
	return _alleys


func half_width_at(z: float) -> float:
	var dz := (z - center.y) / radii.y
	return radii.x * sqrt(maxf(0.0, 1.0 - dz * dz))


func _inside(p: Vector2, scale: float) -> bool:
	var d := (p - center) / (radii * scale)
	return d.length_squared() <= 1.0


func gate_point() -> Vector2:
	return Vector2(center.x, center.y + radii.y)


# --- Đường ------------------------------------------------------------------------------

func _plan_lanes() -> void:
	var g := gate_point()
	_lane = PackedVector2Array([Vector2(g.x, g.y + 2.0), g])
	var wob := [1.2, -0.8, 0.6, -0.5, 0.0]
	for i in alley_z.size():
		_lane.append(Vector2(wob[i % wob.size()], alley_z[i]))
	for z in alley_z:
		var hw := half_width_at(z) - 5.0
		for s in [-1.0, 1.0]:
			var pts := PackedVector2Array()
			var x0: float = lane_x(z) + s * main_lane_width * 0.5
			pts.append(Vector2(x0, z))
			var x: float = absf(x0) + 9.0
			var dz := 0.0
			while x < hw:
				dz = clampf(dz + _rng.randf_range(-0.9, 0.9), -1.6, 1.6)
				pts.append(Vector2(s * x, z + dz))
				x += 9.0
			pts.append(Vector2(s * hw, z + dz * 0.5))
			_alleys.append(pts)


## Toạ độ x của đường trục tại z.
func lane_x(z: float) -> float:
	for i in _lane.size() - 1:
		var a := _lane[i]
		var b := _lane[i + 1]
		if (z <= a.y and z >= b.y):
			return lerpf(a.x, b.x, (a.y - z) / maxf(a.y - b.y, 0.001))
	return _lane[_lane.size() - 1].x


## z của ngõ (nội suy theo x) — ngõ hơi uốn.
static func _alley_z_at(pts: PackedVector2Array, x: float) -> float:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		if (x - a.x) * (x - b.x) <= 0.0:
			return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x) if b.x != a.x else 0.0)
	return pts[pts.size() - 1].y


func _build_lanes(mb: MeshBuilder) -> void:
	_paved_strip(mb, _lane, main_lane_width, 0.06)
	for a in _alleys:
		_paved_strip(mb, a, alley_width, 0.04)


## Dải lát gạch theo đường gấp khúc: hàng gạch xếp ngang, hai mép gạch sẫm.
func _paved_strip(mb: MeshBuilder, pts: PackedVector2Array, width: float, y: float) -> void:
	var dense := Terrain._densify(pts, 0.42)
	var below := Vector3(0, -1, 0)
	var prev: Array = []
	for i in dense.size():
		var p := dense[i]
		var dir: Vector2
		if i == 0:
			dir = dense[1] - dense[0]
		elif i == dense.size() - 1:
			dir = dense[i] - dense[i - 1]
		else:
			dir = dense[i + 1] - dense[i - 1]
		var side := dir.normalized().orthogonal()
		var h := width * 0.5
		var c := 0.18
		var row := [
			Vector3(p.x - side.x * h, y, p.y - side.y * h),
			Vector3(p.x - side.x * (h - c), y, p.y - side.y * (h - c)),
			Vector3(p.x + side.x * (h - c), y, p.y + side.y * (h - c)),
			Vector3(p.x + side.x * h, y, p.y + side.y * h),
		]
		if not prev.is_empty():
			var col := Palette.LANE_BRICK if i % 2 == 0 else Palette.LANE_BRICK.lerp(Palette.LANE_BRICK_DARK, 0.4)
			mb.add_quad(prev[0], prev[1], row[1], row[0], Palette.LANE_BRICK_DARK, (prev[0] + row[1]) * 0.5 + below)
			mb.add_quad(prev[1], prev[2], row[2], row[1], col, (prev[1] + row[2]) * 0.5 + below)
			mb.add_quad(prev[2], prev[3], row[3], row[2], Palette.LANE_BRICK_DARK, (prev[2] + row[3]) * 0.5 + below)
		prev = row


# --- Lô đất + nhà -------------------------------------------------------------------------

## Lên kế hoạch lối ra sông: nối dài vài ngõ ra tới lũy tre, cộng một lối đi lên phía bắc.
func _plan_access() -> void:
	for idx in river_access_alleys:
		if idx < 0 or idx >= _alleys.size():
			continue
		var al := _alleys[idx]
		var a := al[al.size() - 1]
		var side := signf(a.x)
		var b := Vector2(side * half_width_at(a.y), a.y)
		_add_access(PackedVector2Array([a, a.lerp(b, 0.5), b]))
	# Phía bắc: rẽ từ ngõ cuối, phía tây đình
	var last := _alleys[(alley_z.size() - 1) * 2]
	var start := Vector2(north_access_x, _alley_z_at(last, north_access_x))
	var dz := (north_access_x / radii.x)
	var hedge_z := center.y - radii.y * sqrt(maxf(0.0, 1.0 - dz * dz))
	_add_access(PackedVector2Array([start, Vector2(north_access_x + 0.8, lerpf(start.y, hedge_z, 0.5)), Vector2(north_access_x, hedge_z)]))


func _add_access(pts: PackedVector2Array) -> void:
	var b := pts[pts.size() - 1]
	var out := (b - center) / (radii * radii)    # pháp tuyến elip tại b
	out = out.normalized()
	# Kéo dài thêm vài mét để xuyên qua dải lũy tre
	var exit := b + out * 6.0
	pts.append(exit)
	access_paths.append({"points": pts, "exit": exit, "out": out})


## Điểm có nằm trong hành lang lối ra sông không (để không xây nhà / trồng cây lên đó).
func _on_access(p: Vector2, margin: float) -> bool:
	for a in access_paths:
		var pts: PackedVector2Array = a.points
		for i in pts.size() - 1:
			if Terrain._segment_distance(p, pts[i], pts[i + 1]) < access_width * 0.5 + margin:
				return true
	return false


func _reserved(r: Rect2) -> bool:
	# Lô chạm hành lang lối ra sông thì bỏ
	for a in access_paths:
		var pts: PackedVector2Array = a.points
		for i in pts.size() - 1:
			var seg := Rect2(pts[i], Vector2.ZERO).expand(pts[i + 1]).grow(access_width * 0.5 + 0.8)
			if r.intersects(seg):
				return true
	if r.intersects(pagoda_rect.grow(1.0)) or r.intersects(old_pitch_rect.grow(2.5)):
		return true
	if r.end.y > alley_z[alley_z.size() - 1] - 30.0 and r.position.y < alley_z[alley_z.size() - 1] \
			and absf(r.get_center().x) - r.size.x * 0.5 < dinh_half_width:
		return true
	return false


func _build_plots() -> void:
	var pool := VillageHouse.all_styles(_rng)
	var used := {}
	for ai in alley_z.size():
		var stat := MeshBuilder.new(random_seed + 100 + ai, 0.04)
		stat.contact_shade_height = 0.6
		stat.contact_shade_strength = 0.18
		var leaves := MeshBuilder.new(random_seed + 200 + ai, 0.06)
		var ground := MeshBuilder.new(random_seed + 300 + ai, 0.08)
		var glow := MeshBuilder.new(random_seed + 400 + ai, 0.0)
		var z0 := alley_z[ai]
		for s in [-1.0, 1.0]:
			var side := 0 if s < 0.0 else 1
			var alley := _alleys[ai * 2 + side]
			var next_alley: PackedVector2Array = _alleys[(ai + 1) * 2 + side] if ai + 1 < alley_z.size() else PackedVector2Array()
			var x := absf(lane_x(z0)) + main_lane_width * 0.5 + 1.0
			var prev: Dictionary = {}
			while true:
				var w := _rng.randf_range(plot_width_range.x, plot_width_range.y)
				var cx: float = s * (x + w * 0.5)
				var front := _alley_z_at(alley, cx) - alley_width * 0.5 - _rng.randf_range(0.3, 1.2)
				var depth := _rng.randf_range(plot_depth - 2.5, plot_depth + 0.8)
				if not next_alley.is_empty():
					depth = minf(depth, front - (_alley_z_at(next_alley, cx) + alley_width * 0.5 + 0.8))
				var rect := Rect2(cx - w * 0.5, front - depth, w, depth)
				var ok := true
				for corner in [rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), rect.end]:
					if not _inside(corner, plot_margin):
						ok = false
				if not ok:
					break
				x += w + _rng.randf_range(0.0, 1.3)
				if _reserved(rect):
					continue
				_occupied.append(rect.grow(0.6))
				# Lô xoay theo hướng ngõ tại chỗ đó
				var slope := (_alley_z_at(alley, cx + 1.0) - _alley_z_at(alley, cx - 1.0)) * 0.5
				var xf := Transform3D(Basis(Vector3.UP, -atan(slope)), Vector3(cx, 0.0, front))
				if house_count < max_houses:
					var st := VillageHouse.pick_style(pool, used, w, prev)
					if not st.is_empty():
						used[VillageHouse.signature(st)] = true
						for key in ["bays", "roof", "form", "wall", "front", "layout"]:
							var bucket: Dictionary = style_stats.get_or_add(key, {})
							bucket[str(st[key])] = int(bucket.get(str(st[key]), 0)) + 1
						var fb: Dictionary = style_stats.get_or_add("floors", {})
						var fl := str(VillageHouse.floors_of(st))
						fb[fl] = int(fb.get(fl, 0)) + 1
						var info := VillageHouse.build_plot(stat, glow, leaves, ground, xf, w, depth, st, _rng)
						info["seed"] = random_seed * 31 + house_count
						info["name"] = VillageHouse.describe(st)
						var door: Transform3D = info["door"]
						info.erase("door")
						homes.append({"door": door.origin, "forward": door.basis.z.normalized(),
								"gate": info["gate"], "name": info["name"], "key": "house_%d" % house_count})
						info.erase("gate")
						HouseEntry.make_entry_target(self, door, Vector3(1.6, 2.1, 0.4),
								"Vào  ·  " + str(info["name"]), info, "house_%d" % house_count)
						house_count += 1
						prev = st
						continue
				_build_orchard(stat, leaves, ground, xf, w, depth)
		_commit(stat, leaves, ground, glow, "Row%d" % ai)
	unique_styles = used.size()


## Lô không có nhà: vườn cây ăn quả + luống rau, rào dậu.
func _build_orchard(stat: MeshBuilder, leaves: MeshBuilder, ground: MeshBuilder, xf: Transform3D, w: float, depth: float) -> void:
	VillageHouse._fence(stat, leaves, xf, Vector3(-w * 0.5, 0, -0.4), Vector3(w * 0.5, 0, -0.4), "hibiscus_hedge", _rng)
	for i in int(w / 4.5):
		for j in int((depth - 4.0) / 4.6):
			var p := Vector3(-w * 0.5 + 2.2 + i * 4.5 + _rng.randf_range(-0.6, 0.6), 0.0, -3.5 - j * 4.6)
			VillageHouse._fruit_tree(stat, leaves, xf * _t(p.x, 0.0, p.z), _rng)
	VillageHouse._garden(stat, leaves, ground, xf, [Vector2(0.0, -depth + 2.2), Vector2(w * 0.6, 2.4)], "vegetables", _rng)


# --- Lũy tre ------------------------------------------------------------------------------

func _build_hedge() -> void:
	var stems := MeshBuilder.new(random_seed + 50, 0.05)
	stems.contact_shade_height = 0.8
	var leaves := MeshBuilder.new(random_seed + 51, 0.07)
	var g := gate_point()
	var perimeter := TAU * sqrt((radii.x * radii.x + radii.y * radii.y) * 0.5)
	var n := int(perimeter / hedge_spacing)
	for i in n:
		var a := TAU * i / n + _rng.randf_range(-0.01, 0.01)
		var p := center + Vector2(cos(a) * radii.x, sin(a) * radii.y)
		if p.distance_to(g) < gate_gap:
			continue
		if _on_access(p, 3.5):
			continue   # khe lũy tre cho lối ra sông
		var out := Vector3(cos(a) * radii.y, 0.0, sin(a) * radii.x).normalized()  # pháp tuyến elip
		var jit := Vector3(out.x, 0.0, out.z) * _rng.randf_range(-1.0, 1.0)
		_bamboo_clump(stems, leaves, Vector3(p.x, 0.0, p.y) + jit, out)
	add_child(stems.commit_instance("HedgeStems", MeshBuilder.wind_material(hedge_wind, 2.0, 7.0, 0.9)))
	add_child(leaves.commit_instance("HedgeLeaves", MeshBuilder.wind_material(hedge_wind, 2.0, 7.0, 0.9)))


## Một bụi tre của lũy: gốc um tùm, thân vươn nghiêng ra ngoài, lá dày từ thấp lên ngọn
## để cả dải lũy thành bức tường xanh.
func _bamboo_clump(stems: MeshBuilder, leaves: MeshBuilder, base: Vector3, out: Vector3) -> void:
	# Gốc bụi rậm
	leaves.add_blob(Vector3(1.7, 1.1, 1.7), Palette.BAMBOO_LEAF_DARK, _rng, 0.3, _t(base.x, 0.0, base.z))
	for k in _rng.randi_range(4, 6):
		var off := Vector3(_rng.randf_range(-1.2, 1.2), 0.0, _rng.randf_range(-1.2, 1.2))
		var h := _rng.randf_range(6.5, 10.0)
		var lean := out * _rng.randf_range(1.2, 3.0) + Vector3(_rng.randf_range(-0.8, 0.8), 0.0, _rng.randf_range(-0.8, 0.8))
		var top := base + off + lean + Vector3(0, h, 0)
		stems.add_limb(base + off, top, 0.09, 0.05, 5, Palette.BAMBOO_STEM)
		for j in 4:
			var t := 0.38 + j * 0.19
			var p := (base + off).lerp(top, t)
			var sz := lerpf(1.5, 1.05, t)
			var r := Vector3(_rng.randf_range(1.0, 1.4), _rng.randf_range(0.55, 0.75), _rng.randf_range(1.0, 1.4)) * sz
			var col := Palette.BAMBOO_LEAF if _rng.randf() < 0.55 else Palette.BAMBOO_LEAF_DARK
			leaves.add_blob(r, col, _rng, 0.3, _t(p.x + out.x * 0.5 * t, p.y - r.y, p.z + out.z * 0.5 * t))
		# Ngọn cong rủ ra ngoài
		leaves.add_limb(top - Vector3(0, 0.8, 0), top + out * 1.6 - Vector3(0, 0.6, 0), 0.45, 0.05, 4, Palette.BAMBOO_LEAF)


# --- Cổng làng ----------------------------------------------------------------------------

func _build_gate(mb: MeshBuilder) -> void:
	var g := gate_point()
	var xf := _t(g.x, 0.0, g.y)
	var wc := Palette.WALL_WHITE.darkened(0.05)
	var wd := Palette.WALL_WHITE.darkened(0.2)
	var open := main_lane_width * 0.5 + 0.6
	for s in [-1.0, 1.0]:
		var px: float = s * (open + 0.55)
		mb.add_box(Vector3(1.1, 4.3, 1.1), wc, xf * _t(px, 0.0, 0.0))
		mb.add_box(Vector3(1.25, 0.25, 1.25), wd, xf * _t(px, 4.3, 0.0))
		mb.add_pyramid(0.6, 0.7, 4, Palette.ROOF_BROWN, xf * Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(px, 4.55, 0.0)))
		mb.add_box(Vector3(1.3, 0.3, 1.3), wd, xf * _t(px, 0.0, 0.0))
		# Tường cánh thấp dần ra lũy tre
		mb.add_box(Vector3(3.2, 2.2, 0.5), wc, xf * _t(s * (open + 1.1 + 1.6), 0.0, 0.0))
		mb.add_box(Vector3(3.3, 0.12, 0.6), wd, xf * _t(s * (open + 1.1 + 1.6), 2.2, 0.0))
	# Xà vòm + biển (để trống) + mái ngói
	var span := (open + 1.1) * 2.0
	mb.add_box(Vector3(span, 1.0, 1.1), wc, xf * _t(0.0, 3.3, 0.0))
	mb.add_box(Vector3(2.4, 0.6, 0.06), Palette.WOOD, xf * _t(0.0, 3.5, 0.56))
	mb.add_box(Vector3(2.2, 0.45, 0.04), Palette.PLINTH, xf * _t(0.0, 3.57, 0.6))
	VillageHouse.roof(mb, xf, span, 1.2, 4.3, 0.85, 0.45, 0.35, "tile_brown", "hip", wc, wd)


# --- Khu đầu làng: ao làng, giếng, điếm canh, cây đa ---------------------------------------

func _build_entrance(stat: MeshBuilder, leaves: MeshBuilder, ground: MeshBuilder, glow: MeshBuilder) -> void:
	_pond(stat, leaves, Vector3(pond_center.x, 0.0, pond_center.y), pond_radii, false)
	# Giếng làng: thành gạch tròn, mái che nhỏ
	var w := Transform3D(Basis(), well_position)
	stat.add_prism(1.1, 1.1, 0.8, 12, Palette.BRICK, w)
	stat.add_prism(1.18, 1.18, 0.1, 12, Palette.BRICK_DARK, w * _t(0.0, 0.8, 0.0))
	stat.add_prism(0.85, 0.85, 0.92, 12, Palette.WATER.darkened(0.45), w)
	for i in 8:
		var a := TAU * i / 8.0
		ground.add_quad(Vector3(cos(a) * 1.3, 0.03, sin(a) * 1.3) + well_position,
				Vector3(cos(a) * 2.6, 0.03, sin(a) * 2.6) + well_position,
				Vector3(cos(a + TAU / 8.0) * 2.6, 0.03, sin(a + TAU / 8.0) * 2.6) + well_position,
				Vector3(cos(a + TAU / 8.0) * 1.3, 0.03, sin(a + TAU / 8.0) * 1.3) + well_position,
				Palette.LANE_BRICK, well_position + Vector3(0, -1, 0))
	# Điếm canh mái rạ cạnh cổng
	var hut := {"roof": "thatch", "form": "gable", "wall": "mud"}
	var g := gate_point()
	VillageHouse.build_small(stat, glow, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(g.x - 8.0, 0.0, g.y - 5.0)), 3.6, 2.8, 2.0, hut)
	# Cây đa đầu làng
	var tree := BanyanTree.new()
	tree.name = "VillageBanyan"
	tree.random_seed = random_seed + 7
	tree.tree_position = banyan_position
	tree.canopy_radius = 5.0
	tree.canopy_height = 6.2
	add_child(tree)
	tree.build()
	# Hàng cau dọc hai bên đường trục ở đầu làng
	for i in 4:
		var z := g.y - 4.0 - i * 3.2
		for s in [-1.0, 1.0]:
			if s > 0.0 and i >= 2:
				continue
			VillageHouse.areca(stat, leaves, _t(lane_x(z) + s * (main_lane_width * 0.5 + 1.0), 0.0, z), _rng)


## Ao: bờ đất + mặt nước (shader nước), có thể là nửa hình tròn (hồ bán nguyệt).
func _pond(stat: MeshBuilder, leaves: MeshBuilder, c: Vector3, r: Vector2, half: bool) -> void:
	var seg := 28
	var a0 := 0.0 if half else 0.0
	var a1 := PI if half else TAU
	var bank := MeshBuilder.new(random_seed + 60, 0.05)
	var below := c + Vector3(0, -2, 0)
	var rings: Array = [[0.98, 0.05, Palette.EARTH], [1.12, 0.06, Palette.EARTH], [1.3, 0.04, Palette.EARTH.lerp(Palette.GRASS, 0.5)]]
	var wobble := PackedFloat32Array()
	for i in seg + 1:
		wobble.append(1.0 + 0.06 * sin(i * 1.7) + 0.04 * sin(i * 3.1))
	var pt := func(i: int, s: float, y: float) -> Vector3:
		var a := lerpf(a0, a1, float(i) / seg)
		var k := s * (1.0 if half else wobble[i])
		return c + Vector3(cos(a) * r.x * k, y, sin(a) * r.y * k)
	for ri in rings.size() - 1:
		var ra: Array = rings[ri]
		var rb: Array = rings[ri + 1]
		for i in seg:
			bank.add_quad(pt.call(i, ra[0], ra[1]), pt.call(i + 1, ra[0], ra[1]),
					pt.call(i + 1, rb[0], rb[1]), pt.call(i, rb[0], rb[1]), ra[2], below)
	if half:
		# Bờ thẳng của hồ bán nguyệt: kè đá
		stat.add_box(Vector3(r.x * 2.6, 0.35, 0.5), Palette.PLINTH, Transform3D(Basis(), c + Vector3(0, 0, -0.25)))
	add_child(bank.commit_instance("PondBank"))
	# Mặt nước
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in seg:
		for v in [c + Vector3(0, 0.04, 0), pt.call(i, 1.02, 0.04), pt.call(i + 1, 1.02, 0.04)]:
			st.set_color(Color(Palette.WATER, 1.0))
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.name = "PondWater"
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader") as Shader
	mat.set_shader_parameter("opacity", 0.96)
	mat.set_shader_parameter("wave_height", 0.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Lá súng
	for i in 6:
		var a := _rng.randf_range(a0, a1)
		var d := _rng.randf_range(0.2, 0.75)
		var p := c + Vector3(cos(a) * r.x * d, 0.05, sin(a) * r.y * d)
		leaves.add_prism(0.35, 0.35, 0.02, 7, Palette.LILY, Transform3D(Basis(), p))


# --- Đình làng ----------------------------------------------------------------------------

## Đồ lễ ngày mùng 1 / rằm (mục 25): hai hàng cờ hội ngũ sắc dọc sân đình, đỉnh hương đồng trước
## thềm có khói hương. Nhóm `worship_decor` — LunarCalendar chỉ cho hiện vào ngày lễ.
func _build_worship_decor(cx: float, z_front: float, z_steps: float) -> void:
	var decor := Node3D.new()
	decor.name = "WorshipDecor"
	decor.add_to_group("worship_decor")
	decor.visible = false
	add_child(decor)
	var flags := MeshBuilder.new(random_seed + 600, 0.04)
	var stripes: Array[Color] = [Palette.FLAG_RED, Palette.FLOWER_YELLOW, Palette.SIGN_BLUE, Palette.FLOWER_WHITE, Palette.LILY]
	for s in [-1.0, 1.0]:
		for k in 5:
			var px: float = cx + s * 10.5
			var pz := z_front - 1.8 - k * 2.8
			flags.add_prism(0.045, 0.035, 5.2, 5, Palette.BAMBOO_STEM, _t(px, 0.0, pz))
			flags.add_pyramid(0.07, 0.25, 5, Palette.GOLD, _t(px, 5.2, pz))
			# Lá cờ dọc treo trên ngọn, năm sọc màu, tua đỏ dưới đáy
			for i in 5:
				flags.add_box(Vector3(0.03, 0.42, 0.9), stripes[(i + k) % 5], _t(px, 4.85 - i * 0.42, pz + 0.48))
			flags.add_box(Vector3(0.035, 0.1, 0.96), Palette.FLAG_RED.darkened(0.2), _t(px, 4.85 - 5 * 0.42 + 0.32, pz + 0.48))
	decor.add_child(flags.commit_instance("FestivalFlags", MeshBuilder.wind_material(0.12, 2.6, 2.6, 1.3)))
	# Đỉnh hương đồng ba chân trước thềm
	var burner := MeshBuilder.new(random_seed + 601, 0.03)
	var bz := z_steps + 1.6
	for a in 3:
		var ang := TAU * a / 3.0
		burner.add_prism(0.06, 0.05, 0.45, 5, Palette.GOLD.darkened(0.45), _t(cx + cos(ang) * 0.35, 0.0, bz + sin(ang) * 0.35))
	burner.add_prism(0.42, 0.55, 0.5, 10, Palette.GOLD.darkened(0.35), _t(cx, 0.45, bz))
	burner.add_prism(0.55, 0.5, 0.08, 10, Palette.GOLD.darkened(0.2), _t(cx, 0.95, bz))
	burner.add_prism(0.3, 0.12, 0.35, 8, Palette.GOLD.darkened(0.3), _t(cx, 1.03, bz))
	for i in 7:
		var o := Vector2(cos(i * 2.4), sin(i * 2.4)) * 0.22
		burner.add_prism(0.008, 0.008, 0.38, 3, Palette.FLAG_RED, _t(cx + o.x, 0.95, bz + o.y))
	decor.add_child(burner.commit_instance("IncenseBurner"))
	var smoke := CPUParticles3D.new()
	smoke.name = "IncenseSmoke"
	smoke.position = Vector3(cx, 1.4, bz)
	smoke.amount = 24
	smoke.lifetime = 4.0
	smoke.direction = Vector3.UP
	smoke.spread = 8.0
	smoke.initial_velocity_min = 0.25
	smoke.initial_velocity_max = 0.4
	smoke.gravity = Vector3(0.08, 0.05, 0.0)
	smoke.scale_amount_min = 0.25
	smoke.scale_amount_max = 0.5
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.5
	sm.radial_segments = 6
	sm.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(Palette.SMOKE, 0.35)
	sm.material = mat
	smoke.mesh = sm
	var ramp := Curve.new()
	ramp.add_point(Vector2(0.0, 0.4))
	ramp.add_point(Vector2(1.0, 1.6))
	smoke.scale_amount_curve = ramp
	decor.add_child(smoke)


func _build_dinh(stat: MeshBuilder, leaves: MeshBuilder, ground: MeshBuilder, glow: MeshBuilder) -> void:
	var z_front := alley_z[alley_z.size() - 1] - alley_width * 0.5 - 0.6
	dinh_spot = Vector3(lane_x(alley_z[alley_z.size() - 1]), 0.05, z_front - 12.5)
	var cx := lane_x(alley_z[alley_z.size() - 1])
	# Nghi môn: 2 trụ lớn giữa, 2 trụ nhỏ hai bên, có đèn lồng đá trên đỉnh
	var wc := Palette.WALL_WHITE.darkened(0.04)
	var wd := Palette.WALL_WHITE.darkened(0.2)
	for s in [-1.0, 1.0]:
		for k in 2:
			var px: float = cx + s * (2.3 if k == 0 else 5.6)
			var h := 5.2 if k == 0 else 3.8
			stat.add_box(Vector3(0.75, h, 0.75), wc, _t(px, 0.0, z_front))
			stat.add_box(Vector3(0.9, 0.5, 0.9), wd, _t(px, h, z_front))
			stat.add_pyramid(0.5, 0.6, 4, Palette.ROOF_BROWN, Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(px, h + 0.5, z_front)))
		stat.add_box(Vector3(2.5, 1.6, 0.35), wc, _t(cx + s * 3.95, 0.0, z_front))
		stat.add_box(Vector3(dinh_half_width - 6.0, 1.2, 0.3), wc, _t(cx + s * (6.0 + (dinh_half_width - 6.0) * 0.5), 0.0, z_front))
	# Sân đình lát gạch lớn (chừa chỗ hồ bán nguyệt giữa sân)
	var pond_c := Vector3(cx, 0.0, z_front - 7.0)
	var pond_r := Vector2(4.2, 3.2)
	var yard := Rect2(cx - dinh_half_width + 1.5, z_front - 16.0, (dinh_half_width - 1.5) * 2.0, 15.6)
	var ts := 0.8
	var zz := yard.position.y
	while zz < yard.end.y - 0.01:
		var xx := yard.position.x
		while xx < yard.end.x - 0.01:
			var q := Vector2((xx + ts * 0.5 - pond_c.x) / pond_r.x, (zz + ts * 0.5 - pond_c.z) / pond_r.y)
			if zz + ts > pond_c.z - 0.3 and q.length() < 1.4:
				xx += ts
				continue
			var col := Palette.LANE_BRICK if int((xx + zz) / ts) % 2 == 0 else Palette.LANE_BRICK.lerp(Palette.LANE_BRICK_DARK, 0.5)
			ground.add_quad(Vector3(xx + 0.03, 0.05, zz + 0.03), Vector3(xx + ts - 0.03, 0.05, zz + 0.03),
					Vector3(xx + ts - 0.03, 0.05, zz + ts - 0.03), Vector3(xx + 0.03, 0.05, zz + ts - 0.03), col,
					Vector3(xx, -1.0, zz))
			xx += ts
		zz += ts
	# Lớp vữa dưới gạch, chừa khung hồ
	var hole := Rect2(pond_c.x - pond_r.x * 1.35, pond_c.z - 0.6, pond_r.x * 2.7, pond_r.y * 1.35 + 0.6)
	var pieces: Array[Rect2] = [
		Rect2(yard.position.x, yard.position.y, yard.size.x, hole.position.y - yard.position.y),
		Rect2(yard.position.x, hole.end.y, yard.size.x, yard.end.y - hole.end.y),
		Rect2(yard.position.x, hole.position.y, hole.position.x - yard.position.x, hole.size.y),
		Rect2(hole.end.x, hole.position.y, yard.end.x - hole.end.x, hole.size.y),
	]
	for pc in pieces:
		if pc.size.x > 0.01 and pc.size.y > 0.01:
			ground.add_quad(Vector3(pc.position.x, 0.035, pc.position.y), Vector3(pc.end.x, 0.035, pc.position.y),
					Vector3(pc.end.x, 0.035, pc.end.y), Vector3(pc.position.x, 0.035, pc.end.y), Palette.GROUT,
					Vector3(pc.get_center().x, -1.0, pc.get_center().y))
	# Hồ bán nguyệt giữa sân: bờ thẳng hướng về đình, mặt cong hướng ra nghi môn
	_pond(stat, leaves, pond_c, pond_r, true)
	dinh_pond_center = pond_c
	dinh_pond_radii = pond_r * 1.35
	# Tả mạc, hữu mạc hai bên sân
	var side_st := {"roof": "tile_brown", "form": "gable", "wall": "lime_white"}
	for s in [-1.0, 1.0]:
		var sx: float = cx + s * (dinh_half_width - 4.0)
		VillageHouse.build_small(stat, glow, Transform3D(Basis(Vector3.UP, -s * PI * 0.5), Vector3(sx, 0.0, z_front - 9.0)), 8.0, 3.8, 2.3, side_st)
	# Toà đình: nền đá cao, khung cột gỗ, tường sau, mái bốn mái lớn có đầu đao + lưỡng long chầu nguyệt
	var hz := z_front - 16.0 - 7.0
	var xf := _t(cx, 0.0, hz)
	var L := 20.0
	var D := 12.0
	var P := 0.8
	var H := 3.0
	stat.add_box(Vector3(L + 2.0, P, D + 2.0), Palette.PLINTH.darkened(0.08), xf)
	dinh_door = Vector3(cx, 0.05, hz + (D + 2.0) * 0.5 + 1.9)
	_build_worship_decor(cx, z_front, hz + (D + 2.0) * 0.5 + 0.9)
	HouseEntry.make_entry_target(self, xf * _t(0.0, P + 1.5, D * 0.5 - 0.3), Vector3(4.0, 3.0, 0.8),
			"Vào đình làng  ·  bấm chuột hoặc E",
			{"kind": "dinh", "name": "Đình làng", "length": L, "depth": D, "plinth": P,
			"height": H, "veranda": 0.0, "seed": random_seed + 501}, "dinh")
	for i in 3:
		stat.add_box(Vector3(8.0 - i * 1.2, P - i * 0.27, 0.5), Palette.PLINTH, xf * _t(0.0, 0.0, (D + 2.0) * 0.5 + 0.25 + (2 - i) * 0.5))
	stat.add_box(Vector3(L, H, 0.3), Palette.WOOD, xf * _t(0.0, P, -D * 0.5 + 0.15))
	for s in [-1.0, 1.0]:
		stat.add_box(Vector3(0.3, H, D - 0.3), Palette.WOOD, xf * _t(s * (L * 0.5 - 0.15), P, 0.0))
	for ix in 6:
		for iz in 4:
			var x := -L * 0.5 + 0.6 + (L - 1.2) * ix / 5.0
			var z := -D * 0.5 + 0.8 + (D - 1.6) * iz / 3.0
			stat.add_prism(0.24, 0.22, H, 8, Palette.WOOD.darkened(0.1), xf * _t(x, P, z))
			stat.add_prism(0.34, 0.34, 0.15, 8, Palette.PLINTH, xf * _t(x, P, z))
	# Ban thờ thành hoàng phía trong
	stat.add_box(Vector3(3.0, 1.4, 1.2), Palette.ALTAR_RED, xf * _t(0.0, P, -D * 0.5 + 1.0))
	stat.add_box(Vector3(2.6, 0.2, 0.04), Palette.GOLD, xf * _t(0.0, P + 1.1, -D * 0.5 + 1.62))
	stat.add_box(Vector3(L, 0.25, D), Palette.WOOD.darkened(0.15), xf * _t(0.0, P + H, 0.0))
	VillageHouse.roof(stat, xf, L, D, P + H + 0.25, 4.6, 1.8, 1.8, "tile_brown", "hip", Palette.WOOD, Palette.WOOD.darkened(0.2))
	# Lưỡng long chầu nguyệt trên bờ nóc
	var ridge_y := P + H + 0.25 + 4.6 + 0.4
	stat.add_prism(0.5, 0.5, 0.12, 10, Palette.GOLD, xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, ridge_y + 0.7, 0.06)))
	for s in [-1.0, 1.0]:
		var p0 := Vector3(s * 3.0, ridge_y, 0.0)
		var p1 := Vector3(s * 2.0, ridge_y + 0.9, 0.0)
		var p2 := Vector3(s * 1.2, ridge_y + 0.6, 0.0)
		var p3 := Vector3(s * 0.7, ridge_y + 0.85, 0.0)
		stat.add_limb(p0, p1, 0.16, 0.13, 5, Palette.LILY.darkened(0.2), xf)
		stat.add_limb(p1, p2, 0.13, 0.11, 5, Palette.LILY.darkened(0.2), xf)
		stat.add_limb(p2, p3, 0.11, 0.05, 5, Palette.LILY.darkened(0.2), xf)
	# Đèn lồng trong đình sáng ban đêm
	for s in [-1.0, 1.0]:
		var light := OmniLight3D.new()
		light.position = Vector3(cx + s * 4.0, P + H - 0.6, hz + 2.0)
		light.light_color = Palette.WINDOW_GLOW
		light.omni_range = 9.0
		light.light_energy = 0.0
		light.set_meta("max_energy", 2.2)
		light.add_to_group("night_light")
		add_child(light)
	# Cây đa sân đình
	var tree := BanyanTree.new()
	tree.name = "DinhBanyan"
	tree.random_seed = random_seed + 9
	tree.tree_position = Vector3(cx + dinh_half_width - 3.0, 0.0, hz - 3.0)
	tree.canopy_radius = 4.6
	tree.canopy_height = 6.6
	add_child(tree)
	tree.build()


# --- Chùa -------------------------------------------------------------------------------

func _build_pagoda(stat: MeshBuilder, leaves: MeshBuilder, ground: MeshBuilder, glow: MeshBuilder) -> void:
	var r := pagoda_rect
	var cx := r.get_center().x
	pagoda_spot = Vector3(cx, 0.05, r.end.y - 4.0)
	var front := r.end.y
	var wc := Palette.WALL
	var wd := Palette.WALL_DARK
	# Tường bao trước với tam quan (cổng 3 lối, cổng giữa mái hai tầng)
	for s in [-1.0, 1.0]:
		var seg_len := r.size.x * 0.5 - 4.2
		stat.add_box(Vector3(seg_len, 1.6, 0.3), wc, _t(cx + s * (4.2 + seg_len * 0.5), 0.0, front - 0.4))
		stat.add_box(Vector3(seg_len, 0.1, 0.45), Palette.ROOF_BROWN_DARK, _t(cx + s * (4.2 + seg_len * 0.5), 1.6, front - 0.4))
	for k in [-1, 0, 1]:
		var gx: float = cx + k * 2.9
		var big: bool = k == 0
		var h := 3.0 if big else 2.4
		var w := 2.0 if big else 1.4
		for s in [-1.0, 1.0]:
			stat.add_box(Vector3(0.5, h, 0.6), wc, _t(gx + s * (w * 0.5 + 0.25), 0.0, front - 0.4))
		VillageHouse.roof(stat, _t(gx, 0.0, front - 0.4), w + 1.0, 1.0, h, 0.6, 0.35, 0.3, "tile_brown", "hip", wc, wd)
		if big:
			stat.add_box(Vector3(w + 0.8, 0.9, 0.7), wc, _t(gx, h + 0.5, front - 0.4))
			VillageHouse.roof(stat, _t(gx, 0.0, front - 0.4), w + 0.6, 0.8, h + 1.4, 0.55, 0.3, 0.25, "tile_brown", "hip", wc, wd)
	# Sân chùa
	ground.add_quad(Vector3(r.position.x + 1.0, 0.04, r.position.y + 1.0), Vector3(r.end.x - 1.0, 0.04, r.position.y + 1.0),
			Vector3(r.end.x - 1.0, 0.04, front - 0.8), Vector3(r.position.x + 1.0, 0.04, front - 0.8), Palette.YARD,
			Vector3(cx, -1.0, r.get_center().y))
	# Chính điện: mái chồng diêm hai tầng có đầu đao
	var hz := r.position.y + 9.0
	var xf := _t(cx, 0.0, hz)
	var L := 13.0
	var D := 9.0
	var P := 0.7
	var H := 2.8
	stat.add_box(Vector3(L + 1.2, P, D + 1.2), Palette.PLINTH, xf)
	HouseEntry.make_entry_target(self, xf * _t(0.0, P + 1.1, D * 0.5 - 1.5), Vector3(2.6, 2.2, 0.5),
			"Vào chùa  ·  bấm chuột hoặc E",
			{"kind": "pagoda", "name": "Chùa làng", "length": L, "depth": D, "plinth": P,
			"height": H, "veranda": 1.6, "seed": random_seed + 502}, "pagoda")
	stat.add_box(Vector3(4.0, P * 0.5, 0.6), Palette.PLINTH, xf * _t(0.0, 0.0, (D + 1.2) * 0.5 + 0.3))
	stat.add_box(Vector3(L, H, D - 1.6), wc, xf * _t(0.0, P, -0.8))
	for i in 6:
		var x := -L * 0.5 + 0.3 + (L - 0.6) * i / 5.0
		stat.add_prism(0.16, 0.15, H, 8, Palette.ALTAR_RED, xf * _t(x, P, D * 0.5 - 0.3))
	for i in 5:
		var x := -L * 0.5 + L * (i + 0.5) / 5.0
		stat.add_box(Vector3(1.5, H - 0.4, 0.08), Palette.ALTAR_RED, xf * _t(x, P, D * 0.5 - 1.6))
		glow.add_box(Vector3(1.0, 0.3, 0.04), Palette.WINDOW_DARK, xf * _t(x, P + H - 0.9, D * 0.5 - 1.55))
	VillageHouse.roof(stat, xf, L, D, P + H, 1.3, 1.1, 1.1, "tile_brown", "hip", wc, wd)
	stat.add_box(Vector3(L - 3.2, 1.7, D - 3.2), wc, xf * _t(0.0, P + H + 0.6, 0.0))
	VillageHouse.roof(stat, xf, L - 3.2, D - 3.2, P + H + 2.3, 1.9, 0.8, 0.8, "tile_brown", "hip", wc, wd)
	# Gác chuông
	var bx := _t(r.position.x + 4.0, 0.0, front - 6.0)
	stat.add_box(Vector3(2.6, 2.4, 2.6), wc, bx)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			stat.add_box(Vector3(0.35, 1.8, 0.35), wc, bx * _t(sx * 1.1, 2.4, sz * 1.1))
	stat.add_prism(0.35, 0.45, 0.7, 10, Palette.GOLD.darkened(0.35), bx * _t(0.0, 3.0, 0.0))
	VillageHouse.roof(stat, bx, 2.6, 2.6, 4.2, 1.2, 0.5, 0.5, "tile_brown", "hip", wc, wd)
	# Cây trong sân chùa
	for p in [Vector2(r.end.x - 4.0, front - 6.0), Vector2(r.end.x - 3.0, r.position.y + 3.0)]:
		VillageHouse._fruit_tree(stat, leaves, _t(p.x, 0.0, p.y), _rng)
	for s in [-1.0, 1.0]:
		var light := OmniLight3D.new()
		light.position = Vector3(cx + s * 3.5, P + H - 0.4, hz + D * 0.5)
		light.light_color = Palette.WINDOW_GLOW
		light.omni_range = 7.0
		light.light_energy = 0.0
		light.set_meta("max_energy", 1.8)
		light.add_to_group("night_light")
		add_child(light)


# --- Vườn tạp lấp khoảng trống ------------------------------------------------------------

func _is_lane(p: Vector2, margin: float) -> bool:
	for i in _lane.size() - 1:
		if Terrain._segment_distance(p, _lane[i], _lane[i + 1]) < main_lane_width * 0.5 + margin:
			return true
	for a in _alleys:
		for i in a.size() - 1:
			if Terrain._segment_distance(p, a[i], a[i + 1]) < alley_width * 0.5 + margin:
				return true
	return false


## Cây ăn quả, chuối, cau, bụi tre rải ở chỗ trống trong làng (giữa lô và lũy tre).
func _build_wild_gardens() -> void:
	var stat := MeshBuilder.new(random_seed + 70, 0.05)
	stat.contact_shade_height = 0.5
	var leaves := MeshBuilder.new(random_seed + 71, 0.07)
	var dinh_rect := Rect2(-dinh_half_width - 2.0, alley_z[alley_z.size() - 1] - 36.0, dinh_half_width * 2.0 + 4.0, 36.0)
	var entrance := Rect2(pond_center.x - 10.0, gate_point().y - 16.0, banyan_position.x - pond_center.x + 18.0, 16.0)
	var placed := 0
	for attempt in 1400:
		var p := Vector2(_rng.randf_range(-radii.x, radii.x), _rng.randf_range(center.y - radii.y, center.y + radii.y))
		if not _inside(p, 0.9) or _is_lane(p, 1.2):
			continue
		if dinh_rect.has_point(p) or pagoda_rect.grow(1.0).has_point(p) or old_pitch_rect.grow(3.5).has_point(p) or entrance.has_point(p) or _on_access(p, 2.0):
			continue
		var blocked := false
		for r in _occupied:
			if r.has_point(p):
				blocked = true
				break
		if blocked:
			continue
		var xf := _t(p.x, 0.0, p.y)
		var roll := _rng.randf()
		if roll < 0.45:
			VillageHouse._fruit_tree(stat, leaves, xf, _rng)
		elif roll < 0.7:
			VillageHouse.banana(stat, leaves, xf, _rng)
		elif roll < 0.85:
			VillageHouse.areca(stat, leaves, xf, _rng)
		else:
			_bamboo_clump(stat, leaves, Vector3(p.x, 0.0, p.y), Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized())
		placed += 1
	add_child(stat.commit_instance("WildGardenWood"))
	add_child(leaves.commit_instance("WildGardenLeaves", MeshBuilder.wind_material(leaf_wind, 0.6, 6.0, 0.9)))
