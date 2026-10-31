#!/usr/bin/env python3
"""Generates publication-quality charts for the Meta Hackathon video demo and presentation.

Visualizes:
  1. Model Shootout: Muse Spark vs. Muse Wonder vs. LEGATO vs. Hybrid (Note Acc % & Bar Exact Match %)
  2. The Last-Mile Breakdown: How CV notehead alignment eliminates pitch drift
  3. Latency vs. Accuracy Pareto Frontier

Usage:
    ~/.local/bin/uv run --with matplotlib --with numpy python3 scripts/generate_omr_charts.py
"""
import os
from pathlib import Path
import matplotlib.pyplot as plt
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / ".build" / "eval_charts"
OUT_DIR.mkdir(parents=True, exist_ok=True)

# Set clean aesthetic styling
plt.style.use("seaborn-v0_8-whitegrid" if "seaborn-v0_8-whitegrid" in plt.style.available else "default")
plt.rcParams.update({
    "font.size": 12,
    "axes.labelsize": 13,
    "axes.titlesize": 15,
    "xtick.labelsize": 11,
    "ytick.labelsize": 11,
    "legend.fontsize": 11,
    "figure.titlesize": 16,
    "font.family": "sans-serif",
})

# Meta brand colors
META_BLUE = "#0081FB"
META_SKY = "#00C4FF"
META_PURPLE = "#7542FF"
GREEN = "#00A86B"
ORANGE = "#FF8C00"
GRAY = "#707E94"
DARK = "#1C2B33"


def chart_model_shootout():
    """Figure 1: Benchmark Shootout across historical 1895 scan and modern re-engraving."""
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))

    models = [
        "LEGATO\n(Llama 3.2)",
        "Muse Spark 1.3\n(Meta)",
        "Muse Wonder 1.0\n(Meta)",
        "Wonder + CV\n(Hybrid)"
    ]

    # Data: Note Accuracy (%)
    # LEGATO: 0% on 1895 vintage crop (OOD loop); 100.0% on clean modern vector score
    scan_note_acc = [0.0, 47.1, 87.7, 94.8]
    modern_note_acc = [100.0, 69.7, 88.4, 100.0]

    # Data: Bar Exact Match (%)
    scan_bem = [0.0, 14.3, 71.4, 80.4]
    modern_bem = [100.0, 39.3, 67.9, 83.9]

    x = np.arange(len(models))
    width = 0.35

    # Subplot 1: Note Accuracy
    rects1 = ax1.bar(x - width/2, scan_note_acc, width, label="1895 Historic Scan", color=GRAY, alpha=0.85)
    rects2 = ax1.bar(x + width/2, modern_note_acc, width, label="Modern Score", color=META_BLUE, alpha=0.95)
    ax1.set_ylabel("Note Accuracy (%)")
    ax1.set_title("Note-Level Accuracy (Pitch + Duration)", fontweight="bold")
    ax1.set_xticks(x)
    ax1.set_xticklabels(models)
    ax1.set_ylim(0, 115)
    ax1.axhline(90, color="gray", linestyle="--", alpha=0.5, label="High-Fidelity Threshold (90%)")
    ax1.legend(loc="upper left")

    # Add data labels
    for rect in rects1 + rects2:
        h = rect.get_height()
        label = f"{h:.1f}%" if h > 0 else "0% (loop)"
        ax1.annotate(label, xy=(rect.get_x() + rect.get_width() / 2, max(h, 2)),
                     xytext=(0, 4), textcoords="offset points", ha="center", va="bottom",
                     fontsize=10, fontweight="bold", color=DARK if h > 0 else "#CC0000")

    # Subplot 2: Bar Exact Match
    rects3 = ax2.bar(x - width/2, scan_bem, width, label="1895 Historic Scan", color=GRAY, alpha=0.85)
    rects4 = ax2.bar(x + width/2, modern_bem, width, label="Modern Score", color=GREEN, alpha=0.95)
    ax2.set_ylabel("Bar Exact Match (%)")
    ax2.set_title("Bar Exact Match Rate (100% Both Hands)", fontweight="bold")
    ax2.set_xticks(x)
    ax2.set_xticklabels(models)
    ax2.set_ylim(0, 115)
    ax2.legend(loc="upper left")

    for rect in rects3 + rects4:
        h = rect.get_height()
        label = f"{h:.1f}%" if h > 0 else "0% (loop)"
        ax2.annotate(label, xy=(rect.get_x() + rect.get_width() / 2, max(h, 2)),
                     xytext=(0, 4), textcoords="offset points", ha="center", va="bottom",
                     fontsize=10, fontweight="bold", color=DARK if h > 0 else "#CC0000")

    plt.suptitle("OMR Benchmark: Meta Model Shootout (Historical Scans vs. Modern Scores)", fontsize=16, fontweight="bold", y=1.02)
    plt.tight_layout()
    p_png = OUT_DIR / "omr_model_shootout.png"
    p_svg = OUT_DIR / "omr_model_shootout.svg"
    plt.savefig(p_png, dpi=300, bbox_inches="tight")
    plt.savefig(p_svg, bbox_inches="tight")
    plt.close()
    print(f"Saved {p_png}")


