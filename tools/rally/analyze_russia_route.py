import json
import math
import numpy as np

def main():
    with open("game/data/rally/russia_stage1_route.json") as f:
        r = json.load(f)
    pts = np.array(r["points"])

    diffs = np.diff(pts, axis=0)
    seg_lens = np.linalg.norm(diffs, axis=1)
    dists = np.concatenate(([0.0], np.cumsum(seg_lens)))

    tangents = diffs / seg_lens[:, None]
    yaws = np.arctan2(tangents[:, 0], -tangents[:, 2])

    angle_diffs = np.diff(yaws)
    angle_diffs = (angle_diffs + np.pi) % (2 * np.pi) - np.pi

    print("Total route length:", dists[-1])
    print("Points count:", len(pts))

    curves = []
    in_curve = False
    cur_curve = {}
    for i in range(len(angle_diffs)):
        deg = math.degrees(angle_diffs[i])
        if abs(deg) > 2.0:
            if not in_curve:
                in_curve = True
                cur_curve = {
                    "start_idx": i,
                    "total_angle": 0.0,
                    "indices": [i]
                }
            cur_curve["total_angle"] += deg
            cur_curve["indices"].append(i)
        else:
            if in_curve:
                in_curve = False
                cur_curve["end_idx"] = i
                cur_curve["dist"] = dists[cur_curve["start_idx"]]
                cur_curve["len"] = dists[i] - dists[cur_curve["start_idx"]]
                if abs(cur_curve["total_angle"]) > 8.0:
                    curves.append(cur_curve)

    print(f"Detected {len(curves)} distinct curve zones:")
    for idx, c in enumerate(curves):
        direction = "left" if c["total_angle"] < 0 else "right"
        angle = abs(c["total_angle"])
        # Estimate radius R = arc_length / angle_in_radians
        rad = math.radians(angle)
        radius = c["len"] / rad if rad > 0 else 999.0
        
        # CMR2 turn scale:
        # 6: > 120m radius, slight bend (angle < 25 deg)
        # 5: ~80-120m radius (angle 25-45 deg)
        # 4: ~50-80m radius (angle 45-65 deg)
        # 3: ~30-50m radius (angle 65-85 deg)
        # 2: ~18-30m radius (angle 85-110 deg)
        # 1 / open hairpin: ~10-18m radius (angle 110-140 deg)
        # hairpin: < 10m radius or angle > 140 deg
        cmr_kind = 6
        if angle > 135:
            cmr_kind = 8 # hairpin
        elif angle > 110:
            cmr_kind = 7 # open hairpin
        elif angle > 80:
            cmr_kind = 6 # "one" in CMR2 kind mapping: 6 is "one", 5 is "two", 4 is "three", 3 is "four", 2 is "five", 1 is "six"
        elif angle > 60:
            cmr_kind = 5 # "two"
        elif angle > 45:
            cmr_kind = 4 # "three"
        elif angle > 30:
            cmr_kind = 3 # "four"
        elif angle > 18:
            cmr_kind = 2 # "five"
        else:
            cmr_kind = 1 # "six"

        names = {1: "six", 2: "five", 3: "four", 4: "three", 5: "two", 6: "one", 7: "openhairpin", 8: "hairpin"}
        print(f"Curve {idx:02d}: dist={c['dist']:6.1f}m..{c['dist']+c['len']:6.1f}m (pts {c['start_idx']}-{c['end_idx']}) | angle={angle:5.1f} deg {direction:5s} | len={c['len']:4.1f}m R={radius:4.1f}m -> CMR2 call: {names[cmr_kind]}")

if __name__ == "__main__":
    main()
