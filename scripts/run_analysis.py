#!/usr/bin/env python3
"""Run the Python numerical analyses after the MATLAB network stages."""
from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import sys


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "stage", nargs="?", default="all",
        choices=("all", "carbon", "structure", "inference"),
    )
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[1] / "src" / "python"
    stages = {
        "carbon": "carbon_reweighting.py",
        "structure": "urban_structure.py",
        "inference": "clustered_inference.py",
    }
    names = list(stages) if args.stage == "all" else [args.stage]
    for name in names:
        subprocess.run([sys.executable, str(source / stages[name])], check=True)


if __name__ == "__main__":
    main()
