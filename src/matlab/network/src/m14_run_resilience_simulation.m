function out = m14_run_resilience_simulation(layerBundle, backbones, singleOut, roleOut, alignment, yearValue, cfg)
% M14_RUN_RESILIENCE_SIMULATION
% Simulate node-removal attacks by layer hub order, multilayer-role order,
%   and random order, then summarize flow and connectivity retention.

layerNames = ["investment","economic","carbon"];
nodeMetrics = singleOut.nodeMetricsTable;
roleTable = roleOut.roleTable;

orders = struct([]);
orders = append_order_local(orders, "investment_hub_order", city_order_local(nodeMetrics, "investment", 'total_strength', alignment));
orders = append_order_local(orders, "economic_hub_order", city_order_local(nodeMetrics, "economic", 'total_strength', alignment));
orders = append_order_local(orders, "carbon_hub_order", city_order_local(nodeMetrics, "carbon", 'total_strength', alignment));
orders = append_order_local(orders, "multilayer_role_order", role_order_local(roleTable));

rng(cfg.randomSeed + 10 * yearValue);
for iRepeat = 1:cfg.randomAttackRepeats
    orders = append_order_local(orders, "random_order", randperm(alignment.numCities)', iRepeat);
end

curveRows = cell(0, 8);
aucRows = cell(0, 6);
attackRows = cell(0, 6);
diagnosticRows = cell(0, 7);
diagnosticRows(end + 1, :) = {yearValue, 'all', 0, 'all', 'efficiency_retention_status', NaN, char(string(cfg.efficiencyRetentionStatus))}; %#ok<AGROW>

for iOrder = 1:numel(orders)
    orderSpec = orders(iOrder);
    for pos = 1:numel(orderSpec.order)
        cityIdx = orderSpec.order(pos);
        attackRows(end + 1, :) = { ... %#ok<AGROW>
            yearValue, ...
            char(orderSpec.name), ...
            orderSpec.repeat_id, ...
            pos, ...
            alignment.cityTable.city_code(cityIdx), ...
            char(alignment.cityTable.city_cn(cityIdx))};
    end

    for iLayer = 1:numel(layerNames)
        layerName = layerNames(iLayer);
        W = double(layerBundle.(layerName).W);
        B = double(backbones.(layerName).densityMatched > 0);
        B = double((B + B') > 0);
        initialFlow = max(sum(W, 'all'), eps);
        initialEfficiency = global_efficiency_local(B, cfg.computeEfficiency);
        fractions = zeros(alignment.numCities + 1, 1);
        flowCurve = zeros(alignment.numCities + 1, 1);
        giantCurve = zeros(alignment.numCities + 1, 1);
        efficiencyCurve = nan(alignment.numCities + 1, 1);

        removedMask = false(alignment.numCities, 1);
        for step = 0:alignment.numCities
            keep = ~removedMask;
            subW = W(keep, keep);
            subB = B(keep, keep);
            fractions(step + 1) = step / alignment.numCities;
            flowCurve(step + 1) = sum(subW, 'all') / initialFlow;
            giantCurve(step + 1) = largest_component_share_local(subB, alignment.numCities);
            if cfg.computeEfficiency
                currentEfficiency = global_efficiency_local(subB, true);
                if initialEfficiency > 0
                    efficiencyCurve(step + 1) = currentEfficiency / initialEfficiency;
                end
            end
            if step < alignment.numCities
                removedMask(orderSpec.order(step + 1)) = true;
            end
        end

        curveRows = [curveRows; curve_rows_local(yearValue, orderSpec.name, orderSpec.repeat_id, layerName, fractions, flowCurve, giantCurve, efficiencyCurve)]; %#ok<AGROW>
        aucRows(end + 1, :) = auc_row_local(yearValue, orderSpec.name, orderSpec.repeat_id, layerName, "flow_retention", trapz(fractions, flowCurve)); %#ok<AGROW>
        aucRows(end + 1, :) = auc_row_local(yearValue, orderSpec.name, orderSpec.repeat_id, layerName, "giant_component_retention", trapz(fractions, giantCurve)); %#ok<AGROW>

        if cfg.computeEfficiency
            efficiencyAuc = trapz(fractions, nan_to_zero_local(efficiencyCurve));
            diagnosticRows(end + 1, :) = { ... %#ok<AGROW>
                yearValue, ...
                char(orderSpec.name), ...
                orderSpec.repeat_id, ...
                char(layerName), ...
                'efficiency_auc_diagnostic_only', ...
                efficiencyAuc, ...
                'Efficiency retention is diagnostic_only and excluded from paper-ready AUC tables.'};
            diagnosticRows(end + 1, :) = { ... %#ok<AGROW>
                yearValue, ...
                char(orderSpec.name), ...
                orderSpec.repeat_id, ...
                char(layerName), ...
                'efficiency_curve_max', ...
                max(nan_to_zero_local(efficiencyCurve)), ...
                'Used to detect whether efficiency retention exceeds one.'};
        end
    end
end

curveTable = cell2table(curveRows, 'VariableNames', {'year','order_name','repeat_id','layer','fraction_removed','flow_retention','giant_component_retention','efficiency_retention'});
aucSummaryTable = cell2table(aucRows, 'VariableNames', {'year','order_name','repeat_id','layer','metric','auc'});
attackOrderTable = cell2table(attackRows, 'VariableNames', {'year','order_name','repeat_id','position','city_code','city_name'});
diagnosticsTable = cell2table(diagnosticRows, 'VariableNames', {'year','order_name','repeat_id','layer','metric','value','note'});

writetable(curveTable, fullfile(cfg.resultsDir, "resilience_curves_" + string(yearValue) + ".csv"));

out = struct();
out.year = yearValue;
out.curveTable = curveTable;
out.aucSummaryTable = aucSummaryTable;
out.attackOrderTable = attackOrderTable;
out.diagnosticsTable = diagnosticsTable;
end

function orders = append_order_local(orders, name, order, repeatId)
if nargin < 4
    repeatId = 1;
end
item = struct('name', string(name), 'order', order(:), 'repeat_id', repeatId);
if isempty(orders)
    orders = item;
else
    orders(end + 1) = item; %#ok<AGROW>
end
end

function order = city_order_local(nodeMetrics, layerName, metricName, alignment)
hit = nodeMetrics.layer == layerName;
T = sortrows(nodeMetrics(hit, :), metricName, 'descend');
[~, order] = ismember(double(T.city_code), double(alignment.cityTable.city_code));
if any(order == 0)
    error('m14_run_resilience_simulation:MissingAttackCity', ...
        'Failed to map ranked city order for layer %s back to the canonical city list.', layerName);
end
end

function order = role_order_local(roleTable)
attackScore = double(roleTable.bridge_score) + double(roleTable.role_mismatch_score) + ...
    max([double(roleTable.capital_control_score), double(roleTable.production_hub_score), double(roleTable.carbon_responsibility_score)], [], 2);
[~, order] = sort(attackScore, 'descend');
end

function rows = curve_rows_local(yearValue, orderName, repeatId, layerName, fractions, flowCurve, giantCurve, efficiencyCurve)
rows = cell(numel(fractions), 8);
for i = 1:numel(fractions)
    rows(i, :) = {yearValue, char(orderName), repeatId, char(layerName), fractions(i), flowCurve(i), giantCurve(i), efficiencyCurve(i)};
end
end

function row = auc_row_local(yearValue, orderName, repeatId, layerName, metricName, aucVal)
row = {yearValue, char(orderName), repeatId, char(layerName), char(metricName), aucVal};
end

function share = largest_component_share_local(B, totalNodeCount)
if isempty(B)
    share = 0;
    return;
end
compSizes = component_sizes_local(B);
share = max(compSizes) / totalNodeCount;
end

function eff = global_efficiency_local(B, doCompute)
if ~doCompute
    eff = NaN;
    return;
end
N = size(B, 1);
if N <= 1
    eff = 0;
    return;
end

effSum = 0;
for i = 1:N
    d = bfs_distance_local(B, i);
    invD = zeros(size(d));
    mask = isfinite(d) & d > 0;
    invD(mask) = 1 ./ d(mask);
    effSum = effSum + sum(invD);
end
eff = effSum / (N * (N - 1));
end

function dist = bfs_distance_local(B, startNode)
N = size(B, 1);
dist = inf(N, 1);
dist(startNode) = 0;
queue = startNode;
head = 1;
while head <= numel(queue)
    node = queue(head);
    head = head + 1;
    nbr = find(B(node, :) > 0);
    for i = 1:numel(nbr)
        if ~isfinite(dist(nbr(i)))
            dist(nbr(i)) = dist(node) + 1;
            queue(end + 1) = nbr(i); %#ok<AGROW>
        end
    end
end
end

function sizes = component_sizes_local(B)
N = size(B, 1);
visited = false(N, 1);
sizes = [];
for i = 1:N
    if visited(i)
        continue;
    end
    queue = i;
    visited(i) = true;
    head = 1;
    count = 0;
    while head <= numel(queue)
        node = queue(head);
        head = head + 1;
        count = count + 1;
        nbr = find(B(node, :) > 0);
        for j = 1:numel(nbr)
            if ~visited(nbr(j))
                visited(nbr(j)) = true;
                queue(end + 1) = nbr(j); %#ok<AGROW>
            end
        end
    end
    sizes(end + 1) = count; %#ok<AGROW>
end
if isempty(sizes)
    sizes = 0;
end
end

function x = nan_to_zero_local(x)
x(isnan(x)) = 0;
end
