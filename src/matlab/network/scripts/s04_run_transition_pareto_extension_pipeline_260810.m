function out = s04_run_transition_pareto_extension_pipeline_260810(cfg)
% S04_RUN_TRANSITION_PARETO_EXTENSION_PIPELINE_260810
% 基于 final_freeze 冻结转型结果计算完整策略前缀、精确约束前沿与效率缺口

moduleRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(moduleRoot, 'src'));

if nargin < 1 || isempty(cfg)
    cfg = default_cfg_local(moduleRoot);
else
    cfg = complete_cfg_local(cfg, moduleRoot);
end

validate_write_boundary_local(cfg);
validate_solver_local(cfg);
prepare_output_dir_local(cfg.outputDir);
logPath = fullfile(char(cfg.outputDir), ...
    [char(cfg.fileDatePrefix) 'transition_pareto_execution.log']);
diary(logPath);
diaryCleanup = onCleanup(@() diary('off'));
fprintf('Transition Pareto extension started: %s\n', char(cfg.runTimestamp));
fprintf('Frozen input: %s\n', char(cfg.sourceTransitionDir));
fprintf('Independent output: %s\n', char(cfg.outputDir));

inputs = m32_load_transition_pareto_inputs_260810(cfg);
[prefixes, ratioOrders, consistency] = ...
    m33_build_exact_transition_prefixes_260810(inputs, cfg);
[frontier, frontierSelections] = ...
    m34_solve_exact_transition_frontier_260810(inputs, cfg);
[efficiencyGaps, randomGapSummary, keyEtaSummary] = ...
    m35_compute_transition_efficiency_gaps_260810(prefixes, frontier, cfg);

write_data_outputs_local(prefixes, ratioOrders, consistency, frontier, ...
    frontierSelections, efficiencyGaps, randomGapSummary, keyEtaSummary, cfg);

manifest = m36_write_transition_pareto_manifest_260810(inputs, prefixes, ...
    frontier, efficiencyGaps, cfg);
audit = m37_audit_transition_pareto_extension_260810(inputs, prefixes, ...
    ratioOrders, consistency, frontier, frontierSelections, efficiencyGaps, ...
    randomGapSummary, keyEtaSummary, manifest, cfg);

if ~strcmpi(string(audit.status), "PASS")
    error('s04_transition_pareto:AuditFailed', ...
        'Transition Pareto extension audit failed. See %s.', audit.reportPath);
end

