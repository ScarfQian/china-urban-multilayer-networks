function out = s02_run_transition_extension_pipeline(cfg)
% S02_RUN_TRANSITION_EXTENSION_PIPELINE
% 在不覆盖 revised 结果的前提下，计算低碳转型压力测试与治理错配指标

moduleRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(moduleRoot, 'src'));

if nargin < 1 || isempty(cfg)
    cfg = default_transition_cfg_local(moduleRoot);
end

ensure_dir_local(cfg.outputDir);

inputs = m17_load_transition_inputs(cfg);
governance = m18_compute_governance_mismatch_metrics(inputs, cfg);
targetOrders = m19_build_transition_target_orders(inputs, governance, cfg);
stress = m20_run_transition_stress_test(inputs, targetOrders, cfg);
growthConstraint = m21_compare_growth_constraint_strategies(stress, cfg);
manifest = m22_write_transition_manifest(inputs, governance, targetOrders, stress, growthConstraint, cfg);
audit = m23_audit_transition_extension(inputs, governance, targetOrders, stress, growthConstraint, manifest, cfg);

if ~strcmpi(string(audit.status), "PASS")
    error('s02_run_transition_extension_pipeline:AuditFailed', ...
        'Transition extension audit failed. See %s.', audit.reportPath);
end

out = struct();
out.cfg = cfg;
out.inputs = inputs;
out.governance = governance;
out.targetOrders = targetOrders;
out.stress = stress;
out.growthConstraint = growthConstraint;
out.manifest = manifest;
out.audit = audit;
end

function cfg = default_transition_cfg_local(moduleRoot)
% 中文说明: 默认优先使用 MRIO4 的 revised_mrio4，因为它才是四部门正式结果。
candidateMrio4 = study_path('generated', 'network', 'revised_mrio4');
candidateRevised = study_path('generated', 'network', 'revised');
if exist(fullfile(candidateMrio4, 'multilayer_results_manifest.json'), 'file')
    sourceDir = candidateMrio4;
else
    sourceDir = candidateRevised;
end

cfg = struct();
cfg.moduleRoot = string(moduleRoot);
cfg.sourceResultsDir = string(sourceDir);
cfg.outputDir = string(study_path('generated', 'network', 'revised_transition'));
cfg.years = [2015, 2020];
cfg.sampleMode = "pure_city";
cfg.expectedCities = 309;
cfg.excludedProxyCodes = [460000, 530000, 540000, 630000];
cfg.randomSeed = 20260427;
cfg.randomRepeats = 50;
cfg.phiGrid = 0:0.01:1;
cfg.tauValues = [0.05, 0.10, 0.20];
cfg.deltaValues = [0.05, 0.10, 0.20];
cfg.mainTau = 0.10;
cfg.mainDelta = 0.10;
cfg.epsilon = 1e-12;
cfg.etaValues = [0.95, 0.90, 0.85];
cfg.shockTypes = ["carbon_constrained_production", "clean_decarbonization", "hybrid_transition"];
cfg.strategies = ["carbon_hub", "production_hub", "investment_hub", "role_mismatch", ...
    "multilayer_bridge", "capital_carbon_mismatch_abs", "carbon_burden_low_control", ...
    "investment_carbon_exposure", "random"];
cfg.stressTestResolution = "city_level_aggregate";
cfg.auditTolerance = 1e-8;
end

function ensure_dir_local(dirPath)
if ~exist(dirPath, 'dir')
    mkdir(dirPath);
end
end
