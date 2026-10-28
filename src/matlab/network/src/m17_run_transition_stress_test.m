function out = m17_run_transition_stress_test(layerBundle, singleOut, roleOut, alignment, yearValue, cfg)
% M17_RUN_TRANSITION_STRESS_TEST
% Simulate production-constrained low-carbon transition pressure without
%   deleting nodes from the city network.

tauValues = double(cfg.transitionTauValues(:)');
phiValues = double(cfg.transitionPhiValues(:)');
epsilonValue = double(cfg.transitionEpsilon);
randomRepeats = double(cfg.transitionRandomRepeats);

economicW = double(layerBundle.economic.W);
carbonW = double(layerBundle.carbon.W);
economicOut = sum(economicW, 2);
carbonOut = sum(carbonW, 2);
economicTotal = max(sum(economicW, 'all'), epsilonValue);
carbonTotal = max(sum(carbonW, 'all'), epsilonValue);

orderSpecs = build_order_specs_local(singleOut.nodeMetricsTable, roleOut.roleTable, alignment);
[randomCurveTable, randomAucTable, randomOrderTable] = random_strategy_local( ...
    economicOut, carbonOut, economicTotal, carbonTotal, phiValues, tauValues, ...
    randomRepeats, yearValue, alignment, cfg, epsilonValue);

curveRows = table();
aucRows = table();
targetRows = table();
for iOrder = 1:numel(orderSpecs)
    orderSpec = orderSpecs(iOrder);
    targetRows = [targetRows; target_order_table_local(yearValue, orderSpec, alignment)]; %#ok<AGROW>
    [curveTable, aucTable] = evaluate_order_local( ...
        orderSpec.name, orderSpec.order, economicOut, carbonOut, economicTotal, carbonTotal, ...
        phiValues, tauValues, yearValue, epsilonValue);
    curveRows = [curveRows; curveTable]; %#ok<AGROW>
    aucRows = [aucRows; aucTable]; %#ok<AGROW>
end

curveRows = [curveRows; randomCurveTable];
aucRows = [aucRows; randomAucTable];
targetRows = [targetRows; randomOrderTable];

curvesPath = fullfile(cfg.resultsDir, "transition_stress_curves_" + string(yearValue) + ".csv");
writetable(curveRows, curvesPath);

out = struct();
out.year = yearValue;
out.curveTable = curveRows;
out.aucSummaryTable = aucRows;
out.targetOrderTable = targetRows;
out.curvesPath = string(curvesPath);
end

function orderSpecs = build_order_specs_local(nodeMetrics, roleTable, alignment)
orderSpecs = struct([]);
orderSpecs = append_order_local(orderSpecs, "carbon_hub_order", ...
    layer_order_local(nodeMetrics, "carbon", "out_strength", alignment), ...
    layer_scores_local(nodeMetrics, "carbon", "out_strength", alignment));
orderSpecs = append_order_local(orderSpecs, "economic_hub_order", ...
    layer_order_local(nodeMetrics, "economic", "out_strength", alignment), ...
    layer_scores_local(nodeMetrics, "economic", "out_strength", alignment));
orderSpecs = append_order_local(orderSpecs, "investment_hub_order", ...
    layer_order_local(nodeMetrics, "investment", "out_strength", alignment), ...
    layer_scores_local(nodeMetrics, "investment", "out_strength", alignment));
orderSpecs = append_order_local(orderSpecs, "role_mismatch_order", ...
    role_order_local(roleTable, alignment, "role_mismatch_score"), ...
    role_scores_local(roleTable, alignment, "role_mismatch_score"));
orderSpecs = append_order_local(orderSpecs, "multilayer_bridge_order", ...
    role_order_local(roleTable, alignment, "bridge_score"), ...
    role_scores_local(roleTable, alignment, "bridge_score"));
end

function orderSpecs = append_order_local(orderSpecs, name, order, scores)
item = struct();
item.name = string(name);
item.order = order(:);
item.scores = scores(:);
if isempty(orderSpecs)
    orderSpecs = item;
else
    orderSpecs(end + 1) = item; %#ok<AGROW>
end
end

function order = layer_order_local(nodeMetrics, layerName, scoreField, alignment)
scores = layer_scores_local(nodeMetrics, layerName, scoreField, alignment);
[~, order] = sort(scores, 'descend');
end

function scores = layer_scores_local(nodeMetrics, layerName, scoreField, alignment)
hit = string(nodeMetrics.layer) == string(layerName);
T = nodeMetrics(hit, :);
[isFound, idx] = ismember(double(alignment.cityTable.city_code), double(T.city_code));
if ~all(isFound)
    error('m17_run_transition_stress_test:MissingLayerCity', ...
        'Layer %s is missing %d cities required by transition stress test.', ...
        string(layerName), sum(~isFound));
end
scores = double(T{idx, scoreField});
scores(~isfinite(scores)) = -Inf;
end

function order = role_order_local(roleTable, alignment, scoreField)
scores = role_scores_local(roleTable, alignment, scoreField);
[~, order] = sort(scores, 'descend');
end

function scores = role_scores_local(roleTable, alignment, scoreField)
[isFound, idx] = ismember(double(alignment.cityTable.city_code), double(roleTable.city_code));
if ~all(isFound)
    error('m17_run_transition_stress_test:MissingRoleCity', ...
        'Role table is missing %d cities required by transition stress test.', sum(~isFound));
end
scores = double(roleTable{idx, scoreField});
scores(~isfinite(scores)) = -Inf;
end

function [curveTable, aucTable] = evaluate_order_local(strategyName, order, economicOut, carbonOut, economicTotal, carbonTotal, phiValues, tauValues, yearValue, epsilonValue)
curveRows = cell(numel(phiValues) * numel(tauValues), 8);
rowCursor = 0;
for iTau = 1:numel(tauValues)
    tauValue = tauValues(iTau);
    for iPhi = 1:numel(phiValues)
        phiValue = phiValues(iPhi);
        targetCount = target_count_local(phiValue, numel(order));
        if targetCount == 0
            econAffected = 0;
            carbonAffected = 0;
        else
            targetIdx = order(1:targetCount);
            econAffected = sum(economicOut(targetIdx));
            carbonAffected = sum(carbonOut(targetIdx));
        end
        economicRetention = 1 - tauValue * econAffected / economicTotal;
        carbonReduction = tauValue * carbonAffected / carbonTotal;
        economicLoss = 1 - economicRetention;
        transitionEfficiency = carbonReduction / (economicLoss + epsilonValue);
        rowCursor = rowCursor + 1;
        curveRows(rowCursor, :) = { ...
            yearValue, char(strategyName), phiValue, tauValue, ...
            carbonReduction, economicRetention, economicLoss, transitionEfficiency};
    end
end

curveTable = cell2table(curveRows, 'VariableNames', { ...
    'year','strategy','phi','tau','carbon_reduction','economic_retention','economic_loss','transition_efficiency'});
aucTable = auc_summary_local(curveTable);
end

function aucTable = auc_summary_local(curveTable)
[G, keys] = findgroups(curveTable(:, {'year','strategy','tau'}));
aucCarbon = splitapply(@trapz_by_phi_local, curveTable.phi, curveTable.carbon_reduction, G);
aucRetention = splitapply(@trapz_by_phi_local, curveTable.phi, curveTable.economic_retention, G);
aucLoss = splitapply(@trapz_by_phi_local, curveTable.phi, curveTable.economic_loss, G);
aucEfficiency = splitapply(@trapz_by_phi_local, curveTable.phi, curveTable.transition_efficiency, G);
aucTable = keys;
aucTable.auc_carbon_reduction = aucCarbon;
aucTable.auc_economic_retention = aucRetention;
aucTable.auc_economic_loss = aucLoss;
aucTable.auc_transition_efficiency = aucEfficiency;
end

function val = trapz_by_phi_local(phi, y)
[phiSorted, idx] = sort(double(phi));
ySorted = double(y(idx));
val = trapz(phiSorted, ySorted);
end

function count = target_count_local(phiValue, numCities)
if phiValue <= 0
    count = 0;
else
    count = min(numCities, ceil(phiValue * numCities));
end
end

function targetTable = target_order_table_local(yearValue, orderSpec, alignment)
N = numel(orderSpec.order);
rows = cell(N, 6);
for pos = 1:N
    cityIdx = orderSpec.order(pos);
    rows(pos, :) = { ...
        yearValue, ...
        char(orderSpec.name), ...
        pos, ...
        double(alignment.cityTable.city_code(cityIdx)), ...
        char(alignment.cityTable.city_cn(cityIdx)), ...
        double(orderSpec.scores(cityIdx))};
end
targetTable = cell2table(rows, 'VariableNames', { ...
    'year','strategy','position','city_code','city_name','ranking_score'});
end

function [curveTable, aucTable, orderTable] = random_strategy_local(economicOut, carbonOut, economicTotal, carbonTotal, phiValues, tauValues, randomRepeats, yearValue, alignment, cfg, epsilonValue)
N = alignment.numCities;
allCurves = table();
positionSum = zeros(N, 1);
rng(double(cfg.randomSeed) + 100000 + double(yearValue));
for iRepeat = 1:randomRepeats
    order = randperm(N)';
    positionSum(order) = positionSum(order) + (1:N)';
    [curveOne, ~] = evaluate_order_local("random_order", order, economicOut, carbonOut, economicTotal, carbonTotal, phiValues, tauValues, yearValue, epsilonValue);
    curveOne.repeat_id = repmat(iRepeat, height(curveOne), 1);
    allCurves = [allCurves; curveOne]; %#ok<AGROW>
end

[G, keys] = findgroups(allCurves(:, {'year','strategy','phi','tau'}));
carbonReduction = splitapply(@mean, allCurves.carbon_reduction, G);
economicRetention = splitapply(@mean, allCurves.economic_retention, G);
economicLoss = splitapply(@mean, allCurves.economic_loss, G);
transitionEfficiency = splitapply(@mean, allCurves.transition_efficiency, G);
curveTable = keys;
curveTable.carbon_reduction = carbonReduction;
curveTable.economic_retention = economicRetention;
curveTable.economic_loss = economicLoss;
curveTable.transition_efficiency = transitionEfficiency;
curveTable = sortrows(curveTable, {'year','strategy','tau','phi'});
aucTable = auc_summary_local(curveTable);

meanPosition = positionSum ./ randomRepeats;
[~, representativeOrder] = sort(meanPosition, 'ascend');
orderSpec = struct();
orderSpec.name = "random_order";
orderSpec.order = representativeOrder(:);
orderSpec.scores = -meanPosition(:);
orderTable = target_order_table_local(yearValue, orderSpec, alignment);
end
