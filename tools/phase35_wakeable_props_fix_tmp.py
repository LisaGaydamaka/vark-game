from pathlib import Path

path = Path("tools/phase35_wakeable_props_tmp.py")
text = path.read_text(encoding="utf-8")
old = 'tscn = tscn_path.read_text(encoding="utf-8")ntscn = replace_once'
new = 'tscn = tscn_path.read_text(encoding="utf-8")\ntscn = replace_once'
if text.count(old) != 1:
    raise SystemExit(f"expected one staging syntax typo, found {text.count(old)}")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("REPAIRED_WAKEABLE_PROP_STAGING_SYNTAX")
