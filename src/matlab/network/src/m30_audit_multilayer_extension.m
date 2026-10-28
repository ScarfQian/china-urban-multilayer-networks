function audit = m30_audit_multilayer_extension(inputs, edgeOut, liftOut, geometryOut, supraOut, tablesOut, cfg) %#ok<INUSD>
% M30_AUDIT_MULTILAYER_EXTENSION
% 审计 multilayer extension 输出的样本边界、数值范围和必需文件完整性

failures = strings(0, 1);
metricRows = table();

requiredFiles = required_files_local(cfg);
for iFile = 1:numel(requiredFiles)
    pathValue = fullfile(cfg.outputDir, requiredFiles(iFile));
    existsFlag = exist(pathValue, 'file') == 2;
    metricRows = [metricRows; metric_row_local(0, "file_exists", requiredFiles(iFile), double(existsFlag), double(existsFlag), pass_fail_local(existsFlag))]; %#ok<AGROW>
    if ~existsFlag
        failures(end + 1, 1) = "missing_required_file_" + requiredFiles(iFile); %#ok<AGROW>
    end
end

for iYear = 1:numel(cfg.years)
    yearValue = cfg.years(iYear);
    fieldName = "y" + string(yearValue);
    cityCodes = double(inputs.yearData.(fieldName).cityTable.city_code);
    sampleOk = numel(unique(cityCodes)) == cfg.expectedCities && isempty(intersect(cityCodes, double(cfg.excludedProxyCodes(:))));
    metricRows = [metricRows; metric_row_local(yearValue, "sample", "unique_city_count", numel(unique(cityCodes)), cfg.expectedCities, pass_fail_local(sampleOk))]; %#ok<AGROW>
    if ~sampleOk
        failures(end + 1, 1) = "sample_check_failed_" + string(yearValue); %#ok<AGROW>
    end

    multiplexity = edgeOut.edgeSummaryByYear.(fieldName);
    shareSum = sum(multiplexity.dyad_share);
    ok = abs(shareSum - 1) <= cfg.auditTolerance;
    metricRows = [metricRows; metric_row_local(yearValue, "edge_multiplexity", "dyad_share_sum", shareSum, 1, pass_fail_local(ok))]; %#ok<AGROW>
    if ~ok
        failures(end + 1, 1) = "multiplexity_share_sum_failed_" + string(yearValue); %#ok<AGROW>
    end

    geometry = geometryOut.byYear.(fieldName);
    entropyOk = all(geometry.normalized_entropy >= -cfg.auditTolerance & geometry.normalized_entropy <= 1 + cfg.auditTolerance);
    metricRows = [metricRows; metric_row_local(yearValue, "node_geometry", "normalized_entropy_bounds", min(geometry.normalized_entropy), max(geometry.normalized_entropy), pass_fail_local(entropyOk))]; %#ok<AGROW>
    if ~entropyOk
        failures(end + 1, 1) = "entropy_bounds_failed_" + string(yearValue); %#ok<AGROW>
    end

    supra = supraOut.byYear.(fieldName);
    supraOk = all(isfinite(supra.versatility)) && all(supra.versatility >= -cfg.auditTolerance);
    metricRows = [metricRows; metric_row_local(yearValue, "supra_centrality", "versatility_bounds", min(supra.versatility), max(supra.versatility), pass_fail_local(supraOk))]; %#ok<AGROW>
    if ~supraOk
        failures(end + 1, 1) = "supra_centrality_failed_" + string(yearValue); %#ok<AGROW>
    end

    vulnerability = tablesOut.vulnerability.(fieldName);
    vulnerabilityOk = all(vulnerability.vulnerability_score >= -cfg.auditTolerance & vulnerability.vulnerability_score <= 1 + cfg.auditTolerance);
    metricRows = [metricRows; metric_row_local(yearValue, "cross_layer_vulnerability", "vulnerability_bounds", min(vulnerability.vulnerability_score), max(vulnerability.vulnerability_score), pass_fail_local(vulnerabilityOk))]; %#ok<AGROW>
    if ~vulnerabilityOk
        failures(end + 1, 1) = "vulnerability_bounds_failed_" + string(yearValue); %#ok<AGROW>
    end
end

overlapPath = fullfile(cfg.outputDir, 'layer_pair_overlap_summary.csv');
if exist(overlapPath, 'file')
    overlap = readtable(overlapPath, 'TextType', 'string');
    overlapOk = all(overlap.jaccard_overlap >= -cfg.auditTolerance & overlap.jaccard_overlap <= 1 + cfg.auditTolerance) && ...
        all(overlap.weighted_overlap_layer_normalized >= -cfg.auditTolerance & overlap.weighted_overlap_layer_normalized <= 1 + cfg.auditTolerance);
    metricRows = [metricRows; metric_row_local(0, "overlap", "overlap_bounds", min(overlap.weighted_overlap_layer_normalized), max(overlap.weighted_overlap_layer_normalized), pass_fail_local(overlapOk))]; %#ok<AGROW>
    if ~overlapOk
        failures(end + 1, 1) = "overlap_bounds_failed"; %#ok<AGROW>
    end
end

