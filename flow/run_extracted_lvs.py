"""Compare unmodified Magic geometry extraction to post-route schematic SPICE."""
from pathlib import Path
import os
import re
import subprocess

from lvs import parse_verilog
from run_lvs_15ns import parse_libcdl, report_matches

FLOW = Path(__file__).resolve().parent
OUT = Path(os.environ.get("LVS_OUTPUT_DIR", FLOW / "local" / "extracted_lvs")).resolve()


def main():
    pdk = Path(os.environ.get("PDK_ROOT", "/usr/local/share/pdk")) / "sky130A"
    library = pdk / "libs.ref/sky130_fd_sc_hd/spice/sky130_fd_sc_hd.spice"
    setup = pdk / "libs.tech/netgen/sky130A_setup.tcl"
    layout = OUT / "layout.spice"
    extracted = layout.read_text()
    if not re.search(r"^\.subckt\s+SHA256\b", extracted, re.I | re.M):
        raise ValueError("Magic extraction did not define SHA256")
    if not re.search(r"^X\S+.*sky130_fd_pr__(?:nfet|pfet)", extracted, re.I | re.M):
        raise ValueError("No extracted transistor devices found; refusing abstract-only LVS")
    source = Path(os.environ.get("LVS_SOURCE_DIR", FLOW / "local" / "lvs_connected"))
    instances, nets, ports, design = parse_verilog(source / "SHA256_15ns_final.v")
    library_ports = parse_libcdl(library)
    top_ports = [name for name, _ in ports]
    for supply in ("VDD", "VSS"):
        if supply not in nets:
            raise ValueError(f"Missing explicit schematic supply {supply}")
        if supply not in top_ports:
            top_ports.append(supply)
    schematic = OUT / "schematic.spice"
    lines = [f'.include "{library}"', '.subckt ' + design + ' ' + ' '.join(top_ports)]
    for name, (master, pins) in instances.items():
        if master not in library_ports:
            raise ValueError(f"Missing library circuit definition for {master}")
        order = library_ports[master]
        if set(pins) - set(order):
            raise ValueError(f"Unexpected schematic pins on {name}/{master}")
        nodes = []
        for pin in order:
            if pin in pins:
                nodes.append(pins[pin])
            elif pin in ("VGND", "VNB", "VPWR", "VPB"):
                raise ValueError(f"Missing schematic supply {name}/{pin}")
            else:
                nodes.append(f"__OPEN_{name}_{pin}")
        lines.append('X' + name + ' ' + ' '.join(nodes) + ' ' + master)
    lines.append('.ends ' + design)
    schematic.write_text('\n'.join(lines) + '\n')
    report = OUT / "lvs.report"
    if report.exists():
        report.unlink()
    print(f"Schematic generated from {len(instances)} instances, including physical cells", flush=True)
    command = [os.environ.get("NETGEN", "netgen"), "-batch", "lvs",
               f"{layout} SHA256", f"{schematic} SHA256", str(setup), str(report)]
    result = subprocess.run(command, cwd=OUT)
    if result.returncode:
        return result.returncode
    if not report.exists() or not report_matches(report.read_text()):
        print("FAIL: extracted layout does not match schematic; see local/extracted_lvs/lvs.report")
        return 1
    print("PASS: Magic-extracted layout matches schematic")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
