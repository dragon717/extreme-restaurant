extends SceneTree

const Sim = preload("res://scripts/core/simulation.gd")
const Store = preload("res://scripts/core/save_store.gd")
const FIXTURE = "res://tests/fixtures/gallery_v7.json"
var passed := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error(label)

func _initialize() -> void:
	var old := Store.read_checkpoint(FIXTURE)
	var migrated := Sim.new()
	var original := old.duplicate(true)
	check(migrated.restore_state(old).ok, "可载入原版 v7 实际导出的展廊存档")
	check(old == original, "迁移保留读取的旧数据")
	check(migrated.gold == old.gold and migrated.stars == old.stars and migrated.day == old.day, "保留金币、闪星与日期")
	check(migrated.helper_staff == old.helper_staff and migrated.crew_lineup == old.crew_lineup, "保留当班人员")
	check(migrated.owned_relics == old.owned_relics and migrated.legacy_trophies == ["ember_cup"], "区分旧商店奖杯与地块赠品")
	var offer := migrated.trophy_box_offer()
	check(migrated.trophy_draws_total == 0 and offer.gold == 220, "旧支出不计入金币盲盒")
	for tier in offer.pools:
		check("bronze_clock" not in tier and "ember_cup" not in tier, "新奖池排除继承奖杯")
	var saved := migrated.export_state()
	var replay := Sim.new()
	check(replay.restore_state(saved).ok, "新格式可再次读取")
	var reward := migrated.draw_trophy()
	check(reward.ok and replay.draw_trophy() == reward and replay.export_state() == migrated.export_state(), "旧档后首次开箱可复现且只扣一次")
	check(migrated.gold == old.gold-220 and migrated.stars == old.stars and migrated.trophy_box_offer().gold == 365, "只扣金币且下次按第二箱报价")
	var report := original.duplicate(true)
	report.merge(Store.read_checkpoint("res://tests/fixtures/gallery_v7_report_delta.json"),true)
	check(replay.restore_state(report).ok and replay.phase == "REPORT" and replay.last_report == report.last_report, "旧版打烊日报可直接继续")
	check(replay.gold == report.gold and replay.stars == report.stars and replay.crew_lineup.size()==5, "恢复日报不会再结算，保留五人阵容")
	var invalid := original.duplicate(true)
	invalid.trophy_shop = []
	check(not replay.restore_state(invalid).ok, "损坏旧记录不能进入迁移")
	var prefix := "user://gallery-migration-" + Crypto.new().generate_random_bytes(5).hex_encode() + ".json"
	DirAccess.copy_absolute(ProjectSettings.globalize_path(FIXTURE), ProjectSettings.globalize_path(prefix+".bak"))
	check(Store.archive_v7(prefix, Store.read_checkpoint(prefix)).is_empty(), "从恢复用的备份取得旧档原件")
	check(FileAccess.get_file_as_bytes(prefix+".v7.bak") == FileAccess.get_file_as_bytes(FIXTURE), "v7 副本逐字节一致")
	check(Store.write_checkpoint(migrated.export_state(),prefix).is_empty() and Store.archive_v7(prefix, old).is_empty(), "再次保存保留首次归档")
	for suffix in ["",".bak",".v7.bak"]:
		if FileAccess.file_exists(prefix+suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(prefix+suffix))
	print("GALLERY MIGRATION: %d passed / %d failed" % [passed, failed])
	quit(1 if failed else 0)
