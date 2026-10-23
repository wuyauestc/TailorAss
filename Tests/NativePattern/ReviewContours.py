#!/usr/bin/env python3
"""Plot contours exported by Smoke.swift; diagnostic, never an acceptance gate.

Coordinates are sampled by the production Swift geometry implementation in cm.
Point-to-segment distances compare geometric shape, independently of Bezier t.
The discrete result is not a certified continuous Hausdorff bound.
"""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


def directed_distance(points, path):
    starts, ends = path[:-1], path[1:]
    vectors = ends - starts
    squared_lengths = np.sum(vectors * vectors, axis=1)
    offsets = points[:, None, :] - starts[None, :, :]
    t = np.clip(np.sum(offsets * vectors[None, :, :], axis=2) /
                np.maximum(squared_lengths[None, :], 1e-300), 0, 1)
    distances = np.linalg.norm(offsets - t[:, :, None] * vectors[None, :, :], axis=2)
    return float(np.max(np.min(distances, axis=1)))


def review(path, output, metrics_only=False):
    record = json.loads(path.read_text())
    names = sorted(record["actual"])
    changed = []
    metrics = []
    for name in names:
        actual = [np.asarray(e) for e in record["actual"][name]]
        official = [np.asarray(e) for e in record["official"][name]]
        parameter_error = max(float(np.max(np.linalg.norm(a - b, axis=1)))
                              for a, b in zip(actual, official))
        shape_error = max(max(directed_distance(a, b), directed_distance(b, a))
                          for a, b in zip(actual, official))
        metrics.append({"panel": name, "sampled_shape_distance_cm": shape_error,
                        "same_parameter_distance_cm": parameter_error})
        if parameter_error > 1e-5:
            changed.append(name)
    selected = changed or names
    output.mkdir(parents=True, exist_ok=True)
    summary = {"case": record["case"], "units": "cm", "panels": metrics,
               "diagnostic_only": True}
    (output / (path.stem + "-metrics.json")).write_text(json.dumps(summary, indent=2) + "\n")
    if metrics_only:
        print(json.dumps(summary))
        return
    fig, axes = plt.subplots((len(selected) + 1) // 2, 2,
                             figsize=(11, 4.5 * ((len(selected) + 1) // 2)), squeeze=False)
    for ax, name in zip(axes.flat, selected):
        for index, edge in enumerate(record["official"][name]):
            p = np.asarray(edge)
            ax.plot(p[:, 0], p[:, 1], color="#db762c", linestyle="--", linewidth=1.8,
                    label="Official" if index == 0 else None)
        for index, edge in enumerate(record["actual"][name]):
            p = np.asarray(edge)
            ax.plot(p[:, 0], p[:, 1], color="#1767a6", linewidth=1,
                    label="Native Swift" if index == 0 else None)
        item = next(m for m in metrics if m["panel"] == name)
        ax.set_title(f"{name}\nSampled shape distance: {item['sampled_shape_distance_cm'] * 10:.3f} mm")
        ax.set_aspect("equal", adjustable="datalim")
        ax.set_xlabel("cm")
        ax.set_ylabel("cm")
        ax.grid(alpha=0.2)
        ax.legend()
    for ax in list(axes.flat)[len(selected):]:
        ax.set_visible(False)
    fig.suptitle(record["case"] + " — model-space contour review")
    fig.tight_layout()
    output.mkdir(parents=True, exist_ok=True)
    fig.savefig(output / (path.stem + ".png"), dpi=160)
    plt.close(fig)
    print(json.dumps(summary))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", type=Path, nargs="+")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--metrics-only", action="store_true")
    args = parser.parse_args()
    for input_path in args.inputs:
        review(input_path, args.output, args.metrics_only)
