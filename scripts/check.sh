#!/usr/bin/env bash
# Runs every headless check: data validation, dialogue compile, unit tests.
# Set GODOT to your Godot 4.7 console executable if it isn't the default below.
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-/c/Program Files (x86)/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe}"

# First run on a fresh clone: build the import cache and script class list.
if [ ! -f .godot/global_script_class_cache.cfg ]; then
	"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
fi

# gdUnit writes HTML reports to res://reports; keep Godot from importing them.
mkdir -p reports && touch reports/.gdignore

echo "== Data"
"$GODOT" --headless --path . --script res://tools/validate_data.gd 2>&1 | grep -E "Data OK|^res://|^data/|failed" || true
"$GODOT" --headless --path . --script res://tools/validate_data.gd >/dev/null 2>&1

echo "== Dialogue"
"$GODOT" --headless --path . --script res://tools/check_dialogue.gd >/dev/null 2>&1 \
	&& echo "Dialogue OK" \
	|| { "$GODOT" --headless --path . --script res://tools/check_dialogue.gd 2>&1 | grep "\.dialogue:"; exit 1; }

echo "== Maps"
"$GODOT" --headless --path . res://tools/check_maps.tscn 2>&1 | grep -E "Maps OK|^warning|^test_|^[a-z0-9_]+/|^[a-z0-9_]+:" || true
"$GODOT" --headless --path . res://tools/check_maps.tscn >/dev/null 2>&1

echo "== Tests"
"$GODOT" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
	--add res://tests --ignoreHeadlessMode -c 2>&1 \
	| sed 's/\x1b\[[0-9;]*m//g' | grep -E "Statistics|FAILED|Exit code" || true
"$GODOT" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
	--add res://tests --ignoreHeadlessMode -c >/dev/null 2>&1

echo "== Compendium"
"$GODOT" --headless --path . --script res://tools/generate_compendium.gd 2>&1 | grep -E "^Wrote" || true
echo "All checks passed."
