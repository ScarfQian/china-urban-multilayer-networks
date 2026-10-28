#!/usr/bin/env python3
"""Compare production-flow and carbon-flow weights and city positions."""

from __future__ import annotations

import argparse
from pathlib import Path

from study_paths import study_path

import numpy as np
import pandas as pd


YEARS = (2015, 2020)
N_CITIES = 309
TOP_CORRIDORS_PER_TAIL = 15
TOP_CITIES_PER_TAIL = 10
EXPECTED_PRODUCTION_EDGES = {2015: 95_149, 2020: 95_172}
EXPECTED_CARBON_EDGES = {2015: 94_841, 2020: 94_864}
EXPECTED_BACKBONE_EDGES = {2015: 30_849, 2020: 47_883}


def require_files(paths: list[Path]) -> None:
    missing = [path for path in paths if not path.is_file()]
    if missing:
        formatted = "\n".join(f"- {path}" for path in missing)
        raise FileNotFoundError(f"Required final-freeze files are missing:\n{formatted}")


def percentile_rank(values: pd.Series) -> pd.Series:
    """Return average-rank percentiles on [0, 1], including both endpoints."""
    if len(values) <= 1:
        return pd.Series(np.zeros(len(values)), index=values.index, dtype=float)
    ranks = values.rank(method="average", ascending=True)
    return (ranks - 1.0) / (len(values) - 1.0)


def load_city_table(path: Path) -> pd.DataFrame:
    city = pd.read_csv(path)
    required = {
        "city_id",
        "city_code",
        "city_name_std",
        "city_name_en",
        "province_code",
        "province_name_std",
        "included_in_sample",
    }
    missing = sorted(required.difference(city.columns))
    if missing:
        raise ValueError(f"{path} is missing columns: {missing}")
    city = city.loc[city["included_in_sample"] == 1].copy()
    city = city.sort_values("city_id").reset_index(drop=True)
    if len(city) != N_CITIES or city["city_code"].nunique() != N_CITIES:
        raise ValueError(f"Expected {N_CITIES} aligned cities, found {len(city)} rows.")
    if city["city_name_en"].isna().any() or city["city_name_en"].astype(str).str.strip().eq("").any():
        raise ValueError("English city names are incomplete in city_alignment_report.csv.")
    return city


def load_edge_table(path: Path, weight_name: str) -> pd.DataFrame:
    table = pd.read_csv(path)
    required = {
        "source_city_code",
        "target_city_code",
        "source_city_name",
        "target_city_name",
        "weight",
    }
    missing = sorted(required.difference(table.columns))
    if missing:
        raise ValueError(f"{path} is missing columns: {missing}")
    table = table.loc[:, sorted(required)].copy()
    table["source_city_code"] = table["source_city_code"].astype(int)
    table["target_city_code"] = table["target_city_code"].astype(int)
    table["weight"] = pd.to_numeric(table["weight"], errors="raise")
    if (table["weight"] <= 0).any():
        raise ValueError(f"{path} contains non-positive stored edge weights.")
    if table.duplicated(["source_city_code", "target_city_code"]).any():
        raise ValueError(f"{path} contains duplicate directed city pairs.")
    return table.rename(columns={"weight": weight_name})


def load_backbone_pairs(path: Path) -> pd.DataFrame:
    table = pd.read_csv(path)
    required = {"variant", "source_city_code", "target_city_code"}
    missing = sorted(required.difference(table.columns))
    if missing:
        raise ValueError(f"{path} is missing columns: {missing}")
    table = table.loc[table["variant"] == "cumulative_flow_share", list(required)].copy()
    table["source_city_code"] = table["source_city_code"].astype(int)
    table["target_city_code"] = table["target_city_code"].astype(int)
    if table.duplicated(["source_city_code", "target_city_code"]).any():
        raise ValueError(f"{path} contains duplicate cumulative-flow backbone pairs.")
    return table.drop(columns="variant")


def source_paths(final_freeze_dir: Path, year: int) -> dict[str, Path]:
    base = final_freeze_dir / "revised_mrio4"
    transition = final_freeze_dir / "revised_transition"
    return {
        "alignment": base / "city_alignment_report.csv",
        "production_edges": base / "layers" / f"economic_layer_edges_{year}.csv",
        "carbon_edges": base / "layers" / f"carbon_layer_edges_{year}.csv",
        "production_backbone": base / "backbones" / f"backbone_edges_E_{year}.csv",
        "governance": transition / f"governance_mismatch_metrics_{year}.csv",
    }


