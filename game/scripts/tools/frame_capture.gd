class_name FrameCapture
extends Node

# Dev helper: `-- --shot out.png [--after 6.0]` saves one frame and quits.
# Attached by scenes that want to be inspectable from the command line.

const SHOT_ARG := "--shot"
const DELAY_ARG := "--after"


static func attach(host: Node) -> void:
	var path := argument(SHOT_ARG)
	if path.is_empty():
		return
	var capture := FrameCapture.new()
	capture.name = "FrameCapture"
	host.add_child(capture)


static func argument(flag: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == flag and i + 1 < args.size():
			return args[i + 1]
	return ""


static func has_flag(flag: String) -> bool:
	return OS.get_cmdline_user_args().has(flag)


func _ready() -> void:
	_run()


func _run() -> void:
	var path := argument(SHOT_ARG)
	var delay := float(argument(DELAY_ARG)) if not argument(DELAY_ARG).is_empty() else 0.6
	# Let the court viewport bake and the sim settle before grabbing a frame.
	await get_tree().create_timer(maxf(delay, 0.1)).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	if err != OK:
		push_error("Screenshot failed: %s" % error_string(err))
	get_tree().quit(0 if err == OK else 1)
