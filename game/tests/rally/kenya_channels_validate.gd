extends SceneTree

## Valida el registro de los 7 canales: configure por stage con su GLB,
## huellas, diagnóstico y conteo de activos. Sin colisión (lecho uniforme).

const Channels = preload("res://scripts/rally/rally_river_channels.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var expect := {"kenya_stage1": 1, "kenya_stage2": 2, "kenya_stage3": 2,
		"kenya_stage5": 1, "kenya_stage6": 2, "kenya_stage4": 0}
	for stage in expect:
		var path := "res://assets/rally/%s/%s_visual.glb" % [stage, stage]
		var inst := (load(path) as PackedScene).instantiate()
		root.add_child(inst)
		await process_frame
		var rivers := Channels.new()
		root.add_child(rivers)
		var ok := rivers.configure(stage, inst, null, "random", null)
		var n := rivers.active_channel_count()
		print("VALIDATE ", stage, " ok=", ok, " active=", n,
			" diagnostics=", rivers.diagnostics.size())
		for d in rivers.diagnostics:
			print("  DIAG ", d)
			failures.append(str(stage) + ": " + str(d.get("message", "")))
		if n != int(expect[stage]):
			failures.append("%s: activos=%d, esperados=%d" % [stage, n, int(expect[stage])])
		rivers.unbind()
		rivers.queue_free()
		inst.queue_free()
	print("CHANNELS_VALIDATE ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