def chart_error_ablation():
    """Figure 2: The Last Mile: Pitch Correction via Notehead Alignment."""
    fig, ax = plt.subplots(figsize=(10, 5))

    conditions = ["1895 Historical Scan", "Modern Digital Score"]
    raw_wonder_acc = [87.7, 88.4]
    hybrid_wonder_acc = [94.8, 100.0]

    x = np.arange(len(conditions))
    width = 0.35

    b1 = ax.bar(x - width/2, raw_wonder_acc, width, label="Muse Wonder 1.0 (Alone)", color=META_BLUE, alpha=0.85)
    b2 = ax.bar(x + width/2, hybrid_wonder_acc, width, label="Muse Wonder + CV Alignment (Hybrid)", color=GREEN, alpha=0.95)

    ax.set_ylabel("Note Accuracy (%)")
    ax.set_title("The 'Last Mile' Breakthrough: Hybrid Geometric Alignment", fontweight="bold")
    ax.set_xticks(x)
    ax.set_xticklabels(conditions)
    ax.set_ylim(70, 105)
    ax.legend(loc="lower right")

    for rect in b1:
        h = rect.get_height()
        ax.annotate(f"{h:.1f}%\n(Raw)", xy=(rect.get_x() + rect.get_width() / 2, h),
                    xytext=(0, 4), textcoords="offset points", ha="center", va="bottom", fontsize=11)

    for rect in b2:
        h = rect.get_height()
        ax.annotate(f"{h:.1f}%\n(+Pitch Fusion)", xy=(rect.get_x() + rect.get_width() / 2, h),
                    xytext=(0, 4), textcoords="offset points", ha="center", va="bottom", fontsize=11, fontweight="bold", color="#006633")

    plt.tight_layout()
    p_png = OUT_DIR / "hybrid_ablation_breakthrough.png"
    plt.savefig(p_png, dpi=300, bbox_inches="tight")
    plt.close()
    print(f"Saved {p_png}")


def chart_pareto_efficiency():
    """Figure 3: Pareto Frontier (Accuracy vs. Latency)."""
    fig, ax = plt.subplots(figsize=(10, 6))

    points = [
        {"name": "LEGATO (1895 Crop)", "acc": 0.0, "lat": 42.0, "color": GRAY, "marker": "X"},
        {"name": "LEGATO (Modern Score)", "acc": 100.0, "lat": 9.3, "color": META_PURPLE, "marker": "D"},
        {"name": "Muse Spark 1.3 (Modern)", "acc": 69.7, "lat": 25.0, "color": ORANGE, "marker": "o"},
        {"name": "Muse Spark 1.3 (Scan)", "acc": 47.1, "lat": 47.0, "color": ORANGE, "marker": "s"},
        {"name": "Muse Wonder 1.0 (Modern)", "acc": 88.4, "lat": 48.0, "color": META_BLUE, "marker": "o"},
        {"name": "Muse Wonder 1.0 (Scan)", "acc": 87.7, "lat": 126.0, "color": META_BLUE, "marker": "s"},
        {"name": "Hybrid Wonder + CV (Modern)", "acc": 100.0, "lat": 50.0, "color": GREEN, "marker": "*"},
        {"name": "Hybrid Wonder + CV (Scan)", "acc": 94.8, "lat": 128.0, "color": GREEN, "marker": "P"},
    ]

    for p in points:
        ax.scatter(p["lat"], p["acc"], color=p["color"], marker=p["marker"], s=180, label=p["name"],
                   edgecolors="black" if p["marker"] != "X" else None, linewidth=1.2)
        offset = (8, -4) if "Scan" in p["name"] or "Crop" in p["name"] else (8, 4)
        ax.annotate(p["name"], (p["lat"], p["acc"]), xytext=offset, textcoords="offset points", fontsize=10, fontweight="bold")

    ax.set_xlabel("Latency (Seconds per System / Page)")
    ax.set_ylabel("Note Accuracy (%)")
    ax.set_title("OMR Pareto Frontier: Latency vs. Accuracy", fontweight="bold")
    ax.set_ylim(-8, 115)
    ax.set_xlim(0, 155)
    ax.grid(True, linestyle="--", alpha=0.6)

    # Highlight optimal region
    ax.axhspan(90, 108, color=GREEN, alpha=0.1, label="Playable Quality Zone (>=90%)")
    ax.legend(loc="lower right", framealpha=0.9)

    plt.tight_layout()
    p_png = OUT_DIR / "omr_pareto_frontier.png"
    plt.savefig(p_png, dpi=300, bbox_inches="tight")
    plt.close()
    print(f"Saved {p_png}")


if __name__ == "__main__":
    chart_model_shootout()
    chart_error_ablation()
    chart_pareto_efficiency()
    print("All charts generated successfully in", OUT_DIR)
