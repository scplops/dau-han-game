class_name LunarCalendar
extends Node
## Lịch Việt Nam (mục 25): ngày dương lịch, thứ trong tuần, âm lịch (có tháng nhuận) và năm can chi.
## Âm lịch tính theo thuật toán của Hồ Ngọc Đức (thiên văn, múi giờ UTC+7 — giờ Việt Nam).
## Ngày tự sang khi đồng hồ DayNight qua nửa đêm (tiến hoặc lùi); phím `,` / `.` lùi / tiến một ngày.
## Mùng 1 và rằm (15 âm lịch) là ngày đi lễ: dân làng ra đình thắp hương (Villagers), sân đình cắm
## cờ hội, đỉnh hương bốc khói (nhóm `worship_decor`, chỉ hiện ngày lễ).

signal date_changed

@export var day_night: DayNight
## Bắt đầu từ ngày hôm nay của máy; tắt thì dùng `start_date`.
@export var use_system_date: bool = true
@export var start_date: String = "2026-11-05"
## Múi giờ tính âm lịch (Việt Nam: +7).
@export var time_zone: float = 7.0

const CAN: Array[String] = ["Giáp", "Ất", "Bính", "Đinh", "Mậu", "Kỷ", "Canh", "Tân", "Nhâm", "Quý"]
const CHI: Array[String] = ["Tý", "Sửu", "Dần", "Mão", "Thìn", "Tỵ", "Ngọ", "Mùi", "Thân", "Dậu", "Tuất", "Hợi"]
const WEEKDAYS: Array[String] = ["Chủ nhật", "Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy"]
const LUNAR_MONTHS: Array[String] = ["Giêng", "Hai", "Ba", "Tư", "Năm", "Sáu", "Bảy", "Tám", "Chín", "Mười", "Một", "Chạp"]

## Số ngày Julius của ngày đang chạy.
var jd: int = 0
var _lunar_cache: Dictionary = {}


## Đặt ngày ngay khi vào cây (trước _ready của World), để Villagers dựng lịch sinh hoạt đã có ngày.
func _enter_tree() -> void:
	if jd != 0:
		return
	if use_system_date:
		var d := Time.get_date_dict_from_system()
		jd = jd_from_date(int(d.day), int(d.month), int(d.year))
	else:
		var p := start_date.split("-")
		jd = jd_from_date(int(p[2]), int(p[1]), int(p[0]))


func _ready() -> void:
	if day_night != null:
		day_night.day_rolled.connect(func(days: int) -> void: add_days(days))
	_apply.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("day_forward"):
		add_days(1)
	elif event.is_action_pressed("day_back"):
		add_days(-1)


## Đặt ngày theo chuỗi "YYYY-MM-DD".
func set_date_string(s: String) -> void:
	var p := s.split("-")
	if p.size() == 3:
		set_jd(jd_from_date(int(p[2]), int(p[1]), int(p[0])))


func set_jd(value: int) -> void:
	jd = value
	_lunar_cache.clear()
	if is_inside_tree():
		_apply()


func add_days(n: int) -> void:
	set_jd(jd + n)


## Nhảy tới ngày gần nhất (kể cả hôm nay) có ngày âm lịch là `lunar_day`.
func goto_lunar_day(lunar_day: int) -> void:
	for i in 40:
		if int(lunar_at(jd + i).day) == lunar_day:
			set_jd(jd + i)
			return


func _apply() -> void:
	get_tree().call_group("worship_decor", "set_visible", is_worship_day())
	date_changed.emit()


# --- Thông tin ngày ------------------------------------------------------------------------

## [ngày, tháng, năm] dương lịch.
func solar() -> Array[int]:
	return date_from_jd(jd)


## 0 = Chủ nhật, 1 = thứ Hai … 6 = thứ Bảy.
func weekday() -> int:
	return (jd + 1) % 7


func weekday_name() -> String:
	return WEEKDAYS[weekday()]


## {day, month, year, leap} âm lịch của ngày đang chạy.
func lunar() -> Dictionary:
	if _lunar_cache.is_empty():
		_lunar_cache = lunar_at(jd)
	return _lunar_cache


func lunar_at(j: int) -> Dictionary:
	var s := date_from_jd(j)
	return solar_to_lunar(s[0], s[1], s[2], time_zone)


static func can_chi_year(y: int) -> String:
	return "%s %s" % [CAN[(y + 6) % 10], CHI[(y + 8) % 12]]


## Mùng 1 hoặc rằm: ngày đi lễ đình.
func is_worship_day() -> bool:
	var d := int(lunar().day)
	return d == 1 or d == 15


