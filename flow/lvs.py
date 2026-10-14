"""Parse flat OpenROAD DEF and named-port structural Verilog for LVS.

These functions compare DEF connectivity, not extracted metal connectivity.
Unsupported Verilog constructs and inconsistent DEF records raise errors.
Return (instances, nets, ports, design), where instances map names to
(cell_master, {pin: net}) and nets map names to endpoint lists.
"""
from pathlib import Path
import re


def canon_net_name(name):
    return re.sub(r"\s+", "", name).replace("\\", "")


def _section(text, name, required=True):
    match = re.search(rf"^{name}\s+(\d+)\s*;(.*?)^END {name}\s*$", text, re.M | re.S)
    if not match:
        if required:
            raise ValueError(f"Missing DEF section {name}")
        return []
    records = re.findall(r"^\s*-\s+(.*?);", match[2], re.M | re.S)
    if len(records) != int(match[1]):
        raise ValueError(f"DEF {name}: expected {match[1]} records, got {len(records)}")
    return records


def parse_def(path):
    text = Path(path).read_text()
    design = re.search(r"^DESIGN\s+(\S+)\s*;", text, re.M)
    if not design:
        raise ValueError("Missing DEF DESIGN")
    instances, nets, ports = {}, {}, []
    for record in _section(text, "COMPONENTS"):
        name, master = record.split()[:2]
        name = canon_net_name(name)
        if name in instances:
            raise ValueError(f"Duplicate DEF component {name}")
        instances[name] = (canon_net_name(master), {})
    for record in _section(text, "PINS"):
        direction = re.search(r"\+\s+DIRECTION\s+(INPUT|OUTPUT|INOUT)\b", record)
        if not direction:
            raise ValueError(f"Missing DEF pin direction: {record[:80]}")
        ports.append((canon_net_name(record.split()[0]), direction[1]))
    for section in ("NETS", "SPECIALNETS"):
        for record in _section(text, section, required=section == "NETS"):
            net = canon_net_name(record.split()[0])
            endpoints = nets.setdefault(net, [])
            connections = record.split("+", 1)[0]
            for inst, pin in re.findall(r"\(\s*(\S+)\s+(\S+)\s*\)", connections):
                inst, pin = canon_net_name(inst), canon_net_name(pin)
                endpoints.append((inst, pin))
                if inst == "PIN":
                    if pin != net:
                        raise ValueError(f"Unsupported DEF top pin alias: {pin} -> {net}")
                    continue
                if inst == "*" and section == "SPECIALNETS":
                    for _, pinmap in instances.values():
                        if pin in pinmap and pinmap[pin] != net:
                            raise ValueError(f"Conflicting DEF global connection for {pin}")
                        pinmap[pin] = net
                    continue
                if inst not in instances:
                    raise ValueError(f"Unknown DEF component {inst} on {net}")
                pinmap = instances[inst][1]
                if pin in pinmap and pinmap[pin] != net:
                    raise ValueError(f"DEF pin {inst}/{pin} appears on two nets")
                pinmap[pin] = net
            # OpenROAD declares supply ports in Verilog but only special nets in DEF.
            if section == "SPECIALNETS" and re.search(r"\+\s+USE\s+(POWER|GROUND)\b", record):
                if net not in {name for name, _ in ports}:
                    ports.append((net, "INOUT"))
    return instances, nets, ports, canon_net_name(design[1])


def parse_verilog(path):
    text = Path(path).read_text()
    text = re.sub(r"/\*.*?\*/|//[^\n]*|\(\*.*?\*\)", "", text, flags=re.S)
    modules = re.findall(r"\bmodule\s+(\S+)\s*\(.*?\)\s*;(.*?)\bendmodule\b", text, re.S)
    if len(modules) != 1:
        raise ValueError("Expected exactly one flat non-ANSI Verilog module")
    design, body = modules[0]
    instances, nets, ports = {}, {}, []
    for statement in body.split(";"):
        statement = statement.strip()
        if not statement:
            continue
        decl = re.fullmatch(r"(input|output|inout|wire)\s+(.*)", statement, re.S)
        if decl:
            if decl[1] == "wire":
                continue
            names = decl[2].strip()
            bounds = re.match(r"\[\s*(\d+)\s*:\s*(\d+)\s*\]\s*", names)
            if bounds:
                names = names[bounds.end():]
            for name in names.split(","):
                name = canon_net_name(name)
                if bounds:
                    hi, lo = int(bounds[1]), int(bounds[2])
                    step = 1 if lo <= hi else -1
                    ports.extend((f"{name}[{i}]", decl[1].upper()) for i in range(lo, hi + step, step))
                else:
                    ports.append((name, decl[1].upper()))
            continue
        cell = re.fullmatch(r"(\S+)\s+(\S+)\s*\((.*)\)", statement, re.S)
        if not cell:
            raise ValueError(f"Unsupported structural Verilog statement: {statement[:120]}")
        master, inst, connections = cell.groups()
        inst = canon_net_name(inst)
        if inst in instances:
            raise ValueError(f"Duplicate Verilog instance {inst}")
        pinmap = {}
        for connection in (connections.split(",") if connections.strip() else []):
            pin = re.fullmatch(r"\s*\.(\w+)\s*\(\s*(.*?)\s*\)\s*", connection, re.S)
            if not pin or not re.fullmatch(r"(?:\\\S+\s*|[\w$]+)\s*(?:\[\s*\d+\s*\])?", pin[2]):
                raise ValueError(f"Unsupported Verilog pin connection: {connection[:120]}")
            net = canon_net_name(pin[2])
            if pin[1] in pinmap:
                raise ValueError(f"Duplicate Verilog pin {inst}/{pin[1]}")
            pinmap[pin[1]] = net
            nets.setdefault(net, []).append((inst, pin[1]))
        instances[inst] = (canon_net_name(master), pinmap)
    if not instances or not ports:
        raise ValueError("Empty structural Verilog design")
    return instances, nets, ports, canon_net_name(design)
