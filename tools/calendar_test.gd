extends SceneTree
## Kiểm tra lịch âm: đối chiếu các ngày đã biết (Tết, Trung thu, tháng nhuận), thứ trong tuần.
## Dùng: godot --headless --path . -s tools/calendar_test.gd
func _initialize() -> void:
	var cases := [
		# [dương lịch, âm lịch mong đợi "ngày/tháng[n]/năm"]
		["2024-02-10", "1/1/2024"], ["2025-01-29", "1/1/2025"], ["2026-02-17", "1/1/2026"],
		["2027-02-06", "1/1/2027"], ["2025-10-06", "15/8/2025"], ["2024-09-17", "15/8/2024"],
		["2023-03-22", "1/2n/2023"], ["2023-04-20", "1/3/2023"], ["2025-07-25", "1/6n/2025"],
		["2026-11-05", "27/9/2026"], ["2000-01-01", "25/11/1999"], ["2026-02-16", "29/12/2025"],
	]
	var ok := 0
	for c in cases:
		var p: PackedStringArray = str(c[0]).split("-")
		var l := LunarCalendar.solar_to_lunar(int(p[2]), int(p[1]), int(p[0]), 7.0)
		var got := "%d/%d%s/%d" % [int(l.day), int(l.month), "n" if bool(l.leap) else "", int(l.year)]
		var good := got == str(c[1])
		ok += 1 if good else 0
		print("%s → %-12s %s %s" % [c[0], got, "✓" if good else "✗ mong đợi", "" if good else str(c[1])])
	print("Năm 2026: %s, 2025: %s, 2024: %s" % [LunarCalendar.can_chi_year(2026), LunarCalendar.can_chi_year(2025), LunarCalendar.can_chi_year(2024)])
	var j := LunarCalendar.jd_from_date(5, 11, 2026)
	print("5/11/2026 là %s (mong đợi Thứ Năm); đổi ngược: %s" % [LunarCalendar.WEEKDAYS[(j + 1) % 7], str(LunarCalendar.date_from_jd(j))])
	print("ĐÚNG %d/%d" % [ok, cases.size()])
	quit()