## Tên ngày đặc biệt (rỗng nếu ngày thường).
func holiday_name() -> String:
	var l := lunar()
	var d := int(l.day)
	var m := int(l.month)
	if bool(l.leap):
		return "Mùng một" if d == 1 else ("Rằm" if d == 15 else "")
	if m == 1 and d <= 3:
		return "Tết Nguyên đán"
	if m == 1 and d == 15:
		return "Rằm tháng Giêng"
	if m == 3 and d == 10:
		return "Giỗ Tổ Hùng Vương"
	if m == 5 and d == 5:
		return "Tết Đoan ngọ"
	if m == 7 and d == 15:
		return "Rằm tháng Bảy"
	if m == 8 and d == 15:
		return "Tết Trung thu"
	if m == 12 and d == 23:
		return "Ông Công ông Táo"
	if d == 1:
		return "Mùng một"
	if d == 15:
		return "Rằm"
	return ""


## Nghỉ học: Chủ nhật, từ 23 tháng Chạp tới hết mùng 7 Tết.
func is_school_day() -> bool:
	if weekday() == 0:
		return false
	var l := lunar()
	if bool(l.leap):
		return true
	var d := int(l.day)
	var m := int(l.month)
	return not ((m == 12 and d >= 23) or (m == 1 and d <= 7))


## "5/11/2026"
func solar_text() -> String:
	var s := solar()
	return "%d/%d/%d" % [s[0], s[1], s[2]]


## "16/9 Bính Ngọ" (tháng nhuận thêm chữ "n").
func lunar_short() -> String:
	var l := lunar()
	return "%d/%d%s %s" % [int(l.day), int(l.month), "n" if bool(l.leap) else "", can_chi_year(int(l.year))]


## Cách nói ngày âm: "mùng 3", "ngày 12", "rằm", "ngày 30".
static func lunar_day_words(d: int) -> String:
	if d == 15:
		return "rằm"
	if d <= 10:
		return "mùng %d" % d
	return "ngày %d" % d


## "rằm tháng Chín năm Bính Ngọ", "mùng 3 tháng Chạp…", "ngày 12 tháng Tư nhuận…"
func lunar_words() -> String:
	var l := lunar()
	return "%s tháng %s%s năm %s" % [lunar_day_words(int(l.day)), LUNAR_MONTHS[int(l.month) - 1],
			" nhuận" if bool(l.leap) else "", can_chi_year(int(l.year))]


## Dòng ngày cho HUD: "Thứ Năm 5/11/2026 · Âm lịch 16/9 Bính Ngọ · Rằm"
func date_text() -> String:
	var t := "%s %s · Âm lịch %s" % [weekday_name(), solar_text(), lunar_short()]
	var hn := holiday_name()
	if hn != "":
		t += " · " + hn
	return t


# --- Thuật toán (Hồ Ngọc Đức, "Âm lịch Việt Nam") ------------------------------------------

static func jd_from_date(dd: int, mm: int, yy: int) -> int:
	var a := int((14 - mm) / 12)
	var y := yy + 4800 - a
	var m := mm + 12 * a - 3
	var j := dd + int((153 * m + 2) / 5) + 365 * y + int(y / 4) - int(y / 100) + int(y / 400) - 32045
	if j < 2299161:
		j = dd + int((153 * m + 2) / 5) + 365 * y + int(y / 4) - 32083
	return j


static func date_from_jd(j: int) -> Array[int]:
	var b: int
	var c: int
	if j > 2299160:
		var a := j + 32044
		b = int((4 * a + 3) / 146097)
		c = a - int(b * 146097 / 4)
	else:
		b = 0
		c = j + 32082
	var d := int((4 * c + 3) / 1461)
	var e := c - int(1461 * d / 4)
	var m := int((5 * e + 2) / 153)
	var day := e - int((153 * m + 2) / 5) + 1
	var month := m + 3 - 12 * int(m / 10)
	var year := b * 100 + d - 4800 + int(m / 10)
	return [day, month, year]


