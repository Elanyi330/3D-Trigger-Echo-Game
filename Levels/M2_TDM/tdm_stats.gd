# Levels/M2_TDM/tdm_stats.gd
# TDM 战绩模块（2026-08-13 用户拍板）：每局开始为全部 AI（+玩家）随机分配英文名；
# 记录每人击杀/死亡；结算界面按昵称展示 KD 与 KD 比（死亡 0 次 → 显示 MVP）。
# 纯数据无场景依赖，GUT 直测。
class_name TdmStats
extends RefCounted

const NAME_POOL := [
	"Blaze", "Frost", "Raven", "Viper", "Shadow", "Storm", "Onyx", "Cinder",
	"Wraith", "Nova", "Talon", "Echo", "Drift", "Havoc", "Jinx", "Lynx",
	"Magnus", "Nero", "Odin", "Pyro", "Quill", "Rogue", "Sable", "Titan",
	"Umbra", "Vale", "Wren", "Xenon", "Yarrow", "Zephyr", "Ash", "Bolt",
	"Cobra", "Dune", "Ember", "Flint", "Gale", "Hawk", "Iris", "Jade",
]

var player_name := ""
var records := {}  # name -> {"team": "friendly"/"enemy", "kills": int, "deaths": int}

var _names_used: Array = []
var _rng := RandomNumberGenerator.new()


## 每局开始：重置全部战绩与名字分配
func new_match() -> void:
	player_name = ""
	records.clear()
	_names_used.clear()
	_rng.randomize()


## 从名字池随机取一个未用过的英文名（池内不重复；用尽兜底重复使用）
func make_name() -> String:
	var pool: Array = NAME_POOL.filter(func(n: String) -> bool: return not _names_used.has(n))
	if pool.is_empty():
		pool = NAME_POOL.duplicate()
	var n: String = pool[_rng.randi_range(0, pool.size() - 1)]
	_names_used.append(n)
	return n


func register(team: String, name: String) -> void:
	records[name] = {"team": team, "kills": 0, "deaths": 0}


func add_kill(name: String) -> void:
	if records.has(name):
		records[name]["kills"] = int(records[name]["kills"]) + 1


func add_death(name: String) -> void:
	if records.has(name):
		records[name]["deaths"] = int(records[name]["deaths"]) + 1


## 某阵营花名册（有序）：[{name, kills, deaths, kd_text}]
func roster(team: String) -> Array:
	var out: Array = []
	for n in records:
		var r: Dictionary = records[n]
		if r["team"] == team:
			out.append({
				"name": n,
				"kills": r["kills"],
				"deaths": r["deaths"],
				"kd": kd_text(int(r["kills"]), int(r["deaths"])),
			})
	return out


## KD 比文本：死亡 0 次 → "MVP"（2026-08-13 用户规则）；否则保留两位小数
func kd_text(kills: int, deaths: int) -> String:
	if deaths == 0:
		return "MVP"
	return "%.2f" % (float(kills) / float(deaths))
