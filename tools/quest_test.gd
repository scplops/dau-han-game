extends SceneTree
## Chạy thử 5 loại việc nhờ không giao diện: nhận việc qua hội thoại, làm từng bước
## (múc nước, gánh về, nhắn tin, câu cá, nhặt đồ, sút bóng), báo lại, nhận quà. In diễn biến.
## Dùng: godot --headless --path . -s tools/quest_test.gd
var dlg: Dialogue
var fp: FirstPerson
var qs: Quests

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _say_opt(v: Villager, needle: String) -> bool:
	if not dlg.talking:
		dlg.start(v, fp)
	for i in dlg._options.size():
		var t := dlg._fill(str(dlg._options[i].text))
		if t.contains(needle):
			print("    > " + t)
			dlg._choose(i)
			print("    %s: %s" % [v.display_name, dlg._text_label.text])
			return true
	print("    (không thấy lựa chọn '%s')" % needle)
	return false

func _run() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var w := scene.get_node("Weather") as Weather
	w.auto_change = false
	w.set_weather("clear", true)
	await _frames(3)
	dlg = scene.get_node("Dialogue") as Dialogue
	fp = scene.get_node("FirstPerson") as FirstPerson
	qs = scene.get_node("Quests") as Quests
	var vs := scene.get_node("World/Villagers") as Villagers
	fp.enter()
	await _frames(2)
	var plan := {"water": "farmer", "message": "elder", "fish": "carrier", "lost": "elder", "goal": "kid"}
	var used := {}
	for kind: String in plan:
		var giver: Villager = null
		for v in vs.people:
			if v.role == plan[kind] and not used.has(v):
				giver = v
				break
		used[giver] = true
		if not giver.visible:
			vs.call_out(giver)
		var q := qs.make_quest(giver, kind)
		giver.set_meta("quest_offer", q)
		print("\n=== %s — %s ===" % [kind, giver.display_name])
		fp.global_position = giver.global_position + Vector3(1.5, 0.1, 0)
		_say_opt(giver, "giúp gì")
		_say_opt(giver, "để ")
		dlg.end()
		print("    nhận việc: %s · bước: %s" % [q.title, qs._step(q).desc])
		var steps := 0
		while qs.active.has(q) and steps < 6:
			steps += 1
			var st := qs._step(q)
			match str(st.type):
				"pickup":
					qs._pickup(q)
					print("    nhặt/múc → đang cầm: %s" % str(qs.items))
				"goto":
					fp.global_position = st.pos + Vector3(0, 0.3, 0)
					await _frames(5)
					print("    tới nơi → đang cầm: %s" % str(qs.items))
				"catch":
					qs.fishing.basket.append({"name": st.species, "kg": 1.2})
					await _frames(2)
					print("    câu được %s" % st.species)
				"goal":
					var fb: Football = qs.football
					fb._end_match()
					var gx: float = fb.rect.end.x
					fb._place_ball(Vector3(gx - 4.0, 0, fb.rect.get_center().y))
					fb.kick_from_player(Vector3(1, 0, 0), 0.05)
					await create_timer(2.0).timeout
					print("    sút → tỉ số %s" % str(fb.score))
				"talk":
					var who: Villager = st.npc
					if not who.visible:
						fp.global_position = (who.home.front as Vector3) + Vector3(0, 0.3, 0)
						await _frames(3)
						print("    gõ cửa → %s ra cổng: %s" % [who.display_name, who.visible])
					fp.global_position = who.global_position + Vector3(1.5, 0.1, 0)
					dlg.start(who, fp)
					var t := dlg._fill(str(dlg._options[0].text))
					_say_opt(who, t.substr(0, 12))
					dlg.end()
			await _frames(2)
		print("    xong: %s · quà: %s" % [not qs.active.has(q), str(qs.gifts)])
	print("\nTổng: %d việc xong, quà %s, đang cầm %s" % [qs.done_count, str(qs.gifts), str(qs.items)])
	quit()