def analyze_year(
    year: int,
    city: pd.DataFrame,
    paths: dict[str, Path],
) -> tuple[
    pd.DataFrame,
    pd.DataFrame,
    pd.DataFrame,
    pd.DataFrame,
    pd.DataFrame,
    dict[str, object],
]:
    production = load_edge_table(paths["production_edges"], "production_flow")
    carbon = load_edge_table(paths["carbon_edges"], "carbon_flow")
    backbone_pairs = load_backbone_pairs(paths["production_backbone"])

    city_codes = set(city["city_code"].astype(int))
    for label, table in (("production", production), ("carbon", carbon)):
        observed = set(table["source_city_code"]) | set(table["target_city_code"])
        unknown = sorted(observed.difference(city_codes))
        if unknown:
            raise ValueError(f"{year} {label} edges contain unknown city codes: {unknown[:5]}")

    pair_cols = ["source_city_code", "target_city_code"]
    carbon_only = carbon.merge(production[pair_cols], on=pair_cols, how="left", indicator=True)
    carbon_only_count = int((carbon_only["_merge"] == "left_only").sum())
    if carbon_only_count:
        raise ValueError(f"{year} has {carbon_only_count} carbon edges without production support.")

    carbon_values = carbon[pair_cols + ["carbon_flow"]]
    corridor = production.merge(carbon_values, on=pair_cols, how="left", validate="one_to_one")
    corridor["carbon_flow"] = corridor["carbon_flow"].fillna(0.0)
    corridor["year"] = year

    total_production = float(corridor["production_flow"].sum())
    total_carbon = float(corridor["carbon_flow"].sum())
    if total_production <= 0 or total_carbon <= 0:
        raise ValueError(f"{year} layer totals must be positive.")

    national_qbar = total_carbon / total_production
    corridor["effective_carbon_intensity"] = corridor["carbon_flow"] / corridor["production_flow"]
    corridor["production_flow_share"] = corridor["production_flow"] / total_production
    corridor["carbon_flow_share"] = corridor["carbon_flow"] / total_carbon
    positive_carbon = corridor["carbon_flow"] > 0
    corridor["corridor_amplification_log"] = -np.inf
    corridor.loc[positive_carbon, "corridor_amplification_log"] = np.log(
        corridor.loc[positive_carbon, "effective_carbon_intensity"] / national_qbar
    )
    corridor["zero_carbon_flag"] = (~positive_carbon).astype(int)

    share_ratio_log = np.log(
        corridor.loc[positive_carbon, "carbon_flow_share"]
        / corridor.loc[positive_carbon, "production_flow_share"]
    )
    share_ratio_max_abs_diff = float(
        np.max(
            np.abs(
                share_ratio_log.to_numpy()
                - corridor.loc[positive_carbon, "corridor_amplification_log"].to_numpy()
            )
        )
    )

    corridor = corridor.merge(
        backbone_pairs.assign(in_production_cumulative_backbone=1),
        on=pair_cols,
        how="left",
        validate="one_to_one",
    )
    corridor["in_production_cumulative_backbone"] = (
        corridor["in_production_cumulative_backbone"].fillna(0).astype(int)
    )
    backbone = corridor.loc[corridor["in_production_cumulative_backbone"] == 1].copy()

    finite_backbone = backbone.loc[np.isfinite(backbone["corridor_amplification_log"])].copy()
    amplified = finite_backbone.nlargest(TOP_CORRIDORS_PER_TAIL, "corridor_amplification_log").copy()
    amplified["tail"] = "amplified"
    amplified["tail_rank"] = np.arange(1, len(amplified) + 1)
    attenuated = finite_backbone.nsmallest(TOP_CORRIDORS_PER_TAIL, "corridor_amplification_log").copy()
    attenuated["tail"] = "attenuated"
    attenuated["tail_rank"] = np.arange(1, len(attenuated) + 1)
    corridor_extremes = pd.concat([amplified, attenuated], ignore_index=True)

    city_result = city.loc[
        :,
        [
            "city_id",
            "city_code",
            "city_name_std",
            "city_name_en",
            "province_code",
            "province_name_std",
        ],
    ].copy()
    production_out = corridor.groupby("source_city_code")["production_flow"].sum()
    carbon_out = corridor.groupby("source_city_code")["carbon_flow"].sum()
    city_result["year"] = year
    city_result["production_out_strength"] = city_result["city_code"].map(production_out).fillna(0.0)
    city_result["carbon_out_burden"] = city_result["city_code"].map(carbon_out).fillna(0.0)
    city_result["outward_effective_carbon_intensity"] = np.divide(
        city_result["carbon_out_burden"],
        city_result["production_out_strength"],
        out=np.zeros(len(city_result), dtype=float),
        where=city_result["production_out_strength"].to_numpy() > 0,
    )
    city_result["production_position_percentile"] = percentile_rank(
        city_result["production_out_strength"]
    )
    city_result["carbon_burden_percentile"] = percentile_rank(city_result["carbon_out_burden"])
    city_result["position_shift_percentile"] = (
        city_result["carbon_burden_percentile"]
        - city_result["production_position_percentile"]
    )
    city_result["position_shift_percentage_points"] = 100.0 * city_result[
        "position_shift_percentile"
    ]
    city_result["production_flow_share"] = city_result["production_out_strength"] / total_production
    city_result["carbon_burden_share"] = city_result["carbon_out_burden"] / total_carbon

    identity_reconstructed = (
        city_result["production_out_strength"]
        * city_result["outward_effective_carbon_intensity"]
    )
    city_identity_max_abs_diff = float(
        np.max(np.abs(identity_reconstructed - city_result["carbon_out_burden"]))
    )
    city_identity_scale = max(float(city_result["carbon_out_burden"].max()), 1.0)
    city_identity_max_relative_diff = city_identity_max_abs_diff / city_identity_scale

    governance = pd.read_csv(paths["governance"])
    required_governance = {"city_code", "PC_share", "CB_share"}
    missing_governance = sorted(required_governance.difference(governance.columns))
    if missing_governance:
        raise ValueError(f"{paths['governance']} is missing columns: {missing_governance}")
    governance = governance.loc[:, ["city_code", "PC_share", "CB_share"]].copy()
    if len(governance) != N_CITIES or governance["city_code"].nunique() != N_CITIES:
        raise ValueError(f"{year} governance table does not contain {N_CITIES} unique cities.")
    checked = city_result.merge(governance, on="city_code", how="left", validate="one_to_one")
    if checked[["PC_share", "CB_share"]].isna().any().any():
        raise ValueError(f"{year} governance shares are incomplete after city alignment.")
    pc_share_max_abs_diff = float(
        np.max(np.abs(checked["production_flow_share"] - checked["PC_share"]))
    )
    cb_share_max_abs_diff = float(
        np.max(np.abs(checked["carbon_burden_share"] - checked["CB_share"]))
    )

    positive_shift = city_result.nlargest(TOP_CITIES_PER_TAIL, "position_shift_percentage_points").copy()
    positive_shift["tail"] = "carbon_burden_position_higher"
    positive_shift["tail_rank"] = np.arange(1, len(positive_shift) + 1)
    negative_shift = city_result.nsmallest(TOP_CITIES_PER_TAIL, "position_shift_percentage_points").copy()
    negative_shift["tail"] = "production_position_higher"
    negative_shift["tail_rank"] = np.arange(1, len(negative_shift) + 1)
    city_extremes = pd.concat([positive_shift, negative_shift], ignore_index=True)

    summary = {
        "year": year,
        "city_count": len(city_result),
        "production_edge_count": len(corridor),
        "carbon_positive_edge_count": int(positive_carbon.sum()),
        "zero_carbon_production_edge_count": int((~positive_carbon).sum()),
        "production_cumulative_backbone_edges": len(backbone),
        "total_production_flow": total_production,
        "total_carbon_flow": total_carbon,
        "national_effective_carbon_intensity": national_qbar,
        "all_positive_edge_median_ca": float(
            corridor.loc[positive_carbon, "corridor_amplification_log"].median()
        ),
        "backbone_positive_edge_median_ca": float(
            finite_backbone["corridor_amplification_log"].median()
        ),
        "backbone_share_ca_positive": float(
            (finite_backbone["corridor_amplification_log"] > 0).mean()
        ),
        "city_out_strength_spearman": float(
            city_result[["production_out_strength", "carbon_out_burden"]]
            .corr(method="spearman")
            .iloc[0, 1]
        ),
        "position_shift_min_pp": float(city_result["position_shift_percentage_points"].min()),
        "position_shift_max_pp": float(city_result["position_shift_percentage_points"].max()),
        "share_ratio_identity_max_abs_diff": share_ratio_max_abs_diff,
        "city_outward_identity_max_relative_diff": city_identity_max_relative_diff,
        "pc_share_max_abs_diff": pc_share_max_abs_diff,
        "cb_share_max_abs_diff": cb_share_max_abs_diff,
        "carbon_only_edge_count": carbon_only_count,
    }
    return corridor, backbone, corridor_extremes, city_result, city_extremes, summary


