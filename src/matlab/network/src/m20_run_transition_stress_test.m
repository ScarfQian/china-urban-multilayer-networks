function out = m20_run_transition_stress_test(inputs, targetOrders, cfg)
% M20_RUN_TRANSITION_STRESS_TEST
% 执行低碳转型压力测试，包括生产约束、清洁脱碳和混合转型情景

out = struct();
out.curvesByYear = struct();
aucRepeatAll = table();

for iYear = 1:numel(cfg.years)
    yearValue = cfg.years(iYear);
    fieldName = "y" + string(yearValue);
    Y = inputs.yearData.(fieldName);
    yearOrders = targetOrders.table(targetOrders.table.year == yearValue, :);
    curveTable = run_year_curves_local(Y, yearOrders, cfg, yearValue);
    curvePath = fullfile(cfg.outputDir, "transition_stress_curves_" + string(yearValue) + ".csv");
    writetable(curveTable, curvePath);
    out.curvesByYear.(fieldName) = curveTable;
    out.curvePaths.(fieldName) = string(curvePath);
    aucRepeatAll = [aucRepeatAll; auc_repeat_table_local(curveTable)]; %#ok<AGROW>
end

aucSummary = auc_summary_local(aucRepeatAll);
aucPath = fullfile(cfg.outputDir, 'transition_stress_auc_summary.csv');
writetable(aucSummary, aucPath);
out.aucByRepeat = aucRepeatAll;
out.aucSummary = aucSummary;
out.aucPath = string(aucPath);
end

function curveTable = run_year_curves_local(Y, orders, cfg, yearValue)
economicOut = sum(double(Y.W_E), 2);
carbonOut = sum(double(Y.W_C), 2);
economicTotal = sum(double(Y.W_E), 'all');
carbonTotal = sum(double(Y.W_C), 'all');
if economicTotal <= 0 || carbonTotal <= 0
    error('m20_run_transition_stress_test:ZeroLayerTotal', 'Year %d has zero economic or carbon layer total.', yearValue);
end

groups = unique(orders(:, {'strategy', 'repeat_id'}), 'rows', 'stable');
nPhi = numel(cfg.phiGrid);
nShockParam = numel(cfg.tauValues) + numel(cfg.deltaValues) + numel(cfg.tauValues) * numel(cfg.deltaValues);
rowCount = height(groups) * nPhi * nShockParam;
rows = cell(rowCount, 16);
cursor = 0;

for iGroup = 1:height(groups)
    hit = orders.strategy == groups.strategy(iGroup) & orders.repeat_id == groups.repeat_id(iGroup);
    orderRows = sortrows(orders(hit, :), 'position');
    [found, orderIdx] = ismember(double(orderRows.city_code), double(Y.cityTable.city_code));
    if ~all(found)
        error('m20_run_transition_stress_test:OrderCityMismatch', 'Year %d strategy %s repeat %d has unknown city codes.', ...
            yearValue, groups.strategy(iGroup), groups.repeat_id(iGroup));
    end
    for iTau = 1:numel(cfg.tauValues)
        tauValue = double(cfg.tauValues(iTau));
        for iPhi = 1:nPhi
            cursor = cursor + 1;
            rows(cursor, :) = curve_row_local(yearValue, "carbon_constrained_production", groups.strategy(iGroup), ...
                groups.repeat_id(iGroup), cfg.phiGrid(iPhi), tauValue, 0, orderIdx, economicOut, carbonOut, economicTotal, carbonTotal, cfg.epsilon);
        end
    end
    for iDelta = 1:numel(cfg.deltaValues)
        deltaValue = double(cfg.deltaValues(iDelta));
        for iPhi = 1:nPhi
            cursor = cursor + 1;
            rows(cursor, :) = curve_row_local(yearValue, "clean_decarbonization", groups.strategy(iGroup), ...
                groups.repeat_id(iGroup), cfg.phiGrid(iPhi), 0, deltaValue, orderIdx, economicOut, carbonOut, economicTotal, carbonTotal, cfg.epsilon);
        end
    end
    for iTau = 1:numel(cfg.tauValues)
        tauValue = double(cfg.tauValues(iTau));
        for iDelta = 1:numel(cfg.deltaValues)
            deltaValue = double(cfg.deltaValues(iDelta));
            for iPhi = 1:nPhi
                cursor = cursor + 1;
                rows(cursor, :) = curve_row_local(yearValue, "hybrid_transition", groups.strategy(iGroup), ...
                    groups.repeat_id(iGroup), cfg.phiGrid(iPhi), tauValue, deltaValue, orderIdx, economicOut, carbonOut, economicTotal, carbonTotal, cfg.epsilon);
            end
        end
    end
end

curveTable = cell2table(rows, 'VariableNames', {'year','shock_type','strategy','repeat_id','phi','tau','delta', ...
    'n_targeted_cities','carbon_reduction','economic_retention','economic_loss','transition_efficiency', ...
    'carbon_total_original','carbon_total_after','economic_total_original','economic_total_after'});
