function [prefixes, ratioOrders, consistency] = ...
        m33_build_exact_transition_prefixes_260810(inputs, cfg)
% M33_BUILD_EXACT_TRANSITION_PREFIXES_260810
% 对九类既有策略和每个随机序列重建 K=0...309 的完整前缀曲线

prefixes = struct();
ratioParts = cell(numel(cfg.years), 1);
consistencyParts = cell(numel(cfg.years), 1);

for yIdx = 1:numel(cfg.years)
    year = cfg.years(yIdx);
    key = sprintf('y%d', year);
    governance = inputs.governance.(key);
    yearOrders = inputs.targetOrders(inputs.targetOrders.year == year, :);

    ratioOrder = build_ratio_order_local(governance, year, cfg);
    ratioParts{yIdx} = ratioOrder;

    groups = unique(yearOrders(:, {'strategy', 'repeat_id'}), 'rows', 'stable');
    prefixParts = cell(height(groups) + 1, 1);
    for g = 1:height(groups)
        strategy = groups.strategy(g);
        repeatId = groups.repeat_id(g);
        order = yearOrders(yearOrders.strategy == strategy & ...
            yearOrders.repeat_id == repeatId, :);
        order = sortrows(order, 'position');
        prefixParts{g} = build_prefix_local(order, governance, year, ...
            strategy, repeatId, "frozen_transition_target_city_orders", cfg);
    end
    prefixParts{end} = build_prefix_local(ratioOrder, governance, year, ...
        cfg.technicalBenchmark, 1, "derived_CB_share_to_PC_share_ratio", cfg);

    prefixes.(key) = vertcat(prefixParts{:});
    consistencyParts{yIdx} = compare_old_grid_local( ...
        prefixes.(key), inputs.oldMainCurves.(key), cfg);
end

ratioOrders = vertcat(ratioParts{:});
consistency = vertcat(consistencyParts{:});
end

function ratioOrder = build_ratio_order_local(governance, year, cfg)
% 中文说明: 比率基准只衡量模型内碳减排/经济损失效率，不承载治理公平含义。
e = governance.PC_share;
c = governance.CB_share;
rho = zeros(cfg.nCities, 1);
positiveEconomic = e > 0;
rho(positiveEconomic) = c(positiveEconomic) ./ e(positiveEconomic);
rho(~positiveEconomic & c > 0) = Inf;
rho(~positiveEconomic & c == 0) = 0;

ratioOrder = table();
ratioOrder.year = repmat(year, cfg.nCities, 1);
ratioOrder.strategy = repmat(cfg.technicalBenchmark, cfg.nCities, 1);
ratioOrder.repeat_id = ones(cfg.nCities, 1);
ratioOrder.position = zeros(cfg.nCities, 1);
ratioOrder.city_code = governance.city_code;
ratioOrder.city_name = governance.city_name;
ratioOrder.ranking_score = rho;
ratioOrder.ranking_variable = repmat("CB_share_divided_by_PC_share", cfg.nCities, 1);
ratioOrder.benchmark_role = repmat( ...
    "pure_efficiency_technical_benchmark_not_governance_strategy", ...
    cfg.nCities, 1);
ratioOrder = sortrows(ratioOrder, {'ranking_score', 'city_code'}, ...
    {'descend', 'ascend'});
ratioOrder.position = (1:cfg.nCities)';
end

function prefix = build_prefix_local(order, governance, year, strategy, ...
        repeatId, sourceOrder, cfg)
% 中文说明: 每个 K 点严格对应排序前 K 个城市，避免旧 1% 网格的取整损失。
order = sortrows(order, 'position');
[found, loc] = ismember(order.city_code, governance.city_code);
if ~all(found)
    error('m33_transition_prefix:CityJoin', ...
        'City-order join failed for %d %s repeat %d.', year, strategy, repeatId);
end

e = governance.PC_share(loc);
c = governance.CB_share(loc);
rho = zeros(cfg.nCities, 1);
positiveEconomic = e > 0;
rho(positiveEconomic) = c(positiveEconomic) ./ e(positiveEconomic);
rho(~positiveEconomic & c > 0) = Inf;

K = (0:cfg.nCities)';
phi = K / cfg.nCities;
economicLoss = cfg.mainTau * [0; cumsum(e)];
carbonReduction = cfg.mainTau * [0; cumsum(c)];
economicRetention = 1 - economicLoss;
transitionEfficiency = nan(size(K));
valid = economicLoss > cfg.objectiveTolerance;
transitionEfficiency(valid) = carbonReduction(valid) ./ economicLoss(valid);

