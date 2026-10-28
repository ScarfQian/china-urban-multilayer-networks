function [gapDecomposition, attainment, attainmentSummary, ...
        randomIntervalSummary] = ...
        m40_compute_frontier_attainment_and_gap_decomposition_260810( ...
        v1Gaps, binaryFrontier, scopeFrontier, cfg)
% M40_COMPUTE_FRONTIER_ATTAINMENT_AND_GAP_DECOMPOSITION_260810
% 计算系统与范围约束效率缺口、缺口分解及网格积分前沿达到率

gapDecomposition = decompose_gaps_local( ...
    v1Gaps, binaryFrontier, scopeFrontier, cfg);
attainment = compute_attainment_local(v1Gaps, binaryFrontier, cfg);
attainmentSummary = summarize_attainment_local(attainment);
randomIntervalSummary = summarize_random_local(gapDecomposition);
end

function decomposition = decompose_gaps_local( ...
        v1Gaps, binaryFrontier, scopeFrontier, cfg)
parts = cell(height(scopeFrontier), 1);
for i = 1:height(scopeFrontier)
    scope = scopeFrontier(i, :);
    strategy = string(scope.strategy);
    candidate = v1Gaps(v1Gaps.year == scope.year & ...
        abs(v1Gaps.eta - scope.eta) <= cfg.objectiveTolerance & ...
        string(v1Gaps.strategy) == strategy & ...
        v1Gaps.repeat_id == scope.repeat_id, :);
    system = binaryFrontier(binaryFrontier.year == scope.year & ...
        abs(binaryFrontier.eta - scope.eta) <= cfg.objectiveTolerance, :);
    if height(candidate) ~= 1 || height(system) ~= 1
        error('m40_gap_decomposition:JoinFailure', ...
            'Gap join failed for %d %s repeat %d eta=%.3f.', ...
            scope.year, strategy, scope.repeat_id, scope.eta);
    end

    candidateCR = candidate.strategy_carbon_reduction;
    scopeCR = scope.scope_capped_carbon_reduction;
    systemCR = system.carbon_reduction;
    systemGap = clean_nonnegative_local(systemCR - candidateCR, cfg);
    scopeGap = clean_nonnegative_local(scopeCR - candidateCR, cfg);
    coverageComponent = clean_nonnegative_local(systemCR - scopeCR, cfg);
    rankingComponent = scopeGap;

    relativeSystemGap = safe_ratio_local(systemGap, systemCR, cfg);
    relativeScopeGap = safe_ratio_local(scopeGap, scopeCR, cfg);
    systemCapture = safe_ratio_local(candidateCR, systemCR, cfg);
    scopeCapture = safe_ratio_local(candidateCR, scopeCR, cfg);
    coverageShare = safe_ratio_local(coverageComponent, systemGap, cfg);
    rankingShare = safe_ratio_local(rankingComponent, systemGap, cfg);

    row = table();
    row.year = scope.year;
    row.eta = scope.eta;
    row.economic_loss_budget = scope.economic_loss_budget;
    row.strategy = strategy;
    row.strategy_kind = string(scope.strategy_kind);
    row.repeat_id = scope.repeat_id;
    row.candidate_selected_cities = candidate.selected_K;
    row.candidate_carbon_reduction = candidateCR;
    row.candidate_economic_loss = candidate.strategy_economic_loss;
    row.scope_capped_selected_cities = scope.scope_capped_selected_cities;
    row.scope_capped_optimal_reduction = scopeCR;
    row.scope_capped_economic_loss = scope.scope_capped_economic_loss;
    row.unrestricted_selected_cities = system.n_selected_cities;
    row.unrestricted_optimal_reduction = systemCR;
    row.unrestricted_economic_loss = system.economic_loss;
    row.absolute_system_gap = systemGap;
    row.relative_system_gap = relativeSystemGap;
    row.system_frontier_capture_ratio = systemCapture;
    row.absolute_scope_capped_gap = scopeGap;
    row.relative_scope_capped_gap = relativeScopeGap;
    row.scope_capped_capture_ratio = scopeCapture;
    row.coverage_component = coverageComponent;
    row.ranking_component = rankingComponent;
    row.coverage_component_share = coverageShare;
    row.ranking_component_share = rankingShare;
    row.decomposition_residual = systemGap - ...
        (coverageComponent + rankingComponent);
    parts{i} = row;
end
decomposition = vertcat(parts{:});
end

function attainment = compute_attainment_local(v1Gaps, binaryFrontier, cfg)
groups = unique(v1Gaps(:, ...
    {'year', 'strategy', 'strategy_kind', 'repeat_id'}), ...
    'rows', 'stable');
