from pathlib import Path

path = Path("tools/phase35_explicit_prop_physics_tmp.py")
text = path.read_text(encoding="utf-8")
anchor = '''prop = replace_once(prop, push_anchor, impact_methods + push_anchor, "explicit prop impact receiver")

# The generated first-pass implementation routed player pushing too late in the
'''
replacement = '''prop = replace_once(prop, push_anchor, impact_methods + push_anchor, "explicit prop impact receiver")
prop_path.write_text(prop, encoding="utf-8")

# The generated first-pass implementation routed player pushing too late in the
'''
if text.count(anchor) != 1:
    raise SystemExit(f"expected one prop writeback insertion point, found {text.count(anchor)}")
path.write_text(text.replace(anchor, replacement, 1), encoding="utf-8")
print("PERSISTED_EXPLICIT_PROP_STAGING_EDITS")
