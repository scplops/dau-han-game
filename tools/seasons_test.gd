extends SceneTree
## Thử bốn mùa (mục 42), headless: với một ngày giữa mỗi mùa + ngày giáp ranh, in mùa, mức ngả màu lá, hoa phượng,
## hạt bay, mức ve kêu, phân bố thời tiết (2000 lần chọn), trẻ con có được tắm sông không.
## Dùng: godot --headless --path . -s tools/seasons_test.gd
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 30:
		await physics_frame
	var cal := scene.get_node("Calendar") as LunarCalendar
	var dn := scene.get_node("DayNight") as DayNight
	var w := scene.get_node("Weather") as Weather
	var se := scene.get_node("Seasons") as Seasons
	var vs := scene.get_node("World/Villagers") as Villagers
	var snd := scene.get_node("Soundscape") as Soundscape
	var hud := scene.get_node("HUD") as Hud
	w.auto_change = false
	w.set_weather("clear", true)
	dn.auto_run = false
	dn.time_of_day = 10.0
	for date: String in ["2027-03-21", "2027-05-02", "2027-06-20", "2027-09-19", "2027-10-31", "2027-12-19"]:
		cal.set_date_string(date)
		for i in 5:
			await physics_frame
		var cnt := {}
		for i in 2000:
			var k := w._pick_weighted("")
			cnt[k] = int(cnt.get(k, 0)) + 1
		var dist := ""
		for k: String in Weather.ORDER:
			dist += "%s %d%%  " % [Weather.NAMES[k], roundi(int(cnt.get(k, 0)) / 20.0)]
		var swim := 0
		for v in vs.people:
			if v.role == "kid" and vs._choices(v, 10.0).has("swim"):
				swim += 1
		for i in 120:
			await physics_frame
		var cic: AudioStreamPlayer = snd._loops.get("cicada")
		print("%s → %s · HUD \"%s\"" % [date, se.season, hud._date_label.text.split("\n")[0]])
		print("   lá ngả %.2f màu (%.2f %.2f %.2f) · hoa phượng %.2f · hạt bay %.2f (%d hạt, %s) · ve %.2f (%.0f dB) · trẻ muốn tắm sông %d" % [
				se.leaf_mix, se.leaf_color.r, se.leaf_color.g, se.leaf_color.b, se.bloom, se.drift, se._drift.amount,
				"đang rơi" if se._drift.emitting else "tắt", snd.cicada_level, cic.volume_db if cic != null else -99.0, swim])
		print("   thời tiết: %s" % dist)
	quit()
