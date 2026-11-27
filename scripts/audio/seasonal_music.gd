extends AudioStreamPlayer

const TRACKS: Array[AudioStreamOggVorbis] = [
	preload("res://assets/music/spring.ogg"),
	preload("res://assets/music/summer.ogg"),
	preload("res://assets/music/autumn.ogg"),
	preload("res://assets/music/winter.ogg"),
]
const Seasons = preload("res://scripts/core/seasons.gd")
const BUS := &"RestaurantMusic"
const PREFERENCES := "user://canyon_music.cfg"
var muted := false
var bus_index := -1
const BEAT_SECONDS := 60.0 / 84.0
const LEVEL_DB := -6.0

var season := -1
var mix := AudioStreamSynchronized.new()
var transition: Tween

func _ready() -> void:
	bus_index = AudioServer.get_bus_index(BUS)
	if bus_index < 0:
		AudioServer.add_bus()
		bus_index = AudioServer.bus_count-1
		AudioServer.set_bus_name(bus_index,BUS)
	bus = BUS
	var preferences := ConfigFile.new()
	if "--ui-test" not in OS.get_cmdline_user_args() and preferences.load(PREFERENCES) == OK:
		muted = bool(preferences.get_value("music","muted",false))
	AudioServer.set_bus_mute(bus_index,muted)
	playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	mix.stream_count = TRACKS.size()
	for i in TRACKS.size():
		mix.set_sync_stream(i, TRACKS[i])
		mix.set_sync_stream_volume(i, -INF)
	stream = mix

func set_day(day: int) -> void:
	var next := Seasons.at_day(day)
	if next == season: return
	season = next
	if not playing:
		mix.set_sync_stream_volume(season, 0.0)
		volume_linear = 0.0
		play()
		create_tween().tween_property(self, "volume_linear", db_to_linear(LEVEL_DB), 0.25)
		return

	# All arrangements share a sample clock. Retarget from the audible blend
	# if chapter selection or a restart interrupts a previous transition.
	if transition: transition.kill()
	transition = create_tween()
	var power := PackedFloat32Array()
	for i in TRACKS.size():
		power.append(db_to_linear(mix.get_sync_stream_volume(i)) ** 2)
	var position := get_playback_position() + AudioServer.get_time_since_last_mix()
	transition.tween_interval(fposmod(-position, BEAT_SECONDS))
	transition.tween_method(_blend.bind(power, next), 0.0, 1.0, 2.0 * BEAT_SECONDS)

func _blend(progress: float, from_power: PackedFloat32Array, target: int) -> void:
	var weight := smoothstep(0.0, 1.0, progress)
	for i in TRACKS.size():
		var power := lerpf(from_power[i], 1.0 if i == target else 0.0, weight)
		mix.set_sync_stream_volume(i, linear_to_db(sqrt(power)))

func set_muted(value: bool) -> void:
	muted = value
	AudioServer.set_bus_mute(bus_index,value)
	if "--ui-test" not in OS.get_cmdline_user_args():
		var preferences := ConfigFile.new()
		preferences.set_value("music","muted",value)
		preferences.save(PREFERENCES)

func _exit_tree() -> void:
	if transition != null: transition.kill()
	stop()
