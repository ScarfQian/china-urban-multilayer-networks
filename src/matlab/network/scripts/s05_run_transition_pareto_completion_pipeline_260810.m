function out = s05_run_transition_pareto_completion_pipeline_260810(cfg)
% S05_RUN_TRANSITION_PARETO_COMPLETION_PIPELINE_260810
% 补齐范围约束基准、连续上界、IFAR、缺口分解和城市集合机制

moduleRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(moduleRoot, 'src'));

if nargin < 1 || isempty(cfg)
    cfg = default_cfg_local(moduleRoot);
else
    cfg = complete_cfg_local(cfg, moduleRoot);
end

validate_paths_local(cfg);
validate_solver_local(cfg);
prepare_output_dir_local(cfg.outputDir);
logPath = fullfile(char(cfg.outputDir), ...
    [char(cfg.fileDatePrefix) 'transition_pareto_v2_execution.log']);
diary(logPath);
diaryCleanup = onCleanup(@() diary('off'));
fprintf('Transition Pareto v2 started: %s\n', char(cfg.runTimestamp));
fprintf('Frozen input: %s\n', char(cfg.sourceTransitionDir));
fprintf('V1 result input: %s\n', char(cfg.v1ResultDir));
fprintf('Independent v2 output: %s\n', char(cfg.outputDir));

inputs = m32_load_transition_pareto_inputs_260810(cfg);
v1 = load_v1_results_local(cfg);
continuousBound = m38_build_continuous_transition_bound_260810( ...
    inputs, v1.frontier, cfg);
[scopeFrontier, scopeSelections] = ...
    m39_solve_scope_capped_transition_frontier_260810( ...
    inputs, v1.prefixes, cfg);
[gapDecomposition, attainment, attainmentSummary, ...
    randomIntervalSummary] = ...
    m40_compute_frontier_attainment_and_gap_decomposition_260810( ...
    v1.gaps, v1.frontier, scopeFrontier, cfg);
[similarity, substitutions] = ...
    m41_compare_transition_city_sets_260810(inputs, v1.prefixes, ...
    v1.frontierSelections, scopeFrontier, scopeSelections, cfg);

manifest = m42_write_transition_pareto_v2_outputs_260810( ...
    inputs, v1, continuousBound, scopeFrontier, scopeSelections, ...
    gapDecomposition, attainment, attainmentSummary, similarity, ...
    substitutions, randomIntervalSummary, cfg);
audit = m43_audit_transition_pareto_v2_260810( ...
    inputs, v1, continuousBound, scopeFrontier, scopeSelections, ...
    gapDecomposition, attainment, attainmentSummary, similarity, ...
    substitutions, randomIntervalSummary, manifest, cfg);

if ~strcmpi(string(audit.status), "PASS")
    error('s05_transition_pareto_v2:AuditFailed', ...
        'Pareto v2 audit failed. See %s.', audit.reportPath);
end

