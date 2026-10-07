#!/usr/bin/env bash
# Check the design and write fabrication outputs to fab/.
#
# Usage: [BOARDS=n] scripts/export-fab.sh [--force]
#
# Always runs ERC, the netlist check and DRC (with schematic parity and a
# zone refill), then writes the schematic PDF, the BOM, a Mouser BOM-tool
# order CSV for BOARDS boards (default 1), the position file and renders.
# The order CSV takes Mouser part numbers from the symbols' Mouser field;
# lines without one are matched by manufacturer part number. Gerbers and
# drill files are written only when DRC reports no violations and no unrouted
# connections; --force writes them anyway.
set -euo pipefail

cd "$(dirname "$0")/.."
NAME=led-pwm-4bit
BOARDS=${BOARDS:-1}
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

CLI=$(command -v kicad-cli || true)
[[ -z "$CLI" && -x /Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli ]] &&
    CLI=/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli
[[ -z "$CLI" ]] && { echo "kicad-cli not found" >&2; exit 1; }

# Run kicad-cli without its Fontconfig noise, keeping its exit status.
kc() { "$CLI" "$@" 2> >(grep -v Fontconfig >&2); }

mkdir -p fab/reports
rm -f fab/reports/erc.rpt fab/reports/drc.json

echo "== ERC"
kc sch erc --severity-all --exit-code-violations -o fab/reports/erc.rpt $NAME.kicad_sch >/dev/null ||
    { echo "ERC failed, see fab/reports/erc.rpt" >&2; exit 1; }

echo "== Netlist check"
python3 check_netlist.py

echo "== DRC"
# Exit status 5 means violations were found; any other failure means DRC did not run.
kc pcb drc --schematic-parity --refill-zones --severity-all --format json \
    -o fab/reports/drc.json $NAME.kicad_pcb >/dev/null || true
[[ -s fab/reports/drc.json ]] || { echo "DRC did not run" >&2; exit 1; }
read -r VIOLATIONS UNROUTED PARITY < <(python3 - <<'EOF'
import json
d = json.load(open('fab/reports/drc.json'))
print(len(d.get('violations', [])), len(d.get('unconnected_items', [])), len(d.get('schematic_parity', [])))
EOF
)
echo "violations: $VIOLATIONS, unrouted: $UNROUTED, schematic parity: $PARITY"

echo "== Schematic PDF, BOM, Mouser order, positions, renders"
rm -f fab/$NAME-*.pdf fab/$NAME-*.csv fab/$NAME-*.png
kc sch export pdf -o fab/$NAME-schematic.pdf $NAME.kicad_sch >/dev/null
kc sch export bom -o fab/$NAME-bom.csv \
    --fields 'Reference,Value,Footprint,Manufacturer,MPN,Mouser,${QUANTITY}' \
    --labels 'Reference,Value,Footprint,Manufacturer,MPN,Mouser,Qty' \
    --group-by 'Value,Footprint,MPN' $NAME.kicad_sch >/dev/null
kc sch export bom -o fab/reports/mouser-raw.csv \
    --fields 'Mouser,${QUANTITY},MPN,Value,Reference' \
    --labels 'Mouser Part Number,Quantity,Manufacturer Part Number,Description,Customer Part Number' \
    --group-by 'MPN' --ref-range-delimiter '' $NAME.kicad_sch >/dev/null
BOARDS=$BOARDS python3 - <<'EOF'
import csv, os
boards = int(os.environ['BOARDS'])
rows = list(csv.reader(open('fab/reports/mouser-raw.csv', newline='')))
with open('fab/led-pwm-4bit-mouser-order.csv', 'w', newline='') as f:
    w = csv.writer(f, quoting=csv.QUOTE_MINIMAL)
    w.writerow(rows[0])
    for r in rows[1:]:
        if r[2].strip():
            r[1] = str(int(r[1]) * boards)
            w.writerow(r)
os.remove('fab/reports/mouser-raw.csv')
EOF
kc pcb export pos --format csv --units mm --side both -o fab/$NAME-pos.csv $NAME.kicad_pcb >/dev/null
kc pcb render --side top --width 1600 --height 1200 --quality high -o fab/$NAME-top.png $NAME.kicad_pcb >/dev/null
kc pcb render --side bottom --width 1600 --height 1200 --quality high -o fab/$NAME-bottom.png $NAME.kicad_pcb >/dev/null

if [[ "$VIOLATIONS" != 0 || "$UNROUTED" != 0 || "$PARITY" != 0 ]] && [[ $FORCE == 0 ]]; then
    echo "Skipped Gerbers and drill files: route the board until DRC is clean, or pass --force."
    exit 0
fi

echo "== Gerbers and drill files"
rm -rf fab/gerbers fab/$NAME-gerbers.zip && mkdir -p fab/gerbers
kc pcb export gerbers --check-zones --subtract-soldermask -o fab/gerbers \
    -l F.Cu,B.Cu,F.Paste,B.Paste,F.Silkscreen,B.Silkscreen,F.Mask,B.Mask,Edge.Cuts $NAME.kicad_pcb >/dev/null
kc pcb export drill --format excellon --excellon-units mm --excellon-zeros-format decimal \
    --excellon-oval-format alternate --drill-origin absolute --excellon-separate-th \
    --generate-map --map-format pdf -o fab/gerbers/ $NAME.kicad_pcb >/dev/null
(cd fab/gerbers && zip -q ../$NAME-gerbers.zip ./*)
echo "Wrote fab/$NAME-gerbers.zip"