curveTable = sortrows(curveTable, {'year','shock_type','strategy','repeat_id','tau','delta','phi'});
end

function row = curve_row_local(yearValue, shockType, strategy, repeatId, phi, tau, delta, orderIdx, economicOut, carbonOut, economicTotal, carbonTotal, epsilonValue)
n = numel(orderIdx);
targetCount = target_count_local(phi, n);
if targetCount == 0
    affectedEconomic = 0;
    affectedCarbon = 0;
else
    targetIdx = orderIdx(1:targetCount);
    affectedEconomic = sum(economicOut(targetIdx));
    affectedCarbon = sum(carbonOut(targetIdx));
end

switch string(shockType)
    case "carbon_constrained_production"
        economicAfter = economicTotal - tau * affectedEconomic;
        carbonAfter = carbonTotal - tau * affectedCarbon;
    case "clean_decarbonization"
        economicAfter = economicTotal;
        carbonAfter = carbonTotal - delta * affectedCarbon;
    case "hybrid_transition"
        economicAfter = economicTotal - tau * affectedEconomic;
        carbonFactor = 1 - (1 - tau) * (1 - delta);
        carbonAfter = carbonTotal - carbonFactor * affectedCarbon;
    otherwise
        error('m20_run_transition_stress_test:UnknownShockType', 'Unknown shock type: %s', shockType);
end

economicAfter = max(economicAfter, 0);
carbonAfter = max(carbonAfter, 0);
carbonReduction = 1 - carbonAfter / carbonTotal;
economicRetention = economicAfter / economicTotal;
economicLoss = 1 - economicRetention;
if string(shockType) == "clean_decarbonization"
    transitionEfficiency = NaN;
else
    transitionEfficiency = carbonReduction / (economicLoss + epsilonValue);
end

row = {yearValue, char(shockType), char(strategy), double(repeatId), double(phi), double(tau), double(delta), ...
    double(targetCount), carbonReduction, economicRetention, economicLoss, transitionEfficiency, ...
    carbonTotal, carbonAfter, economicTotal, economicAfter};
end

function count = target_count_local(phi, n)
if phi <= 0
    count = 0;
else
    count = min(n, ceil(double(phi) * n));
end
end

function aucTable = auc_repeat_table_local(curveTable)
[G, keys] = findgroups(curveTable(:, {'year','shock_type','strategy','repeat_id','tau','delta'}));
aucCarbon = splitapply(@trapz_local, curveTable.phi, curveTable.carbon_reduction, G);
aucRetention = splitapply(@trapz_local, curveTable.phi, curveTable.economic_retention, G);
aucLoss = splitapply(@trapz_local, curveTable.phi, curveTable.economic_loss, G);
aucEfficiency = splitapply(@trapz_nan_local, curveTable.phi, curveTable.transition_efficiency, G);
aucTable = keys;
aucTable.auc_carbon_reduction = aucCarbon;
aucTable.auc_economic_retention = aucRetention;
aucTable.auc_economic_loss = aucLoss;
aucTable.auc_transition_efficiency = aucEfficiency;
end

function val = trapz_local(phi, y)
[phiSorted, idx] = sort(double(phi));
val = trapz(phiSorted, double(y(idx)));
end

function val = trapz_nan_local(phi, y)
if all(isnan(y))
    val = NaN;
else
    val = trapz_local(phi, y);
end
end

function summary = auc_summary_local(aucRepeat)
[G, keys] = findgroups(aucRepeat(:, {'year','shock_type','strategy','tau','delta'}));
summary = keys;
summary.auc_carbon_reduction_mean = splitapply(@mean, aucRepeat.auc_carbon_reduction, G);
summary.auc_carbon_reduction_sd = splitapply(@sd_zero_one_local, aucRepeat.auc_carbon_reduction, G);
summary.auc_economic_retention_mean = splitapply(@mean, aucRepeat.auc_economic_retention, G);
summary.auc_economic_retention_sd = splitapply(@sd_zero_one_local, aucRepeat.auc_economic_retention, G);
summary.auc_economic_loss_mean = splitapply(@mean, aucRepeat.auc_economic_loss, G);
summary.auc_economic_loss_sd = splitapply(@sd_zero_one_local, aucRepeat.auc_economic_loss, G);
summary.auc_transition_efficiency_mean = splitapply(@mean_omitnan_local, aucRepeat.auc_transition_efficiency, G);
summary.auc_transition_efficiency_sd = splitapply(@sd_omitnan_local, aucRepeat.auc_transition_efficiency, G);
summary.n_repeats = splitapply(@numel, aucRepeat.repeat_id, G);
end

function v = mean_omitnan_local(x)
x = x(isfinite(x));
if isempty(x)
    v = NaN;
else
    v = mean(x);
end
end

function v = sd_omitnan_local(x)
x = x(isfinite(x));
if numel(x) <= 1
    v = 0;
else
    v = std(x);
end
end

function v = sd_zero_one_local(x)
if numel(x) <= 1
    v = 0;
else
    v = std(x);
end
end