def format_corridor(row: pd.Series) -> str:
    return (
        f"{row['source_city_name_en']} -> {row['target_city_name_en']} "
        f"(CA={row['corridor_amplification_log']:.3f})"
    )


def format_city(row: pd.Series) -> str:
    return f"{row['city_name_en']} ({row['position_shift_percentage_points']:+.1f} pp)"


def replicated_city_shift_table(city_extremes: pd.DataFrame) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    for tail in city_extremes["tail"].unique():
        blocks = {
            year: city_extremes.loc[
                (city_extremes["year"] == year) & (city_extremes["tail"] == tail)
            ].set_index("city_code")
            for year in YEARS
        }
        shared_codes = sorted(set(blocks[2015].index).intersection(blocks[2020].index))
        for city_code in shared_codes:
            row_2015 = blocks[2015].loc[city_code]
            row_2020 = blocks[2020].loc[city_code]
            rows.append(
                {
                    "tail": tail,
                    "city_code": city_code,
                    "city_name_en": row_2020["city_name_en"],
                    "position_shift_2015_pp": row_2015["position_shift_percentage_points"],
                    "position_shift_2020_pp": row_2020["position_shift_percentage_points"],
                    "tail_rank_2015": int(row_2015["tail_rank"]),
                    "tail_rank_2020": int(row_2020["tail_rank"]),
                }
            )
    return pd.DataFrame(rows)


