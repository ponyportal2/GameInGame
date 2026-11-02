extends RefCounted

# Only host-created attachment identities are accepted, never workspace paths.
# Relative identities survive game metadata rename along with chat.jsonl.
const Metadata = preload("res://src/core/metadata_store.gd")
const MAX_PNG_BYTES = 8 * 1024 * 1024
var game_name := ""

func _path(id: String) -> String:
    if game_name.is_empty() or id.length() != 32:
        return ""
    for c in id:
        if c not in "0123456789abcdef": return ""
    return Metadata.new().game_meta_dir(game_name).path_join("pictures").path_join(id + ".png")

func save_picture(image: Image) -> Dictionary:
    if image == null or image.is_empty() or game_name.is_empty():
        return {"ok": false, "error": "No game picture to attach."}
    var bytes := image.save_png_to_buffer()
    if bytes.size() > MAX_PNG_BYTES:
        return {"ok": false, "error": "Picture exceeds the 8 MiB attachment limit."}
    var id := Crypto.new().generate_random_bytes(16).hex_encode()
    var path := _path(id)
    if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
        return {"ok": false, "error": "Could not create the picture folder."}
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null: return {"ok": false, "error": "Could not save the picture."}
    file.store_buffer(bytes)
    var error := file.get_error()
    file.close()
    if error != OK:
        DirAccess.remove_absolute(path)
        return {"ok": false, "error": "Could not finish saving the picture."}
    return {"ok": true, "id": id}

func inspect_picture(id: String) -> Dictionary:
    var path := _path(id)
    if path == "" or not FileAccess.file_exists(path):
        return {"ok": false, "error": "Picture not found in this game's chat attachments."}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null or file.get_length() > MAX_PNG_BYTES:
        return {"ok": false, "error": "Picture cannot be read or exceeds the attachment limit."}
    var bytes := file.get_buffer(file.get_length())
    var image := Image.new()
    if image.load_png_from_buffer(bytes) != OK:
        return {"ok": false, "error": "Attachment is not a valid PNG."}
    return {"ok": true, "id": id, "mime_type": "image/png", "image_base64": Marshalls.raw_to_base64(bytes)}

func picture_image(id: String) -> Image:
    var result := inspect_picture(id)
    if not result.ok: return null
    var image := Image.new()
    image.load_png_from_buffer(Marshalls.base64_to_raw(result.image_base64))
    return image

func remove_draft(id: String) -> void:
    var path := _path(id)
    if path != "": DirAccess.remove_absolute(path)
