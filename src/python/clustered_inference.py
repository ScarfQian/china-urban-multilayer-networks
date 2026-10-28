#!/usr/bin/env python3
"""Estimate province-clustered uncertainty for the city-structure models."""

from __future__ import annotations

import argparse
from pathlib import Path

from study_paths import study_path

import numpy as np
import pandas as pd
import statsmodels.api as sm
from scipy.stats import t as student_t


YEARS = (2015, 2020)
N_CITIES = 309
EXPECTED_CLUSTERS = 27
COEFFICIENT_TOLERANCE = 1e-10
STANDARD_ERROR_TOLERANCE = 1e-10

MODEL_SPECS = (
    (
        "investment_position",
        "log_ic_share_z",
        ("log_total_output_z", "services_share_z"),
    ),
    (
        "outward_effective_carbon_intensity",
        "log1p_relative_outward_effective_carbon_intensity_z",
        ("industry_share_z", "transport_share_z", "log_total_output_z"),
    ),
    (
        "investment_carbon_burden_mismatch_services",
        "CRM_z",
        ("services_share_z", "log_total_output_z"),
    ),
    (
        "investment_carbon_burden_mismatch_industry",
        "CRM_z",
        ("industry_share_z", "log_total_output_z"),
    ),
)

OUTCOME_LABELS = {
    "log_ic_share_z": "Outward investment-network position",
    "log1p_relative_outward_effective_carbon_intensity_z": (
        "Outward effective carbon intensity"
    ),
    "CRM_z": "Investment-carbon-burden mismatch",
}

PREDICTOR_LABELS = {
    "log_total_output_z": "Total output (log)",
    "services_share_z": "Services output share",
    "industry_share_z": "Industry output share",
    "transport_share_z": "Transport output share",
}


def require_files(paths: list[Path]) -> None:
    missing = [path for path in paths if not path.is_file()]
    if missing:
        formatted = "\n".join(f"- {path}" for path in missing)
        raise FileNotFoundError(f"Required files are missing:\n{formatted}")


def build_design(
    data: pd.DataFrame,
    predictors: tuple[str, ...],
) -> pd.DataFrame:
    province_dummies = pd.get_dummies(
        data["province_name_std"].astype(str),
        prefix="province",
        drop_first=True,
        dtype=float,
    )
    return pd.concat(
        [
            pd.Series(1.0, index=data.index, name="intercept"),
            data[list(predictors)].astype(float),
            province_dummies,
        ],
        axis=1,
    )


