"""Run with klayout -b -r verify_gds_local.py; check exported GDS structure."""
from pathlib import Path
import hashlib
import json
import sys
import pya

flow = Path(__file__).resolve().parent
sys.path.insert(0, str(flow))
from lvs import parse_verilog

path = flow / "local/gds/SHA256_final.gds"
layout = pya.Layout()
layout.read(str(path))
top = layout.cell("SHA256")
if top is None or top.bbox().empty():
    raise ValueError("GDS top SHA256 is missing or empty")
if {cell.name for cell in layout.top_cells()} != {"SHA256"}:
    raise ValueError("Unexpected unreferenced GDS top cells")
instances = sum(max(1, inst.na) * max(1, inst.nb) for inst in top.each_inst())
expected = len(parse_verilog(flow / "local/route_repaired/SHA256_15ns_final.v")[0])
if instances != expected:
    raise ValueError(f"GDS instance count {instances} differs from final netlist {expected}")
result = {"top": top.name, "instances": instances, "dbu_um": layout.dbu,
          "bbox_um": [value * layout.dbu for value in
                      (top.bbox().left, top.bbox().bottom, top.bbox().right, top.bbox().top)],
          "bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
(path.parent / "validation.json").write_text(json.dumps(result, indent=2) + "\n")
print("GDS STRUCTURE CHECK PASSED")
print(json.dumps(result, indent=2))
