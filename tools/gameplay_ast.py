"""Print GDScript call sites for the restaurant service loop. Requires gdtoolkit."""
from pathlib import Path

from gdtoolkit.parser import parser

ROOT = Path(__file__).resolve().parents[1]
TARGETS = {
    "scripts/ui/main.gd": {"_process", "_open_day"},
    "scripts/core/simulation.gd": {
        "step", "_advance_customer", "_advance_staff", "_dispatch_staff",
        "_dispatch_chef", "_dispatch_waiter", "_arrive_task", "_complete_action",
        "_record_food_wait", "_checkout", "_close_day", "call_current",
    },
}
count = 0
files = sorted((ROOT / "scripts").rglob("*.gd"))
for path in files:
    source = path.read_text(encoding="utf-8")
    lines = source.splitlines()
    tree = parser.parse(source, gather_metadata=True)
    for function in tree.find_data("func_def"):
        count += 1
        name = str(function.children[0].children[0])
        relative = path.relative_to(ROOT).as_posix()
        if name not in TARGETS.get(relative, set()):
            continue
        print(f"{relative}:{function.meta.line} {name}")
        calls = set()
        for expression in function.iter_subtrees():
            if expression.data not in {"standalone_call", "getattr_call"}:
                continue
            meta = expression.meta
            if meta.line == meta.end_line:
                calls.add(lines[meta.line - 1][meta.column - 1:meta.end_column - 1].split("(", 1)[0])
        print("  " + ", ".join(sorted(calls)))
print(f"{len(files)} scripts, {count} functions")