out = struct();
out.cfg = cfg;
out.inputs = inputs;
out.v1 = v1;
out.continuousBound = continuousBound;
out.scopeFrontier = scopeFrontier;
out.scopeSelections = scopeSelections;
out.gapDecomposition = gapDecomposition;
out.attainment = attainment;
out.attainmentSummary = attainmentSummary;
out.similarity = similarity;
out.substitutions = substitutions;
out.randomIntervalSummary = randomIntervalSummary;
out.manifest = audit.manifest;
out.audit = audit;
fprintf('Transition Pareto v2 completed: %s\n', ...
    char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
fprintf('TRANSITION_PARETO_V2_STATUS=%s\n', audit.status);
clear diaryCleanup;
end

function cfg = default_cfg_local(moduleRoot)
% 中文说明: 配置锁定为正式两年、309 城市和 tau=0.10。
cfg = struct();
cfg.moduleRoot = string(moduleRoot);
cfg.finalFreezeDir = study_path('data', 'reference');
cfg.sourceTransitionDir = string(study_path('generated', 'network', ...
    'revised_transition'));
cfg.v1ResultDir = string(study_path('generated', 'network', ...
    'revised_transition_pareto_extension'));
cfg.outputDir = string(study_path('generated', 'network', ...
    'revised_transition_pareto_extension_v2'));
cfg.years = [2015, 2020];
cfg.nCities = 309;
cfg.sampleMode = "pure_city";
cfg.mainTau = 0.10;
cfg.erGrid = 1.000:-0.001:0.900;
cfg.scopeEta = [0.99, 0.975, 0.95, 0.925, 0.90];
cfg.mainEta = 0.95;
cfg.randomRepeats = 50;
cfg.mipGapTolerance = 0;
cfg.mipGapAbs = 1e-12;
cfg.solverGapAcceptance = 1e-8;
cfg.solverAbsoluteGapAcceptance = 1e-9;
cfg.feasibilityTolerance = 1e-9;
cfg.objectiveTolerance = 1e-10;
cfg.excludedProxyCodes = [460000, 530000, 540000, 630000];
cfg.solver = "gurobi";
cfg.solverSeed = 20260810;
cfg.strategies = ["carbon_hub", "production_hub", "investment_hub", ...
    "role_mismatch", "multilayer_bridge", ...
    "capital_carbon_mismatch_abs", "carbon_burden_low_control", ...
    "investment_carbon_exposure", "random"];
cfg.technicalBenchmark = "carbon_economic_ratio";
cfg.fileDatePrefix = "260810-";
cfg.runTimestamp = string(datetime('now', ...
    'Format', 'yyyy-MM-dd HH:mm:ss'));
end

function cfg = complete_cfg_local(cfg, moduleRoot)
defaults = default_cfg_local(moduleRoot);
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(cfg, names{i}) || isempty(cfg.(names{i}))
        cfg.(names{i}) = defaults.(names{i});
    end
end
end

function validate_paths_local(cfg)
% Protect the data and previously computed unrestricted frontier.
outputPath = canonical_path_local(cfg.outputDir);
inputs = [string(cfg.sourceTransitionDir), string(cfg.v1ResultDir), study_path('data')];
for i = 1:numel(inputs)
    sourcePath = canonical_path_local(inputs(i));
    if outputPath == sourcePath || startsWith(outputPath, sourcePath + filesep)
        error('run_models:OutputOverlapsInput', 'Choose an output directory outside the input data.');
    end
end
end

function validate_solver_local(cfg)
if ~strcmpi(string(cfg.solver), "gurobi") || isempty(which('gurobi'))
    error('s05_transition_pareto_v2:GurobiMissing', ...
        'Verified Gurobi MATLAB API is required.');
end
model = struct();
model.A = sparse(0, 1);
model.obj = 1;
model.lb = 0;
model.ub = 1;
model.vtype = 'B';
model.modelsense = 'max';
model.rhs = [];
model.sense = '';
result = gurobi(model, struct('OutputFlag', 0));
if ~strcmpi(string(result.status), "OPTIMAL")
    error('s05_transition_pareto_v2:GurobiTestFailed', ...
        'Gurobi test status is %s.', string(result.status));
end
end

function prepare_output_dir_local(outputDir)
% 中文说明: v2 目录若已有正式文件则停止，避免覆盖或混入失败残留。
outputDir = char(outputDir);
if exist(outputDir, 'dir')
    entries = dir(outputDir);
    names = string({entries.name});
    keep = ~ismember(names, [".", "..", ".gitkeep"]);
    if any(keep)
        error('s05_transition_pareto_v2:OutputNotEmpty', ...
            'V2 output directory is not empty: %s', outputDir);
    end
else
    mkdir(outputDir);
end
end

function v1 = load_v1_results_local(cfg)
% 中文说明: v1 系统前沿和完整前缀作为只读正式输入，不调用 s04 重算。
prefix = char(cfg.fileDatePrefix);
base = char(cfg.v1ResultDir);
required = [
    string(sprintf('%stransition_exact_prefix_curves_2015.csv', prefix))
    string(sprintf('%stransition_exact_prefix_curves_2020.csv', prefix))
    string([prefix 'transition_exact_frontier.csv'])
    string([prefix 'transition_exact_frontier_city_selections.csv'])
    string([prefix 'transition_strategy_efficiency_gaps.csv'])
    string([prefix 'transition_pareto_manifest.json'])
    ];
paths = strings(numel(required), 1);
for i = 1:numel(required)
    paths(i) = string(fullfile(base, char(required(i))));
    if ~exist(paths(i), 'file')
        error('s05_transition_pareto_v2:MissingV1Input', ...
            'Required v1 result is missing: %s', paths(i));
    end
end

v1 = struct();
v1.prefixes = struct();
for year = cfg.years
    key = sprintf('y%d', year);
    tablePath = fullfile(base, sprintf( ...
        '%stransition_exact_prefix_curves_%d.csv', prefix, year));
    current = readtable(tablePath, 'VariableNamingRule', 'preserve');
    current.strategy = string(current.strategy);
    current.strategy_kind = string(current.strategy_kind);
    current.city_name_added = string(current.city_name_added);
    current.source_order = string(current.source_order);
    v1.prefixes.(key) = current;
end
v1.frontier = readtable(fullfile(base, ...
    [prefix 'transition_exact_frontier.csv']), ...
    'VariableNamingRule', 'preserve');
v1.frontierSelections = readtable(fullfile(base, ...
    [prefix 'transition_exact_frontier_city_selections.csv']), ...
    'VariableNamingRule', 'preserve');
v1.frontierSelections.city_name = string(v1.frontierSelections.city_name);
v1.gaps = readtable(fullfile(base, ...
    [prefix 'transition_strategy_efficiency_gaps.csv']), ...
    'VariableNamingRule', 'preserve');
v1.gaps.strategy = string(v1.gaps.strategy);
v1.gaps.strategy_kind = string(v1.gaps.strategy_kind);
v1.manifest = jsondecode(fileread(fullfile(base, ...
    [prefix 'transition_pareto_manifest.json'])));
v1.requiredPaths = paths;

if ~isfield(v1.manifest, 'audit_status') || ...
        ~strcmpi(string(v1.manifest.audit_status), "PASS") || ...
        v1.manifest.n_cities ~= cfg.nCities || ...
        abs(v1.manifest.main_tau - cfg.mainTau) > cfg.objectiveTolerance
    error('s05_transition_pareto_v2:InvalidV1Manifest', ...
        'V1 manifest is not a compatible audited formal input.');
end
end

function path = canonical_path_local(pathValue)
fileObject = java.io.File(char(pathValue));
path = string(char(fileObject.getCanonicalPath()));
end
