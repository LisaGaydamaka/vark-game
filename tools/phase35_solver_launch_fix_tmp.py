from pathlib import Path

path = Path("tools/phase35_solver_launch_tmp.py")
text = path.read_text(encoding="utf-8")
old = 'plan = plan_path.read_text(encoding="utf-8")nold = '
new = 'plan = plan_path.read_text(encoding="utf-8")\nold = '
if text.count(old) != 1:
    raise SystemExit(f"solver staging typo marker count={text.count(old)}")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