## Ngày Julius (đã làm tròn theo múi giờ) của điểm sóc thứ k tính từ 1/1/1900.
static func new_moon_day(k: int, tz: float) -> int:
	var T := k / 1236.85
	var T2 := T * T
	var T3 := T2 * T
	var dr := PI / 180.0
	var Jd1 := 2415020.75933 + 29.53058868 * k + 0.0001178 * T2 - 0.000000155 * T3
	Jd1 += 0.00033 * sin((166.56 + 132.87 * T - 0.009173 * T2) * dr)
	var M := 359.2242 + 29.10535608 * k - 0.0000333 * T2 - 0.00000347 * T3
	var Mpr := 306.0253 + 385.81691806 * k + 0.0107306 * T2 + 0.00001236 * T3
	var F := 21.2964 + 390.67050646 * k - 0.0016528 * T2 - 0.00000239 * T3
	var C1 := (0.1734 - 0.000393 * T) * sin(M * dr) + 0.0021 * sin(2 * dr * M)
	C1 = C1 - 0.4068 * sin(Mpr * dr) + 0.0161 * sin(dr * 2 * Mpr)
	C1 = C1 - 0.0004 * sin(dr * 3 * Mpr)
	C1 = C1 + 0.0104 * sin(dr * 2 * F) - 0.0051 * sin(dr * (M + Mpr))
	C1 = C1 - 0.0074 * sin(dr * (M - Mpr)) + 0.0004 * sin(dr * (2 * F + M))
	C1 = C1 - 0.0004 * sin(dr * (2 * F - M)) - 0.0006 * sin(dr * (2 * F + Mpr))
	C1 = C1 + 0.0010 * sin(dr * (2 * F - Mpr)) + 0.0005 * sin(dr * (2 * Mpr + M))
	var deltat: float
	if T < -11:
		deltat = 0.001 + 0.000839 * T + 0.0002261 * T2 - 0.00000845 * T3 - 0.000000081 * T * T3
	else:
		deltat = -0.000278 + 0.000265 * T + 0.000262 * T2
	var JdNew := Jd1 + C1 - deltat
	return int(floor(JdNew + 0.5 + tz / 24.0))


## Kinh độ mặt trời lúc 0h ngày jdn, chia 12 cung (0…11).
static func sun_longitude(jdn: int, tz: float) -> int:
	var T := (jdn - 2451545.5 - tz / 24.0) / 36525.0
	var T2 := T * T
	var dr := PI / 180.0
	var M := 357.52910 + 35999.05030 * T - 0.0001559 * T2 - 0.00000048 * T * T2
	var L0 := 280.46645 + 36000.76983 * T + 0.0003032 * T2
	var DL := (1.914600 - 0.004817 * T - 0.000014 * T2) * sin(dr * M)
	DL = DL + (0.019993 - 0.000101 * T) * sin(dr * 2 * M) + 0.000290 * sin(dr * 3 * M)
	var L := (L0 + DL) * dr
	L = L - PI * 2 * floor(L / (PI * 2))
	return int(floor(L / PI * 6))


## Ngày bắt đầu tháng 11 âm lịch (tháng có đông chí) của năm yy.
static func lunar_month11(yy: int, tz: float) -> int:
	var off := jd_from_date(31, 12, yy) - 2415021
	var k := int(floor(off / 29.530588853))
	var nm := new_moon_day(k, tz)
	if sun_longitude(nm, tz) >= 9:
		nm = new_moon_day(k - 1, tz)
	return nm


static func leap_month_offset(a11: int, tz: float) -> int:
	var k := int(floor((a11 - 2415021.076998695) / 29.530588853 + 0.5))
	var last := 0
	var i := 1
	var arc := sun_longitude(new_moon_day(k + i, tz), tz)
	while true:
		last = arc
		i += 1
		arc = sun_longitude(new_moon_day(k + i, tz), tz)
		if not (arc != last and i < 14):
			break
	return i - 1


static func solar_to_lunar(dd: int, mm: int, yy: int, tz: float) -> Dictionary:
	var day_number := jd_from_date(dd, mm, yy)
	var k := int(floor((day_number - 2415021.076998695) / 29.530588853))
	var month_start := new_moon_day(k + 1, tz)
	if month_start > day_number:
		month_start = new_moon_day(k, tz)
	var a11 := lunar_month11(yy, tz)
	var b11 := a11
	var lunar_year: int
	if a11 >= month_start:
		lunar_year = yy
		a11 = lunar_month11(yy - 1, tz)
	else:
		lunar_year = yy + 1
		b11 = lunar_month11(yy + 1, tz)
	var lunar_day := day_number - month_start + 1
	var diff := int(floor((month_start - a11) / 29.0))
	var leap := false
	var lunar_month := diff + 11
	if b11 - a11 > 365:
		var leap_diff := leap_month_offset(a11, tz)
		if diff >= leap_diff:
			lunar_month = diff + 10
			if diff == leap_diff:
				leap = true
	if lunar_month > 12:
		lunar_month -= 12
	if lunar_month >= 11 and diff < 4:
		lunar_year -= 1
	return {"day": lunar_day, "month": lunar_month, "year": lunar_year, "leap": leap}
