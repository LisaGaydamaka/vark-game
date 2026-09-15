class_name PersistentIdSource
extends RefCounted


const PERSISTENT_ID_KEY: String = "persistent_id"
const MAX_ID_GENERATION_ATTEMPTS: int = 32


static func source_sha256(source: String) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(source.to_utf8_buffer()) != OK:
		return ""
	return context.finish().hex_encode()


static func read_source(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {
			"ok": false,
			"text": "",
			"error": "Could not open map source for reading: %s" % path,
		}
	var text: String = file.get_as_text()
	file.close()
	return {
		"ok": true,
		"text": text,
		"error": "",
	}


static func inspect_file(path: String) -> Dictionary:
	var read_result: Dictionary = read_source(path)
	if not bool(read_result["ok"]):
		return {
			"ok": false,
			"valid": false,
			"source_hash": "",
			"candidates": [],
			"missing": [],
			"duplicates": [],
			"error": str(read_result["error"]),
		}
	var source: String = str(read_result["text"])
	var result: Dictionary = inspect_source(source)
	result["source_hash"] = source_sha256(source)
	return result


static func inspect_source(source: String) -> Dictionary:
	var entities: Array = _scan_entities(source)
	var candidates: Array = []
	var missing: Array = []
	var duplicates: Array = []
	var first_owner_by_id: Dictionary = {}

	for entity_variant: Variant in entities:
		var entity: Dictionary = entity_variant
		if not _is_identity_candidate(entity):
			continue

		var properties: Dictionary = entity["properties"]
		var persistent_id: String = str(
			properties.get(PERSISTENT_ID_KEY, "")
		).strip_edges()
		var summary := {
			"entity_index": int(entity["entity_index"]),
			"classname": str(properties.get("classname", "")),
			"persistent_id": persistent_id,
		}
		candidates.append(summary)

		if persistent_id.is_empty():
			missing.append(summary.duplicate(true))
			continue

		if first_owner_by_id.has(persistent_id):
			duplicates.append({
				"entity_index": int(entity["entity_index"]),
				"first_entity_index": int(first_owner_by_id[persistent_id]),
				"classname": str(properties.get("classname", "")),
				"persistent_id": persistent_id,
			})
			continue

		first_owner_by_id[persistent_id] = int(entity["entity_index"])

	return {
		"ok": true,
		"valid": missing.is_empty() and duplicates.is_empty(),
		"source_hash": source_sha256(source),
		"candidates": candidates,
		"missing": missing,
		"duplicates": duplicates,
		"error": "",
	}


static func repair_source(
	source: String,
	id_factory: Callable = Callable()
) -> Dictionary:
	var lines: Array[String] = _split_lines(source)
	var entities: Array = _scan_entities(source)
	var used_ids: Dictionary = {}
	var first_owner_by_id: Dictionary = {}
	var repair_reason_by_index: Dictionary = {}

	for entity_variant: Variant in entities:
		var entity: Dictionary = entity_variant
		if not _is_identity_candidate(entity):
			continue
		var properties: Dictionary = entity["properties"]
		var persistent_id: String = str(
			properties.get(PERSISTENT_ID_KEY, "")
		).strip_edges()
		var entity_index: int = int(entity["entity_index"])

		if persistent_id.is_empty():
			repair_reason_by_index[entity_index] = "missing"
			continue

		used_ids[persistent_id] = true
		if first_owner_by_id.has(persistent_id):
			repair_reason_by_index[entity_index] = "duplicate"
		else:
			first_owner_by_id[persistent_id] = entity_index

	# Generate replacement IDs in source/entity order. Line edits happen in reverse
	# later only so insertions cannot invalidate offsets of earlier entities.
	var new_id_by_index: Dictionary = {}
	for entity_variant: Variant in entities:
		var entity: Dictionary = entity_variant
		var entity_index: int = int(entity["entity_index"])
		if not repair_reason_by_index.has(entity_index):
			continue
		var new_id: String = _next_unique_id(used_ids, id_factory)
		if new_id.is_empty():
			return {
				"ok": false,
				"changed": false,
				"source": source,
				"source_hash": source_sha256(source),
				"repairs": [],
				"error": "Could not generate a unique persistent_id.",
			}
		used_ids[new_id] = true
		new_id_by_index[entity_index] = new_id

	var repairs: Array = []
	for reverse_index: int in range(entities.size() - 1, -1, -1):
		var entity: Dictionary = entities[reverse_index]
		var entity_index: int = int(entity["entity_index"])
		if not repair_reason_by_index.has(entity_index):
			continue

		var new_id: String = str(new_id_by_index[entity_index])
		var properties: Dictionary = entity["properties"]
		var property_lines: Dictionary = entity["property_lines"]
		var old_id: String = str(properties.get(PERSISTENT_ID_KEY, ""))
		if property_lines.has(PERSISTENT_ID_KEY):
			var line_index: int = int(property_lines[PERSISTENT_ID_KEY])
			var prefix: String = _leading_prefix(lines[line_index])
			lines[line_index] = "%s\"%s\" \"%s\"" % [
				prefix,
				PERSISTENT_ID_KEY,
				new_id,
			]
		else:
			var classname_line: int = int(
				property_lines.get("classname", int(entity["start_line"]))
			)
			var prefix: String = _leading_prefix(lines[classname_line])
			lines.insert(
				classname_line + 1,
				"%s\"%s\" \"%s\"" % [prefix, PERSISTENT_ID_KEY, new_id]
			)

		repairs.append({
			"entity_index": entity_index,
			"classname": str(properties.get("classname", "")),
			"reason": str(repair_reason_by_index[entity_index]),
			"old_id": old_id,
			"new_id": new_id,
		})

	var repaired_source: String = "\n".join(lines)
	return {
		"ok": true,
		"changed": not repairs.is_empty(),
		"source": repaired_source,
		"source_hash": source_sha256(repaired_source),
		"repairs": repairs,
		"error": "",
	}


static func repair_file(
	path: String,
	expected_source_hash: String,
	id_factory: Callable = Callable()
) -> Dictionary:
	var read_result: Dictionary = read_source(path)
	if not bool(read_result["ok"]):
		return _file_failure(str(read_result["error"]), false)

	var original_source: String = str(read_result["text"])
	var original_hash: String = source_sha256(original_source)
	if (
		not expected_source_hash.is_empty()
		and original_hash != expected_source_hash
	):
		return _file_failure(
			"Map source changed since the caller inspected it; refusing stale writeback.",
			true,
			original_hash
		)

	var repair_result: Dictionary = repair_source(original_source, id_factory)
	if not bool(repair_result["ok"]):
		return _file_failure(str(repair_result["error"]), false, original_hash)
	if not bool(repair_result["changed"]):
		return {
			"ok": true,
			"changed": false,
			"stale": false,
			"source_hash": original_hash,
			"repairs": [],
			"error": "",
		}

	# Re-read immediately before writeback so an edit made while repair work was
	# being prepared cannot be overwritten by stale generated text.
	var before_write: Dictionary = read_source(path)
	if (
		not bool(before_write["ok"])
		or str(before_write["text"]) != original_source
	):
		return _file_failure(
			"Map source changed during repair; refusing stale writeback.",
			true,
			original_hash
		)

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _file_failure(
			"Could not open map source for writeback: %s" % path,
			false,
			original_hash
		)
	file.store_string(str(repair_result["source"]))
	file.flush()
	file.close()

	var verify_result: Dictionary = read_source(path)
	if (
		not bool(verify_result["ok"])
		or str(verify_result["text"]) != str(repair_result["source"])
	):
		return _file_failure(
			"Persistent-ID source writeback did not verify exactly.",
			false,
			original_hash
		)

	return {
		"ok": true,
		"changed": true,
		"stale": false,
		"source_hash": str(repair_result["source_hash"]),
		"repairs": repair_result["repairs"],
		"error": "",
	}


static func _file_failure(
	error: String,
	stale: bool,
	source_hash: String = ""
) -> Dictionary:
	return {
		"ok": false,
		"changed": false,
		"stale": stale,
		"source_hash": source_hash,
		"repairs": [],
		"error": error,
	}


static func _next_unique_id(
	used_ids: Dictionary,
	id_factory: Callable
) -> String:
	for _attempt: int in MAX_ID_GENERATION_ATTEMPTS:
		var candidate: String = ""
		if id_factory.is_valid():
			candidate = str(id_factory.call()).strip_edges()
		else:
			candidate = _generate_random_id()
		if not candidate.is_empty() and not used_ids.has(candidate):
			return candidate
	return ""


static func _generate_random_id() -> String:
	var crypto := Crypto.new()
	return "vark_" + crypto.generate_random_bytes(16).hex_encode()


static func _is_identity_candidate(entity: Dictionary) -> bool:
	var properties: Dictionary = entity["properties"]
	var classname: String = str(properties.get("classname", "")).strip_edges()
	if classname.is_empty() or classname == "worldspawn":
		return false
	if classname == "func_group" and properties.has("_tb_type"):
		return false
	return true


static func _scan_entities(source: String) -> Array:
	var lines: Array[String] = _split_lines(source)
	var entities: Array = []
	var depth: int = 0
	var current: Dictionary = {}

	for line_index: int in lines.size():
		var stripped: String = lines[line_index].strip_edges()
		if stripped == "{":
			if depth == 0:
				current = {
					"entity_index": entities.size(),
					"start_line": line_index,
					"end_line": -1,
					"properties": {},
					"property_lines": {},
				}
			depth += 1
			continue

		if stripped == "}":
			if depth > 0:
				depth -= 1
			if depth == 0 and not current.is_empty():
				current["end_line"] = line_index
				entities.append(current)
				current = {}
			continue

		if depth != 1 or current.is_empty() or not stripped.begins_with("\""):
			continue

		var property_pair: Dictionary = _parse_property_line(stripped)
		if property_pair.is_empty():
			continue
		var key: String = str(property_pair["key"])
		var properties: Dictionary = current["properties"]
		properties[key] = property_pair["value"]
		current["properties"] = properties
		var property_lines: Dictionary = current["property_lines"]
		property_lines[key] = line_index
		current["property_lines"] = property_lines

	return entities


static func _parse_property_line(line: String) -> Dictionary:
	var key_end: int = line.find("\"", 1)
	if key_end < 0:
		return {}
	var value_start: int = line.find("\"", key_end + 1)
	if value_start < 0:
		return {}
	var value_end: int = line.find("\"", value_start + 1)
	if value_end < 0:
		return {}
	return {
		"key": line.substr(1, key_end - 1),
		"value": line.substr(value_start + 1, value_end - value_start - 1),
	}


static func _split_lines(source: String) -> Array[String]:
	var lines: Array[String] = []
	for line: String in source.split("\n", true):
		lines.append(line)
	return lines


static func _leading_prefix(line: String) -> String:
	var quote_index: int = line.find("\"")
	if quote_index <= 0:
		return ""
	return line.substr(0, quote_index)
