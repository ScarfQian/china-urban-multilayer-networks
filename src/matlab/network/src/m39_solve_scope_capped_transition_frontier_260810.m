function [scopeFrontier, scopeSelections] = ...
        m39_solve_scope_capped_transition_frontier_260810( ...
        inputs, prefixes, cfg)
% M39_SOLVE_SCOPE_CAPPED_TRANSITION_FRONTIER_260810
% 在候选策略可行城市数上限内求解精确碳减排组合

allPrefixes = table();
for year = cfg.years
    key = sprintf('y%d', year);
    allPrefixes = [allPrefixes; prefixes.(key)]; %#ok<AGROW>
end
groups = unique(allPrefixes(:, ...
    {'year', 'strategy', 'strategy_kind', 'repeat_id'}), ...
    'rows', 'stable');

params = gurobi_params_local(cfg);
cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
frontierParts = cell(height(groups) * numel(cfg.scopeEta), 1);
selectionParts = cell(height(groups) * numel(cfg.scopeEta), 1);
cursor = 0;

for g = 1:height(groups)
    year = groups.year(g);
    strategy = string(groups.strategy(g));
    strategyKind = string(groups.strategy_kind(g));
    repeatId = groups.repeat_id(g);
    key = sprintf('y%d', year);
    governance = inputs.governance.(key);
    curve = allPrefixes(allPrefixes.year == year & ...
        string(allPrefixes.strategy) == strategy & ...
        allPrefixes.repeat_id == repeatId, :);
    curve = sortrows(curve, 'K');

    for eta = cfg.scopeEta
        budget = 1 - eta;
        candidate = select_strategy_prefix_local(curve, budget, cfg);
        candidateWarmStart = candidate_solution_local( ...
            curve, candidate.K, governance, cfg);
        cacheKey = sprintf('%d|%.12f|%d', year, eta, candidate.K);
        if isKey(cache, cacheKey)
            solved = cache(cacheKey);
            cacheReused = true;
        else
            [solution, diagnostics] = solve_scope_local( ...
                governance.PC_share(:), governance.CB_share(:), ...
                budget, candidate.K, candidateWarmStart, params, cfg);
            solved = struct();
            solved.solution = solution;
            solved.diagnostics = diagnostics;
            solved.actualEL = cfg.mainTau * ...
                (governance.PC_share(:)' * solution);
            solved.actualCR = cfg.mainTau * ...
                (governance.CB_share(:)' * solution);
            solved.nSelected = sum(solution);
            cache(cacheKey) = solved;
            cacheReused = false;
        end

        if solved.actualEL > budget + cfg.feasibilityTolerance
            error('m39_scope_frontier:BudgetViolation', ...
                '%d %s repeat %d eta=%.3f exceeds the budget.', ...
                year, strategy, repeatId, eta);
        end
        if solved.nSelected > candidate.K
            error('m39_scope_frontier:CityCapViolation', ...
                '%d %s repeat %d eta=%.3f exceeds K=%d.', ...
                year, strategy, repeatId, eta, candidate.K);
        end
        if solved.actualCR + cfg.feasibilityTolerance < ...
                candidate.carbon_reduction
            error('m39_scope_frontier:CandidateDominatesExact', ...
                'Candidate prefix exceeds scope-capped optimum for %d %s.', ...
                year, strategy);
        end

        cursor = cursor + 1;
        frontierParts{cursor} = frontier_row_local(year, eta, strategy, ...
            strategyKind, repeatId, candidate, solved, cacheReused, cfg);
        selectionParts{cursor} = selection_rows_local(governance, ...
            solved.solution, year, eta, strategy, strategyKind, repeatId, ...
            candidate.K, budget, cfg);
    end
end

scopeFrontier = vertcat(frontierParts{1:cursor});
selectionParts = selectionParts(1:cursor);
nonempty = ~cellfun(@isempty, selectionParts);
if any(nonempty)
    scopeSelections = vertcat(selectionParts{nonempty});
else
    scopeSelections = empty_selection_table_local();
end
end

function selected = select_strategy_prefix_local(curve, budget, cfg)
% 中文说明: 候选城市数来自该排序在预算内的字典序最佳完整前缀。
feasible = curve(curve.economic_loss <= ...
    budget + cfg.feasibilityTolerance, :);
if isempty(feasible)
    error('m39_scope_frontier:NoFeasiblePrefix', ...
        'No candidate prefix is feasible for budget %.6f.', budget);
end
bestCarbon = max(feasible.carbon_reduction);
candidates = feasible(feasible.carbon_reduction >= ...
    bestCarbon - cfg.objectiveTolerance, :);
bestLoss = min(candidates.economic_loss);
candidates = candidates(candidates.economic_loss <= ...
    bestLoss + cfg.objectiveTolerance, :);
bestK = min(candidates.K);
selected = candidates(candidates.K == bestK, :);
selected = selected(1, :);
end

function x = candidate_solution_local(curve, candidateK, governance, cfg)
% 中文说明: 候选前缀本身是范围约束模型的可行热启动。
x = zeros(cfg.nCities, 1);
if candidateK == 0
    return;
end
selectedRows = curve(curve.K > 0 & curve.K <= candidateK, :);
[found, loc] = ismember(selectedRows.city_code_added, governance.city_code);
if ~all(found) || numel(unique(loc)) ~= candidateK
    error('m39_scope_frontier:CandidateSetJoin', ...
        'Candidate prefix city set cannot be reconstructed.');
end
x(loc) = 1;
end

function params = gurobi_params_local(cfg)
% 中文说明: 优先要求零相对间隙，同时记录绝对目标边界差供审计。
params = struct();
params.OutputFlag = 0;
params.LogToConsole = 0;
params.MIPGap = cfg.mipGapTolerance;
params.MIPGapAbs = cfg.mipGapAbs;
params.FeasibilityTol = cfg.feasibilityTolerance;
params.IntFeasTol = cfg.feasibilityTolerance;
params.OptimalityTol = cfg.feasibilityTolerance;
params.NumericFocus = 3;
params.Seed = cfg.solverSeed;
end

function [xFinal, diagnostics] = solve_scope_local( ...
        e, c, budget, cityCap, warmStart, params, cfg)
% 中文说明: 后一阶段通过显式容限约束保持前一阶段目标。
n = numel(e);
tauE = cfg.mainTau * e;
tauC = cfg.mainTau * c;

base = struct();
base.A = sparse([tauE'; ones(1, n)]);
base.rhs = [budget; cityCap];
base.sense = ['<'; '<'];
base.lb = zeros(n, 1);
base.ub = ones(n, 1);
base.vtype = repmat('B', n, 1);
base.start = warmStart;

stage1 = base;
stage1.modelsense = 'max';
stage1.obj = tauC;
r1 = gurobi(stage1, params);
validate_result_local(r1, 'stage 1', cfg);

stage2 = base;
stage2.A = sparse([base.A; tauC']);
stage2.rhs = [base.rhs; r1.objval - cfg.objectiveTolerance];
stage2.sense = [base.sense; '>'];
stage2.modelsense = 'min';
stage2.obj = tauE;
stage2.start = round(r1.x);
r2 = gurobi(stage2, params);
validate_result_local(r2, 'stage 2', cfg);

stage3 = base;
stage3.A = sparse([base.A; tauC'; tauE']);
stage3.rhs = [base.rhs; r1.objval - cfg.objectiveTolerance; ...
    r2.objval + cfg.objectiveTolerance];
stage3.sense = [base.sense; '>'; '<'];
stage3.modelsense = 'min';
stage3.obj = ones(n, 1);
stage3.start = round(r2.x);
r3 = gurobi(stage3, params);
validate_result_local(r3, 'stage 3', cfg);

xFinal = double(r3.x > 0.5);
diagnostics = diagnostics_local(r1, r2, r3);
end

function validate_result_local(result, stageLabel, cfg)
if ~isfield(result, 'status') || ...
        ~strcmpi(string(result.status), "OPTIMAL")
    status = "MISSING";
    if isfield(result, 'status')
        status = string(result.status);
    end
    error('m39_scope_frontier:NotOptimal', ...
        'Gurobi %s did not return OPTIMAL: %s', stageLabel, status);
end
gap = result_gap_local(result);
if ~isfinite(gap) || gap > cfg.solverGapAcceptance
    error('m39_scope_frontier:GapExceeded', ...
        'Gurobi %s relative gap %.12g exceeds %.12g.', ...
        stageLabel, gap, cfg.solverGapAcceptance);
end
end

function d = diagnostics_local(r1, r2, r3)
d = struct();
results = {r1, r2, r3};
for stage = 1:3
    result = results{stage};
    d.(sprintf('stage%dStatus', stage)) = string(result.status);
    d.(sprintf('stage%dObjective', stage)) = result.objval;
    d.(sprintf('stage%dGap', stage)) = result_gap_local(result);
    d.(sprintf('stage%dBound', stage)) = ...
        result_field_local(result, 'objbound');
    d.(sprintf('stage%dAbsoluteBoundGap', stage)) = ...
        absolute_bound_gap_local(result);
    d.(sprintf('stage%dRuntime', stage)) = ...
        result_field_local(result, 'runtime');
    d.(sprintf('stage%dNodeCount', stage)) = ...
        result_field_local(result, 'nodecount');
end
end

function gap = result_gap_local(result)
if isfield(result, 'mipgap') && isfinite(result.mipgap)
    gap = result.mipgap;
elseif isfield(result, 'status') && ...
        strcmpi(string(result.status), "OPTIMAL")
    gap = 0;
else
    gap = NaN;
end
end

function gap = absolute_bound_gap_local(result)
bound = result_field_local(result, 'objbound');
if isfield(result, 'objval') && isfinite(result.objval) && isfinite(bound)
    gap = abs(result.objval - bound);
else
    gap = NaN;
end
end

function value = result_field_local(result, fieldName)
if isfield(result, fieldName)
    value = result.(fieldName);
else
    value = NaN;
end
end

function row = frontier_row_local(year, eta, strategy, strategyKind, ...
        repeatId, candidate, solved, cacheReused, cfg)
d = solved.diagnostics;
row = table();
row.year = year;
row.eta = eta;
row.economic_loss_budget = 1 - eta;
row.strategy = strategy;
row.strategy_kind = strategyKind;
row.repeat_id = repeatId;
row.candidate_K = candidate.K;
row.candidate_phi = candidate.phi;
row.candidate_carbon_reduction = candidate.carbon_reduction;
row.candidate_economic_loss = candidate.economic_loss;
row.scope_capped_carbon_reduction = solved.actualCR;
row.scope_capped_economic_loss = solved.actualEL;
row.scope_capped_economic_retention = 1 - solved.actualEL;
row.scope_capped_selected_cities = solved.nSelected;
row.stage1_optimal_carbon_reduction = d.stage1Objective;
row.stage2_minimum_economic_loss = d.stage2Objective;
row.stage3_minimum_city_count = d.stage3Objective;
row.stage1_status = d.stage1Status;
row.stage2_status = d.stage2Status;
row.stage3_status = d.stage3Status;
row.stage1_relative_gap = d.stage1Gap;
row.stage2_relative_gap = d.stage2Gap;
row.stage3_relative_gap = d.stage3Gap;
row.stage1_objective_bound = d.stage1Bound;
row.stage2_objective_bound = d.stage2Bound;
row.stage3_objective_bound = d.stage3Bound;
row.stage1_absolute_bound_gap = d.stage1AbsoluteBoundGap;
row.stage2_absolute_bound_gap = d.stage2AbsoluteBoundGap;
row.stage3_absolute_bound_gap = d.stage3AbsoluteBoundGap;
row.stage1_runtime_seconds = d.stage1Runtime;
row.stage2_runtime_seconds = d.stage2Runtime;
row.stage3_runtime_seconds = d.stage3Runtime;
row.stage1_node_count = d.stage1NodeCount;
row.stage2_node_count = d.stage2NodeCount;
row.stage3_node_count = d.stage3NodeCount;
row.cache_reused = cacheReused;
row.solver = "gurobi";
row.optimality_statement = "optimal_within_configured_numerical_tolerances";
row.city_cap_constraint = "sum_x_less_than_or_equal_to_candidate_K";
row.tau = cfg.mainTau;
end

function rows = selection_rows_local(governance, solution, year, eta, ...
        strategy, strategyKind, repeatId, candidateK, budget, cfg)
selected = find(solution > 0.5);
if isempty(selected)
    rows = [];
    return;
end
city = governance(selected, {'city_code', 'city_name', ...
    'PC_share', 'CB_share'});
city = sortrows(city, 'city_code');
rho = zeros(height(city), 1);
positiveEconomic = city.PC_share > cfg.feasibilityTolerance;
rho(positiveEconomic) = city.CB_share(positiveEconomic) ./ ...
    city.PC_share(positiveEconomic);
rho(~positiveEconomic & city.CB_share > cfg.objectiveTolerance) = Inf;

rows = table();
rows.year = repmat(year, height(city), 1);
rows.eta = repmat(eta, height(city), 1);
rows.economic_loss_budget = repmat(budget, height(city), 1);
rows.strategy = repmat(strategy, height(city), 1);
rows.strategy_kind = repmat(strategyKind, height(city), 1);
rows.repeat_id = repmat(repeatId, height(city), 1);
rows.candidate_K = repmat(candidateK, height(city), 1);
rows.selection_row = (1:height(city))';
rows.city_code = city.city_code;
rows.city_name = string(city.city_name);
rows.PC_share = city.PC_share;
rows.CB_share = city.CB_share;
rows.carbon_economic_ratio = rho;
rows.economic_loss_contribution = cfg.mainTau * city.PC_share;
rows.carbon_reduction_contribution = cfg.mainTau * city.CB_share;
end

function rows = empty_selection_table_local()
rows = table('Size', [0, 15], ...
    'VariableTypes', {'double', 'double', 'double', 'string', 'string', ...
    'double', 'double', 'double', 'double', 'string', 'double', 'double', ...
    'double', 'double', 'double'}, ...
    'VariableNames', {'year', 'eta', 'economic_loss_budget', 'strategy', ...
    'strategy_kind', 'repeat_id', 'candidate_K', 'selection_row', ...
    'city_code', 'city_name', 'PC_share', 'CB_share', ...
    'carbon_economic_ratio', 'economic_loss_contribution', ...
    'carbon_reduction_contribution'});
end
