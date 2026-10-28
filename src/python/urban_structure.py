#!/usr/bin/env python3
"""Relate city output and sector composition to investment position and carbon burdens."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from study_paths import study_path

import numpy as np
import pandas as pd
from scipy.io import loadmat
from scipy.stats import norm, spearmanr


YEARS = (2015, 2020)
N_CITIES = 309
N_CANONICAL_NODES = 313
N_SECTORS = 4
SECTOR_NAMES = {
    1: "Agriculture",
    2: "Industry",
    3: "Transport",
    4: "Services",
}


def require_files(paths: list[Path]) -> None:
    missing = [path for path in paths if not path.is_file()]
    if missing:
        formatted = "\n".join(f"- {path}" for path in missing)
        raise FileNotFoundError(f"Required files are missing:\n{formatted}")


def zscore(values: pd.Series) -> pd.Series:
    values = pd.to_numeric(values, errors="raise").astype(float)
    standard_deviation = float(values.std(ddof=1))
    if not np.isfinite(standard_deviation) or standard_deviation <= 0:
        raise ValueError(f"Cannot standardize {values.name}: non-positive variance.")
    return (values - float(values.mean())) / standard_deviation


def load_mrio_x(path: Path) -> tuple[np.ndarray, int, int]:
    loaded = loadmat(
        path,
        squeeze_me=True,
        struct_as_record=False,
        variable_names=["city"],
    )
    if "city" not in loaded:
        raise ValueError(f"{path} does not contain the expected city struct.")
    city = loaded["city"]
    required = ["X", "numCities", "numSectors"]
    missing = [field for field in required if not hasattr(city, field)]
    if missing:
        raise ValueError(f"{path} city struct is missing fields: {missing}")
    n_cities = int(city.numCities)
    n_sectors = int(city.numSectors)
    output = np.asarray(city.X, dtype=float).reshape(-1)
    if n_cities != N_CANONICAL_NODES or n_sectors != N_SECTORS:
        raise ValueError(
            f"{path} has {n_cities} cities and {n_sectors} sectors; "
            f"expected {N_CANONICAL_NODES} and {N_SECTORS}."
        )
    if output.size != n_cities * n_sectors:
        raise ValueError(f"{path} X has {output.size} cells, expected {n_cities * n_sectors}.")
    if not np.isfinite(output).all() or (output < 0).any():
        raise ValueError(f"{path} X contains non-finite or negative values.")
    return output.reshape(n_cities, n_sectors), n_cities, n_sectors


def fit_hc1_model(
    data: pd.DataFrame,
    year: int,
    model_name: str,
    outcome: str,
    focal_predictors: list[str],
) -> tuple[pd.DataFrame, dict[str, object], pd.DataFrame]:
    province_dummies = pd.get_dummies(
        data["province_name_std"].astype(str),
        prefix="province",
        drop_first=True,
        dtype=float,
    )
    design = pd.concat(
        [
            pd.Series(1.0, index=data.index, name="intercept"),
            data[focal_predictors].astype(float),
            province_dummies,
        ],
        axis=1,
    )
    y = data[outcome].to_numpy(dtype=float)
    x = design.to_numpy(dtype=float)
    if not np.isfinite(x).all() or not np.isfinite(y).all():
        raise ValueError(f"{year} {model_name} contains non-finite model inputs.")
    rank = int(np.linalg.matrix_rank(x))
    if rank != x.shape[1]:
        raise ValueError(
            f"{year} {model_name} design rank is {rank}, expected {x.shape[1]}."
        )

    beta, _, _, _ = np.linalg.lstsq(x, y, rcond=None)
    fitted = x @ beta
    residual = y - fitted
    n, k = x.shape
    xtx_inv = np.linalg.inv(x.T @ x)
    meat = x.T @ ((residual**2)[:, None] * x)
    covariance = (n / (n - k)) * xtx_inv @ meat @ xtx_inv
    standard_errors = np.sqrt(np.maximum(np.diag(covariance), 0.0))
    z_values = np.divide(beta, standard_errors, out=np.full_like(beta, np.nan), where=standard_errors > 0)
    p_values = 2.0 * norm.sf(np.abs(z_values))

    ss_residual = float(np.sum(residual**2))
    ss_total = float(np.sum((y - y.mean()) ** 2))
    r_squared = 1.0 - ss_residual / ss_total
    adjusted_r_squared = 1.0 - (1.0 - r_squared) * (n - 1) / (n - k)

    coefficient_rows = []
    for predictor in focal_predictors:
        index = design.columns.get_loc(predictor)
        coefficient_rows.append(
            {
                "year": year,
                "model": model_name,
                "outcome": outcome,
                "predictor": predictor,
                "standardized_coefficient": beta[index],
                "hc1_standard_error": standard_errors[index],
                "ci95_low": beta[index] - 1.96 * standard_errors[index],
                "ci95_high": beta[index] + 1.96 * standard_errors[index],
                "z_value": z_values[index],
                "p_value": p_values[index],
                "n_cities": n,
                "province_fixed_effects": province_dummies.shape[1],
                "r_squared": r_squared,
                "adjusted_r_squared": adjusted_r_squared,
            }
        )

    predictor_correlation = data[focal_predictors].corr().to_numpy(dtype=float)
    inverse_correlation = np.linalg.inv(predictor_correlation)
    vif_rows = [
        {
            "year": year,
            "model": model_name,
            "predictor": predictor,
            "vif_focal_predictors": inverse_correlation[index, index],
        }
        for index, predictor in enumerate(focal_predictors)
    ]
    diagnostics = {
        "year": year,
        "model": model_name,
        "n_cities": n,
        "n_parameters": k,
        "design_rank": rank,
        "province_fixed_effects": province_dummies.shape[1],
        "r_squared": r_squared,
        "adjusted_r_squared": adjusted_r_squared,
        "residual_mean": float(residual.mean()),
        "residual_sd": float(residual.std(ddof=1)),
        "max_focal_vif": float(np.max(np.diag(inverse_correlation))),
    }
    return pd.DataFrame(coefficient_rows), diagnostics, pd.DataFrame(vif_rows)


def classify_replication(coefficients: pd.DataFrame) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    for (model, predictor), block in coefficients.groupby(["model", "predictor"], sort=False):
        block = block.sort_values("year")
        if set(block["year"]) != set(YEARS):
            status = "incomplete"
        else:
            signs = np.sign(block["standardized_coefficient"].to_numpy())
            same_sign = bool(signs[0] == signs[1] and signs[0] != 0)
            ci_excludes_zero = bool(
                (
                    (block["ci95_low"] > 0) & (block["ci95_high"] > 0)
                    | (block["ci95_low"] < 0) & (block["ci95_high"] < 0)
                ).all()
            )
            if same_sign and ci_excludes_zero:
                status = "consistent_association"
            elif same_sign:
                status = "same_sign_uncertain"
            else:
                status = "direction_not_replicated"
        rows.append(
            {
                "model": model,
                "predictor": predictor,
                "replication_status": status,
                "coefficient_2015": float(
                    block.loc[block["year"] == 2015, "standardized_coefficient"].iloc[0]
                ),
                "coefficient_2020": float(
                    block.loc[block["year"] == 2020, "standardized_coefficient"].iloc[0]
                ),
            }
        )
    return pd.DataFrame(rows)


def build_year_table(
    year: int,
    mrio_path: Path,
    city_alignment_path: Path,
    carbon_intensity_path: Path,
    governance_path: Path,
    position_shift_path: Path,
) -> tuple[pd.DataFrame, dict[str, object]]:
    city = pd.read_csv(city_alignment_path).sort_values("city_id").reset_index(drop=True)
    if len(city) != N_CITIES or city["city_code"].nunique() != N_CITIES:
        raise ValueError(f"Expected {N_CITIES} aligned cities in {city_alignment_path}.")
    excluded_ids = sorted(set(range(1, N_CANONICAL_NODES + 1)).difference(city["city_id"]))
    if excluded_ids != [235, 267, 268, 293]:
        raise ValueError(f"Unexpected excluded canonical city IDs: {excluded_ids}")

    output_matrix, n_canonical, n_sectors = load_mrio_x(mrio_path)
    selected_output = output_matrix[city["city_id"].to_numpy(dtype=int) - 1, :]
    sector_output = pd.DataFrame(
        selected_output,
        columns=[f"{SECTOR_NAMES[index].lower()}_output" for index in range(1, N_SECTORS + 1)],
    )
    city_variables = pd.concat(
        [
            city[
                [
                    "city_id",
                    "city_code",
                    "city_name_std",
                    "city_name_en",
                    "province_code",
                    "province_name_std",
                ]
            ].reset_index(drop=True),
            sector_output,
        ],
        axis=1,
    )
    city_variables["year"] = year
    output_columns = [column for column in city_variables if column.endswith("_output")]
    city_variables["total_output"] = city_variables[output_columns].sum(axis=1)
    if (city_variables["total_output"] <= 0).any():
        raise ValueError(f"{year} contains non-positive city total output.")
    for sector_name in SECTOR_NAMES.values():
        lower = sector_name.lower()
        city_variables[f"{lower}_share"] = (
            city_variables[f"{lower}_output"] / city_variables["total_output"]
        )
    share_columns = [f"{name.lower()}_share" for name in SECTOR_NAMES.values()]
    share_sum_max_abs_diff = float(
        np.max(np.abs(city_variables[share_columns].sum(axis=1) - 1.0))
    )

    carbon_intensity = pd.read_csv(carbon_intensity_path)
    required_intensity = {"city_code", "mrio4_sector_code", "output_x"}
    missing_intensity = sorted(required_intensity.difference(carbon_intensity.columns))
    if missing_intensity:
        raise ValueError(f"{carbon_intensity_path} is missing columns: {missing_intensity}")
    long_output = city_variables.melt(
        id_vars=["city_code"],
        value_vars=output_columns,
        var_name="sector_name",
        value_name="mrio_package_output_x",
    )
    sector_code_map = {
        f"{name.lower()}_output": code for code, name in SECTOR_NAMES.items()
    }
    long_output["mrio4_sector_code"] = long_output["sector_name"].map(sector_code_map)
    output_check = long_output.merge(
        carbon_intensity[["city_code", "mrio4_sector_code", "output_x"]],
        on=["city_code", "mrio4_sector_code"],
        how="left",
        validate="one_to_one",
    )
    if output_check["output_x"].isna().any():
        raise ValueError(f"{year} output_x validation is incomplete.")
    output_x_max_abs_diff = float(
        np.max(np.abs(output_check["mrio_package_output_x"] - output_check["output_x"]))
    )
    output_x_scale = max(float(output_check["output_x"].max()), 1.0)
    output_x_max_relative_diff = output_x_max_abs_diff / output_x_scale

    governance = pd.read_csv(governance_path)
    governance_columns = [
        "city_code",
        "IC_share",
        "PC_share",
        "CB_share",
        "CRM",
    ]
    missing_governance = sorted(set(governance_columns).difference(governance.columns))
    if missing_governance:
        raise ValueError(f"{governance_path} is missing columns: {missing_governance}")
    position = pd.read_csv(position_shift_path)
    position = position.loc[position["year"] == year].copy()
    position_columns = [
        "city_code",
        "outward_effective_carbon_intensity",
        "position_shift_percentage_points",
        "production_flow_share",
        "carbon_burden_share",
    ]
    missing_position = sorted(set(position_columns).difference(position.columns))
    if missing_position:
        raise ValueError(f"{position_shift_path} is missing columns: {missing_position}")

    city_variables = city_variables.merge(
        governance[governance_columns], on="city_code", how="left", validate="one_to_one"
    ).merge(position[position_columns], on="city_code", how="left", validate="one_to_one")
    if city_variables[governance_columns[1:] + position_columns[1:]].isna().any().any():
        raise ValueError(f"{year} city structural variables are incomplete after merging.")

    pc_share_max_abs_diff = float(
        np.max(np.abs(city_variables["PC_share"] - city_variables["production_flow_share"]))
    )
    cb_share_max_abs_diff = float(
        np.max(np.abs(city_variables["CB_share"] - city_variables["carbon_burden_share"]))
    )
    national_qbar = float(city_variables["carbon_burden_share"].sum()) / float(
        city_variables["production_flow_share"].sum()
    )
    # At the share scale, CB = PC * qbar_out / national_qbar_raw. Recover the
    # raw national intensity from each positive city and verify it is constant.
    positive = city_variables["PC_share"] > 0
    implied_national_qbar = (
        city_variables.loc[positive, "PC_share"]
        * city_variables.loc[positive, "outward_effective_carbon_intensity"]
        / city_variables.loc[positive, "CB_share"]
    )
    raw_national_qbar = float(implied_national_qbar.median())
    reconstructed_cb = (
        city_variables["PC_share"]
        * city_variables["outward_effective_carbon_intensity"]
        / raw_national_qbar
    )
    cb_identity_max_abs_diff = float(np.max(np.abs(reconstructed_cb - city_variables["CB_share"])))

    city_variables["log_total_output"] = np.log(city_variables["total_output"])
    if (city_variables["IC_share"] <= 0).any():
        raise ValueError(f"{year} contains non-positive investment-network shares.")
    city_variables["log_ic_share"] = np.log(city_variables["IC_share"])
    positive_effective_intensity = city_variables.loc[
        city_variables["outward_effective_carbon_intensity"] > 0,
        "outward_effective_carbon_intensity",
    ]
    if positive_effective_intensity.empty:
        raise ValueError(f"{year} has no positive outward effective carbon intensity.")
    effective_intensity_scale = float(positive_effective_intensity.median())
    city_variables["log1p_relative_outward_effective_carbon_intensity"] = np.log1p(
        city_variables["outward_effective_carbon_intensity"] / effective_intensity_scale
    )
    standardize_columns = [
        "log_total_output",
        "log_ic_share",
        "log1p_relative_outward_effective_carbon_intensity",
        "agriculture_share",
        "industry_share",
        "transport_share",
        "services_share",
        "CRM",
    ]
    for column in standardize_columns:
        city_variables[f"{column}_z"] = zscore(city_variables[column])

    checks = {
        "year": year,
        "mrio_path": str(mrio_path),
        "canonical_nodes": n_canonical,
        "included_cities": len(city_variables),
        "sectors": n_sectors,
        "excluded_canonical_ids": "|".join(map(str, excluded_ids)),
        "share_sum_max_abs_diff": share_sum_max_abs_diff,
        "output_x_max_relative_diff": output_x_max_relative_diff,
        "pc_share_max_abs_diff": pc_share_max_abs_diff,
        "cb_share_max_abs_diff": cb_share_max_abs_diff,
        "cb_accounting_identity_max_abs_diff": cb_identity_max_abs_diff,
        "raw_national_effective_carbon_intensity": raw_national_qbar,
        "share_scale_national_ratio": national_qbar,
        "positive_effective_carbon_intensity_median": effective_intensity_scale,
        "zero_effective_carbon_intensity_cities": int(
            (city_variables["outward_effective_carbon_intensity"] == 0).sum()
        ),
    }
    return city_variables, checks


def build_correlations(data: pd.DataFrame, year: int) -> pd.DataFrame:
    pairs = [
        ("IC_share", "total_output"),
        ("IC_share", "services_share"),
        ("IC_share", "industry_share"),
        ("CB_share", "PC_share"),
        ("CB_share", "outward_effective_carbon_intensity"),
        ("outward_effective_carbon_intensity", "industry_share"),
        ("outward_effective_carbon_intensity", "transport_share"),
        ("outward_effective_carbon_intensity", "services_share"),
        ("CRM", "services_share"),
        ("CRM", "industry_share"),
    ]
    rows = []
    for outcome, correlate in pairs:
        rho, p_value = spearmanr(data[outcome], data[correlate])
        rows.append(
            {
                "year": year,
                "outcome": outcome,
                "correlate": correlate,
                "spearman_rho": rho,
                "p_value": p_value,
                "n_cities": len(data),
            }
        )
    return pd.DataFrame(rows)


def write_audit(
    path: Path,
    variables: pd.DataFrame,
    checks: pd.DataFrame,
    correlations: pd.DataFrame,
    coefficients: pd.DataFrame,
    replication: pd.DataFrame,
    diagnostics: pd.DataFrame,
    source_paths: dict[str, Path],
    result_dir: Path,
) -> None:
    check_rows: list[tuple[str, bool, str]] = []
    for row in checks.itertuples(index=False):
        year = int(row.year)
        check_rows.extend(
            [
                (f"{year} included cities", row.included_cities == N_CITIES, str(row.included_cities)),
                (f"{year} canonical MRIO nodes", row.canonical_nodes == N_CANONICAL_NODES, str(row.canonical_nodes)),
                (f"{year} MRIO4 sectors", row.sectors == N_SECTORS, str(row.sectors)),
                (
                    f"{year} sector-share closure",
                    row.share_sum_max_abs_diff <= 1e-12,
                    f"max abs diff={row.share_sum_max_abs_diff:.3e}",
                ),
                (
                    f"{year} package X versus frozen output_x",
                    row.output_x_max_relative_diff <= 1e-12,
                    f"max relative diff={row.output_x_max_relative_diff:.3e}",
                ),
                (
                    f"{year} PC_share alignment",
                    row.pc_share_max_abs_diff <= 1e-12,
                    f"max abs diff={row.pc_share_max_abs_diff:.3e}",
                ),
                (
                    f"{year} CB_share alignment",
                    row.cb_share_max_abs_diff <= 1e-12,
                    f"max abs diff={row.cb_share_max_abs_diff:.3e}",
                ),
                (
                    f"{year} CB accounting identity",
                    row.cb_accounting_identity_max_abs_diff <= 1e-12,
                    f"max abs diff={row.cb_accounting_identity_max_abs_diff:.3e}",
                ),
            ]
        )
    check_rows.append(
        (
            "focal-predictor collinearity",
            bool((diagnostics["max_focal_vif"] < 5).all()),
            f"maximum VIF={diagnostics['max_focal_vif'].max():.3f}",
        )
    )
    overall = all(passed for _, passed, _ in check_rows)

    lines = [
        "# Four-sector city-structure associations",
        "",
        "## Scientific scope",
        "",
        "The analysis uses city gross-output composition in the four formal MRIO4 sectors: Agriculture, Industry, Transport and Services. Outward carbon burden is decomposed by the accounting identity linking production-flow share and outward effective carbon intensity. Separate annual models examine associations with outward investment-network position, effective carbon intensity and investment-carbon-burden mismatch.",
        "",
        "The models use standardized continuous variables, province fixed effects and HC1 heteroskedasticity-robust standard errors. Investment-network share enters in natural logs. Outward effective carbon intensity enters as log(1 + qbar divided by the annual positive-city median), retaining the zero-emission Shihezi observation. Services and Industry shares enter separate mismatch models because the four sector shares form a constrained composition. Cross-year comparisons summarize coefficient direction and whether the 95% intervals exclude zero.",
        "",
        "## Input files",
        "",
    ]
    for role, source_path in source_paths.items():
        lines.append(f"- {role}: `{source_path}`")

    lines.extend(
        [
            "",
            "## Numerical checks",
            "",
            "| Check | Status | Evidence |",
            "|---|---|---|",
        ]
    )
    for name, passed, evidence in check_rows:
        lines.append(f"| {name} | {'PASS' if passed else 'FAIL'} | {evidence} |")

    lines.extend(["", "## Accounting results", ""])
    for year in YEARS:
        block = variables.loc[variables["year"] == year]
        pc_cb = correlations.loc[
            (correlations["year"] == year)
            & (correlations["outcome"] == "CB_share")
            & (correlations["correlate"] == "PC_share"),
            "spearman_rho",
        ].iloc[0]
        q_cb = correlations.loc[
            (correlations["year"] == year)
            & (correlations["outcome"] == "CB_share")
            & (correlations["correlate"] == "outward_effective_carbon_intensity"),
            "spearman_rho",
        ].iloc[0]
        lines.extend(
            [
                f"### {year}",
                "",
                f"- Carbon-burden share correlates with production-flow share at Spearman rho `{pc_cb:.3f}` and with outward effective carbon intensity at rho `{q_cb:.3f}`.",
                f"- Mean MRIO4 composition: Agriculture `{block['agriculture_share'].mean():.3f}`, Industry `{block['industry_share'].mean():.3f}`, Transport `{block['transport_share'].mean():.3f}`, Services `{block['services_share'].mean():.3f}`.",
                "",
            ]
        )

    lines.extend(
        [
            "## Cross-year coefficient comparison",
            "",
            "| Model | Predictor | 2015 coefficient | 2020 coefficient | Status |",
            "|---|---|---:|---:|---|",
        ]
    )
    for row in replication.itertuples(index=False):
        lines.append(
            f"| {row.model} | {row.predictor} | {row.coefficient_2015:.3f} | "
            f"{row.coefficient_2020:.3f} | {row.replication_status} |"
        )

    stable = replication.loc[
        replication["replication_status"] == "consistent_association"
    ]
    lines.extend(
        ["", "## Associations across both years", "",
         f"{len(stable)} model–predictor pairs have the same coefficient sign "
         "and 95% intervals excluding zero in both years."]
    )

    lines.extend(
        [
            "",
            "## Output files",
            "",
            f"- `{result_dir / '260826-MRIO4CityStructuralVariables.csv'}`",
            f"- `{result_dir / '260826-StructuralSpearmanAssociations.csv'}`",
            f"- `{result_dir / '260826-StructuralAssociationCoefficients.csv'}`",
            f"- `{result_dir / '260826-StructuralAssociationReplication.csv'}`",
            f"- `{result_dir / '260826-StructuralModelDiagnostics.csv'}`",
            f"- `{result_dir / '260826-StructuralPredictorVIF.csv'}`",
            f"- `{result_dir / '260826-MRIO4StructureChecks.csv'}`",
            "",
            "## Verdict",
            "",
            f"**{'PASS' if overall else 'FAIL'}.** The sample, sector shares and flow identities {'agree' if overall else 'do not agree'} with the stated definitions.",
        ]
    )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--network-dir", "--final-freeze-dir", dest="final_freeze_dir", type=Path, default=study_path("generated", "network"))
    parser.add_argument("--output-dir", "--revision-dir", dest="revision_dir", type=Path, default=study_path("generated", "analysis"))
    args = parser.parse_args()

    final_freeze_dir = args.final_freeze_dir.expanduser().resolve()
    revision_dir = args.revision_dir.expanduser().resolve()
    result_dir = revision_dir / "UrbanStructure"
    audit_dir = revision_dir / "validation"
    result_dir.mkdir(parents=True, exist_ok=True)
    audit_dir.mkdir(parents=True, exist_ok=True)

    manifest_path = final_freeze_dir / "revised_mrio4" / "multilayer_results_manifest.json"
    require_files([manifest_path])
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    frozen_inputs = manifest.get("frozen_inputs", {})
    mrio_paths = {
        2015: Path(frozen_inputs["city_mrio_2015_4"]).expanduser(),
        2020: Path(frozen_inputs["city_mrio_2020_hybrid_4"]).expanduser(),
    }
    for year, recorded_path in mrio_paths.items():
        if not recorded_path.is_absolute():
            mrio_paths[year] = manifest_path.parent / recorded_path
    alignment_path = final_freeze_dir / "revised_mrio4" / "city_alignment_report.csv"
    position_shift_path = (
        revision_dir / "CarbonReweighting" / "260826-CityPositionShift.csv"
    )
    carbon_intensity_paths = {
        year: final_freeze_dir
        / "revised_mrio4"
        / "layers"
        / f"city_sector_carbon_intensity_{year}.csv"
        for year in YEARS
    }
    governance_paths = {
        year: final_freeze_dir
        / "revised_transition"
        / f"governance_mismatch_metrics_{year}.csv"
        for year in YEARS
    }
    required = [
        alignment_path,
        position_shift_path,
        *mrio_paths.values(),
        *carbon_intensity_paths.values(),
        *governance_paths.values(),
    ]
    require_files(required)

    year_tables: list[pd.DataFrame] = []
    check_rows: list[dict[str, object]] = []
    correlation_tables: list[pd.DataFrame] = []
    coefficient_tables: list[pd.DataFrame] = []
    diagnostic_rows: list[dict[str, object]] = []
    vif_tables: list[pd.DataFrame] = []

    model_specs = [
        (
            "investment_position",
            "log_ic_share_z",
            ["log_total_output_z", "services_share_z"],
        ),
        (
            "outward_effective_carbon_intensity",
            "log1p_relative_outward_effective_carbon_intensity_z",
            ["industry_share_z", "transport_share_z", "log_total_output_z"],
        ),
        (
            "investment_carbon_burden_mismatch_services",
            "CRM_z",
            ["services_share_z", "log_total_output_z"],
        ),
        (
            "investment_carbon_burden_mismatch_industry",
            "CRM_z",
            ["industry_share_z", "log_total_output_z"],
        ),
    ]

    for year in YEARS:
        year_table, year_checks = build_year_table(
            year,
            mrio_paths[year],
            alignment_path,
            carbon_intensity_paths[year],
            governance_paths[year],
            position_shift_path,
        )
        year_tables.append(year_table)
        check_rows.append(year_checks)
        correlation_tables.append(build_correlations(year_table, year))
        for model_name, outcome, predictors in model_specs:
            coefficients, diagnostics, vif = fit_hc1_model(
                year_table,
                year,
                model_name,
                outcome,
                predictors,
            )
            coefficient_tables.append(coefficients)
            diagnostic_rows.append(diagnostics)
            vif_tables.append(vif)

    variables = pd.concat(year_tables, ignore_index=True)
    checks = pd.DataFrame(check_rows)
    correlations = pd.concat(correlation_tables, ignore_index=True)
    coefficients = pd.concat(coefficient_tables, ignore_index=True)
    diagnostics = pd.DataFrame(diagnostic_rows)
    vif = pd.concat(vif_tables, ignore_index=True)
    replication = classify_replication(coefficients)

    variables.to_csv(result_dir / "260826-MRIO4CityStructuralVariables.csv", index=False)
    correlations.to_csv(result_dir / "260826-StructuralSpearmanAssociations.csv", index=False)
    coefficients.to_csv(result_dir / "260826-StructuralAssociationCoefficients.csv", index=False)
    replication.to_csv(result_dir / "260826-StructuralAssociationReplication.csv", index=False)
    diagnostics.to_csv(result_dir / "260826-StructuralModelDiagnostics.csv", index=False)
    vif.to_csv(result_dir / "260826-StructuralPredictorVIF.csv", index=False)
    checks.to_csv(result_dir / "260826-MRIO4StructureChecks.csv", index=False)

    source_path_map = {
        "final-freeze manifest": manifest_path,
        "2015 MRIO4 package": mrio_paths[2015],
        "2020 MRIO4 package": mrio_paths[2020],
        "city alignment": alignment_path,
        "2015 carbon-intensity output check": carbon_intensity_paths[2015],
        "2020 carbon-intensity output check": carbon_intensity_paths[2020],
        "2015 governance metrics": governance_paths[2015],
        "2020 governance metrics": governance_paths[2020],
        "carbon-reweighting city table": position_shift_path,
    }
    write_audit(
        audit_dir / "260826-MRIO4UrbanStructureAssociationAudit.md",
        variables,
        checks,
        correlations,
        coefficients,
        replication,
        diagnostics,
        source_path_map,
        result_dir,
    )

    if not (
        (checks["included_cities"] == N_CITIES).all()
        and (checks["share_sum_max_abs_diff"] <= 1e-12).all()
        and (checks["output_x_max_relative_diff"] <= 1e-12).all()
        and (checks["pc_share_max_abs_diff"] <= 1e-12).all()
        and (checks["cb_share_max_abs_diff"] <= 1e-12).all()
        and (checks["cb_accounting_identity_max_abs_diff"] <= 1e-12).all()
        and (diagnostics["max_focal_vif"] < 5).all()
    ):
        raise RuntimeError("MRIO4 urban-structure audit failed; see the audit report.")

    print("MRIO4 URBAN STRUCTURE STATUS: PASS")
    print(f"Output directory: {result_dir}")


if __name__ == "__main__":
    main()