out = struct();
out.cfg = cfg;
out.inputs = inputs;
out.prefixes = prefixes;
out.ratioOrders = ratioOrders;
out.consistency = consistency;
out.frontier = frontier;
out.frontierSelections = frontierSelections;
out.efficiencyGaps = efficiencyGaps;
out.randomGapSummary = randomGapSummary;
out.keyEtaSummary = keyEtaSummary;
out.manifest = audit.manifest;
out.audit = audit;
fprintf('Transition Pareto extension completed: %s\n', ...
    char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
fprintf('TRANSITION_PARETO_STATUS=%s\n', audit.status);
clear diaryCleanup;
end

function cfg = default_cfg_local(moduleRoot)
% 中文说明: 配置固定为用户指定的正式两年、309 城市与 tau=0.10。
cfg = struct();
cfg.moduleRoot = string(moduleRoot);
cfg.finalFreezeDir = study_path('data', 'reference');
cfg.sourceTransitionDir = string(study_path('generated', 'network', ...
    'revised_transition'));
cfg.outputDir = string(study_path('generated', 'network', ...
    'revised_transition_pareto_extension'));
cfg.years = [2015, 2020];
cfg.nCities = 309;
cfg.sampleMode = "pure_city";
cfg.mainTau = 0.10;
cfg.erGrid = 1.000:-0.001:0.900;
cfg.keyEta = [0.99, 0.975, 0.95, 0.925, 0.90];
cfg.mainEta = 0.95;
cfg.randomRepeats = 50;
cfg.mipGapTolerance = 1e-8;
cfg.feasibilityTolerance = 1e-9;
cfg.objectiveTolerance = 1e-10;
cfg.consistencyTolerance = 1e-10;
cfg.excludedProxyCodes = [460000, 530000, 540000, 630000];
cfg.solver = "gurobi";
cfg.solverSeed = 20260810;
cfg.strategies = ["carbon_hub", "production_hub", "investment_hub", ...
    "role_mismatch", "multilayer_bridge", "capital_carbon_mismatch_abs", ...
    "carbon_burden_low_control", "investment_carbon_exposure", "random"];
cfg.technicalBenchmark = "carbon_economic_ratio";
cfg.fileDatePrefix = "260810-";
cfg.executor = "research_code";
cfg.runTimestamp = string(datetime('now', ...
    'Format', 'yyyy-MM-dd HH:mm:ss'));
end

function cfg = complete_cfg_local(cfg, moduleRoot)
% 中文说明: 自定义配置只覆盖显式字段，其余字段沿用正式默认值。
defaults = default_cfg_local(moduleRoot);
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(cfg, names{i}) || isempty(cfg.(names{i}))
        cfg.(names{i}) = defaults.(names{i});
    end
end
end

function validate_solver_local(cfg)
% 中文说明: 只允许实际可运行的 Gurobi 精确求解路径，不静默降级到近似算法。
if ~strcmpi(string(cfg.solver), "gurobi")
    error('s04_transition_pareto:UnsupportedSolver', ...
        'This implementation maintains only the verified Gurobi path.');
end
if isempty(which('gurobi'))
    error('s04_transition_pareto:GurobiMissing', ...
        'Gurobi MATLAB API is not available. Exact frontier computation stopped.');
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
params = struct('OutputFlag', 0);
try
    result = gurobi(model, params);
catch ME
    error('s04_transition_pareto:GurobiUnavailable', ...
        'Gurobi API or license test failed: %s', ME.message);
end
if ~strcmpi(string(result.status), "OPTIMAL")
    error('s04_transition_pareto:GurobiTestNotOptimal', ...
        'Gurobi test did not return OPTIMAL: %s', string(result.status));
end
end

function validate_write_boundary_local(cfg)
% Keep numerical outputs separate from data and the source result tables.
outputPath = canonical_path_local(cfg.outputDir);
sourcePath = canonical_path_local(cfg.sourceTransitionDir);
dataPath = canonical_path_local(study_path('data'));
if outputPath == sourcePath || startsWith(outputPath, sourcePath + filesep) ...
        || outputPath == dataPath || startsWith(outputPath, dataPath + filesep)
    error('run_models:OutputOverlapsInput', 'Choose an output directory outside the input data.');
end
end

function path = canonical_path_local(pathValue)
fileObject = java.io.File(char(pathValue));
path = string(char(fileObject.getCanonicalPath()));
end

function prepare_output_dir_local(outputDir)
% 中文说明: 独立结果目录若已有文件则停止，避免覆盖旧扩展结果。
outputDir = char(outputDir);
if exist(outputDir, 'dir')
    entries = dir(outputDir);
    names = string({entries.name});
    keep = ~ismember(names, [".", "..", ".gitkeep"]);
    if any(keep)
        error('s04_transition_pareto:OutputNotEmpty', ...
            'Output directory is not empty and will not be overwritten: %s', outputDir);
    end
else
    mkdir(outputDir);
end
end

function write_data_outputs_local(prefixes, ratioOrders, consistency, frontier, ...
        frontierSelections, efficiencyGaps, randomGapSummary, keyEtaSummary, cfg)
% 中文说明: 所有新结果只写入独立扩展目录，并使用日期前缀保留版本边界。
prefix = char(cfg.fileDatePrefix);
outDir = char(cfg.outputDir);
for year = cfg.years
    key = sprintf('y%d', year);
    writetable(prefixes.(key), fullfile(outDir, ...
        sprintf('%stransition_exact_prefix_curves_%d.csv', prefix, year)));
end
writetable(ratioOrders, fullfile(outDir, ...
    [prefix 'transition_carbon_economic_ratio_orders.csv']));
writetable(consistency, fullfile(outDir, ...
    [prefix 'transition_prefix_consistency_check.csv']));
writetable(frontier, fullfile(outDir, ...
    [prefix 'transition_exact_frontier.csv']));
writetable(frontierSelections, fullfile(outDir, ...
    [prefix 'transition_exact_frontier_city_selections.csv']));
writetable(efficiencyGaps, fullfile(outDir, ...
    [prefix 'transition_strategy_efficiency_gaps.csv']));
writetable(randomGapSummary, fullfile(outDir, ...
    [prefix 'transition_random_efficiency_gap_summary.csv']));
writetable(keyEtaSummary, fullfile(outDir, ...
    [prefix 'transition_efficiency_gap_key_eta_summary.csv']));
end
