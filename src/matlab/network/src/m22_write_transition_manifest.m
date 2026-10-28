function manifest = m22_write_transition_manifest(inputs, governance, targetOrders, stress, growthConstraint, cfg)
% M22_WRITE_TRANSITION_MANIFEST
% 写出 machine-readable manifest 和简明运行说明

files = list_files_local(cfg.outputDir);
manifest = struct();
manifest.source_revised_results_directory = char(inputs.sourceResultsDir);
manifest.output_directory = char(cfg.outputDir);
manifest.created_at = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss Z'));
manifest.sample_mode = char(cfg.sampleMode);
manifest.n_cities = double(cfg.expectedCities);
manifest.excluded_proxy_codes = double(cfg.excludedProxyCodes(:)');
manifest.stress_test_resolution = char(cfg.stressTestResolution);
manifest.shock_types = cellstr(cfg.shockTypes(:));
manifest.tau_values = double(cfg.tauValues(:)');
manifest.delta_values = double(cfg.deltaValues(:)');
manifest.phi_grid = [double(min(cfg.phiGrid)), double(max(cfg.phiGrid)), double(cfg.phiGrid(2) - cfg.phiGrid(1))];
manifest.strategies = cellstr(cfg.strategies(:));
manifest.random_repeats = double(targetOrders.randomRepeats);
manifest.epsilon = double(cfg.epsilon);
manifest.files_created = files;
manifest.audit_status = 'PENDING';
manifest.governance_metric_files = { ...
    'governance_mismatch_metrics_2015.csv', ...
    'governance_mismatch_metrics_2020.csv', ...
    'table_top_governance_mismatch_cities.csv'};
manifest.transition_output_files = { ...
    'transition_target_city_orders.csv', ...
    'transition_stress_curves_2015.csv', ...
    'transition_stress_curves_2020.csv', ...
    'transition_stress_auc_summary.csv', ...
    'transition_strategy_under_growth_constraint.csv'};

manifestPath = fullfile(cfg.outputDir, 'transition_results_manifest.json');
write_json_local(manifestPath, manifest);
manifest.path = string(manifestPath);

summaryPath = fullfile(cfg.outputDir, 'transition_pipeline_run_summary.md');
write_summary_local(summaryPath, inputs, governance, targetOrders, stress, growthConstraint, cfg);
manifest.summaryPath = string(summaryPath);
end

function files = list_files_local(outputDir)
D = dir(outputDir);
D = D(~[D.isdir]);
names = string({D.name});
names = sort(names(:));
files = cellstr(names);
end

function write_json_local(pathValue, data)
txt = jsonencode(data, 'PrettyPrint', true);
fid = fopen(pathValue, 'w');
if fid < 0
    error('m22_write_transition_manifest:WriteFailed', 'Cannot write %s.', pathValue);
end
cleanupObj = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', txt);
delete(cleanupObj);
end

function write_summary_local(pathValue, inputs, governance, targetOrders, stress, growthConstraint, cfg)
fid = fopen(pathValue, 'w');
if fid < 0
    error('m22_write_transition_manifest:WriteFailed', 'Cannot write %s.', pathValue);
end
cleanupObj = onCleanup(@() fclose(fid));
fprintf(fid, '# Low-carbon transition extension run summary\n\n');
fprintf(fid, '- Run time: %s\n', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
fprintf(fid, '- Source revised results: `%s`\n', inputs.sourceResultsDir);
fprintf(fid, '- Output directory: `%s`\n', cfg.outputDir);
fprintf(fid, '- Sample mode: `%s`, retained cities: %d\n\n', cfg.sampleMode, cfg.expectedCities);
fprintf(fid, '## Added metrics\n\n');
fprintf(fid, 'The extension adds governance mismatch metrics linking investment control, production centrality, carbon burden, carbon inflow, and investment-based carbon exposure. It does not replace the existing role classification.\n\n');
fprintf(fid, '## Stress-test scenarios\n\n');
fprintf(fid, '- `carbon_constrained_production`: targeted source-city outgoing economic and carbon flows are attenuated together.\n');
fprintf(fid, '- `clean_decarbonization`: targeted source-city carbon flows are attenuated while economic flows stay unchanged; transition efficiency is not comparable and is recorded as NaN.\n');
fprintf(fid, '- `hybrid_transition`: targeted source-city economic flows are attenuated and carbon flows receive additional intensity reduction.\n\n');
fprintf(fid, '## Generated outputs\n\n');
fprintf(fid, '- Governance metric rows: %d\n', height(governance.topTable));
fprintf(fid, '- Target-order rows: %d\n', height(targetOrders.table));
fprintf(fid, '- AUC summary rows: %d\n', height(stress.aucSummary));
fprintf(fid, '- Growth-constraint rows: %d\n\n', height(growthConstraint.table));
fprintf(fid, '## Paper interpretation\n\n');
fprintf(fid, 'These outputs should be interpreted as a complex-network transition stress test based on weighted node/edge attenuation. They are not causal policy evaluation, general-equilibrium simulation, or node-deletion failure analysis.\n\n');
fprintf(fid, '## Audit\n\n');
fprintf(fid, 'Audit is executed after manifest writing. See `transition_audit_report.md` for the final PASS/FAIL status.\n');
delete(cleanupObj);
end
