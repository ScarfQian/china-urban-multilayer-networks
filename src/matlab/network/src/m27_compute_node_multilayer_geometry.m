function out = m27_compute_node_multilayer_geometry(inputs, cfg)
% M27_COMPUTE_NODE_MULTILAYER_GEOMETRY
% 计算节点在三层强度空间中的几何位置、平衡熵和主导层

topAll = table();
out = struct();
out.byYear = struct();
for iYear = 1:numel(cfg.years)
    yearValue = cfg.years(iYear);
    fieldName = "y" + string(yearValue);
    Y = inputs.yearData.(fieldName);
    M = Y.nodeMetrics;
    cityTable = Y.cityTable;
    roleMismatch = existing_or_zero_local(M, 'role_mismatch_index');
    strength = [double(M.investment_strength_layer_normalized), ...
        double(M.economic_strength_layer_normalized), ...
        double(M.carbon_strength_layer_normalized)];
    strength(~isfinite(strength) | strength < 0) = 0;
    denom = sum(strength, 2);
    p = zeros(size(strength));
    nz = denom > 0;
    p(nz, :) = strength(nz, :) ./ denom(nz);
    entropy = -sum(p .* log(max(p, eps)), 2);
    normalizedEntropy = entropy ./ log(3);
    [dominantShare, dominantIdx] = max(p, [], 2);
    dominantLayer = cfg.layerNames(dominantIdx)';
    distanceToBalanced = sqrt(sum((p - 1/3) .^ 2, 2));

    T = table();
    T.year = repmat(yearValue, height(cityTable), 1);
    T.city_code = double(cityTable.city_code);
    T.city_name = string(cityTable.city_name);
    T.p_I = p(:, 1);
    T.p_E = p(:, 2);
    T.p_C = p(:, 3);
    T.layer_balance_entropy = entropy;
    T.normalized_entropy = normalizedEntropy;
    T.dominant_layer = dominantLayer;
    T.dominant_layer_share = dominantShare;
    T.distance_to_balanced_point = distanceToBalanced;
    T.role_mismatch_index = roleMismatch;

    pathValue = fullfile(cfg.outputDir, "node_multilayer_geometry_" + string(yearValue) + ".csv");
    writetable(T, pathValue);
    out.byYear.(fieldName) = T;
    topAll = [topAll; top_geometry_local(T, yearValue)]; %#ok<AGROW>
end
topPath = fullfile(cfg.outputDir, 'table_multilayer_geometry_top_cities.csv');
writetable(topAll, topPath);
out.topTable = topAll;
out.topPath = string(topPath);
end

function v = existing_or_zero_local(T, name)
if ismember(name, T.Properties.VariableNames)
    v = double(T.(name));
else
    v = zeros(height(T), 1);
end
end

function topAll = top_geometry_local(T, yearValue)
metrics = ["normalized_entropy", "distance_to_balanced_point", "role_mismatch_index"];
directions = ["descend", "descend", "descend"];
topAll = table();
for iMetric = 1:numel(metrics)
    values = double(T.(metrics(iMetric)));
    [sortedValues, order] = sort(values, directions(iMetric));
    keepN = min(20, height(T));
    rows = table();
    rows.year = repmat(yearValue, keepN, 1);
    rows.metric = repmat(metrics(iMetric), keepN, 1);
    rows.rank = (1:keepN)';
    rows.city_code = double(T.city_code(order(1:keepN)));
    rows.city_name = string(T.city_name(order(1:keepN)));
    rows.value = sortedValues(1:keepN);
    rows.dominant_layer = string(T.dominant_layer(order(1:keepN)));
    topAll = [topAll; rows]; %#ok<AGROW>
end
end
