"""Read-only spawn inventory around the position recorded by GAMEPLAY REPAIR."""
import argparse
from collections import Counter
import json
from math import dist
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--world", type=int, default=426)
parser.add_argument("--position", type=float, nargs=3, default=[4110.71, -658.6249, -5145.48])
args = parser.parse_args()
data_dir = Path(__file__).resolve().parents[1] / "apps/bezgelor_data/priv/data"
with (data_dir / "creature_spawns.json").open(encoding="utf-8") as source:
    data = json.load(source)
zone = next(zone for zone in data["zone_spawns"] if zone["world_id"] == args.world)
spawns = zone["creature_spawns"]
result = {"world_id": args.world, "zone_name": zone.get("zone_name"), "position": args.position,
          "total_spawns": len(spawns), "radii": {}}
for radius in [200, 500, 1000]:
    nearby = [spawn for spawn in spawns if dist(spawn["position"], args.position) <= radius]
    result["radii"][radius] = {"count": len(nearby),
        "faction1_counts": dict(sorted(Counter(spawn.get("faction1", 0) for spawn in nearby).items()))}
result["nearest_per_faction1"] = {}
for spawn in sorted(spawns, key=lambda spawn: dist(spawn["position"], args.position)):
    faction = spawn.get("faction1", 0)
    if faction not in result["nearest_per_faction1"]:
        result["nearest_per_faction1"][faction] = {"spawn_id": spawn["id"],
            "creature_id": spawn["creature_id"], "position": spawn["position"],
            "distance": round(dist(spawn["position"], args.position), 2)}
print(json.dumps(result, indent=2))
