"""Convert a .glb into something Mixamo's auto-rigger will accept.

Mixamo takes OBJ, FBX or ZIP, and rejects glTF outright. Meshes that carry UVs
and a texture have to go up as a zip of .obj + .mtl + image, otherwise the
unwrap is lost and the rigged model comes back untexturable.

    python tools/dev/glb_to_obj.py model.glb [more.glb ...]

Writes <name>_for_mixamo.obj beside each input, or <name>_for_mixamo.zip when
the model has a texture.
"""

import json
import pathlib
import struct
import sys
import zipfile

COMPONENT_FORMATS = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
TYPE_COUNTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_glb(path):
    raw = path.read_bytes()
    if raw[:4] != b"glTF":
        raise ValueError("%s is not a binary glTF" % path.name)
    offset, meta, binary = 12, None, None
    while offset < len(raw):
        length, kind = struct.unpack("<II", raw[offset:offset + 8])
        chunk = raw[offset + 8:offset + 8 + length]
        if kind == 0x4E4F534A:
            meta = json.loads(chunk.decode("utf-8"))
        elif kind == 0x004E4942:
            binary = chunk
        offset += 8 + length
    return meta, binary


def accessor(meta, binary, index):
    """Returns a flat list of an accessor's values, honouring byte strides."""
    acc = meta["accessors"][index]
    count = acc["count"]
    per = TYPE_COUNTS[acc["type"]]
    fmt = COMPONENT_FORMATS[acc["componentType"]]
    size = struct.calcsize(fmt)
    view = meta["bufferViews"][acc["bufferView"]]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = view.get("byteStride") or per * size
    out = []
    for i in range(count):
        out.extend(struct.unpack_from("<%d%s" % (per, fmt), binary, start + i * stride))
    return out


def texture_bytes(meta, binary, material_index):
    if material_index is None or not meta.get("images"):
        return None, None
    material = meta["materials"][material_index]
    info = material.get("pbrMetallicRoughness", {}).get("baseColorTexture")
    if info is None:
        return None, None
    image = meta["images"][meta["textures"][info["index"]]["source"]]
    if "bufferView" not in image:
        return None, None
    view = meta["bufferViews"][image["bufferView"]]
    start = view.get("byteOffset", 0)
    data = binary[start:start + view["byteLength"]]
    ext = ".jpg" if image.get("mimeType") == "image/jpeg" else ".png"
    return data, ext


def convert(path):
    meta, binary = read_glb(path)
    stem = path.stem + "_for_mixamo"

    positions, uvs, normals, faces = [], [], [], []
    image_data = image_ext = None

    for mesh in meta.get("meshes", []):
        for prim in mesh["primitives"]:
            if prim.get("mode", 4) != 4:
                continue
            attrs = prim["attributes"]
            base = len(positions) // 3
            positions.extend(accessor(meta, binary, attrs["POSITION"]))
            has_uv = "TEXCOORD_0" in attrs
            has_normal = "NORMAL" in attrs
            if has_uv:
                uvs.extend(accessor(meta, binary, attrs["TEXCOORD_0"]))
            if has_normal:
                normals.extend(accessor(meta, binary, attrs["NORMAL"]))
            if "indices" in prim:
                indices = accessor(meta, binary, prim["indices"])
            else:
                indices = list(range(len(positions) // 3 - base))
            for i in range(0, len(indices) - 2, 3):
                faces.append(tuple(base + indices[i + k] + 1 for k in range(3)))
            if image_data is None:
                image_data, image_ext = texture_bytes(meta, binary, prim.get("material"))

    if not faces:
        raise ValueError("%s has no triangles" % path.name)

    has_uv = len(uvs) // 2 == len(positions) // 3
    has_normal = len(normals) == len(positions)

    lines = ["# %s converted for Mixamo auto-rigging" % path.name]
    if image_data:
        lines.append("mtllib %s.mtl" % stem)
    for i in range(0, len(positions), 3):
        lines.append("v %.6f %.6f %.6f" % tuple(positions[i:i + 3]))
    if has_uv:
        for i in range(0, len(uvs), 2):
            # glTF UVs run top-down, OBJ runs bottom-up.
            lines.append("vt %.6f %.6f" % (uvs[i], 1.0 - uvs[i + 1]))
    if has_normal:
        for i in range(0, len(normals), 3):
            lines.append("vn %.6f %.6f %.6f" % tuple(normals[i:i + 3]))
    if image_data:
        lines.append("usemtl body")
    for a, b, c in faces:
        if has_uv and has_normal:
            lines.append("f %d/%d/%d %d/%d/%d %d/%d/%d" % (a, a, a, b, b, b, c, c, c))
        elif has_uv:
            lines.append("f %d/%d %d/%d %d/%d" % (a, a, b, b, c, c))
        elif has_normal:
            lines.append("f %d//%d %d//%d %d//%d" % (a, a, b, b, c, c))
        else:
            lines.append("f %d %d %d" % (a, b, c))
    obj_text = "\n".join(lines) + "\n"

    summary = "%s: %d verts, %d tris, uv=%s normals=%s" % (
        path.name, len(positions) // 3, len(faces), has_uv, has_normal)

    if image_data:
        image_name = stem + image_ext
        mtl = "newmtl body\nKa 1 1 1\nKd 1 1 1\nd 1\nillum 2\nmap_Kd %s\n" % image_name
        out = path.with_name(stem + ".zip")
        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as archive:
            archive.writestr(stem + ".obj", obj_text)
            archive.writestr(stem + ".mtl", mtl)
            archive.writestr(image_name, image_data)
        return out, summary + " (zipped with texture)"

    out = path.with_name(stem + ".obj")
    out.write_text(obj_text, encoding="utf-8")
    return out, summary


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    for name in argv:
        path = pathlib.Path(name)
        if not path.exists():
            print("missing: %s" % path)
            continue
        out, summary = convert(path)
        print("%s\n   -> %s (%.1f KB)" % (summary, out.name, out.stat().st_size / 1024))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
