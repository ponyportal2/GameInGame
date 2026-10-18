extends RefCounted

# Godot's writer leaves some ASCII control characters raw. Native harnesses
# require strict JSON; escape any that survived serialization, including keys.
static func stringify(value: Variant) -> String:
    var text = JSON.stringify(value)
    for code in range(32):
        var character = String.chr(code)
        if not character.is_empty(): text = text.replace(character, "\\u%04x" % code)
    return text
