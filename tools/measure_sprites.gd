extends SceneTree
## Dev tool: dump every registry sprite's IMPORTED size + opaque alpha bbox +
## SCALE, so import-cap drift is measurable instead of guessed at.
##   godot --headless --path . -s res://tools/measure_sprites.gd

const Art := preload("res://src/view/art.gd")


func _init() -> void:
	var keys := Art.TEX.keys()
	keys.sort()
	print("key,imp_w,imp_h,bbox_w,bbox_h,scale,drawn_w,drawn_h")
	for k in keys:
		var t: Texture2D = Art.TEX[k]
		var img := t.get_image()
		var sz := img.get_size()
		var x0 := sz.x
		var y0 := sz.y
		var x1 := -1
		var y1 := -1
		for y in sz.y:
			for x in sz.x:
				if img.get_pixel(x, y).a > 0.35:
					x0 = mini(x0, x)
					y0 = mini(y0, y)
					x1 = maxi(x1, x)
					y1 = maxi(y1, y)
		var bw := 0 if x1 < 0 else x1 - x0 + 1
		var bh := 0 if y1 < 0 else y1 - y0 + 1
		var s: float = Art.draw_scale(k)
		print("%s,%d,%d,%d,%d,%.3f,%.1f,%.1f" % [k, sz.x, sz.y, bw, bh, s, bw * s, bh * s])
	# Ready-to-paste SPRITE_CANVAS rows for tests/test_view_honesty.gd.
	print("--- SPRITE_CANVAS ---")
	var sk := Art.SCALE.keys()
	sk.sort()
	var line := ""
	for i in sk.size():
		var t2: Texture2D = Art.TEX[sk[i]]
		var m := maxi(int(t2.get_size().x), int(t2.get_size().y))
		line += '"%s": %d, ' % [sk[i], m]
		if line.length() > 88:
			print("\t" + line.strip_edges())
			line = ""
	if line != "":
		print("\t" + line.strip_edges())
	quit()
