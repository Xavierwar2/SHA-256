"""Create annotated scientific plots from native OpenROAD heatmap CSV data."""
from pathlib import Path
import csv
import math
import re
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import PatchCollection
from matplotlib.patches import Rectangle

out = Path(__file__).resolve().parent / "local/heatmaps"
maps = {
    "placement_density": "Placement density",
    "pin_density": "Pin density",
    "power_density": "Power density (default switching activity)",
    "estimated_congestion": "Estimated congestion (RUDY)",
    "routing_congestion": "Routing congestion",
    "ir_drop_VDD": "VDD static IR drop (met1)",
    "ir_drop_VSS": "VSS static voltage rise (met1)",
}
for name, title in maps.items():
    with (out / f"{name}.csv").open() as f:
        reader = csv.reader(f)
        header = next(reader)
        rows = [tuple(map(float, row)) for row in reader if row]
    if not rows or any(not all(math.isfinite(v) for v in row) for row in rows):
        raise ValueError(f"Missing or invalid heatmap values in {name}")
    patches = [Rectangle((x0, y0), x1-x0, y1-y0) for x0, y0, x1, y1, _ in rows]
    factor = 1
    if name.startswith("ir_drop"):
        csv_unit = re.search(r"\(([^)]+)\)", header[-1]).group(1)
        factor = {"V": 1000, "mV": 1, "uV": 0.001, "µV": 0.001}[csv_unit]
    values = [row[-1] * factor for row in rows]
    unit = "IR drop (mV)" if name.startswith("ir_drop") else header[-1].replace("value", "Value").replace("uW", "µW")
    figure, axes = plt.subplots(figsize=(8, 7), layout="constrained")
    collection = PatchCollection(patches, cmap="viridis", edgecolor="none")
    collection.set_array(values)
    collection.set_clim(0, max(values) if max(values) > 0 else 1)
    axes.add_collection(collection)
    axes.set(xlim=(0,600), ylim=(0,600), xlabel="X (µm)", ylabel="Y (µm)", title=title)
    axes.set_aspect("equal")
    axes.set_facecolor("#eeeeee")
    figure.colorbar(collection, ax=axes, label=unit, shrink=0.9)
    figure.savefig(out / f"{name}_plot.png", dpi=200)
    plt.close(figure)
    print(f"Saved {name}_plot.png; data range {min(values):.6g} to {max(values):.6g} {unit}")
