from pathlib import Path

path = Path("tools/phase35_explicit_prop_physics_tmp.py")
text = path.read_text(encoding="utf-8")
old = '''prop = replace_once(
    prop,
    '\\tcan_sleep = true\\n\\tfreeze = false\\n\\tsleeping = true\\n',
    '\\tcan_sleep = true\\n\\tfreeze = true\\n\\tsleeping = true\\n',
    "stable settled ready state",
)
'''
new = '''prop = replace_once(
    prop,
    '\\tcontinuous_cd = true\\n\\tlock_rotation = true\\n\\tcan_sleep = true\\n\\tfreeze = false\\n\\tsleeping = true\\n',
    '\\tcontinuous_cd = true\\n\\tlock_rotation = true\\n\\tcan_sleep = true\\n\\tfreeze = true\\n\\tsleeping = true\\n',
    "stable settled ready state",
)
'''
if text.count(old) != 1:
    raise SystemExit(f"expected one ambiguous ready-state edit, found {text.count(old)}")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("DISAMBIGUATED_EXPLICIT_PROP_STAGING_ANCHOR")
