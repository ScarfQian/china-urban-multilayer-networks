#!/usr/bin/env python3
"""Compare recomputed outputs with reference numerical tables held locally."""
from __future__ import annotations

import argparse
from pathlib import Path
import sys

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src" / "python"))
from study_paths import study_path

TABLES = {
    "network_summary.csv": ("network", "network/revised_mrio4/single_layer_network_summary.csv"),
    "qap_2015.csv": ("network", "network/revised_mrio4/qap_results_2015_final.csv"),
    "qap_2020.csv": ("network", "network/revised_mrio4/qap_results_2020_final.csv"),
    "node_removal_auc.csv": ("network", "network/revised_mrio4/resilience_auc_summary.csv"),
    "layer_overlap.csv": ("network", "network/revised_multilayer_extension/layer_pair_overlap_summary.csv"),
    "unrestricted_frontier.csv": ("targeting", "network/revised_transition_pareto_extension/260810-transition_exact_frontier.csv"),
    "count_constrained_frontier.csv": ("targeting", "network/revised_transition_pareto_extension_v2/260810-transition_scope_capped_frontier.csv"),
    "integrated_attainment.csv": ("targeting", "network/revised_transition_pareto_extension_v2/260810-transition_integrated_frontier_attainment_summary.csv"),
    "unrestricted_cities_er095.csv": ("targeting", "network/revised_transition_pareto_extension/260810-transition_exact_frontier_city_selections.csv"),
    "count_constrained_cities_er095.csv": ("targeting", "network/revised_transition_pareto_extension_v2/260810-transition_scope_capped_city_selections.csv"),
    "carbon_reweighting.csv": ("python", "analysis/CarbonReweighting/260826-CarbonReweightingSummary.csv"),
    "structural_coefficients.csv": ("python", "analysis/UrbanStructure/260826-StructuralAssociationCoefficients.csv"),
    "clustered_coefficients.csv": ("python", "analysis/UrbanStructure/260827-ProvinceClusteredStructuralAssociationCoefficients.csv"),
}
TIMING_FIELDS = ("runtime", "run_time", "elapsed", "solver_node_count", "solver_nodecount", "work_units")


def compare(reference: Path, generated: Path) -> tuple[int, float]:
    expected = pd.read_csv(reference)
    actual = pd.read_csv(generated)
    if reference.name.endswith("_cities_er095.csv"):
        actual = actual.loc[np.isclose(actual["eta"], 0.95, rtol=0, atol=1e-10)]
        if "strategy" in actual:
            actual = actual.loc[actual["strategy"] == "carbon_burden_low_control"]
    columns = [
        name for name in expected.columns
        if not any(word in name.lower() for word in TIMING_FIELDS)
    ]
    missing = set(columns).difference(actual.columns)
    if missing:
        raise ValueError(f"Missing result columns: {sorted(missing)}")
    keys = [name for name in
            ("year", "eta", "strategy", "random_id", "repeat_id", "model",
             "model_name", "outcome", "predictor", "term", "city_code", "layer")
            if name in columns]
    if keys:
        expected = expected.sort_values(keys, kind="stable")
        actual = actual.sort_values(keys, kind="stable")
    expected = expected.reset_index(drop=True)
    actual = actual.reset_index(drop=True)
    if len(expected) != len(actual):
        raise ValueError(f"Row counts differ: {len(expected)} versus {len(actual)}")
    max_difference = 0.0
    tolerance = 1e-8 if "frontier" in reference.name or "attainment" in reference.name else 1e-10
    for name in columns:
        left, right = expected[name], actual[name]
        if pd.api.types.is_numeric_dtype(left):
            right = pd.to_numeric(right, errors="raise")
            a, b = left.to_numpy(dtype=float), right.to_numpy(dtype=float)
            if not np.allclose(a, b, rtol=0, atol=tolerance, equal_nan=True):
                raise ValueError(f"Numerical result differs in column {name}")
            finite = np.isfinite(a) & np.isfinite(b)
            if finite.any():
                max_difference = max(max_difference, float(np.max(np.abs(a[finite]-b[finite]))))
        elif not left.fillna("").astype(str).equals(right.fillna("").astype(str)):
            raise ValueError(f"Result labels differ in column {name}")
    return len(expected), max_difference


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--reference-root", type=Path, required=True,
        help="Local directory containing the study's reference numerical tables.",
    )
    parser.add_argument("--group", choices=("all", "network", "targeting", "python"), default="all")
    parser.add_argument("--output-root", type=Path, default=study_path("generated"))
    args = parser.parse_args()
    checked = 0
    for name, (group, relative) in TABLES.items():
        if args.group not in ("all", group):
            continue
        output = args.output_root / relative
        if not output.is_file():
            raise FileNotFoundError(f"Run the {group} stages first: {output}")
        rows, difference = compare(args.reference_root / name, output)
        print(f"{name}: {rows} rows agree; maximum absolute difference {difference:.3g}")
        checked += 1
    print(f"VERIFIED_TABLES={checked}")


if __name__ == "__main__":
    main()
