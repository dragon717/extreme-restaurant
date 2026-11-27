extends SceneTree

const Music = preload("res://scripts/audio/seasonal_music.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var music := Music.new()
	root.add_child(music)
	for track in Music.TRACKS:
		check(track.loop and track.beat_count == 144 and track.bpm == 84, "循环拍数与节拍一致")
		var playback := track.instantiate_playback()
		playback.start(track.get_length() - 0.2)
		var frames := playback.mix_audio(1.0, int(AudioServer.get_mix_rate() * 0.4))
		check(playback.get_loop_count() == 1 and playback.is_playing(), "解码器实际跨过尾首")
		# Check every 20 ms around the join, including both sides of it.
		var window := int(AudioServer.get_mix_rate() * 0.02)
		for at in range(window, frames.size() - window, window):
			var energy := 0.0
			for j in range(at, at + window):
				energy += frames[j].length_squared()
			check(energy / window > 0.000001, "循环接点有声音")
		playback.stop()

	music.set_day(7)
	check(music.season == 0, "第七天仍是春季")
	var clock := music.get_stream_playback()
	for boundary in [[8, 1], [15, 2], [22, 3], [29, 0]]:
		var day: int = boundary[0]
		music.set_day(day)
		check(music.season == boundary[1], "第 %d 天进入对应季节" % day)
		var fade := music.transition
		music.set_day(day + 1)
		check(music.transition == fade and music.get_stream_playback() == clock, "同季跨日保留播放头")
		fade.custom_step(3.0)
		for i in Music.TRACKS.size():
			var gain := db_to_linear(music.mix.get_sync_stream_volume(i))
			check(is_equal_approx(gain, 1.0 if i == music.season else 0.0), "交接完成后仅当季可闻")
	music.set_day(8)
	music.transition.custom_step(1.0)
	music.set_day(22)
	music.transition.custom_step(3.0)
	check(music.season == 3 and is_zero_approx(music.mix.get_sync_stream_volume(3)), "快速重选以最后的季节为准")
	music.set_muted(true)
	check(AudioServer.is_bus_mute(music.bus_index) and music.get_stream_playback() == clock, "关闭音乐保留播放头")
	music.set_muted(false)
	check(not AudioServer.is_bus_mute(music.bus_index),"恢复音乐不会改变营业或环境音")
	music.stop()
	music.queue_free()
	await create_timer(1.0).timeout
	print("Seasonal music failures: ", failures)
	quit(1 if failures else 0)
