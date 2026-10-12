"""Prepare a downloaded humanoid model (GLB/GLTF/FBX/OBJ) for Roblox Avatar Setup, headless.

  "C:\\Program Files\\Blender Foundation\\Blender 5.0\\blender.exe" -b -P prep_external_model.py -- \
      --in <model.glb> --out <model-roblox.fbx> [--tris 10500] [--height 1.75]

Steps: rest pose (animation removed), shape keys dropped (Avatar Setup regenerates the face rig), all transforms
applied, triangles decimated to the Avatar Setup budget (10,742 total), model scaled to --height metres with its
feet on the origin, FBX exported with embedded textures. Import in Studio with Scale Unit = Meter (1.75 m is about
6.25 studs) and run Avatar Setup / AutoSetupAvatarAsync. Prints one JSON line with before/after stats.
"""
import argparse
import json
import os
import sys

import bmesh
import bpy
from mathutils import Vector


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="src", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--tris", type=int, default=10500)
    ap.add_argument("--height", type=float, default=1.75)
    return ap.parse_args(argv)


def import_model(path):
    ext = os.path.splitext(path)[1].lower()
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    else:
        raise SystemExit(f"unsupported model type {ext}")


def meshes():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def tri_count(obj):
    deps = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(deps)
    mesh = evaluated.to_mesh()
    count = sum(len(p.vertices) - 2 for p in mesh.polygons)
    evaluated.to_mesh_clear()
    return count


def world_bounds():
    deps = bpy.context.evaluated_depsgraph_get()
    lo = Vector((float("inf"),) * 3)
    hi = Vector((float("-inf"),) * 3)
    for obj in meshes():
        evaluated = obj.evaluated_get(deps)
        mesh = evaluated.to_mesh()
        for v in mesh.vertices:
            p = evaluated.matrix_world @ v.co
            lo = Vector((min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)))
            hi = Vector((max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z)))
        evaluated.to_mesh_clear()
    return lo, hi


def apply_all_transforms():
    bpy.ops.object.select_all(action="SELECT")
    with bpy.context.temp_override(selected_editable_objects=list(bpy.context.scene.objects),
                                   active_object=bpy.context.scene.objects[0]):
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)


def main():
    a = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    import_model(a.src)
    if not meshes():
        raise SystemExit("no mesh objects found in " + a.src)

    for obj in bpy.context.scene.objects:
        if obj.animation_data:
            obj.animation_data.action = None
        if obj.type == "ARMATURE":
            obj.data.pose_position = "REST"
    # Importers (glTF) add helper meshes used only as bone display shapes; they must not be exported or measured.
    helpers = set()
    for obj in bpy.context.scene.objects:
        if obj.type == "ARMATURE":
            for bone in obj.pose.bones:
                if bone.custom_shape:
                    helpers.add(bone.custom_shape)
                    bone.custom_shape = None
    for helper in helpers:
        bpy.data.objects.remove(helper, do_unlink=True)
    for obj in meshes():
        if obj.data.shape_keys:
            obj.shape_key_clear()
        # glTF/FBX imports split vertices along UV seams and hard edges; collapse decimation preserves those open
        # boundaries and stalls. Weld them first (UVs live on face corners, so texturing survives the merge).
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        size = max(obj.dimensions) or 1.0
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=size * 1e-5)
        bm.to_mesh(obj.data)
        bm.free()

    before = sum(tri_count(o) for o in meshes())
    after = before
    # Collapse decimation can stall above the target on dense or seam-heavy meshes, so repeat until within budget.
    for _ in range(5):
        if after <= a.tris:
            break
        ratio = max(0.01, a.tris / after * 0.97)
        for obj in meshes():
            mod = obj.modifiers.new("BudgetDecimate", "DECIMATE")
            mod.ratio = ratio
            # Decimate before the Armature modifier so skin weights are carried onto the reduced mesh.
            while obj.modifiers.find(mod.name) > 0:
                with bpy.context.temp_override(object=obj, active_object=obj):
                    bpy.ops.object.modifier_move_up(modifier=mod.name)
            with bpy.context.temp_override(object=obj, active_object=obj):
                bpy.ops.object.modifier_apply(modifier=mod.name)
        after = sum(tri_count(o) for o in meshes())

    apply_all_transforms()
    lo, hi = world_bounds()
    height = hi.z - lo.z
    if height <= 0:
        raise SystemExit("model has no vertical extent")
    factor = a.height / height
    centre = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    for obj in bpy.context.scene.objects:
        if obj.parent is None:
            obj.location = (obj.location - centre) * factor
            obj.scale = obj.scale * factor
    apply_all_transforms()
    bpy.ops.object.select_all(action="SELECT")
    for obj in bpy.context.scene.objects:
        if obj.parent is None:
            with bpy.context.temp_override(selected_editable_objects=[obj], active_object=obj):
                bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    lo2, hi2 = world_bounds()

    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    bpy.ops.export_scene.fbx(filepath=a.out, use_selection=False, apply_scale_options="FBX_SCALE_UNITS",
                             axis_forward="-Z", axis_up="Y", add_leaf_bones=False, bake_anim=False,
                             path_mode="COPY", embed_textures=True)
    print(json.dumps({
        "in": a.src, "out": a.out, "trisBefore": before, "trisAfter": after, "budget": a.tris,
        "heightMetres": round(hi2.z - lo2.z, 4), "minZ": round(lo2.z, 4),
        "armatures": sum(1 for o in bpy.context.scene.objects if o.type == "ARMATURE"),
        "meshes": len(meshes()), "withinBudget": after <= 10742,
    }))


if __name__ == "__main__":
    main()
