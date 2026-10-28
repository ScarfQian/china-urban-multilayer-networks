function [similarity, substitutions] = ...
        m41_compare_transition_city_sets_260810(inputs, prefixes, ...
        unrestrictedSelections, scopeFrontier, scopeSelections, cfg)
% M41_COMPARE_TRANSITION_CITY_SETS_260810
% 比较候选、范围约束精确和不限制范围精确城市集合

allPrefixes = table();
for year = cfg.years
    key = sprintf('y%d', year);
    allPrefixes = [allPrefixes; prefixes.(key)]; %#ok<AGROW>
end

deterministic = scopeFrontier(string(scopeFrontier.strategy) ~= "random", :);
similarityParts = cell(height(deterministic), 1);
substitutionParts = cell(height(deterministic), 1);

for i = 1:height(deterministic)
    row = deterministic(i, :);
    year = row.year;
    eta = row.eta;
    strategy = string(row.strategy);
    repeatId = row.repeat_id;
    key = sprintf('y%d', year);
    governance = inputs.governance.(key);

    curve = allPrefixes(allPrefixes.year == year & ...
        string(allPrefixes.strategy) == strategy & ...
        allPrefixes.repeat_id == repeatId, :);
    candidateRows = curve(curve.K > 0 & curve.K <= row.candidate_K, :);
    candidateSet = unique(candidateRows.city_code_added);
    candidateSet = candidateSet(isfinite(candidateSet));

    scopeRows = scopeSelections(scopeSelections.year == year & ...
        abs(scopeSelections.eta - eta) <= cfg.objectiveTolerance & ...
        string(scopeSelections.strategy) == strategy & ...
        scopeSelections.repeat_id == repeatId, :);
    scopeSet = unique(scopeRows.city_code);

    unrestrictedRows = unrestrictedSelections( ...
        unrestrictedSelections.year == year & ...
        abs(unrestrictedSelections.eta - eta) <= cfg.objectiveTolerance, :);
    unrestrictedSet = unique(unrestrictedRows.city_code);

    common = intersect(candidateSet, scopeSet);
    candidateOnly = setdiff(candidateSet, scopeSet);
    scopeOnly = setdiff(scopeSet, candidateSet);
    unionScope = union(candidateSet, scopeSet);
    unionSystem = union(candidateSet, unrestrictedSet);

    candidateScopeJaccard = numel(common) / numel(unionScope);
    candidateSystemJaccard = numel(intersect( ...
        candidateSet, unrestrictedSet)) / numel(unionSystem);
    candidateCoverage = numel(common) / numel(scopeSet);

    removed = governance(ismember(governance.city_code, candidateOnly), :);
    added = governance(ismember(governance.city_code, scopeOnly), :);
    removedEL = cfg.mainTau * sum(removed.PC_share);
    removedCR = cfg.mainTau * sum(removed.CB_share);
    addedEL = cfg.mainTau * sum(added.PC_share);
    addedCR = cfg.mainTau * sum(added.CB_share);

    summary = table();
    summary.year = year;
    summary.eta = eta;
    summary.economic_loss_budget = 1 - eta;
    summary.strategy = strategy;
    summary.strategy_kind = string(row.strategy_kind);
    summary.repeat_id = repeatId;
    summary.candidate_count = numel(candidateSet);
    summary.scope_exact_count = numel(scopeSet);
    summary.unrestricted_exact_count = numel(unrestrictedSet);
    summary.jaccard_candidate_vs_scope_exact = candidateScopeJaccard;
    summary.jaccard_candidate_vs_unrestricted_exact = candidateSystemJaccard;
    summary.n_common = numel(common);
    summary.n_candidate_only = numel(candidateOnly);
    summary.n_scope_exact_only = numel(scopeOnly);
    summary.candidate_coverage_of_scope_exact = candidateCoverage;
    summary.removed_economic_loss_contribution = removedEL;
    summary.added_economic_loss_contribution = addedEL;
    summary.net_economic_loss_change = addedEL - removedEL;
    summary.removed_carbon_reduction_contribution = removedCR;
    summary.added_carbon_reduction_contribution = addedCR;
    summary.net_carbon_reduction_change = addedCR - removedCR;
    similarityParts{i} = summary;

    substitutionParts{i} = substitution_rows_local(governance, ...
        candidateSet, scopeSet, unrestrictedSet, year, eta, strategy, ...
        string(row.strategy_kind), repeatId, cfg);
end

similarity = vertcat(similarityParts{:});
nonempty = ~cellfun(@isempty, substitutionParts);
if any(nonempty)
    substitutions = vertcat(substitutionParts{nonempty});
else
    substitutions = empty_substitution_table_local();
end
end

function rows = substitution_rows_local(governance, candidateSet, ...
        scopeSet, unrestrictedSet, year, eta, strategy, strategyKind, ...
        repeatId, cfg)
cityCodes = union(candidateSet, scopeSet);
if isempty(cityCodes)
    rows = [];
    return;
end
[found, loc] = ismember(cityCodes, governance.city_code);
if ~all(found)
    error('m41_city_sets:GovernanceJoin', ...
        'City-set join failed for %d %s.', year, strategy);
end
city = governance(loc, {'city_code', 'city_name', 'PC_share', 'CB_share'});
city = sortrows(city, 'city_code');
inCandidate = ismember(city.city_code, candidateSet);
inScope = ismember(city.city_code, scopeSet);
status = repmat("common", height(city), 1);
status(inCandidate & ~inScope) = "candidate_only";
status(~inCandidate & inScope) = "scope_exact_only";

rho = zeros(height(city), 1);
positiveEconomic = city.PC_share > cfg.feasibilityTolerance;
rho(positiveEconomic) = city.CB_share(positiveEconomic) ./ ...
    city.PC_share(positiveEconomic);
rho(~positiveEconomic & city.CB_share > cfg.objectiveTolerance) = Inf;

rows = table();
rows.year = repmat(year, height(city), 1);
rows.eta = repmat(eta, height(city), 1);
rows.economic_loss_budget = repmat(1 - eta, height(city), 1);
rows.strategy = repmat(strategy, height(city), 1);
rows.strategy_kind = repmat(strategyKind, height(city), 1);
rows.repeat_id = repmat(repeatId, height(city), 1);
rows.city_code = city.city_code;
rows.city_name = string(city.city_name);
rows.membership_status = status;
rows.in_candidate = inCandidate;
rows.in_scope_exact = inScope;
rows.in_unrestricted_exact = ismember(city.city_code, unrestrictedSet);
rows.PC_share = city.PC_share;
rows.CB_share = city.CB_share;
rows.carbon_economic_ratio = rho;
rows.economic_loss_contribution = cfg.mainTau * city.PC_share;
rows.carbon_reduction_contribution = cfg.mainTau * city.CB_share;
end

function rows = empty_substitution_table_local()
rows = table('Size', [0, 17], ...
    'VariableTypes', {'double', 'double', 'double', 'string', 'string', ...
    'double', 'double', 'string', 'string', 'logical', 'logical', ...
    'logical', 'double', 'double', 'double', 'double', 'double'}, ...
    'VariableNames', {'year', 'eta', 'economic_loss_budget', 'strategy', ...
    'strategy_kind', 'repeat_id', 'city_code', 'city_name', ...
    'membership_status', 'in_candidate', 'in_scope_exact', ...
    'in_unrestricted_exact', 'PC_share', 'CB_share', ...
    'carbon_economic_ratio', 'economic_loss_contribution', ...
    'carbon_reduction_contribution'});
end
