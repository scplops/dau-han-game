extends SceneTree
## Thử mùa vụ (headless):
## 1) Đi qua các ngày trong vụ: giai đoạn, số khóm lúa ruộng nhà mình đang hiện / gốc rạ / có bông, nước ruộng,
##    ô ngoài đồng có nước, đống rơm, sân phơi thóc, trâu kéo cày, mức bận, việc ngoài đồng, lời nông dân.
## 2) Thời gian vẽ lại (ms). 3) Mùa cấy 8:30 và mùa gặt: nông dân ra đồng làm đúng dáng (plant / reap).
## Dùng: godot --headless --path . -s tools/farming_test.gd
func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _visible(m: MultiMesh, i: int) -> bool:
	return m.get_instance_transform(i).basis.get_scale().length() > 0.001

func _run() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var w := scene.get_node("Weather") as Weather
	w.auto_change = false
	w.set_weather("clear", true)
	await _frames(5)
	var fm := scene.get_node("Farming") as Farming
	var rf := scene.get_node("World/RiceField") as RiceField
	var dn := scene.get_node("DayNight") as DayNight
	var cal := scene.get_node("Calendar") as LunarCalendar
	dn.time_of_day = 10.0
	print("Hôm nay %s: ngày %.1f của vụ — %s" % [cal.solar_text(), fm.day_in_cycle(0.0), fm.stage_text()])
	for d in [2.0, 7.0, 9.0, 20.0, 45.0, 58.0, 70.0, 82.0, 85.0, 89.0]:
		fm.set_cycle_day(d)
		var c := fm.counts
		var shown := int(c.home_shown)
		var stub := int(c.home_stubble)
		var ears := int(c.home_ears)
		var owater := int(c.outer_water)
		var stacks := int(c.stacks)
		var yards := int(c.yards)
		var sheaves := int(c.sheaves)
		fm._step_plow(0.1)
		var fw := fm.field_work(Vector3(60, 0, 0))
		print("ngày %4.1f %-11s | nhà: lúa %4d (gốc rạ %4d, bông %4d), nước %s, bó lúa %2d | đồng: nước %3d/%d, rơm %3d | sân phơi %2d | cày %s | bận ×%.1f | ngoài đồng: %s (%s)" % [
				d, fm.stage_key(), shown, stub, ears, fm._home_water[0].visible, sheaves, owater, fm._outer.size(), stacks, yards,
				fm._plow.visible, fm.busy(), fw.text, fw.anim])
	print("   lời nông dân lúc gặt: %s" % fm.rice_talk())
	var t0 := Time.get_ticks_usec()
	for k in 5:
		fm.refresh(true)
	print("Vẽ lại toàn bộ: %.1f ms / lần (%d khóm + %d ô ruộng ngoài đồng)" % [(Time.get_ticks_usec() - t0) / 5000.0, rf.base_xforms.size(), fm._outer.size()])
	# Nông dân ra đồng theo mùa
	var vs := scene.get_node("World/Villagers") as Villagers
	while cal.weekday() == 0:
		cal.add_days(1)
	for d in [8.0, 83.0]:
		fm.set_cycle_day(d)
		dn.time_of_day = 8.5
		vs.replan()
		Engine.time_scale = 8.0
		await _frames(60 * 20)
		Engine.time_scale = 1.0
		var anims := {}
		var going := 0
		for v in vs.people:
			if v.activity == "field":
				going += 1
				if v.state != Villager.State.WALK:
					anims[v.work_anim] = int(anims.get(v.work_anim, 0)) + 1
		print("ngày %d (%s) 8:30: %d người ra đồng, dáng ở ruộng %s" % [int(d), fm.stage_key(), going, anims])
	quit()
