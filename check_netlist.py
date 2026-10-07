#!/usr/bin/env python3
"""Compare the schematic netlist with docs/netlist.txt.

Usage: check_netlist.py [netlist.xml]

Without an argument the netlist is exported with kicad-cli first. Exits
non-zero on any difference: missing or extra nets, pins on the wrong
net, pins that appear twice, unlisted pins, or connected NC pins.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
SCH = os.path.join(HERE, 'led-pwm-4bit.kicad_sch')
REF = os.path.join(HERE, 'docs', 'netlist.txt')
KICAD_CLI_MAC = '/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli'


def load_reference(path):
    nets, nc = {}, set()
    for line in open(path):
        line = line.split('#', 1)[0].strip()
        if not line:
            continue
        name, pins = line.split(':', 1)
        pins = pins.split()
        if name == 'NC':
            nc.update(pins)
        else:
            if name in nets:
                sys.exit(f'{path}: net {name} listed twice')
            nets[name] = set(pins)
    return nets, nc


def export_netlist(out):
    cli = shutil.which('kicad-cli') or KICAD_CLI_MAC
    subprocess.run([cli, 'sch', 'export', 'netlist', '--format', 'kicadxml', '-o', out, SCH],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def load_kicad(path):
    root = ET.parse(path).getroot()
    parts = {}
    libparts = {(lp.get('lib'), lp.get('part')): [p.get('num') for p in lp.iter('pin')]
                for lp in root.iter('libpart')}
    for comp in root.iter('comp'):
        ref = comp.get('ref')
        ls = comp.find('libsource')
        parts[ref] = libparts.get((ls.get('lib'), ls.get('part')), [])
    nets = {}
    for net in root.iter('net'):
        # Local labels on the root sheet are exported as "/NAME".
        name = re.sub(r'^/', '', net.get('name'))
        nets[name] = [f"{n.get('ref')}.{n.get('pin')}" for n in net.iter('node')]
    return parts, nets


def main():
    if len(sys.argv) > 1:
        xml = sys.argv[1]
    else:
        xml = os.path.join(tempfile.mkdtemp(), 'netlist.xml')
        export_netlist(xml)
    ref_nets, ref_nc = load_reference(REF)
    parts, nets = load_kicad(xml)
    errors = []

    seen = {}
    for name, pins in nets.items():
        for p in pins:
            if p in seen:
                errors.append(f'pin {p} is on both {seen[p]} and {name}')
            seen[p] = name

    got_nc = set()
    for name, pins in nets.items():
        if name.startswith('unconnected-'):
            got_nc.update(pins)
            continue
        if name not in ref_nets:
            errors.append(f'extra net {name}: {" ".join(sorted(pins))}')
            continue
        want, got = ref_nets[name], set(pins)
        if len(pins) != len(got):
            errors.append(f'net {name} lists a pin twice')
        for p in sorted(want - got):
            errors.append(f'net {name}: missing {p} (found on {seen.get(p, "no net")})')
        for p in sorted(got - want):
            errors.append(f'net {name}: unexpected {p}')
    for name in sorted(set(ref_nets) - set(nets)):
        errors.append(f'missing net {name}')
    for p in sorted(ref_nc - got_nc):
        errors.append(f'{p} should be unconnected but is on {seen.get(p, "no net")}')
    for p in sorted(got_nc - ref_nc):
        errors.append(f'{p} is unconnected but not listed as NC')

    all_ref_pins = set().union(*ref_nets.values()) | ref_nc
    for ref, pins in sorted(parts.items()):
        for num in pins:
            if f'{ref}.{num}' not in seen:
                errors.append(f'pin {ref}.{num} is on no net')
    for p in sorted(all_ref_pins):
        ref, num = p.split('.')
        if ref not in parts:
            errors.append(f'{p}: part {ref} not in schematic')
        elif num not in parts[ref]:
            errors.append(f'{p}: part {ref} has no pin {num}')
    extra_parts = sorted(set(parts) - {p.split('.')[0] for p in all_ref_pins} - {'H1', 'H2'})
    for ref in extra_parts:
        errors.append(f'part {ref} is not in the reference netlist')
    for ref in ('H1', 'H2'):
        if ref not in parts:
            errors.append(f'part {ref} missing')
        elif parts[ref]:
            errors.append(f'part {ref} should have no pins')

    if errors:
        print('\n'.join(errors))
        print(f'FAIL: {len(errors)} difference(s)')
        return 1
    print(f'OK: {len(ref_nets)} nets, {len(ref_nc)} NC pins, {len(parts)} parts match {os.path.relpath(REF, HERE)}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
