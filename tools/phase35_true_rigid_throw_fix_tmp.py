from pathlib import Path

path = Path("tools/phase35_true_rigid_throw_tmp.py")
text = path.read_text(encoding="utf-8")
old = 'testing = testing_path.read_text(encoding="utf-8")ntesting_old = '
new = 'testing = testing_path.read_text(encoding="utf-8")\ntesting_old = '
if text.count(old) != 1:
    raise SystemExit(f"staging typo marker count={text.count(old)}")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
