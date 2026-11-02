"""Merge the supplied GLBs without rebuilding their skinned meshes.

This keeps the original skin and inverse-bind data intact. Blender can render
the supplied rigs, but re-exporting them changes their bind transforms.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import struct


JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942


def read_glb(path: str) -> tuple[dict, bytes]:
    data = open(path, "rb").read()
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2 or length != len(data):
        raise ValueError(f"Not a valid GLB 2 file: {path}")
    cursor = 12
    document = None
    binary = b""
    while cursor < len(data):
        chunk_length, chunk_type = struct.unpack_from("<II", data, cursor)
        cursor += 8
        chunk = data[cursor:cursor + chunk_length]
        cursor += chunk_length
        if chunk_type == JSON_CHUNK:
            document = json.loads(chunk.decode("utf-8").rstrip(" \t\r\n\0"))
        elif chunk_type == BIN_CHUNK:
            binary = chunk
    if document is None:
        raise ValueError(f"GLB has no JSON chunk: {path}")
    if document.get("animations"):
        raise ValueError(f"Expected a model with no animations: {path}")
    return document, binary


def remap_texture_indices(value, texture_base: int) -> None:
    if isinstance(value, dict):
        for key, child in list(value.items()):
            if key == "index" and isinstance(child, int):
                value[key] = child + texture_base
            else:
                remap_texture_indices(child, texture_base)
    elif isinstance(value, list):
        for child in value:
            remap_texture_indices(child, texture_base)


def matrix_to_trs(matrix: list[float]):
    # glTF matrices are column-major. The rigged source nodes use translation
    # matrices; this also handles a harmless rotated/scaled source joint.
    columns = [
        [matrix[column * 4 + row] for row in range(3)]
        for column in range(3)
    ]
    scales = [math.sqrt(sum(value * value for value in column)) for column in columns]
    scales = [value or 1.0 for value in scales]
    rotation = [[columns[col][row] / scales[col] for col in range(3)] for row in range(3)]
    trace = rotation[0][0] + rotation[1][1] + rotation[2][2]
    if trace > 0:
        s = math.sqrt(trace + 1.0) * 2
        q = ((rotation[2][1] - rotation[1][2]) / s,
             (rotation[0][2] - rotation[2][0]) / s,
             (rotation[1][0] - rotation[0][1]) / s, 0.25 * s)
    elif rotation[0][0] > rotation[1][1] and rotation[0][0] > rotation[2][2]:
        s = math.sqrt(1.0 + rotation[0][0] - rotation[1][1] - rotation[2][2]) * 2
        q = (0.25 * s, (rotation[0][1] + rotation[1][0]) / s,
             (rotation[0][2] + rotation[2][0]) / s,
             (rotation[2][1] - rotation[1][2]) / s)
    elif rotation[1][1] > rotation[2][2]:
        s = math.sqrt(1.0 + rotation[1][1] - rotation[0][0] - rotation[2][2]) * 2
        q = ((rotation[0][1] + rotation[1][0]) / s, 0.25 * s,
             (rotation[1][2] + rotation[2][1]) / s,
             (rotation[0][2] - rotation[2][0]) / s)
    else:
        s = math.sqrt(1.0 + rotation[2][2] - rotation[0][0] - rotation[1][1]) * 2
        q = ((rotation[0][2] + rotation[2][0]) / s,
             (rotation[1][2] + rotation[2][1]) / s, 0.25 * s,
             (rotation[1][0] - rotation[0][1]) / s)
    return [matrix[12], matrix[13], matrix[14]], list(q), scales


def quaternion(axis: str, angle: float) -> list[float]:
    value = math.sin(angle / 2.0)
    if axis == "x":
        return [value, 0.0, 0.0, math.cos(angle / 2.0)]
    if axis == "y":
        return [0.0, value, 0.0, math.cos(angle / 2.0)]
    return [0.0, 0.0, value, math.cos(angle / 2.0)]


def add_court_animations(result: dict, packed: bytearray, actor_nodes: dict[str, dict[str, int]]):
    frames = [0.0, 0.32, 0.64, 0.96, 1.28]
    while len(packed) % 4:
        packed.append(0)
    input_view = len(result["bufferViews"])
    time_bytes = struct.pack("<5f", *frames)
    result["bufferViews"].append({"buffer": 0, "byteOffset": len(packed), "byteLength": len(time_bytes)})
    packed.extend(time_bytes)
    input_accessor = len(result["accessors"])
    result["accessors"].append({
        "bufferView": input_view, "componentType": 5126, "count": len(frames),
        "type": "SCALAR", "min": [frames[0]], "max": [frames[-1]],
    })

    tracks = {
        "Idle": {"girl": {}, "boy": {}, "judge": {}},
        "Claimant_Talk": {"girl": {"LeftArm": ("z", [-0.72, -0.28, -0.66, -0.33, -0.72]),
                                     "LeftForeArm": ("y", [0.18, -0.16, 0.08, -0.12, 0.18])}},
        "Respondent_Talk": {"boy": {"RightArm": ("z", [0.72, 0.28, 0.66, 0.33, 0.72]),
                                      "RightForeArm": ("y", [-0.18, 0.16, -0.08, 0.12, -0.18])}},
        "Judge_Talk": {"judge": {"RightArm": ("z", [0.72, 0.38, 0.55, 0.30, 0.72]),
                                  "RightForeArm": ("y", [-0.18, 0.20, -0.08, 0.16, -0.18])}},
    }
    idle_sway = [-0.72, -0.68, -0.72, -0.76, -0.72]
    for role in tracks["Idle"]:
        tracks["Idle"][role] = {
            "LeftArm": ("z", idle_sway),
            "RightArm": ("z", [0.72, 0.76, 0.72, 0.68, 0.72]),
            "LeftForeArm": ("y", [0.18] * len(frames)),
            "RightForeArm": ("y", [-0.18] * len(frames)),
        }

    # Talk clips keep every non-speaker at a calm lowered-arm pose.
    calm = {
        "LeftArm": ("z", [-0.72] * len(frames)),
        "RightArm": ("z", [0.72] * len(frames)),
        "LeftForeArm": ("y", [0.18] * len(frames)),
        "RightForeArm": ("y", [-0.18] * len(frames)),
    }
    for clip in ("Claimant_Talk", "Respondent_Talk", "Judge_Talk"):
        active_role = next(iter(tracks[clip]))
        for role in ("girl", "boy", "judge"):
            if role != active_role:
                tracks[clip][role] = calm

    animations = []
    for clip_name, roles in tracks.items():
        samplers = []
        channels = []
        for role, tracks_for_role in roles.items():
            for bone_name, (axis, angles) in tracks_for_role.items():
                node_index = actor_nodes[role].get(bone_name)
                if node_index is None:
                    raise ValueError(f"Missing {bone_name} in {role} rig")
                source_node = result["nodes"][node_index]
                if "matrix" in source_node:
                    translation, rotation, scale = matrix_to_trs(source_node.pop("matrix"))
                    source_node["translation"] = translation
                    source_node["rotation"] = rotation
                    if any(abs(value - 1.0) > 1e-6 for value in scale):
                        source_node["scale"] = scale
                while len(packed) % 4:
                    packed.append(0)
                output_view = len(result["bufferViews"])
                rotations = [quaternion(axis, angle) for angle in angles]
                output_bytes = struct.pack("<" + "f" * (len(rotations) * 4),
                                           *(value for row in rotations for value in row))
                result["bufferViews"].append({
                    "buffer": 0, "byteOffset": len(packed), "byteLength": len(output_bytes)
                })
                packed.extend(output_bytes)
                output_accessor = len(result["accessors"])
                result["accessors"].append({
                    "bufferView": output_view, "componentType": 5126,
                    "count": len(rotations), "type": "VEC4",
                })
                sampler_index = len(samplers)
                samplers.append({"input": input_accessor, "output": output_accessor, "interpolation": "LINEAR"})
                channels.append({"sampler": sampler_index,
                                 "target": {"node": node_index, "path": "rotation"}})
        animations.append({"name": clip_name, "samplers": samplers, "channels": channels})
    result["animations"] = animations


def merge(parts: list[tuple[str, str, tuple[float, float, float], float, float]], output: str):
    result = {
        "asset": {"version": "2.0", "generator": "Closer Court GLB scene assembler"},
        "nodes": [], "meshes": [], "skins": [], "materials": [], "textures": [],
        "images": [], "samplers": [], "accessors": [], "bufferViews": [],
        "buffers": [], "scenes": [], "scene": 0,
        "extensionsUsed": [], "extensionsRequired": [],
    }
    packed = bytearray()
    wrapper_nodes = []
    actor_nodes: dict[str, dict[str, int]] = {}

    for role, path, translation, yaw, uniform_scale in parts:
        doc, binary = read_glb(path)
        bases = {name: len(result.get(name, [])) for name in (
            "nodes", "meshes", "skins", "materials", "textures", "images",
            "samplers", "accessors", "bufferViews", "animations", "cameras",
        )}
        binary_base = (len(packed) + 3) & ~3
        packed.extend(b"\0" * (binary_base - len(packed)))
        packed.extend(binary)

        for view in doc.get("bufferViews", []):
            view["buffer"] = 0
            view["byteOffset"] = view.get("byteOffset", 0) + binary_base
        for accessor in doc.get("accessors", []):
            if "bufferView" in accessor:
                accessor["bufferView"] += bases["bufferViews"]
            sparse = accessor.get("sparse")
            if sparse:
                sparse["indices"]["bufferView"] += bases["bufferViews"]
                sparse["values"]["bufferView"] += bases["bufferViews"]
        for image in doc.get("images", []):
            if "bufferView" in image:
                image["bufferView"] += bases["bufferViews"]
        for texture in doc.get("textures", []):
            if "source" in texture:
                texture["source"] += bases["images"]
            if "sampler" in texture:
                texture["sampler"] += bases["samplers"]
            for extension in texture.get("extensions", {}).values():
                if "source" in extension:
                    extension["source"] += bases["images"]
        for material in doc.get("materials", []):
            remap_texture_indices(material, bases["textures"])
        for mesh in doc.get("meshes", []):
            for primitive in mesh.get("primitives", []):
                if "indices" in primitive:
                    primitive["indices"] += bases["accessors"]
                if "material" in primitive:
                    primitive["material"] += bases["materials"]
                for key in primitive.get("attributes", {}):
                    primitive["attributes"][key] += bases["accessors"]
                for target in primitive.get("targets", []):
                    for key in target:
                        target[key] += bases["accessors"]
        for skin in doc.get("skins", []):
            skin["joints"] = [item + bases["nodes"] for item in skin["joints"]]
            if "skeleton" in skin:
                skin["skeleton"] += bases["nodes"]
            if "inverseBindMatrices" in skin:
                skin["inverseBindMatrices"] += bases["accessors"]
        for node in doc.get("nodes", []):
            if "children" in node:
                node["children"] = [item + bases["nodes"] for item in node["children"]]
            if "mesh" in node:
                node["mesh"] += bases["meshes"]
            if "skin" in node:
                node["skin"] += bases["skins"]
            if "camera" in node:
                node["camera"] += bases["cameras"]
        for scene in doc.get("scenes", []):
            scene["nodes"] = [item + bases["nodes"] for item in scene.get("nodes", [])]

        for key in ("nodes", "meshes", "skins", "materials", "textures", "images",
                    "samplers", "accessors", "bufferViews", "animations", "cameras"):
            if key in doc:
                result.setdefault(key, []).extend(doc[key])
        if role in ("claimant", "respondent", "judge"):
            bone_names = {"LeftArm", "RightArm", "LeftForeArm", "RightForeArm"}
            actor_key = {"claimant": "girl", "respondent": "boy", "judge": "judge"}[role]
            actor_nodes[actor_key] = {
                node["name"]: bases["nodes"] + index
                for index, node in enumerate(doc.get("nodes", []))
                if node.get("name") in bone_names
            }
        for key in ("extensionsUsed", "extensionsRequired"):
            result[key] = list(dict.fromkeys(result[key] + doc.get(key, [])))

        source_scene = doc.get("scenes", [{}])[doc.get("scene", 0)]
        roots = source_scene.get("nodes", [])
        wrapper = {"name": f"{role.title()}_Court_Anchor", "children": roots}
        if translation != (0.0, 0.0, 0.0):
            wrapper["translation"] = list(translation)
        if yaw:
            wrapper["rotation"] = [0.0, __import__("math").sin(yaw / 2), 0.0, __import__("math").cos(yaw / 2)]
        if uniform_scale != 1.0:
            wrapper["scale"] = [uniform_scale] * 3
        wrapper_nodes.append(len(result["nodes"]))
        result["nodes"].append(wrapper)

    add_court_animations(result, packed, actor_nodes)
    result["buffers"] = [{"byteLength": len(packed)}]
    result["scenes"] = [{"name": "Closer Couple Court", "nodes": wrapper_nodes}]
    os.makedirs(os.path.dirname(os.path.abspath(output)), exist_ok=True)
    json_bytes = json.dumps(result, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    json_bytes += b" " * ((-len(json_bytes)) % 4)
    packed.extend(b"\0" * ((-len(packed)) % 4))
    glb_length = 12 + 8 + len(json_bytes) + 8 + len(packed)
    with open(output, "wb") as out:
        out.write(struct.pack("<4sII", b"glTF", 2, glb_length))
        out.write(struct.pack("<II", len(json_bytes), JSON_CHUNK))
        out.write(json_bytes)
        out.write(struct.pack("<II", len(packed), BIN_CHUNK))
        out.write(packed)
    print(f"Wrote {output} ({os.path.getsize(output):,} bytes)")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--room", required=True)
    parser.add_argument("--girl", required=True)
    parser.add_argument("--boy", required=True)
    parser.add_argument("--judge", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    # GLTF coordinates are Y-up. These are the same positions previewed in Blender.
    parts = [
        ("courtroom", args.room, (0.0, 0.0, 0.0), 0.0, 5.0),
        ("claimant", args.girl, (-1.6, 0.2, 2.2), 0.16, 1.0),
        ("respondent", args.boy, (1.6, 0.2, 2.2), -0.16, 1.0),
        ("judge", args.judge, (0.0, 0.2, -2.2), 0.0, 1.0),
    ]
    merge(parts, args.output)


if __name__ == "__main__":
    main()
