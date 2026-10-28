function [frontier, selections] = ...
        m34_solve_exact_transition_frontier_260810(inputs, cfg)
% M34_SOLVE_EXACT_TRANSITION_FRONTIER_260810
% 在 ER 网格上求解碳减排最大化的二元精确约束前沿

frontierParts = cell(numel(cfg.years), 1);
selectionParts = cell(numel(cfg.years) * numel(cfg.erGrid), 1);
selectionCursor = 0;

params = gurobi_params_local(cfg);

for yIdx = 1:numel(cfg.years)
    year = cfg.years(yIdx);
    key = sprintf('y%d', year);
    governance = inputs.governance.(key);
    e = governance.PC_share(:);
    c = governance.CB_share(:);
    warmStart = zeros(cfg.nCities, 1);
    rows = cell(numel(cfg.erGrid), 1);

    for etaIdx = 1:numel(cfg.erGrid)
        eta = cfg.erGrid(etaIdx);
        budget = 1 - eta;
        [solution, diagnostics] = solve_lexicographic_local( ...
            e, c, budget, warmStart, params, cfg);
        warmStart = solution;

        actualEL = cfg.mainTau * (e' * solution);
        actualCR = cfg.mainTau * (c' * solution);
        actualER = 1 - actualEL;
        selectedCount = sum(solution);

        if actualEL > budget + cfg.feasibilityTolerance
            error('m34_exact_frontier:BudgetViolation', ...
                '%d eta=%.3f violates the economic-loss budget.', year, eta);
        end
        if actualCR < diagnostics.stage1Objective - ...
                cfg.objectiveTolerance - cfg.feasibilityTolerance
            error('m34_exact_frontier:CarbonLexicographicViolation', ...
                '%d eta=%.3f violates the stage-1 carbon optimum.', year, eta);
        end
        if actualEL > diagnostics.stage2Objective + ...
                cfg.objectiveTolerance + cfg.feasibilityTolerance
            error('m34_exact_frontier:EconomicLexicographicViolation', ...
                '%d eta=%.3f violates the stage-2 economic optimum.', year, eta);
        end

        rows{etaIdx} = frontier_row_local(year, eta, budget, actualEL, ...
            actualER, actualCR, selectedCount, diagnostics, cfg);

        selectionCursor = selectionCursor + 1;
        selectionParts{selectionCursor} = selection_rows_local( ...
            governance, solution, year, eta, budget, cfg);

        if mod(etaIdx - 1, 10) == 0 || etaIdx == numel(cfg.erGrid)
            fprintf(['Exact frontier %d: eta=%.3f, CR=%.8f, ' ...
                'EL=%.8f, cities=%d\n'], ...
                year, eta, actualCR, actualEL, selectedCount);
        end
    end
    frontierParts{yIdx} = vertcat(rows{:});
end

frontier = vertcat(frontierParts{:});
selectionParts = selectionParts(1:selectionCursor);
nonempty = ~cellfun(@isempty, selectionParts);
if any(nonempty)
    selections = vertcat(selectionParts{nonempty});
else
    selections = empty_selection_table_local();
end
end

function params = gurobi_params_local(cfg)
% 中文说明: 同时约束相对间隙、绝对间隙、可行性和整数可行性。
params = struct();
params.OutputFlag = 0;
params.LogToConsole = 0;
params.MIPGap = cfg.mipGapTolerance;
params.MIPGapAbs = cfg.objectiveTolerance;
params.FeasibilityTol = cfg.feasibilityTolerance;
params.IntFeasTol = cfg.feasibilityTolerance;
params.OptimalityTol = cfg.feasibilityTolerance;
params.NumericFocus = 3;
params.Seed = cfg.solverSeed;
end

function [xFinal, diagnostics] = solve_lexicographic_local( ...
        e, c, budget, warmStart, params, cfg)
% 中文说明: 每一阶段都要求全局最优；后一阶段用显式约束保持前一阶段目标。
n = numel(e);
tauE = cfg.mainTau * e;
tauC = cfg.mainTau * c;

base = struct();
base.A = sparse(tauE');
base.rhs = budget;
base.sense = '<';
base.lb = zeros(n, 1);
base.ub = ones(n, 1);
base.vtype = repmat('B', n, 1);
base.start = warmStart;

stage1 = base;
stage1.modelsense = 'max';
stage1.obj = tauC;
r1 = gurobi(stage1, params);
validate_result_local(r1, 'stage 1', cfg);
stage1Objective = r1.objval;

stage2 = base;
stage2.A = sparse([tauE'; tauC']);
stage2.rhs = [budget; stage1Objective - cfg.objectiveTolerance];
stage2.sense = ['<'; '>'];
stage2.modelsense = 'min';
stage2.obj = tauE;
stage2.start = round(r1.x);
r2 = gurobi(stage2, params);
validate_result_local(r2, 'stage 2', cfg);
stage2Objective = r2.objval;

stage3 = base;
stage3.A = sparse([tauE'; tauC'; tauE']);
stage3.rhs = [budget; stage1Objective - cfg.objectiveTolerance; ...
    stage2Objective + cfg.objectiveTolerance];
stage3.sense = ['<'; '>'; '<'];
stage3.modelsense = 'min';
stage3.obj = ones(n, 1);
stage3.start = round(r2.x);
r3 = gurobi(stage3, params);
validate_result_local(r3, 'stage 3', cfg);

xFinal = double(r3.x > 0.5);
diagnostics = struct();
diagnostics.stage1Status = string(r1.status);
diagnostics.stage2Status = string(r2.status);
diagnostics.stage3Status = string(r3.status);
diagnostics.stage1Objective = stage1Objective;
diagnostics.stage2Objective = stage2Objective;
diagnostics.stage3Objective = r3.objval;
diagnostics.stage1Gap = result_gap_local(r1);
diagnostics.stage2Gap = result_gap_local(r2);
diagnostics.stage3Gap = result_gap_local(r3);
diagnostics.stage1Bound = result_field_local(r1, 'objbound');
diagnostics.stage2Bound = result_field_local(r2, 'objbound');
diagnostics.stage3Bound = result_field_local(r3, 'objbound');
diagnostics.stage1Runtime = result_field_local(r1, 'runtime');
diagnostics.stage2Runtime = result_field_local(r2, 'runtime');
diagnostics.stage3Runtime = result_field_local(r3, 'runtime');
diagnostics.stage1NodeCount = result_field_local(r1, 'nodecount');
diagnostics.stage2NodeCount = result_field_local(r2, 'nodecount');
diagnostics.stage3NodeCount = result_field_local(r3, 'nodecount');
end

function validate_result_local(result, stageLabel, cfg)
if ~isfield(result, 'status') || ~strcmpi(string(result.status), "OPTIMAL")
    status = "MISSING";
    if isfield(result, 'status')
        status = string(result.status);
    end
    error('m34_exact_frontier:NotGloballyOptimal', ...
        'Gurobi %s did not return OPTIMAL: %s', stageLabel, status);
end
gap = result_gap_local(result);
if ~isfinite(gap) || gap > cfg.mipGapTolerance + eps(cfg.mipGapTolerance)
    error('m34_exact_frontier:GapExceeded', ...
        'Gurobi %s relative gap %.12g exceeds %.12g.', ...
        stageLabel, gap, cfg.mipGapTolerance);
end
end

function gap = result_gap_local(result)
if isfield(result, 'mipgap') && isfinite(result.mipgap)
    gap = result.mipgap;
elseif isfield(result, 'status') && strcmpi(string(result.status), "OPTIMAL")
    gap = 0;
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

function row = frontier_row_local(year, eta, budget, actualEL, actualER, ...
        actualCR, selectedCount, d, cfg)
row = table();
row.year = year;
row.eta = eta;
row.economic_loss_budget = budget;
row.tau = cfg.mainTau;
row.carbon_reduction = actualCR;
row.economic_loss = actualEL;
row.economic_retention = actualER;
row.n_selected_cities = selectedCount;
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
row.stage1_runtime_seconds = d.stage1Runtime;
row.stage2_runtime_seconds = d.stage2Runtime;
row.stage3_runtime_seconds = d.stage3Runtime;
row.stage1_node_count = d.stage1NodeCount;
row.stage2_node_count = d.stage2NodeCount;
row.stage3_node_count = d.stage3NodeCount;
row.solver = "gurobi";
row.frontier_scope = "global_optimum_at_this_ER_grid_point";
end

function rows = selection_rows_local(governance, solution, year, eta, budget, cfg)
selected = find(solution > 0.5);
if isempty(selected)
    rows = [];
    return;
end
city = governance(selected, {'city_code', 'city_name', 'PC_share', 'CB_share'});
city = sortrows(city, 'city_code');
rho = zeros(height(city), 1);
positiveEconomic = city.PC_share > 0;
rho(positiveEconomic) = city.CB_share(positiveEconomic) ./ ...
    city.PC_share(positiveEconomic);
rho(~positiveEconomic & city.CB_share > 0) = Inf;

rows = table();
rows.year = repmat(year, height(city), 1);
rows.eta = repmat(eta, height(city), 1);
rows.economic_loss_budget = repmat(budget, height(city), 1);
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
rows = table('Size', [0, 11], ...
    'VariableTypes', {'double', 'double', 'double', 'double', 'double', ...
    'string', 'double', 'double', 'double', 'double', 'double'}, ...
    'VariableNames', {'year', 'eta', 'economic_loss_budget', 'selection_row', ...
    'city_code', 'city_name', 'PC_share', 'CB_share', ...
    'carbon_economic_ratio', 'economic_loss_contribution', ...
    'carbon_reduction_contribution'});
end
