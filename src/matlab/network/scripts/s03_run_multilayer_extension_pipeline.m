function out = s03_run_multilayer_extension_pipeline(cfg)
% S03_RUN_MULTILAYER_EXTENSION_PIPELINE
% 计算真正跨层的 multilayer 指标，并写入独立 revised_multilayer_extension 输出面

moduleRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(moduleRoot, 'src'));

if nargin < 1 || isempty(cfg)
    cfg = default_extension_cfg_local(moduleRoot);
end

ensure_dir_local(cfg.outputDir);

inputs = m24_load_multilayer_extension_inputs(cfg);
edgeOut = m25_compute_edge_multiplexity_overlap(inputs, cfg);
liftOut = m26_compute_cross_layer_conditional_lift(inputs, cfg);
geometryOut = m27_compute_node_multilayer_geometry(inputs, cfg);
supraOut = m28_compute_supra_centrality_versatility(inputs, geometryOut, cfg);
tablesOut = m29_compute_community_vulnerability_transition_tables(inputs, cfg);
auditOut = m30_audit_multilayer_extension(inputs, edgeOut, liftOut, geometryOut, supraOut, tablesOut, cfg);

if ~strcmpi(string(auditOut.status), "PASS")
    error('s03_run_multilayer_extension_pipeline:AuditFailed', ...
        'Multilayer extension audit failed. See %s.', auditOut.reportPath);
end

out = struct();
out.cfg = cfg;
out.inputs = inputs;
out.edge = edgeOut;
out.lift = liftOut;
out.geometry = geometryOut;
out.supra = supraOut;
out.tables = tablesOut;
out.audit = auditOut;
end

function cfg = default_extension_cfg_local(moduleRoot)
resultsRoot = study_path('generated', 'network');
cfg = struct();
cfg.moduleRoot = string(moduleRoot);
cfg.sourceResultsDir = string(fullfile(resultsRoot, 'revised_mrio4'));
cfg.transitionResultsDir = string(fullfile(resultsRoot, 'revised_transition'));
cfg.outputDir = string(fullfile(resultsRoot, 'revised_multilayer_extension'));
cfg.years = [2015, 2020];
cfg.sampleMode = "pure_city";
cfg.expectedCities = 309;
cfg.excludedProxyCodes = [460000, 530000, 540000, 630000];
cfg.layerNames = ["investment", "production", "carbon"];
cfg.layerCodes = ["I", "E", "C"];
cfg.layerMatrixFields = ["W_I", "W_E", "W_C"];
cfg.highWeightQuantiles = [0.90, 0.95, 0.99];
cfg.omegaValues = [0.1, 0.5, 1, 2];
cfg.pagerankAlpha = 0.85;
cfg.pagerankTolerance = 1e-10;
cfg.pagerankMaxIter = 1000;
cfg.auditTolerance = 1e-8;
cfg.transitionMainShock = "carbon_constrained_production";
cfg.transitionMainTau = 0.10;
cfg.transitionMainDelta = 0;
end

function ensure_dir_local(dirPath)
if ~exist(dirPath, 'dir')
    mkdir(dirPath);
end
end
