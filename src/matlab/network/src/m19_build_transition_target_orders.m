function out = m19_build_transition_target_orders(inputs, governance, cfg)
% M19_BUILD_TRANSITION_TARGET_ORDERS
% 构造低碳转型压力测试的城市排序策略

allOrders = table();
randomRepeats = resolve_random_repeats_local(inputs, cfg);

for iYear = 1:numel(cfg.years)
    yearValue = cfg.years(iYear);
    fieldName = "y" + string(yearValue);
    cityTable = inputs.yearData.(fieldName).cityTable;
    roleTable = align_table_local(inputs.yearData.(fieldName).roleTable, cityTable);
    G = governance.byYear.(fieldName);

    allOrders = [allOrders; deterministic_order_local(yearValue, "carbon_hub", G.CB_share, "CB_share", cityTable)]; %#ok<AGROW>
    allOrders = [allOrders; deterministic_order_local(yearValue, "production_hub", G.PC_share, "PC_share", cityTable)]; %#ok<AGROW>
    allOrders = [allOrders; deterministic_order_local(yearValue, "investment_hub", G.IC_share, "IC_share", cityTable)]; %#ok<AGROW>
    allOrders = [allOrders; deterministic_order_local(yearValue, "role_mismatch", double(roleTable.role_mismatch_score), "role_mismatch_score", cityTable)]; %#ok<AGROW>
    allOrders = [allOrders; deterministic_order_local(yearValue, "multilayer_bridge", bridge_score_local(roleTable, G), "bridge_score_or_participation", cityTable)]; %#ok<AGROW>
    allOrders = [allOrders; deterministic_order_local(yearValue, "capital_carbon_mismatch_abs", abs(G.CRM), "abs_CRM", cityTable)]; %#ok<AGROW>
    allOrders = [allOrders; deterministic_order_local(yearValue, "carbon_burden_low_control", -G.CRM, "CB_z_minus_IC_z", cityTable)]; %#ok<AGROW>
    allOrders = [allOrders; deterministic_order_local(yearValue, "investment_carbon_exposure", G.ICE, "ICE", cityTable)]; %#ok<AGROW>

    rng(double(cfg.randomSeed) + double(yearValue));
    n = height(cityTable);
    for repeatId = 1:randomRepeats
        order = randperm(n)';
        allOrders = [allOrders; order_table_local(yearValue, "random", repeatId, order, -double((1:n)'), "random_permutation", cityTable)]; %#ok<AGROW>
    end
end

ordersPath = fullfile(cfg.outputDir, 'transition_target_city_orders.csv');
writetable(allOrders, ordersPath);

out = struct();
out.table = allOrders;
out.path = string(ordersPath);
out.randomRepeats = randomRepeats;
end

function randomRepeats = resolve_random_repeats_local(inputs, cfg)
if isfield(inputs, 'randomRepeatsFromManifest') && isfinite(inputs.randomRepeatsFromManifest)
    randomRepeats = double(inputs.randomRepeatsFromManifest);
else
    randomRepeats = double(cfg.randomRepeats);
end
if randomRepeats <= 0
    randomRepeats = double(cfg.randomRepeats);
end
end

function aligned = align_table_local(T, cityTable)
[found, idx] = ismember(double(cityTable.city_code), double(T.city_code));
if ~all(found)
    error('m19_build_transition_target_orders:CityMissing', 'Role table misses %d cities.', sum(~found));
end
aligned = T(idx, :);
end

function score = bridge_score_local(roleTable, G)
if ismember('bridge_score', roleTable.Properties.VariableNames)
    score = double(roleTable.bridge_score);
elseif ismember('participation_normalized', G.Properties.VariableNames)
    score = double(G.participation_normalized);
else
    score = zeros(height(G), 1);
end
score(~isfinite(score)) = -Inf;
end

function T = deterministic_order_local(yearValue, strategy, scores, variableName, cityTable)
[~, order] = sort(double(scores), 'descend', 'MissingPlacement', 'last');
T = order_table_local(yearValue, strategy, 1, order, double(scores(order)), variableName, cityTable);
end

function T = order_table_local(yearValue, strategy, repeatId, order, rankingScores, rankingVariable, cityTable)
n = numel(order);
T = table();
T.year = repmat(yearValue, n, 1);
T.strategy = repmat(string(strategy), n, 1);
T.repeat_id = repmat(repeatId, n, 1);
T.position = (1:n)';
T.city_code = double(cityTable.city_code(order));
T.city_name = string(cityTable.city_name(order));
T.ranking_score = double(rankingScores(:));
T.ranking_variable = repmat(string(rankingVariable), n, 1);
end