def fit_model(
    data: pd.DataFrame,
    year: int,
    model_name: str,
    outcome: str,
    predictors: tuple[str, ...],
    baseline: pd.DataFrame,
) -> tuple[pd.DataFrame, dict[str, object]]:
    if len(data) != N_CITIES:
        raise ValueError(f"{year} has {len(data)} cities; expected {N_CITIES}.")
    groups = data["province_name_std"].astype(str)
    n_clusters = int(groups.nunique())
    if n_clusters != EXPECTED_CLUSTERS:
        raise ValueError(
            f"{year} has {n_clusters} province groups; expected {EXPECTED_CLUSTERS}."
        )

    design = build_design(data, predictors)
    x = design.to_numpy(dtype=float)
    y = data[outcome].to_numpy(dtype=float)
    if not np.isfinite(x).all() or not np.isfinite(y).all():
        raise ValueError(f"{year} {model_name} contains non-finite values.")
    rank = int(np.linalg.matrix_rank(x))
    if rank != x.shape[1]:
        raise ValueError(
            f"{year} {model_name} design rank is {rank}; expected {x.shape[1]}."
        )

    fitted = sm.OLS(y, x).fit()
    hc1 = fitted.get_robustcov_results(cov_type="HC1", use_t=False)
    clustered = fitted.get_robustcov_results(
        cov_type="cluster",
        groups=groups.to_numpy(),
        use_correction=True,
        df_correction=True,
        use_t=True,
    )

    cluster_df = n_clusters - 1
    t_critical = float(student_t.ppf(0.975, df=cluster_df))
    coefficient_rows: list[dict[str, object]] = []
    coefficient_differences: list[float] = []
    hc1_differences: list[float] = []

    for predictor in predictors:
        index = int(design.columns.get_loc(predictor))
        coefficient = float(fitted.params[index])
        hc1_se = float(hc1.bse[index])
        cluster_se = float(clustered.bse[index])
        cluster_t = coefficient / cluster_se
        cluster_p = float(2.0 * student_t.sf(abs(cluster_t), df=cluster_df))
        cluster_ci_low = coefficient - t_critical * cluster_se
        cluster_ci_high = coefficient + t_critical * cluster_se

        baseline_row = baseline[
            (baseline["year"] == year)
            & (baseline["model"] == model_name)
            & (baseline["predictor"] == predictor)
        ]
        if len(baseline_row) != 1:
            raise ValueError(
                f"Expected one baseline row for {year} {model_name} {predictor}; "
                f"found {len(baseline_row)}."
            )
        baseline_row = baseline_row.iloc[0]
        coefficient_difference = abs(
            coefficient - float(baseline_row["standardized_coefficient"])
        )
        hc1_difference = abs(hc1_se - float(baseline_row["hc1_standard_error"]))
        coefficient_differences.append(coefficient_difference)
        hc1_differences.append(hc1_difference)

        coefficient_rows.append(
            {
                "year": year,
                "model": model_name,
                "outcome": outcome,
                "outcome_label": OUTCOME_LABELS[outcome],
                "predictor": predictor,
                "predictor_label": PREDICTOR_LABELS[predictor],
                "standardized_coefficient": coefficient,
                "cluster_standard_error": cluster_se,
                "cluster_ci95_low": cluster_ci_low,
                "cluster_ci95_high": cluster_ci_high,
                "cluster_t_value": cluster_t,
                "cluster_p_value": cluster_p,
                "cluster_ci_excludes_zero": bool(
                    cluster_ci_low > 0.0 or cluster_ci_high < 0.0
                ),
                "hc1_standard_error": hc1_se,
                "hc1_ci95_low": float(baseline_row["ci95_low"]),
                "hc1_ci95_high": float(baseline_row["ci95_high"]),
                "hc1_z_value": float(baseline_row["z_value"]),
                "hc1_p_value": float(baseline_row["p_value"]),
                "n_cities": len(data),
                "n_clusters": n_clusters,
                "cluster_degrees_of_freedom": cluster_df,
                "province_fixed_effects": design.shape[1] - len(predictors) - 1,
                "n_parameters": design.shape[1],
                "r_squared": float(fitted.rsquared),
                "adjusted_r_squared": float(fitted.rsquared_adj),
                "coefficient_difference_from_baseline": coefficient_difference,
                "hc1_se_difference_from_baseline": hc1_difference,
            }
        )

    cluster_sizes = groups.value_counts()
    n, k = x.shape
    diagnostics = {
        "year": year,
        "model": model_name,
        "n_cities": n,
        "n_clusters": n_clusters,
        "cluster_degrees_of_freedom": cluster_df,
        "minimum_cluster_size": int(cluster_sizes.min()),
        "maximum_cluster_size": int(cluster_sizes.max()),
        "n_parameters": k,
        "design_rank": rank,
        "province_fixed_effects": design.shape[1] - len(predictors) - 1,
        "cluster_covariance_correction_factor": (
            n_clusters / (n_clusters - 1) * (n - 1) / (n - k)
        ),
        "r_squared": float(fitted.rsquared),
        "adjusted_r_squared": float(fitted.rsquared_adj),
        "maximum_coefficient_difference_from_baseline": max(coefficient_differences),
        "maximum_hc1_se_difference_from_baseline": max(hc1_differences),
    }
    return pd.DataFrame(coefficient_rows), diagnostics


