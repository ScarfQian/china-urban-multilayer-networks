function out = m11_classify_multilayer_roles(singleOut, crossOut, alignment, yearValue, cfg)
% M11_CLASSIFY_MULTILAYER_ROLES
% Classify cities into capital-control, production-hub, carbon-responsibility,
%   multilayer-bridge, and role-mismatch roles with explicit unclassified cases.

singleNode = singleOut.nodeMetricsTable;
multiNode = sortrows(crossOut.multilayerNodeMetrics, 'city_code');

investmentHit = sortrows(singleNode(singleNode.layer == "investment", :), 'city_code');
economicHit = sortrows(singleNode(singleNode.layer == "economic", :), 'city_code');
carbonHit = sortrows(singleNode(singleNode.layer == "carbon", :), 'city_code');

capitalScore = zscore_vector_local(double(investmentHit.out_strength)) + zscore_vector_local(double(investmentHit.pagerank));
productionScore = zscore_vector_local(double(economicHit.total_strength)) + zscore_vector_local(double(economicHit.pagerank));
carbonScore = zscore_vector_local(double(carbonHit.out_strength)) + zscore_vector_local(double(carbonHit.pagerank));
bridgeScore = zscore_vector_local(double(multiNode.participation_normalized)) + ...
    zscore_vector_local(mean([double(investmentHit.pagerank), double(economicHit.pagerank), double(carbonHit.pagerank)], 2));
mismatchScore = zscore_vector_local(double(multiNode.role_mismatch_index));

roleTopCut = quantile_local([capitalScore; productionScore; carbonScore], cfg.roleTopQuantile);
bridgeTopCut = quantile_local(bridgeScore, cfg.bridgeTopQuantile);
mismatchTopCut = quantile_local(mismatchScore, cfg.roleTopQuantile);

isCapital = double(capitalScore >= roleTopCut);
isProduction = double(productionScore >= roleTopCut);
isCarbon = double(carbonScore >= roleTopCut);
isBridge = double(bridgeScore >= bridgeTopCut);
isMismatch = double(mismatchScore >= mismatchTopCut);

dominantRelativeLayer = strings(alignment.numCities, 1);
relativeLeaningRole = strings(alignment.numCities, 1);
primaryRole = repmat("unclassified", alignment.numCities, 1);

for iCity = 1:alignment.numCities
    [~, idx] = max([capitalScore(iCity), productionScore(iCity), carbonScore(iCity)]);
    if idx == 1
        dominantRelativeLayer(iCity) = "capital";
        relativeLeaningRole(iCity) = "capital-leaning";
    elseif idx == 2
        dominantRelativeLayer(iCity) = "production";
        relativeLeaningRole(iCity) = "production-leaning";
    else
        dominantRelativeLayer(iCity) = "carbon";
        relativeLeaningRole(iCity) = "carbon-leaning";
    end

    hasTopRoleFlag = any([isCapital(iCity), isProduction(iCity), isCarbon(iCity), isBridge(iCity)] == 1);
    if isMismatch(iCity) == 1
        primaryRole(iCity) = "role-mismatch city";
    elseif isBridge(iCity) == 1
        primaryRole(iCity) = "multilayer-bridge city";
    elseif hasTopRoleFlag
        [~, dominantIdx] = max([capitalScore(iCity), productionScore(iCity), carbonScore(iCity)]);
        if dominantIdx == 1 && isCapital(iCity) == 1
            primaryRole(iCity) = "capital-control city";
        elseif dominantIdx == 2 && isProduction(iCity) == 1
            primaryRole(iCity) = "production-hub city";
        elseif dominantIdx == 3 && isCarbon(iCity) == 1
            primaryRole(iCity) = "carbon-responsibility city";
        elseif isCapital(iCity) == 1
            primaryRole(iCity) = "capital-control city";
        elseif isProduction(iCity) == 1
            primaryRole(iCity) = "production-hub city";
        elseif isCarbon(iCity) == 1
            primaryRole(iCity) = "carbon-responsibility city";
        end
    end
end

roleTable = table( ...
    repmat(yearValue, alignment.numCities, 1), ...
    double(alignment.cityTable.city_code), ...
    string(alignment.cityTable.city_cn), ...
    capitalScore, productionScore, carbonScore, bridgeScore, mismatchScore, ...
    dominantRelativeLayer, relativeLeaningRole, ...
    isCapital, isProduction, isCarbon, isBridge, isMismatch, ...
    double(isCapital + isProduction + isCarbon + isBridge + isMismatch > 0), ...
    primaryRole, ...
    'VariableNames', {'year','city_code','city_name', ...
    'capital_control_score','production_hub_score','carbon_responsibility_score','bridge_score','role_mismatch_score', ...
    'dominant_relative_layer','relative_leaning_role', ...
    'is_capital_control','is_production_hub','is_carbon_responsibility','is_multilayer_bridge','is_role_mismatch', ...
    'has_any_role_flag','primary_role'});

outputCsv = fullfile(cfg.resultsDir, "role_type_classification_" + string(yearValue) + ".csv");
writetable(roleTable, outputCsv);

out = struct();
out.year = yearValue;
out.roleTable = roleTable;
out.outputCsv = string(outputCsv);
end

function z = zscore_vector_local(x)
mu = mean(x);
sigma = std(x);
if sigma == 0
    z = zeros(size(x));
else
    z = (x - mu) ./ sigma;
end
end

function q = quantile_local(x, p)
x = sort(double(x(:)));
if isempty(x)
    q = NaN;
    return;
end
pos = 1 + (numel(x) - 1) * p;
lo = floor(pos);
hi = ceil(pos);
if lo == hi
    q = x(lo);
else
    q = x(lo) + (pos - lo) * (x(hi) - x(lo));
end
end
