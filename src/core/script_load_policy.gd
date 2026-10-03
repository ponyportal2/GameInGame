extends RefCounted

# A coding convention, not a sandbox. Inspect direct loading calls without
# confusing comments or quoted examples with executable GDScript.
const LOAD_METHODS = ["load", "load_threaded_request", "load_threaded_get"]
const SCRIPT_EXTENSIONS = ["gd", "gdc", "gde", "cs"]
const SAFE_RUNTIME_ASSET_EXTENSIONS = ["png", "jpg", "jpeg", "wav", "ogg"]

static func first_violation(source: String) -> Dictionary:
    var tokens = _tokens(source)
    for i in range(tokens.size() - 1):
        var token: Dictionary = tokens[i]
        if token.kind != "identifier" or token.value not in LOAD_METHODS or tokens[i + 1].value != "(":
            continue
        if i > 0 and tokens[i - 1].value == "func":
            continue
        var args = _arguments(tokens, i + 1)
        if args.is_empty():
            continue # An incomplete call belongs to Godot's compiler.
        var qualified = i > 0 and tokens[i - 1].value == "."
        var max_args = 4 if token.value == "load_threaded_request" else (3 if token.value == "load" and qualified else 1)
        if args.size() > max_args:
            continue # Invalid API arity also belongs to Godot.
        var path = _literal(args[0])
        var hint = _literal(args[1]) if args.size() > 1 else null
        if path != null and str(path).get_extension().to_lower() in SCRIPT_EXTENSIONS:
            return {"line": token.line, "message": "Runtime script loading is not supported. Use preload() or script inheritance for script dependencies."}
        if hint != null and ClassDB.class_exists(str(hint)) and ClassDB.is_parent_class(str(hint), "Script"):
            return {"line": token.line, "message": "Runtime Script/GDScript loading is not supported. Use preload() or script inheritance."}
        if path == null or str(path).begins_with("uid://") or str(path).get_extension().is_empty():
            return {"line": token.line, "message": "Runtime loading supports only literal PNG/JPG/JPEG/WAV/OGG paths. Use a literal approved asset path, or preload a statically known resource."}
        if str(path).get_extension().to_lower() not in SAFE_RUNTIME_ASSET_EXTENSIONS:
            return {"line": token.line, "message": "Runtime loading of scenes, serialized resources, and other unapproved asset formats is unsupported. Use preload() with a statically known resource path."}
    return {}

static func _literal(argument: Array):
    if argument.size() == 1 and argument[0].kind == "string" and not str(argument[0].value).contains("\\"):
        return argument[0].value
    return null

static func _arguments(tokens: Array[Dictionary], opening: int) -> Array:
    var arguments: Array = []
    var current: Array = []
    var closing: Array[String] = [")"]
    for i in range(opening + 1, tokens.size()):
        var token: Dictionary = tokens[i]
        if token.kind == "symbol":
            if token.value in ["(", "[", "{"]:
                closing.append({"(": ")", "[": "]", "{": "}"}[token.value])
            elif token.value in [")", "]", "}"]:
                if token.value != closing.back():
                    return []
                closing.pop_back()
                if closing.is_empty():
                    if not current.is_empty():
                        arguments.append(current)
                    return arguments
            elif token.value == "," and closing.size() == 1:
                if current.is_empty():
                    return []
                arguments.append(current)
                current = []
                continue
        current.append(token)
    return [] # Leave malformed source to Godot's compiler.

static func _tokens(source: String) -> Array[Dictionary]:
    var tokens: Array[Dictionary] = []
    var i = 0
    var line = 1
    while i < source.length():
        var character = source[i]
        if character == "\n":
            line += 1
            i += 1
            continue
        if character in [" ", "\t", "\r"] or (character == "\\" and i + 1 < source.length() and source[i + 1] == "\n"):
            i += 1
            continue
        if character == "#":
            while i < source.length() and source[i] != "\n":
                i += 1
            continue
        var raw = false
        if character in ["r", "&", "^"] and i + 1 < source.length() and source[i + 1] in ["'", "\""]:
            raw = character == "r"
            i += 1
            character = source[i]
        if character in ["'", "\""]:
            var start_line = line
            var delimiter = character.repeat(3) if source.substr(i, 3) == character.repeat(3) else character
            i += delimiter.length()
            var start = i
            while i < source.length() and source.substr(i, delimiter.length()) != delimiter:
                if source[i] == "\\" and i + 1 < source.length():
                    if source[i + 1] == "\n":
                        line += 1
                    i += 2
                else:
                    if source[i] == "\n":
                        line += 1
                    i += 1
            var value = source.substr(start, i - start)
            if i >= source.length():
                return [] # Unterminated strings make tokenization uncertain.
            tokens.append({"kind": "string", "value": value if raw else value.c_unescape(), "line": start_line})
            i += delimiter.length()
            continue
        if _identifier_character(character):
            var start = i
            while i < source.length() and _identifier_character(source[i]):
                i += 1
            tokens.append({"kind": "identifier", "value": source.substr(start, i - start), "line": line})
        else:
            tokens.append({"kind": "symbol", "value": character, "line": line})
            i += 1
    return tokens

static func _identifier_character(character: String) -> bool:
    return character == "_" or character.is_valid_unicode_identifier() or character.is_valid_int()
