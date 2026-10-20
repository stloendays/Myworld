"""用 Blender 脚本生成 A 字形木屋与门板模型（GLB）。

运行（仓库根目录）：
    blender --background --factory-startup --python devtools/blender/build_cabin.py

输出：
    assets/imported/cabin/cabin_aframe.glb   木屋外壳、屋面、梁架、玻璃窗框、门廊、坡道、铸铁炉、门廊灯
    assets/imported/cabin/door_leaf.glb      正门门板（铰链在原点，沿 +Z 展开）
    assets/source/cabin_aframe.blend         可在 Blender 中继续编辑的源文件

尺寸与 scripts/buildings/Cabin.gd 的碰撞完全一致（Godot 坐标：+X 朝湖，屋脊沿 X，地板顶面 y = 0）。
几何先在 Godot 坐标中构建，最后统一换算到 Blender 的 Z 向上坐标；glTF 导出时再换回 Y 向上。
UV 以米为单位做盒式投影，纹理方向沿构件的长边；Godot 端按材质名（M_*）替换为 PBR 材质。
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "imported", "cabin")
SRC_DIR = os.path.join(ROOT, "assets", "source")

LENGTH = 10.0
HALF_SPAN = 4.4
RIDGE = 7.0
DOOR_HALF = 0.6
DOOR_H = 2.2
DECK_DEPTH = 3.0
GROUND_DROP = 0.4

# Godot (x, y, z) -> Blender (x, -z, y)
G2B = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))

MATERIAL_COLORS = {
    "M_RoofSlate": (0.25, 0.25, 0.27),
    "M_Lining": (0.75, 0.55, 0.35),
    "M_Siding": (0.40, 0.26, 0.16),
    "M_Beam": (0.55, 0.36, 0.22),
    "M_Frame": (0.12, 0.09, 0.07),
    "M_Floor": (0.55, 0.38, 0.24),
    "M_Deck": (0.35, 0.28, 0.22),
    "M_Stone": (0.40, 0.38, 0.35),
    "M_Hearth": (0.25, 0.25, 0.26),
    "M_Glass": (0.60, 0.70, 0.80),
    "M_Metal": (0.05, 0.05, 0.05),
    "M_FireGlow": (1.0, 0.42, 0.10),
    "M_LampGlow": (1.0, 0.78, 0.50),
    "M_Door": (0.45, 0.28, 0.16),
}


class Builder:
    """按材质累积几何；每个材质最终生成一个对象。"""

    def __init__(self, name):
        self.name = name
        self.meshes = {}

    def _target(self, mat):
        if mat not in self.meshes:
            bm = bmesh.new()
            bm.loops.layers.uv.new("UVMap")
            self.meshes[mat] = bm
        return self.meshes[mat]

    def _merge(self, mat, src, matrix):
        dst = self._target(mat)
        uv_dst = dst.loops.layers.uv["UVMap"]
        uv_src = src.loops.layers.uv["UVMap"]
        vmap = {}
        for v in src.verts:
            vmap[v] = dst.verts.new(G2B @ matrix @ v.co)
        for f in src.faces:
            nf = dst.faces.new([vmap[v] for v in f.verts])
            nf.smooth = False
            for ln, lo in zip(nf.loops, f.loops):
                ln[uv_dst].uv = lo[uv_src].uv

    @staticmethod
    def _box_uv(bm, extents, fit=None):
        """米制盒式投影；u 沿面内较长的一边。fit=(轴u, 轴v, 尺寸u, 尺寸v) 时把整张贴图铺满该面。"""
        uv = bm.loops.layers.uv["UVMap"]
        bm.normal_update()
        for f in bm.faces:
            n = f.normal
            axis = max(range(3), key=lambda i: abs(n[i]))
            a, b = [i for i in range(3) if i != axis]
            if extents[b] > extents[a]:
                a, b = b, a
            for loop in f.loops:
                co = loop.vert.co
                if fit is not None and axis == fit[0]:
                    loop[uv].uv = (co[fit[1]] / fit[3] + 0.5, co[fit[2]] / fit[4] + 0.5)
                else:
                    loop[uv].uv = (co[a], co[b])

    def box(self, mat, size, matrix, bevel=0.0, fit=None):
        bm = bmesh.new()
        bm.loops.layers.uv.new("UVMap")
        bmesh.ops.create_cube(bm, size=1.0)
        for v in bm.verts:
            v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        if bevel > 0.0:
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, offset_type="OFFSET",
                            segments=1, profile=0.5, affect="EDGES")
        self._box_uv(bm, size, fit)
        self._merge(mat, bm, matrix)
        bm.free()

    def prism_x(self, mat, poly, x_center, thickness):
        """(z, y) 平面上的凸多边形，沿 X 挤出。"""
        bm = bmesh.new()
        bm.loops.layers.uv.new("UVMap")
        x0, x1 = x_center - thickness / 2, x_center + thickness / 2
        front = [bm.verts.new((x1, p[1], p[0])) for p in poly]
        back = [bm.verts.new((x0, p[1], p[0])) for p in poly]
        bm.faces.new(front)
        bm.faces.new(list(reversed(back)))
        n = len(poly)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new([front[i], back[i], back[j], front[j]])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        zs = [p[0] for p in poly]
        ys = [p[1] for p in poly]
        self._box_uv(bm, (thickness, max(ys) - min(ys), max(zs) - min(zs)))
        self._merge(mat, bm, Matrix.Identity(4))
        bm.free()

    def cylinder(self, mat, radius, height, center, segments=14, radius_top=None):
        bm = bmesh.new()
        bm.loops.layers.uv.new("UVMap")
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                              radius1=radius, radius2=radius if radius_top is None else radius_top,
                              depth=height, matrix=Matrix.Rotation(-math.pi / 2, 4, "X"))
        self._box_uv(bm, (radius * 2, height, radius * 2))
        self._merge(mat, bm, Matrix.Translation(center))
        bm.free()

    def build_objects(self, collection):
        objs = []
        for mat, bm in self.meshes.items():
            mesh = bpy.data.meshes.new(f"{self.name}_{mat}")
            bm.normal_update()
            bm.to_mesh(mesh)
            bm.free()
            mesh.materials.append(material(mat))
            obj = bpy.data.objects.new(f"{self.name}_{mat}", mesh)
            collection.objects.link(obj)
            objs.append(obj)
        return objs


_materials = {}


def material(name):
    if name in _materials:
        return _materials[name]
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except AttributeError:
        pass
    color = MATERIAL_COLORS.get(name, (0.8, 0.8, 0.8))
    if m.node_tree is not None:
        for node in m.node_tree.nodes:
            if node.type == "BSDF_PRINCIPLED":
                node.inputs["Base Color"].default_value = (*color, 1.0)
    m.diffuse_color = (*color, 1.0)
    _materials[name] = m
    return m


def at(pos, basis=None):
    m = Matrix.Translation(Vector(pos))
    if basis is not None:
        m = m @ basis.to_4x4()
    return m


def slab_basis(side):
    """屋面坐标系：x 沿屋脊，y 从屋檐指向屋脊，z 指向屋外。side = -1（-Z 一侧）或 +1。"""
    eave = Vector((0.0, 0.0, side * HALF_SPAN))
    ridge = Vector((0.0, RIDGE, 0.0))
    up = (ridge - eave).normalized()
    x = Vector((side, 0.0, 0.0))
    out = x.cross(up)
    basis = Matrix((x, up, out)).transposed()
    return basis, (eave + ridge) / 2, up, out


def roof_height_at(z):
    return RIDGE * (1.0 - abs(z) / HALF_SPAN)


def build_cabin(b):
    slope_len = math.hypot(HALF_SPAN, RIDGE)

    # 地板与石基
    b.box("M_Floor", (LENGTH, 0.3, HALF_SPAN * 2), at((0, -0.15, 0)))
    b.box("M_Stone", (LENGTH + 0.2, 1.25, HALF_SPAN * 2 + 0.2), at((0, -0.925, 0)), bevel=0.03)

    # 屋面：内衬板、椽子、石板瓦逐行叠铺、封檐板
    eave_overhang = 0.45
    gable_overhang = 0.4
    courses = 17
    for side in (-1, 1):
        basis, mid, up, out = slab_basis(side)
        b.box("M_Lining", (LENGTH + 0.1, slope_len, 0.05), at(mid + out * 0.025, basis))
        b.box("M_Beam", (LENGTH + 2 * gable_overhang, slope_len + eave_overhang, 0.12),
              at(mid + out * 0.11 - up * eave_overhang / 2, basis))
        for x in (-4.6, -2.3, 0.0, 2.3, 4.6):
            b.box("M_Beam", (0.16, slope_len - 0.15, 0.22), at(mid - out * 0.11 + Vector((x, 0, 0)), basis), bevel=0.015)
        total = slope_len + eave_overhang + 0.1
        step = total / courses
        tilt = Matrix.Rotation(math.radians(-3.0), 3, "X")
        for k in range(courses):
            s = -slope_len / 2 - eave_overhang + (k + 0.5) * step
            centre = mid + up * s + out * (0.19 + 0.012 * (k % 2))
            b.box("M_RoofSlate", (LENGTH + 2 * gable_overhang + 0.04, step + 0.1, 0.04), at(centre, basis @ tilt))
        for gx in (-(LENGTH / 2 + gable_overhang), LENGTH / 2 + gable_overhang):
            b.box("M_Frame", (0.06, total, 0.34), at(mid + out * 0.15 - up * eave_overhang / 2 + Vector((gx, 0, 0)), basis))
    # 屋脊盖板
    for side in (-1, 1):
        basis, mid, up, out = slab_basis(side)
        b.box("M_Frame", (LENGTH + 2 * gable_overhang + 0.06, 0.32, 0.05), at(Vector((0, RIDGE, 0)) - up * 0.12 + out * 0.24, basis))

    # 系梁与屋脊梁（室内）
    for x in (-2.3, 0.0, 2.3):
        w = 2 * HALF_SPAN * (1 - 4.3 / RIDGE)
        b.box("M_Beam", (0.14, 0.2, w), at((x, 4.3, 0)), bevel=0.012)
    b.box("M_Beam", (LENGTH, 0.24, 0.2), at((0, RIDGE - 0.35, 0)), bevel=0.015)

    # 正立面：三块玻璃 + 窗框
    fx = LENGTH / 2
    y_edge = roof_height_at(DOOR_HALF)
    b.prism_x("M_Glass", [(-HALF_SPAN, 0.0), (-DOOR_HALF, 0.0), (-DOOR_HALF, y_edge)], fx, 0.03)
    b.prism_x("M_Glass", [(DOOR_HALF, 0.0), (HALF_SPAN, 0.0), (DOOR_HALF, y_edge)], fx, 0.03)
    b.prism_x("M_Glass", [(-DOOR_HALF, DOOR_H), (DOOR_HALF, DOOR_H), (DOOR_HALF, y_edge), (0.0, RIDGE), (-DOOR_HALF, y_edge)], fx, 0.03)
    for z in (-(DOOR_HALF + 0.06), DOOR_HALF + 0.06):
        b.box("M_Frame", (0.16, y_edge, 0.12), at((fx, y_edge / 2, z)), bevel=0.01)
    for z in (-2.4, 2.4):
        h = roof_height_at(z)
        b.box("M_Frame", (0.14, h, 0.1), at((fx, h / 2, z)), bevel=0.01)
    for y in (DOOR_H + 0.05, 4.5):
        w = 2 * HALF_SPAN * (1 - y / RIDGE)
        b.box("M_Frame", (0.14, 0.12, w), at((fx, y, 0)), bevel=0.01)
    b.box("M_Frame", (0.2, 0.1, HALF_SPAN * 2), at((fx, 0.05, 0)))
    # 三角窗沿屋面斜边的窗框
    for side in (-1, 1):
        edge_len = math.hypot(HALF_SPAN, RIDGE)
        ang = math.atan2(HALF_SPAN, RIDGE) * (-side)
        b.box("M_Frame", (0.14, edge_len, 0.12), at((fx, RIDGE / 2, side * HALF_SPAN / 2), Matrix.Rotation(ang, 3, "X")))

    # 背立面：外侧竖向护墙板 + 内侧墙板
    back = [(-HALF_SPAN, 0.0), (HALF_SPAN, 0.0), (0.0, RIDGE)]
    b.prism_x("M_Siding", back, -LENGTH / 2 - 0.05, 0.08)
    b.prism_x("M_Lining", back, -LENGTH / 2 + 0.04, 0.08)
    # 背立面小窗（装饰）
    b.box("M_Frame", (0.12, 1.0, 1.0), at((-LENGTH / 2 - 0.1, 3.3, 0)), bevel=0.01)
    b.box("M_Glass", (0.02, 0.8, 0.8), at((-LENGTH / 2 - 0.16, 3.3, 0)))

    # 门廊：逐块木板 + 龙骨 + 石基
    x0 = LENGTH / 2
    board = 0.14
    gap = 0.012
    n = int(DECK_DEPTH / (board + gap))
    for i in range(n):
        x = x0 + (i + 0.5) * (board + gap)
        b.box("M_Deck", (board, 0.05, 6.0), at((x, -0.025, 0)), bevel=0.006)
    for z in (-2.8, 0.0, 2.8):
        b.box("M_Beam", (DECK_DEPTH, 0.18, 0.12), at((x0 + DECK_DEPTH / 2, -0.14, z)))
    b.box("M_Stone", (DECK_DEPTH, 0.8, 6.0), at((x0 + DECK_DEPTH / 2, -0.65, 0)), bevel=0.03)
    # 坡道（与 Cabin.gd 的坡道碰撞同一几何）
    run = 3.6
    drop = GROUND_DROP + 0.12
    angle = math.atan2(drop, run)
    rot = Matrix.Rotation(-angle, 3, "Z")
    along = rot @ Vector((1, 0, 0))
    start = Vector((x0 + DECK_DEPTH, 0.0, 0.0))
    length = math.hypot(run, drop)
    count = int(length / (board + gap))
    for i in range(count):
        c = start + along * ((i + 0.5) * (board + gap)) + (rot @ Vector((0, -0.025, 0)))
        b.box("M_Deck", (board, 0.05, 2.2), at(c, rot), bevel=0.006)
    for z in (-1.0, 1.0):
        b.box("M_Beam", (length, 0.16, 0.1), at(start + along * (length / 2) + rot @ Vector((0, -0.13, z)), rot))

    # 门框（门洞两侧与上方的门套）
    b.box("M_Frame", (0.18, 0.14, DOOR_HALF * 2 + 0.24), at((fx, DOOR_H + 0.07, 0)), bevel=0.01)

    # 门廊灯
    b.box("M_Beam", (0.12, 2.6, 0.12), at((x0 + 0.15, 1.3, 1.25)), bevel=0.01)
    b.box("M_Metal", (0.22, 0.04, 0.22), at((x0 + 0.3, 2.6, 1.25)))
    b.box("M_LampGlow", (0.16, 0.24, 0.16), at((x0 + 0.3, 2.45, 1.25)))
    b.box("M_Metal", (0.2, 0.03, 0.2), at((x0 + 0.3, 2.32, 1.25)))

    # 铸铁炉、烟囱、炉台
    s = Vector((-3.9, 0.0, -1.0))
    b.box("M_Hearth", (1.5, 0.05, 1.3), at(s + Vector((0.1, 0.025, 0))), bevel=0.01)
    for dx in (-0.25, 0.25):
        for dz in (-0.2, 0.2):
            b.box("M_Metal", (0.06, 0.22, 0.06), at(s + Vector((dx, 0.16, dz))))
    b.box("M_Metal", (0.7, 0.72, 0.56), at(s + Vector((0, 0.63, 0))), bevel=0.03)
    b.box("M_Metal", (0.76, 0.05, 0.62), at(s + Vector((0, 1.01, 0))), bevel=0.01)
    b.box("M_FireGlow", (0.02, 0.32, 0.4), at(s + Vector((0.36, 0.62, 0))))
    b.box("M_Metal", (0.04, 0.42, 0.5), at(s + Vector((0.355, 0.62, 0))))
    b.cylinder("M_Metal", 0.09, 6.3, s + Vector((0, 1.03 + 3.15, 0)))
    b.cylinder("M_Metal", 0.16, 0.12, s + Vector((0, 7.4, 0)))


def build_door(b):
    w, h, t = 1.18, 2.18, 0.06
    # 门板两面把整张门板贴图铺满一次（轴 0 = X 面，u 沿 Z，v 沿 Y）
    b.box("M_Door", (t, h, w), at((0, h / 2 + 0.01, w / 2)), bevel=0.004, fit=(0, 2, 1, w, h))
    for x in (-0.06, 0.06):
        b.box("M_Metal", (0.03, 0.04, 0.16), at((x, 1.05, w - 0.16)))
        b.box("M_Metal", (0.03, 0.12, 0.03), at((x, 1.05, w - 0.1)))


def export(objs, path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(SRC_DIR, exist_ok=True)
    scene_col = bpy.context.scene.collection
    cabin_col = bpy.data.collections.new("Cabin")
    door_col = bpy.data.collections.new("DoorLeaf")
    scene_col.children.link(cabin_col)
    scene_col.children.link(door_col)

    cabin = Builder("Cabin")
    build_cabin(cabin)
    cabin_objs = cabin.build_objects(cabin_col)
    door = Builder("Door")
    build_door(door)
    door_objs = door.build_objects(door_col)

    export(cabin_objs, os.path.join(OUT_DIR, "cabin_aframe.glb"))
    export(door_objs, os.path.join(OUT_DIR, "door_leaf.glb"))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC_DIR, "cabin_aframe.blend"))
    tris = sum(len(o.data.polygons) for o in cabin_objs)
    print(f"CABIN_OK objects={len(cabin_objs)} faces={tris} door_objects={len(door_objs)}")


main()
