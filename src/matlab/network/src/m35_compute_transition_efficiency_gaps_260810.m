function [gaps, randomSummary, keyEtaSummary] = ...
        m35_compute_transition_efficiency_gaps_260810(prefixes, frontier, cfg)
% M35_COMPUTE_TRANSITION_EFFICIENCY_GAPS_260810
% 在相同经济保持率预算下比较策略完整前缀与精确前沿

allPrefixes = table();
for year = cfg.years
    key = sprintf('y%d', year);
    allPrefixes = [allPrefixes; prefixes.(key)]; %#ok<AGROW>
end

groups = unique(allPrefixes(:, ...
    {'year', 'strategy', 'strategy_kind', 'repeat_id'}), 'rows', 'stable');
parts = cell(height(groups), 1);

for g = 1:height(groups)
    year = groups.year(g);
    strategy = groups.strategy(g);
    strategyKind = groups.strategy_kind(g);
    repeatId = groups.repeat_id(g);
    curve = allPrefixes(allPrefixes.year == year & ...
        allPrefixes.strategy == strategy & ...
        allPrefixes.repeat_id == repeatId, :);
    curve = sortrows(curve, 'K');
    rows = cell(numel(cfg.erGrid), 1);

    for etaIdx = 1:numel(cfg.erGrid)
        eta = cfg.erGrid(etaIdx);
        budget = 1 - eta;
        selected = select_strategy_prefix_local(curve, budget, cfg);
        exact = frontier(frontier.year == year & ...
            abs(frontier.eta - eta) <= cfg.objectiveTolerance, :);
        if height(exact) ~= 1
            error('m35_efficiency_gap:FrontierJoin', ...
                'Expected one exact frontier row for %d eta=%.3f.', year, eta);
        end

        rawGap = exact.carbon_reduction - selected.carbon_reduction;
        if abs(rawGap) <= cfg.objectiveTolerance + cfg.feasibilityTolerance
            carbonGap = 0;
        else
            carbonGap = rawGap;
        end
        if exact.carbon_reduction > cfg.objectiveTolerance
            relativeGap = carbonGap / exact.carbon_reduction;
            frontierCapture = selected.carbon_reduction / exact.carbon_reduction;
        else
            relativeGap = NaN;
            frontierCapture = NaN;
        end
        dominanceStatus = "PASS";
        if carbonGap < -cfg.feasibilityTolerance
            dominanceStatus = "FAIL";
        end

        row = table();
        row.year = year;
        row.eta = eta;
        row.economic_loss_budget = budget;
        row.strategy = strategy;
        row.strategy_kind = strategyKind;
        row.repeat_id = repeatId;
        row.selected_K = selected.K;
        row.selected_phi = selected.phi;
        row.strategy_carbon_reduction = selected.carbon_reduction;
        row.strategy_economic_loss = selected.economic_loss;
        row.strategy_economic_retention = selected.economic_retention;
        row.frontier_carbon_reduction = exact.carbon_reduction;
        row.frontier_economic_loss = exact.economic_loss;
        row.frontier_economic_retention = exact.economic_retention;
        row.frontier_selected_cities = exact.n_selected_cities;
        row.carbon_reduction_efficiency_gap = carbonGap;
        row.relative_efficiency_gap = relativeGap;
        row.frontier_capture_ratio = frontierCapture;
        row.frontier_dominance_status = dominanceStatus;
        rows{etaIdx} = row;
    end
    parts{g} = vertcat(rows{:});
end

gaps = vertcat(parts{:});
allSummary = summarize_gap_groups_local(gaps, cfg);
randomSummary = allSummary(allSummary.strategy == "random", :);
keyMask = false(height(allSummary), 1);
for eta = cfg.keyEta
    keyMask = keyMask | abs(allSummary.eta - eta) <= cfg.objectiveTolerance;
end
keyEtaSummary = allSummary(keyMask, :);
end

function selected = select_strategy_prefix_local(curve, budget, cfg)
% 中文说明: 同一策略内部也按减碳、实际损失、城市数执行字典序选择。
feasible = curve(curve.economic_loss <= budget + cfg.feasibilityTolerance, :);
if isempty(feasible)
    error('m35_efficiency_gap:NoFeasiblePrefix', ...
        'No feasible strategy prefix found for budget %.6f.', budget);
end
bestCarbon = max(feasible.carbon_reduction);
candidates = feasible(feasible.carbon_reduction >= ...
    bestCarbon - cfg.objectiveTolerance, :);
bestLoss = min(candidates.economic_loss);
candidates = candidates(candidates.economic_loss <= ...
    bestLoss + cfg.objectiveTolerance, :);
bestK = min(candidates.K);
selected = candidates(candidates.K == bestK, :);
selected = selected(1, :);
end

function summary = summarize_gap_groups_local(gaps, cfg)
% 中文说明: 统一汇总可让随机 50 次分布与确定性单次结果使用相同字段。
groups = unique(gaps(:, {'year', 'eta', 'strategy', 'strategy_kind'}), ...
    'rows', 'stable');
parts = cell(height(groups), 1);
for g = 1:height(groups)
    sub = gaps(gaps.year == groups.year(g) & ...
        abs(gaps.eta - groups.eta(g)) <= cfg.objectiveTolerance & ...
        gaps.strategy == groups.strategy(g), :);
    carbon = sub.strategy_carbon_reduction;
    gap = sub.carbon_reduction_efficiency_gap;
    relativeGap = sub.relative_efficiency_gap;
    selectedK = sub.selected_K;

    row = table();
    row.year = groups.year(g);
    row.eta = groups.eta(g);
    row.economic_loss_budget = 1 - groups.eta(g);
    row.strategy = groups.strategy(g);
    row.strategy_kind = groups.strategy_kind(g);
    row.n_repeats = height(sub);
    row.strategy_carbon_reduction_mean = mean(carbon, 'omitnan');
    row.strategy_carbon_reduction_sd = std(carbon, 0, 'omitnan');
    row.strategy_carbon_reduction_p05 = quantile_local(carbon, 0.05);
    row.strategy_carbon_reduction_median = quantile_local(carbon, 0.50);
    row.strategy_carbon_reduction_p95 = quantile_local(carbon, 0.95);
    row.efficiency_gap_mean = mean(gap, 'omitnan');
    row.efficiency_gap_sd = std(gap, 0, 'omitnan');
    row.efficiency_gap_p05 = quantile_local(gap, 0.05);
    row.efficiency_gap_median = quantile_local(gap, 0.50);
    row.efficiency_gap_p95 = quantile_local(gap, 0.95);
    row.relative_efficiency_gap_mean = mean(relativeGap, 'omitnan');
    row.selected_K_mean = mean(selectedK, 'omitnan');
    row.selected_phi_mean = mean(sub.selected_phi, 'omitnan');
    row.frontier_carbon_reduction = sub.frontier_carbon_reduction(1);
    row.frontier_economic_loss = sub.frontier_economic_loss(1);
    row.frontier_selected_cities = sub.frontier_selected_cities(1);
    parts{g} = row;
end
summary = vertcat(parts{:});
end

function q = quantile_local(values, probability)
% 中文说明: 使用线性插值分位数，避免额外依赖 Statistics Toolbox。
values = sort(values(isfinite(values)));
if isempty(values)
    q = NaN;
    return;
end
if numel(values) == 1
    q = values(1);
    return;
end
position = 1 + (numel(values) - 1) * probability;
lower = floor(position);
upper = ceil(position);
weight = position - lower;
q = values(lower) * (1 - weight) + values(upper) * weight;
end