if strategy == cfg.technicalBenchmark
    strategyKind = "technical_benchmark";
    isExisting = false;
    isGovernance = false;
elseif strategy == "random"
    strategyKind = "random_benchmark";
    isExisting = true;
    isGovernance = false;
else
    strategyKind = "governance_strategy";
    isExisting = true;
    isGovernance = true;
end

nRows = cfg.nCities + 1;
prefix = table();
prefix.year = repmat(year, nRows, 1);
prefix.strategy = repmat(strategy, nRows, 1);
prefix.strategy_kind = repmat(strategyKind, nRows, 1);
prefix.repeat_id = repmat(repeatId, nRows, 1);
prefix.K = K;
prefix.phi = phi;
prefix.city_code_added = [NaN; order.city_code];
prefix.city_name_added = [string(missing); string(order.city_name)];
prefix.economic_share_added = [0; e];
prefix.carbon_share_added = [0; c];
prefix.carbon_economic_ratio_added = [NaN; rho];
prefix.economic_loss = economicLoss;
prefix.economic_retention = economicRetention;
prefix.carbon_reduction = carbonReduction;
prefix.transition_efficiency = transitionEfficiency;
prefix.tau = repmat(cfg.mainTau, nRows, 1);
prefix.source_order = repmat(sourceOrder, nRows, 1);
prefix.is_existing_transition_strategy = repmat(isExisting, nRows, 1);
prefix.is_governance_strategy = repmat(isGovernance, nRows, 1);
prefix.is_technical_benchmark = repmat(strategy == cfg.technicalBenchmark, nRows, 1);
end

function consistency = compare_old_grid_local(prefix, oldCurves, cfg)
% 中文说明: 使用冻结表中已保存的目标城市数定位新前缀，避免重复解释浮点 ceil。
groups = unique(oldCurves(:, {'year', 'strategy', 'repeat_id'}), ...
    'rows', 'stable');
parts = cell(height(groups), 1);
for g = 1:height(groups)
    year = groups.year(g);
    strategy = groups.strategy(g);
    repeatId = groups.repeat_id(g);
    old = oldCurves(oldCurves.year == year & ...
        oldCurves.strategy == strategy & oldCurves.repeat_id == repeatId, :);
    old = sortrows(old, 'phi');
    current = prefix(prefix.year == year & prefix.strategy == strategy & ...
        prefix.repeat_id == repeatId, :);
    current = sortrows(current, 'K');
    index = round(old.n_targeted_cities) + 1;
    if any(index < 1 | index > height(current))
        error('m33_transition_prefix:OldTargetCount', ...
            'Old target count is outside K=0...309 for %d %s repeat %d.', ...
            year, strategy, repeatId);
    end
    matched = current(index, :);
    expectedCount = ceil(old.phi * cfg.nCities);
    countFormulaOk = old.n_targeted_cities == expectedCount;
    carbonDiff = matched.carbon_reduction - old.carbon_reduction;
    retentionDiff = matched.economic_retention - old.economic_retention;
    lossDiff = matched.economic_loss - old.economic_loss;
    pointOk = countFormulaOk & ...
        abs(carbonDiff) <= cfg.consistencyTolerance & ...
        abs(retentionDiff) <= cfg.consistencyTolerance & ...
        abs(lossDiff) <= cfg.consistencyTolerance;

    part = table();
    part.year = old.year;
    part.strategy = old.strategy;
    part.repeat_id = old.repeat_id;
    part.old_phi = old.phi;
    part.K = old.n_targeted_cities;
    part.ceil_phi_n = expectedCount;
    part.target_count_formula_ok = countFormulaOk;
    part.old_carbon_reduction = old.carbon_reduction;
    part.new_carbon_reduction = matched.carbon_reduction;
    part.carbon_reduction_difference = carbonDiff;
    part.old_economic_retention = old.economic_retention;
    part.new_economic_retention = matched.economic_retention;
    part.economic_retention_difference = retentionDiff;
    part.old_economic_loss = old.economic_loss;
    part.new_economic_loss = matched.economic_loss;
    part.economic_loss_difference = lossDiff;
    part.status = repmat("FAIL", height(part), 1);
    part.status(pointOk) = "PASS";
    parts{g} = part;
end
consistency = vertcat(parts{:});
end
