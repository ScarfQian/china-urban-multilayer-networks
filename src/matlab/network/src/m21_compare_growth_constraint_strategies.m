function out = m21_compare_growth_constraint_strategies(stress, cfg)
% M21_COMPARE_GROWTH_CONSTRAINT_STRATEGIES
% 在经济保持率约束下比较不同低碳转型排序策略

allSelected = table();
for iYear = 1:numel(cfg.years)
    yearValue = cfg.years(iYear);
    fieldName = "y" + string(yearValue);
    curveTable = stress.curvesByYear.(fieldName);
    meanCurve = average_repeats_local(curveTable);
    allSelected = [allSelected; select_by_eta_local(meanCurve, cfg.etaValues)]; %#ok<AGROW>
end

outPath = fullfile(cfg.outputDir, 'transition_strategy_under_growth_constraint.csv');
writetable(allSelected, outPath);
out = struct();
out.table = allSelected;
out.path = string(outPath);
end

function meanCurve = average_repeats_local(curveTable)
[G, keys] = findgroups(curveTable(:, {'year','shock_type','strategy','phi','tau','delta'}));
meanCurve = keys;
meanCurve.n_targeted_cities = splitapply(@max, curveTable.n_targeted_cities, G);
meanCurve.carbon_reduction = splitapply(@mean, curveTable.carbon_reduction, G);
meanCurve.economic_retention = splitapply(@mean, curveTable.economic_retention, G);
meanCurve.economic_loss = splitapply(@mean, curveTable.economic_loss, G);
meanCurve.transition_efficiency = splitapply(@mean_omitnan_local, curveTable.transition_efficiency, G);
end

function selectedAll = select_by_eta_local(meanCurve, etaValues)
[G, keys] = findgroups(meanCurve(:, {'year','shock_type','strategy','tau','delta'}));
selectedAll = table();
for iGroup = 1:max(G)
    block = sortrows(meanCurve(G == iGroup, :), 'phi');
    key = keys(iGroup, :);
    for iEta = 1:numel(etaValues)
        eta = double(etaValues(iEta));
        feasible = block.economic_retention >= eta - 1e-12;
        if ~any(feasible)
            row = selected_row_local(key, eta, NaN, NaN, NaN, NaN, NaN, 0, "no_valid_curve");
        else
            feasibleBlock = block(feasible, :);
            [~, bestIdx] = max(feasibleBlock.carbon_reduction);
            best = feasibleBlock(bestIdx, :);
            positiveFeasible = any(feasibleBlock.phi > 0);
            if ~positiveFeasible
                status = "only_phi_zero_feasible";
            elseif best.phi < max(block.phi) && any(block.economic_retention(block.phi > best.phi) < eta - 1e-12)
                status = "binding";
            else
                status = "nonbinding";
            end
            row = selected_row_local(key, eta, best.phi, best.carbon_reduction, best.economic_retention, ...
                best.economic_loss, best.transition_efficiency, best.n_targeted_cities, status);
        end
        selectedAll = [selectedAll; row]; %#ok<AGROW>
    end
end
end

function row = selected_row_local(key, eta, phi, carbonReduction, economicRetention, economicLoss, transitionEfficiency, nTargeted, status)
row = table();
row.year = key.year;
row.shock_type = string(key.shock_type);
row.strategy = string(key.strategy);
row.tau = key.tau;
row.delta = key.delta;
row.eta = eta;
row.selected_phi = phi;
row.max_carbon_reduction_at_ER_constraint = carbonReduction;
row.economic_retention_at_selected_phi = economicRetention;
row.economic_loss_at_selected_phi = economicLoss;
row.transition_efficiency_at_selected_phi = transitionEfficiency;
row.n_targeted_cities = nTargeted;
row.constraint_status = string(status);
end

function v = mean_omitnan_local(x)
x = x(isfinite(x));
if isempty(x)
    v = NaN;
else
    v = mean(x);
end
end