transitionOk = all(isfinite(tablesOut.transitionMatrix.auc_carbon_reduction_mean)) && ...
    all(isfinite(tablesOut.transitionMatrix.auc_economic_retention_mean)) && ...
    all(isfinite(tablesOut.transitionMatrix.auc_economic_loss_mean)) && ...
    all(isfinite(tablesOut.transitionMatrix.auc_transition_efficiency_mean));
metricRows = [metricRows; metric_row_local(0, "transition_strategy_matrix", "finite_values", double(transitionOk), double(transitionOk), pass_fail_local(transitionOk))]; %#ok<AGROW>
if ~transitionOk
    failures(end + 1, 1) = "transition_strategy_matrix_nan_failed"; %#ok<AGROW>
end

metricPath = fullfile(cfg.outputDir, 'audit_multilayer_metric_bounds.csv');
writetable(metricRows, metricPath);

if isempty(failures)
    status = "PASS";
else
    status = "FAIL";
end

reportPath = fullfile(cfg.outputDir, 'multilayer_extension_audit_report.md');
write_report_local(reportPath, status, failures, cfg);
manifestPath = fullfile(cfg.outputDir, 'multilayer_extension_manifest.json');
write_manifest_local(manifestPath, status, requiredFiles, cfg);

audit = struct();
audit.status = status;
audit.failures = failures;
audit.metricPath = string(metricPath);
audit.reportPath = string(reportPath);
audit.manifestPath = string(manifestPath);
end

function files = required_files_local(cfg) %#ok<INUSD>
files = [ ...
    "edge_multiplexity_summary_2015.csv", ...
    "edge_multiplexity_summary_2020.csv", ...
    "layer_pair_overlap_summary.csv", ...
    "cross_layer_edge_conditional_lift_2015.csv", ...
    "cross_layer_edge_conditional_lift_2020.csv", ...
    "node_multilayer_geometry_2015.csv", ...
    "node_multilayer_geometry_2020.csv", ...
    "table_multilayer_geometry_top_cities.csv", ...
    "supra_centrality_2015.csv", ...
    "supra_centrality_2020.csv", ...
    "supra_centrality_omega_sensitivity.csv", ...
    "community_alignment_2015.csv", ...
    "community_alignment_2020.csv", ...
    "cross_layer_vulnerability_matrix_2015.csv", ...
    "cross_layer_vulnerability_matrix_2020.csv", ...
    "table_transition_strategy_matrix.csv"];
end

function row = metric_row_local(yearValue, checkType, metric, value1, value2, status)
row = table();
row.year = yearValue;
row.check_type = string(checkType);
row.metric = string(metric);
row.value_1 = double(value1);
row.value_2 = double(value2);
row.status = string(status);
end

function status = pass_fail_local(x)
if x
    status = "PASS";
else
    status = "FAIL";
end
end

function write_report_local(pathValue, status, failures, cfg)
fid = fopen(pathValue, 'w');
if fid < 0
    error('m30_audit_multilayer_extension:WriteFailed', 'Cannot write %s.', pathValue);
end
cleanupObj = onCleanup(@() fclose(fid));
fprintf(fid, '# Multilayer extension audit report\n\n');
fprintf(fid, '- Date: 2026-04-27\n');
fprintf(fid, '- Author: Codex\n');
fprintf(fid, '- Source revised results: `%s`\n', cfg.sourceResultsDir);
fprintf(fid, '- Transition source results: `%s`\n', cfg.transitionResultsDir);
fprintf(fid, '- Output directory: `%s`\n', cfg.outputDir);
fprintf(fid, '- Sample: `%s`, n=%d\n\n', cfg.sampleMode, cfg.expectedCities);
if isempty(failures)
    fprintf(fid, 'No blocking audit failure was found.\n\n');
else
    fprintf(fid, 'Blocking audit failures:\n\n');
    for i = 1:numel(failures)
        fprintf(fid, '- %s\n', failures(i));
    end
    fprintf(fid, '\n');
end
fprintf(fid, 'AUDIT_STATUS = %s\n', status);
delete(cleanupObj);
end

function write_manifest_local(pathValue, status, requiredFiles, cfg)
manifest = struct();
manifest.created_at = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss Z'));
manifest.source_revised_results_directory = char(cfg.sourceResultsDir);
manifest.transition_results_directory = char(cfg.transitionResultsDir);
manifest.output_directory = char(cfg.outputDir);
manifest.sample_mode = char(cfg.sampleMode);
manifest.n_cities = double(cfg.expectedCities);
manifest.excluded_proxy_codes = double(cfg.excludedProxyCodes(:)');
manifest.modules = {'edge_multiplexity_overlap','cross_layer_conditional_lift','node_multilayer_geometry', ...
    'supra_centrality_versatility','community_alignment','cross_layer_vulnerability','transition_strategy_matrix'};
manifest.required_files = cellstr(requiredFiles(:));
manifest.audit_status = char(status);
try
    txt = jsonencode(manifest, 'PrettyPrint', true);
catch
    txt = jsonencode(manifest);
end
fid = fopen(pathValue, 'w');
if fid < 0
    error('m30_audit_multilayer_extension:WriteFailed', 'Cannot write %s.', pathValue);
end
cleanupObj = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', txt);
delete(cleanupObj);
end
