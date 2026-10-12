import bpy, sys, os
argv = sys.argv[sys.argv.index("--") + 1:]
glb, outdir = argv[0], argv[1]
wanted = argv[2].split(",")
os.makedirs(outdir, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scn = bpy.context.scene
scn.render.fps = 30
scn.render.fps_base = 1.0
bpy.ops.import_scene.gltf(filepath=glb)
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
print("ARMATURE", arm.name, "bones", len(arm.data.bones))
print("ACTIONS", [a.name for a in bpy.data.actions])
ad = arm.animation_data or arm.animation_data_create()
for tr in list(ad.nla_tracks):
    ad.nla_tracks.remove(tr)
bpy.context.view_layer.objects.active = arm
for o in bpy.context.selected_objects:
    o.select_set(False)
arm.select_set(True)
for want in wanted:
    acts = [a for a in bpy.data.actions if a.name == want or a.name.startswith(want + "_") or a.name.startswith(want + ".")]
    acts = [a for a in acts if not any(a.name.startswith(w + "_") and w != want and len(w) > len(want) for w in wanted)]
    if not acts:
        print("MISSING", want)
        continue
    act = acts[0]
    ad.action = act
    if hasattr(ad, "action_slot") and len(getattr(act, "slots", [])):
        slot = None
        for s in act.slots:
            if getattr(s, "target_id_type", "OBJECT") == "OBJECT":
                slot = s
                break
        ad.action_slot = slot or act.slots[0]
    fs, fe = act.frame_range
    fs, fe = int(round(fs)), int(round(fe))
    scn.frame_start, scn.frame_end = fs, fe
    out = os.path.join(outdir, want + ".bvh")
    bpy.ops.export_anim.bvh(filepath=out, check_existing=False, global_scale=1.0, frame_start=fs, frame_end=fe,
                            rotate_mode="NATIVE", root_transform_only=False)
    print("EXPORTED", want, act.name, fs, fe, out)
