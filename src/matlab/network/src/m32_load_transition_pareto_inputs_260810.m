function inputs = m32_load_transition_pareto_inputs_260810(cfg)
% M32_LOAD_TRANSITION_PARETO_INPUTS_260810
% 只读加载治理份额、既有排序和旧正式情景曲线

sourceDir = char(cfg.sourceTransitionDir);
required = [
    "governance_mismatch_metrics_2015.csv"
    "governance_mismatch_metrics_2020.csv"
    "transition_target_city_orders.csv"
    "transition_stress_curves_2015.csv"
    "transition_stress_curves_2020.csv"
    ];
for i = 1:numel(required)
    path = fullfile(sourceDir, char(required(i)));
    if ~exist(path, 'file')
        error('m32_transition_pareto:MissingInput', ...
            'Required final-freeze input is missing: %s', path);
    end
end

inputs = struct();
inputs.sourceDir = string(sourceDir);
inputs.governance = struct();
inputs.oldMainCurves = struct();

for year = cfg.years
    key = sprintf('y%d', year);
    govPath = fullfile(sourceDir, ...
        sprintf('governance_mismatch_metrics_%d.csv', year));
    gov = readtable(govPath, 'VariableNamingRule', 'preserve');
    require_columns_local(gov, ["year", "city_code", "city_name", ...
        "PC_share", "CB_share"], govPath);
    gov.city_name = string(gov.city_name);
    gov = sortrows(gov, 'city_code');
    validate_governance_local(gov, year, cfg);
    inputs.governance.(key) = gov;

    curvePath = fullfile(sourceDir, ...
        sprintf('transition_stress_curves_%d.csv', year));
    curves = readtable(curvePath, 'VariableNamingRule', 'preserve');
    require_columns_local(curves, ["year", "shock_type", "strategy", ...
        "repeat_id", "phi", "tau", "delta", "n_targeted_cities", ...
        "carbon_reduction", "economic_retention", "economic_loss"], curvePath);
    mainMask = string(curves.shock_type) == "carbon_constrained_production" & ...
        abs(curves.tau - cfg.mainTau) <= cfg.objectiveTolerance & ...
        abs(curves.delta) <= cfg.objectiveTolerance;
    curves = curves(mainMask, :);
    curves.strategy = string(curves.strategy);
    validate_old_curves_local(curves, year, cfg);
    inputs.oldMainCurves.(key) = curves;
end

ordersPath = fullfile(sourceDir, 'transition_target_city_orders.csv');
orders = readtable(ordersPath, 'VariableNamingRule', 'preserve');
require_columns_local(orders, ["year", "strategy", "repeat_id", ...
    "position", "city_code", "city_name", "ranking_score", ...
    "ranking_variable"], ordersPath);
orders.strategy = string(orders.strategy);
orders.city_name = string(orders.city_name);
orders.ranking_variable = string(orders.ranking_variable);
validate_orders_local(orders, inputs.governance, cfg);
inputs.targetOrders = orders;
inputs.requiredFiles = required;
end

function validate_governance_local(gov, year, cfg)
% 中文说明: 生产和碳份额必须来自相同 309 城市冻结样本并分别归一为 1。
if height(gov) ~= cfg.nCities || numel(unique(gov.city_code)) ~= cfg.nCities
    error('m32_transition_pareto:CityCount', ...
        '%d governance table must contain %d unique cities.', year, cfg.nCities);
end
if any(gov.year ~= year)
    error('m32_transition_pareto:YearMismatch', ...
        'Governance table year mismatch for %d.', year);
end
if any(ismember(gov.city_code, cfg.excludedProxyCodes))
    error('m32_transition_pareto:ProxyNode', ...
        'Proxy city code found in %d governance input.', year);
end
if any(~isfinite(gov.PC_share)) || any(~isfinite(gov.CB_share)) || ...
        any(gov.PC_share < -cfg.feasibilityTolerance) || ...
        any(gov.CB_share < -cfg.feasibilityTolerance)
    error('m32_transition_pareto:InvalidShares', ...
        'Nonfinite or negative PC_share/CB_share found for %d.', year);
end
if abs(sum(gov.PC_share) - 1) > cfg.feasibilityTolerance || ...
        abs(sum(gov.CB_share) - 1) > cfg.feasibilityTolerance
    error('m32_transition_pareto:ShareNormalization', ...
        'PC_share and CB_share must each sum to one for %d.', year);
end
end

function validate_orders_local(orders, governance, cfg)
% 中文说明: 每个确定性策略和每个随机重复都必须是完整、无重复的 309 城市排列。
actualStrategies = unique(orders.strategy);
if ~all(ismember(cfg.strategies, actualStrategies)) || ...
        ~all(ismember(actualStrategies, cfg.strategies))
    error('m32_transition_pareto:StrategySet', ...
        'Frozen target-order strategy set differs from the configured nine strategies.');
end
for year = cfg.years
    key = sprintf('y%d', year);
    expectedCodes = governance.(key).city_code;
    for strategy = cfg.strategies
        sub = orders(orders.year == year & orders.strategy == strategy, :);
        repeats = unique(sub.repeat_id);
        expectedRepeats = 1;
        if strategy == "random"
            expectedRepeats = cfg.randomRepeats;
        end
        if numel(repeats) ~= expectedRepeats
            error('m32_transition_pareto:RepeatCount', ...
                '%d %s has %d repeats; expected %d.', ...
                year, strategy, numel(repeats), expectedRepeats);
        end
        for repeatId = reshape(repeats, 1, [])
            group = sortrows(sub(sub.repeat_id == repeatId, :), 'position');
            if height(group) ~= cfg.nCities || ...
                    ~isequal(group.position(:), (1:cfg.nCities)') || ...
                    numel(unique(group.city_code)) ~= cfg.nCities || ...
                    ~isequal(sort(group.city_code), sort(expectedCodes))
                error('m32_transition_pareto:IncompleteOrder', ...
                    '%d %s repeat %d is not a complete city permutation.', ...
                    year, strategy, repeatId);
            end
        end
    end
end
end

function validate_old_curves_local(curves, year, cfg)
% 中文说明: 旧曲线只用于一致性核对，必须保留完整九策略和 50 个随机重复。
if isempty(curves) || any(curves.year ~= year)
    error('m32_transition_pareto:OldCurveYear', ...
        'No valid frozen main-scenario curves found for %d.', year);
end
for strategy = cfg.strategies
    sub = curves(curves.strategy == strategy, :);
    repeats = unique(sub.repeat_id);
    expectedRepeats = 1;
    if strategy == "random"
        expectedRepeats = cfg.randomRepeats;
    end
    if numel(repeats) ~= expectedRepeats
        error('m32_transition_pareto:OldCurveRepeats', ...
            'Frozen %d %s curve repeat count is inconsistent.', year, strategy);
    end
    for repeatId = reshape(repeats, 1, [])
        group = sub(sub.repeat_id == repeatId, :);
        if height(group) ~= 101 || numel(unique(group.phi)) ~= 101
            error('m32_transition_pareto:OldCurveGrid', ...
                'Frozen %d %s repeat %d must contain 101 old-grid points.', ...
                year, strategy, repeatId);
        end
    end
end
end

function require_columns_local(tbl, required, sourcePath)
missing = required(~ismember(required, string(tbl.Properties.VariableNames)));
if ~isempty(missing)
    error('m32_transition_pareto:MissingColumns', ...
        'Missing columns in %s: %s', sourcePath, strjoin(missing, ', '));
end
end