def classify_replication(coefficients: pd.DataFrame) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    for (model, predictor), block in coefficients.groupby(
        ["model", "predictor"], sort=False
    ):
        block = block.sort_values("year")
        if tuple(block["year"]) != YEARS:
            raise ValueError(f"{model} {predictor} does not contain both years.")
        signs = np.sign(block["standardized_coefficient"].to_numpy(dtype=float))
        same_sign = bool(signs[0] == signs[1] and signs[0] != 0)
        both_exclude_zero = bool(block["cluster_ci_excludes_zero"].all())
        if same_sign and both_exclude_zero:
            status = "stable_main_text_association"
        elif same_sign:
            status = "same_signed_cluster_uncertain"
        else:
            status = "sign_reversal_exclude_from_mechanism_claim"
        rows.append(
            {
                "model": model,
                "predictor": predictor,
                "cluster_replication_status": status,
                "coefficient_2015": float(block.iloc[0]["standardized_coefficient"]),
                "cluster_ci95_low_2015": float(block.iloc[0]["cluster_ci95_low"]),
                "cluster_ci95_high_2015": float(block.iloc[0]["cluster_ci95_high"]),
                "cluster_p_value_2015": float(block.iloc[0]["cluster_p_value"]),
                "coefficient_2020": float(block.iloc[1]["standardized_coefficient"]),
                "cluster_ci95_low_2020": float(block.iloc[1]["cluster_ci95_low"]),
                "cluster_ci95_high_2020": float(block.iloc[1]["cluster_ci95_high"]),
                "cluster_p_value_2020": float(block.iloc[1]["cluster_p_value"]),
            }
        )
    return pd.DataFrame(rows)


def build_table_ready(coefficients: pd.DataFrame) -> pd.DataFrame:
    columns = [
        "year",
        "model",
        "outcome_label",
        "predictor_label",
        "standardized_coefficient",
        "cluster_standard_error",
        "cluster_ci95_low",
        "cluster_ci95_high",
        "cluster_p_value",
        "hc1_standard_error",
        "hc1_ci95_low",
        "hc1_ci95_high",
        "hc1_p_value",
        "n_cities",
        "n_clusters",
        "province_fixed_effects",
        "adjusted_r_squared",
    ]
    return coefficients[columns].copy()