parts = cell(height(groups), 1);
for g = 1:height(groups)
    year = groups.year(g);
    strategy = string(groups.strategy(g));
    repeatId = groups.repeat_id(g);
    curve = v1Gaps(v1Gaps.year == year & ...
        string(v1Gaps.strategy) == strategy & ...
        v1Gaps.repeat_id == repeatId, :);
    exact = binaryFrontier(binaryFrontier.year == year, :);
    curve = sortrows(curve, 'economic_loss_budget');
    exact = sortrows(exact, 'economic_loss_budget');
    if height(curve) ~= numel(cfg.erGrid) || ...
            height(exact) ~= numel(cfg.erGrid) || ...
            max(abs(curve.economic_loss_budget - ...
            exact.economic_loss_budget)) > cfg.objectiveTolerance
        error('m40_attainment:GridMismatch', ...
            'IFAR grid mismatch for %d %s repeat %d.', ...
            year, strategy, repeatId);
    end
    strategyArea = trapz(curve.economic_loss_budget, ...
        curve.strategy_carbon_reduction);
    frontierArea = trapz(exact.economic_loss_budget, ...
        exact.carbon_reduction);
    ifar = strategyArea / frontierArea;

    row = table();
    row.year = year;
    row.strategy = strategy;
    row.strategy_kind = string(groups.strategy_kind(g));
    row.repeat_id = repeatId;
    row.grid_budget_min = min(curve.economic_loss_budget);
    row.grid_budget_max = max(curve.economic_loss_budget);
    row.grid_point_count = height(curve);
    row.strategy_area = strategyArea;
    row.frontier_area = frontierArea;
    row.integrated_frontier_attainment = ifar;
    row.integration_method = "trapz_on_fixed_101_point_budget_grid";
    row.curve_treatment = "unsmoothed_step_values_at_configured_grid";
    parts{g} = row;
end
attainment = vertcat(parts{:});
end

function summary = summarize_attainment_local(attainment)
groups = unique(attainment(:, {'year', 'strategy', 'strategy_kind'}), ...
    'rows', 'stable');
parts = cell(height(groups), 1);
for g = 1:height(groups)
    sub = attainment(attainment.year == groups.year(g) & ...
        string(attainment.strategy) == string(groups.strategy(g)), :);
    values = sub.integrated_frontier_attainment;
    row = table();
    row.year = groups.year(g);
    row.strategy = string(groups.strategy(g));
    row.strategy_kind = string(groups.strategy_kind(g));
    row.n_repeats = height(sub);
    row.integrated_frontier_attainment_mean = mean(values, 'omitnan');
    row.integrated_frontier_attainment_sd = std(values, 0, 'omitnan');
    row.integrated_frontier_attainment_p025 = quantile_local(values, 0.025);
    row.integrated_frontier_attainment_median = quantile_local(values, 0.50);
    row.integrated_frontier_attainment_p975 = quantile_local(values, 0.975);
    row.strategy_area_mean = mean(sub.strategy_area, 'omitnan');
    row.frontier_area = sub.frontier_area(1);
    parts{g} = row;
end
summary = vertcat(parts{:});
end

function summary = summarize_random_local(decomposition)
randomRows = decomposition(string(decomposition.strategy) == "random", :);
groups = unique(randomRows(:, {'year', 'eta'}), 'rows', 'stable');
parts = cell(height(groups), 1);
for g = 1:height(groups)
    sub = randomRows(randomRows.year == groups.year(g) & ...
        abs(randomRows.eta - groups.eta(g)) <= eps(groups.eta(g)), :);
    row = table();
    row.year = groups.year(g);
    row.eta = groups.eta(g);
    row.economic_loss_budget = 1 - groups.eta(g);
    row.strategy = "random";
    row.n_repeats = height(sub);
    row.candidate_carbon_reduction_mean = ...
        mean(sub.candidate_carbon_reduction, 'omitnan');
    row.candidate_carbon_reduction_sd = ...
        std(sub.candidate_carbon_reduction, 0, 'omitnan');
    row.candidate_carbon_reduction_p025 = ...
        quantile_local(sub.candidate_carbon_reduction, 0.025);
    row.candidate_carbon_reduction_p975 = ...
        quantile_local(sub.candidate_carbon_reduction, 0.975);
    row.scope_capped_optimal_reduction_mean = ...
        mean(sub.scope_capped_optimal_reduction, 'omitnan');
    row.scope_capped_optimal_reduction_p025 = ...
        quantile_local(sub.scope_capped_optimal_reduction, 0.025);
    row.scope_capped_optimal_reduction_p975 = ...
        quantile_local(sub.scope_capped_optimal_reduction, 0.975);
    row.relative_system_gap_mean = mean(sub.relative_system_gap, 'omitnan');
    row.relative_system_gap_p025 = ...
        quantile_local(sub.relative_system_gap, 0.025);
    row.relative_system_gap_p975 = ...
        quantile_local(sub.relative_system_gap, 0.975);
    row.relative_scope_capped_gap_mean = ...
        mean(sub.relative_scope_capped_gap, 'omitnan');
    row.relative_scope_capped_gap_p025 = ...
        quantile_local(sub.relative_scope_capped_gap, 0.025);
    row.relative_scope_capped_gap_p975 = ...
        quantile_local(sub.relative_scope_capped_gap, 0.975);
    parts{g} = row;
end
summary = vertcat(parts{:});
end

function value = clean_nonnegative_local(value, cfg)
if abs(value) <= cfg.objectiveTolerance + cfg.feasibilityTolerance
    value = 0;
end
end

function ratio = safe_ratio_local(numerator, denominator, cfg)
if denominator > cfg.objectiveTolerance
    ratio = numerator / denominator;
else
    ratio = NaN;
end
end

function q = quantile_local(values, probability)
% 中文说明: 使用线性插值分位数，避免依赖 Statistics Toolbox。
values = sort(values(isfinite(values)));
if isempty(values)
    q = NaN;
    return;
end
if isscalar(values)
    q = values(1);
    return;
end
position = 1 + (numel(values) - 1) * probability;
lower = floor(position);
upper = ceil(position);
weight = position - lower;
q = values(lower) * (1 - weight) + values(upper) * weight;
end
