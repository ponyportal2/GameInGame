extends RefCounted

# Godot's writer leaves some ASCII control characters raw. Native harnesses
# require strict JSON; escape any that survived serialization, including keys.
static func stringify(value: Variant) -> String:
    var text = JSON.stringify(value)
    # Start at 1: String.chr(0) is not a NUL. It reports "Unicode parsing error
    # ... Unexpected NUL character" and yields U+FFFD, so escaping it rewrote
    # every U+FFFD in the payload as a \u0000 escape and turned each response
    # into a fresh diagnostic. JSON.stringify already substitutes U+FFFD for a
    # real NUL, so code 0 never survives to be escaped.
    for code in range(1, 32):
        var character = String.chr(code)
        if not character.is_empty(): text = text.replace(character, "\\u%04x" % code)
    return text