def write_audit(
    path: Path,
    coefficients: pd.DataFrame,
    replication: pd.DataFrame,
    diagnostics: pd.DataFrame,
    input_files: list[Path],
    output_files: list[Path],
) -> None:
    coefficient_pass = bool(
        diagnostics["maximum_coefficient_difference_from_baseline"].max()
        <= COEFFICIENT_TOLERANCE
    )
    hc1_pass = bool(
        diagnostics["maximum_hc1_se_difference_from_baseline"].max()
        <= STANDARD_ERROR_TOLERANCE
    )
    dimension_pass = bool(
        (diagnostics["n_cities"] == N_CITIES).all()
        and (diagnostics["n_clusters"] == EXPECTED_CLUSTERS).all()
        and (diagnostics["province_fixed_effects"] == EXPECTED_CLUSTERS - 1).all()
        and (diagnostics["design_rank"] == diagnostics["n_parameters"]).all()
    )
    finite_pass = bool(
        np.isfinite(
            coefficients[
                [
                    "standardized_coefficient",
                    "cluster_standard_error",
                    "cluster_ci95_low",
                    "cluster_ci95_high",
                    "cluster_p_value",
                ]
            ].to_numpy(dtype=float)
        ).all()
    )
    overall = coefficient_pass and hc1_pass and dimension_pass and finite_pass

    lines = [
        "# Province-Clustered Urban-Structure Inference Audit",
        "",
        "Date: 2026-08-27  ",
        "Creator: **ScarfQian**",
        "",
        "## Scope",
        "",
        "The sensitivity keeps the existing outcomes, predictors, standardization, "
        "309-city samples and province fixed effects. It replaces HC1 uncertainty "
        "with province-clustered uncertainty using the 27 province groups present "
        "in the analysis data. OLS coefficients are unchanged.",
        "",
        "## Inputs",
        "",
        *[f"- `{item}`" for item in input_files],
        "",
        "## Implementation",
        "",
        "- Estimator: OLS with the existing design matrix.",
        "- Cluster variable: `province_name_std` (27 groups).",
        "- Covariance: statsmodels cluster covariance with finite-sample correction.",
        "- Inference: two-sided t tests and 95% intervals with 26 cluster degrees of freedom.",
        "- Comparison: existing HC1 standard errors and intervals retained in the table-ready output.",
        "",
        "## Verification",
        "",
        f"- City and cluster dimensions: **{'PASS' if dimension_pass else 'FAIL'}**.",
        f"- OLS coefficients reproduce the baseline: **{'PASS' if coefficient_pass else 'FAIL'}**.",
        f"- HC1 standard errors reproduce the baseline: **{'PASS' if hc1_pass else 'FAIL'}**.",
        f"- Cluster estimates are finite: **{'PASS' if finite_pass else 'FAIL'}**.",
        "",
        "## Cross-Year Evidence Status",
        "",
        "| Model | Predictor | Cluster-Based Status |",
        "|---|---|---|",
    ]
    for row in replication.itertuples(index=False):
        lines.append(
            f"| {row.model} | {row.predictor} | {row.cluster_replication_status} |"
        )
    lines.extend(
        [
            "",
            "## Outputs",
            "",
            *[f"- `{item}`" for item in output_files],
            "",
            "## Verdict",
            "",
            f"**{'PASS' if overall else 'FAIL'}.** "
            "The clustered results are valid for manuscript and figure revision."
            if overall
            else "**FAIL.** Downstream manuscript and figure revision must stop.",
        ]
    )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    if not overall:
        raise RuntimeError("Province-clustered inference audit failed.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", "--revision-dir", dest="revision_dir", type=Path, default=study_path("generated", "analysis"))
    args = parser.parse_args()
    revision_dir = args.revision_dir.expanduser().resolve()
    result_dir = revision_dir / "UrbanStructure"
    audit_dir = revision_dir / "validation"
    result_dir.mkdir(parents=True, exist_ok=True)
    audit_dir.mkdir(parents=True, exist_ok=True)

    variables_path = result_dir / "260826-MRIO4CityStructuralVariables.csv"
    baseline_path = result_dir / "260826-StructuralAssociationCoefficients.csv"
    require_files([variables_path, baseline_path])
    variables = pd.read_csv(variables_path)
    baseline = pd.read_csv(baseline_path)

    coefficient_tables: list[pd.DataFrame] = []
    diagnostic_rows: list[dict[str, object]] = []
    for year in YEARS:
        year_data = variables[variables["year"] == year].copy()
        for model_name, outcome, predictors in MODEL_SPECS:
            coefficients, diagnostics = fit_model(
                year_data,
                year,
                model_name,
                outcome,
                predictors,
                baseline,
            )
            coefficient_tables.append(coefficients)
            diagnostic_rows.append(diagnostics)

    coefficients = pd.concat(coefficient_tables, ignore_index=True)
    diagnostics = pd.DataFrame(diagnostic_rows)
    replication = classify_replication(coefficients)
    table_ready = build_table_ready(coefficients)

    coefficient_path = (
        result_dir / "260827-ProvinceClusteredStructuralAssociationCoefficients.csv"
    )
    replication_path = (
        result_dir / "260827-ProvinceClusteredStructuralAssociationReplication.csv"
    )
    diagnostic_path = (
        result_dir / "260827-ProvinceClusteredStructuralModelDiagnostics.csv"
    )
    table_path = result_dir / "260827-SupplementaryTableS2-UrbanStructureModels.csv"
    audit_path = audit_dir / "260827-ProvinceClusteredUrbanStructureInferenceAudit.md"

    coefficients.to_csv(coefficient_path, index=False)
    replication.to_csv(replication_path, index=False)
    diagnostics.to_csv(diagnostic_path, index=False)
    table_ready.to_csv(table_path, index=False)
    write_audit(
        audit_path,
        coefficients,
        replication,
        diagnostics,
        [variables_path, baseline_path],
        [coefficient_path, replication_path, diagnostic_path, table_path],
    )
    print("PROVINCE-CLUSTERED INFERENCE STATUS: PASS")
    print(f"Cities per year: {N_CITIES}")
    print(f"Province clusters: {EXPECTED_CLUSTERS}")
    print(f"Output directory: {result_dir}")


if __name__ == "__main__":
    main()