def write_audit(
    output_path: Path,
    final_freeze_dir: Path,
    result_dir: Path,
    summaries: pd.DataFrame,
    corridor_extremes: pd.DataFrame,
    city_extremes: pd.DataFrame,
    replicated_city_shifts: pd.DataFrame,
    source_file_rows: list[tuple[int, str, Path]],
) -> None:
    checks: list[tuple[str, bool, str]] = []
    for row in summaries.itertuples(index=False):
        year = int(row.year)
        checks.extend(
            [
                (f"{year} city count", row.city_count == N_CITIES, str(row.city_count)),
                (
                    f"{year} production edges",
                    row.production_edge_count == EXPECTED_PRODUCTION_EDGES[year],
                    str(row.production_edge_count),
                ),
                (
                    f"{year} carbon-positive edges",
                    row.carbon_positive_edge_count == EXPECTED_CARBON_EDGES[year],
                    str(row.carbon_positive_edge_count),
                ),
                (
                    f"{year} production cumulative backbone edges",
                    row.production_cumulative_backbone_edges == EXPECTED_BACKBONE_EDGES[year],
                    str(row.production_cumulative_backbone_edges),
                ),
                (
                    f"{year} corridor share-ratio identity",
                    row.share_ratio_identity_max_abs_diff <= 1e-12,
                    f"max abs diff={row.share_ratio_identity_max_abs_diff:.3e}",
                ),
                (
                    f"{year} city outward identity",
                    row.city_outward_identity_max_relative_diff <= 1e-12,
                    f"max relative diff={row.city_outward_identity_max_relative_diff:.3e}",
                ),
                (
                    f"{year} PC_share reproduction",
                    row.pc_share_max_abs_diff <= 1e-12,
                    f"max abs diff={row.pc_share_max_abs_diff:.3e}",
                ),
                (
                    f"{year} CB_share reproduction",
                    row.cb_share_max_abs_diff <= 1e-12,
                    f"max abs diff={row.cb_share_max_abs_diff:.3e}",
                ),
                (
                    f"{year} carbon support subset",
                    row.carbon_only_edge_count == 0,
                    f"carbon-only edges={row.carbon_only_edge_count}",
                ),
            ]
        )
    overall = all(passed for _, passed, _ in checks)

    lines = [
        "# Carbon-Intensity Reweighting Analysis Audit",
        "",
        "Date: 2026-08-26  ",
        "Creator: **ScarfQian**",
        "",
        "## Scientific definition",
        "",
        "The analysis compares each positive intercity production flow with its frozen carbon-weighted counterpart. Corridor amplification is `CA = log[(W_C/W_E)/qbar]`, where `qbar` is the national production-flow-weighted carbon intensity in the same year. The city position shift is the within-year percentile of outward carbon burden minus the percentile of outward production flow.",
        "",
        "All positive production edges enter the calculations. The display subset was fixed before execution as the 95% cumulative production-flow backbone. Corridor tables retain the 15 largest and 15 smallest finite CA values per year. City tables retain the 10 largest positive and 10 largest negative percentile shifts per year.",
        "",
        "## Input boundary",
        "",
        f"- Final-freeze root: `{final_freeze_dir}`",
        "- City sample: 309 aligned cities",
        "- Years: 2015 and 2020, analysed separately",
        "- External data: none",
        "- Upstream network reconstruction: not run",
        "",
        "### Source files",
        "",
        "| Year | Role | Source file |",
        "|---:|---|---|",
    ]
    for year, role, path in source_file_rows:
        lines.append(f"| {year} | {role} | `{path}` |")

    lines.extend(
        [
            "",
            "## Numerical checks",
            "",
            "| Check | Status | Evidence |",
            "|---|---|---|",
        ]
    )
    for name, passed, evidence in checks:
        lines.append(f"| {name} | {'PASS' if passed else 'FAIL'} | {evidence} |")

    lines.extend(["", "## Main derived results", ""])
    for summary in summaries.itertuples(index=False):
        year = int(summary.year)
        year_corridors = corridor_extremes.loc[
            (corridor_extremes["year"] == year) & (corridor_extremes["tail"] == "amplified")
        ].sort_values("tail_rank")
        year_positive = city_extremes.loc[
            (city_extremes["year"] == year)
            & (city_extremes["tail"] == "carbon_burden_position_higher")
        ].sort_values("tail_rank")
        year_negative = city_extremes.loc[
            (city_extremes["year"] == year)
            & (city_extremes["tail"] == "production_position_higher")
        ].sort_values("tail_rank")
        lines.extend(
            [
                f"### {year}",
                "",
                f"- National effective carbon intensity: `{summary.national_effective_carbon_intensity:.8g}` carbon-flow units per production-flow unit.",
                f"- Production and carbon outward-strength Spearman correlation: `{summary.city_out_strength_spearman:.3f}`.",
                f"- City position-shift range: `{summary.position_shift_min_pp:.1f}` to `{summary.position_shift_max_pp:.1f}` percentage points.",
                "- Highest-CA backbone corridors: "
                + "; ".join(format_corridor(row) for _, row in year_corridors.head(5).iterrows())
                + ".",
                "- Largest upward carbon-burden shifts: "
                + "; ".join(format_city(row) for _, row in year_positive.head(5).iterrows())
                + ".",
                "- Largest downward carbon-burden shifts: "
                + "; ".join(format_city(row) for _, row in year_negative.head(5).iterrows())
                + ".",
                "",
            ]
        )

    lines.extend(
        [
            "## Replicated city-position shifts",
            "",
            "The fixed top-ten tails share the following cities across both annual cross-sections:",
            "",
        ]
    )
    for tail in replicated_city_shifts["tail"].unique():
        block = replicated_city_shifts.loc[replicated_city_shifts["tail"] == tail]
        label = (
            "higher carbon-burden position"
            if tail == "carbon_burden_position_higher"
            else "higher production-flow position"
        )
        items = [
            f"{row.city_name_en} ({row.position_shift_2015_pp:+.1f} pp in 2015; "
            f"{row.position_shift_2020_pp:+.1f} pp in 2020)"
            for row in block.itertuples(index=False)
        ]
        lines.append(f"- {label}: " + "; ".join(items) + ".")

    lines.extend(
        [
            "",
            "## Output files",
            "",
            f"- `{result_dir / '260826-CorridorCarbonReweighting.csv'}`",
            f"- `{result_dir / '260826-BackboneCorridorCarbonReweighting.csv'}`",
            f"- `{result_dir / '260826-CorridorCarbonReweightingExtremes.csv'}`",
            f"- `{result_dir / '260826-CityPositionShift.csv'}`",
            f"- `{result_dir / '260826-CityPositionShiftExtremes.csv'}`",
            f"- `{result_dir / '260826-ReplicatedCityPositionShift.csv'}`",
            f"- `{result_dir / '260826-CarbonReweightingSummary.csv'}`",
            "",
            "## Verdict",
            "",
            f"**{'PASS' if overall else 'FAIL'}.** The derived evidence {'is' if overall else 'is not'} consistent with the stated flow identities.",
        ]
    )
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--network-dir", "--final-freeze-dir", dest="final_freeze_dir", type=Path, default=study_path("generated", "network"))
    parser.add_argument("--output-dir", "--revision-dir", dest="revision_dir", type=Path, default=study_path("generated", "analysis"))
    args = parser.parse_args()

    final_freeze_dir = args.final_freeze_dir.expanduser().resolve()
    revision_dir = args.revision_dir.expanduser().resolve()
    result_dir = revision_dir / "CarbonReweighting"
    audit_dir = revision_dir / "validation"
    result_dir.mkdir(parents=True, exist_ok=True)
    audit_dir.mkdir(parents=True, exist_ok=True)

    all_paths = {year: source_paths(final_freeze_dir, year) for year in YEARS}
    required = sorted({path for paths in all_paths.values() for path in paths.values()})
    require_files(required)

    city = load_city_table(all_paths[YEARS[0]]["alignment"])
    corridors: list[pd.DataFrame] = []
    backbones: list[pd.DataFrame] = []
    corridor_extremes_all: list[pd.DataFrame] = []
    city_results: list[pd.DataFrame] = []
    city_extremes_all: list[pd.DataFrame] = []
    summary_rows: list[dict[str, object]] = []

    for year in YEARS:
        (
            corridor,
            backbone,
            corridor_extremes,
            city_result,
            city_extremes,
            summary,
        ) = analyze_year(year, city, all_paths[year])
        city_names = city.set_index("city_code")["city_name_en"]
        for table in (corridor, backbone, corridor_extremes):
            table["source_city_name_en"] = table["source_city_code"].map(city_names)
            table["target_city_name_en"] = table["target_city_code"].map(city_names)
        corridors.append(corridor)
        backbones.append(backbone)
        corridor_extremes_all.append(corridor_extremes)
        city_results.append(city_result)
        city_extremes_all.append(city_extremes)
        summary_rows.append(summary)

    corridor_output = pd.concat(corridors, ignore_index=True)
    backbone_output = pd.concat(backbones, ignore_index=True)
    corridor_extremes_output = pd.concat(corridor_extremes_all, ignore_index=True)
    city_output = pd.concat(city_results, ignore_index=True)
    city_extremes_output = pd.concat(city_extremes_all, ignore_index=True)
    replicated_city_shifts = replicated_city_shift_table(city_extremes_output)
    summary_output = pd.DataFrame(summary_rows)

    corridor_output.to_csv(result_dir / "260826-CorridorCarbonReweighting.csv", index=False)
    backbone_output.to_csv(result_dir / "260826-BackboneCorridorCarbonReweighting.csv", index=False)
    corridor_extremes_output.to_csv(
        result_dir / "260826-CorridorCarbonReweightingExtremes.csv", index=False
    )
    city_output.to_csv(result_dir / "260826-CityPositionShift.csv", index=False)
    city_extremes_output.to_csv(result_dir / "260826-CityPositionShiftExtremes.csv", index=False)
    replicated_city_shifts.to_csv(
        result_dir / "260826-ReplicatedCityPositionShift.csv", index=False
    )
    summary_output.to_csv(result_dir / "260826-CarbonReweightingSummary.csv", index=False)

    source_file_rows: list[tuple[int, str, Path]] = []
    for year in YEARS:
        for role, path in all_paths[year].items():
            source_file_rows.append((year, role, path))
    write_audit(
        audit_dir / "260826-CarbonReweightingAudit.md",
        final_freeze_dir,
        result_dir,
        summary_output,
        corridor_extremes_output,
        city_extremes_output,
        replicated_city_shifts,
        source_file_rows,
    )

    if not (
        (summary_output["city_count"] == N_CITIES).all()
        and (summary_output["share_ratio_identity_max_abs_diff"] <= 1e-12).all()
        and (summary_output["city_outward_identity_max_relative_diff"] <= 1e-12).all()
        and (summary_output["pc_share_max_abs_diff"] <= 1e-12).all()
        and (summary_output["cb_share_max_abs_diff"] <= 1e-12).all()
    ):
        raise RuntimeError("Carbon reweighting audit failed; see the audit report.")

    print("CARBON REWEIGHTING STATUS: PASS")
    print(f"Output directory: {result_dir}")


if __name__ == "__main__":
    main()
