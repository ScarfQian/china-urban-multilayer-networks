function manifest = m42_write_transition_pareto_v2_outputs_260810( ...
        inputs, v1, continuousBound, scopeFrontier, scopeSelections, ...
        gapDecomposition, attainment, attainmentSummary, similarity, ...
        substitutions, randomIntervalSummary, cfg)
% M42_WRITE_TRANSITION_PARETO_V2_OUTPUTS_260810
% 写出 Pareto v2 正式结果、manifest 与运行摘要

prefix = char(cfg.fileDatePrefix);
outDir = char(cfg.outputDir);
files = output_files_local(prefix);

writetable(continuousBound, fullfile(outDir, files.continuous));
writetable(scopeFrontier, fullfile(outDir, files.scopeFrontier));
writetable(scopeSelections, fullfile(outDir, files.scopeSelections));
writetable(gapDecomposition, fullfile(outDir, files.decomposition));
writetable(attainment, fullfile(outDir, files.attainment));
writetable(attainmentSummary, fullfile(outDir, files.attainmentSummary));
writetable(similarity, fullfile(outDir, files.similarity));
writetable(substitutions, fullfile(outDir, files.substitutions));
writetable(randomIntervalSummary, fullfile(outDir, files.randomIntervals));

manifest = struct();
manifest.created_at = char(cfg.runTimestamp);
manifest.module = 'transition_pareto_scope_completion_v2';
manifest.module_root = char(cfg.moduleRoot);
manifest.source_transition_directory = char(cfg.sourceTransitionDir);
manifest.source_v1_directory = char(cfg.v1ResultDir);
manifest.output_directory = outDir;
manifest.sample_mode = char(cfg.sampleMode);
manifest.years = cfg.years;
manifest.n_cities = cfg.nCities;
manifest.main_tau = cfg.mainTau;
manifest.er_grid = struct('start', cfg.erGrid(1), ...
    'end', cfg.erGrid(end), 'step', -0.001, ...
    'point_count', numel(cfg.erGrid));
manifest.scope_eta = cfg.scopeEta;
manifest.main_eta = cfg.mainEta;
manifest.random_repeats = cfg.randomRepeats;
manifest.solver = struct('name', 'gurobi', ...
    'matlab_api_path', which('gurobi'), ...
    'mip_gap_parameter', cfg.mipGapTolerance, ...
    'mip_gap_abs_parameter', cfg.mipGapAbs, ...
    'relative_gap_acceptance', cfg.solverGapAcceptance, ...
    'absolute_bound_gap_acceptance', cfg.solverAbsoluteGapAcceptance, ...
    'feasibility_tolerance', cfg.feasibilityTolerance, ...
    'objective_lock_tolerance', cfg.objectiveTolerance, ...
    'seed', cfg.solverSeed);
manifest.matlab_version = version;
manifest.strategies = cellstr(cfg.strategies);
manifest.technical_benchmark = struct( ...
    'name', char(cfg.technicalBenchmark), ...
    'definition', 'CB_share divided by PC_share with explicit zero handling', ...
    'interpretation', ...
    'pure efficiency technical benchmark, not a governance strategy');
manifest.scientific_definition = struct( ...
    'economic_flow_share', 'PC_share', ...
    'carbon_flow_share', 'CB_share', ...
    'production_flow_loss', ...
    'tau * sum(PC_share for selected cities)', ...
    'carbon_flow_reduction', ...
    'tau * sum(CB_share for selected cities)', ...
    'economic_retention', '1 - production_flow_loss');
manifest.scope_capped_definition = [ ...
    'Maximize carbon-flow reduction subject to the production-flow-loss ' ...
    'budget and sum(x)<=candidate feasible city count.'];
manifest.continuous_bound_definition = [ ...
    'Fractional-city intervention upper bound; at most one positive-cost ' ...
    'city is partially selected.'];
manifest.ifar_definition = [ ...
    'Ratio of unsmoothed strategy and exact-frontier trapezoid areas on ' ...
    'the configured 101-point budget grid.'];
manifest.optimality_statement = ...
    'optimal within configured numerical tolerances';
manifest.frontier_scope = [ ...
    'Each ER grid point is an independent static city-combination problem; ' ...
    'not a nested cumulative transition path and not the complete Pareto set.'];
manifest.interpretation_boundary = [ ...
    'Weighted-attenuation network stress test; not a CGE model, welfare ' ...
    'analysis, causal policy evaluation or administrative cost model.'];
manifest.v1_system_frontier_recomputed = false;
manifest.v1_system_frontier_reused = true;
manifest.upstream_modules_rerun = false;
manifest.final_freeze_modified = false;
manifest.v1_result_modified = false;
manifest.continuous_bound_row_count = height(continuousBound);
manifest.scope_frontier_row_count = height(scopeFrontier);
manifest.scope_selection_row_count = height(scopeSelections);
manifest.gap_decomposition_row_count = height(gapDecomposition);
manifest.attainment_row_count = height(attainment);
manifest.similarity_row_count = height(similarity);
manifest.substitution_row_count = height(substitutions);
manifest.input_files = cellstr([string(inputs.sourceDir) + filesep + ...
    string(inputs.requiredFiles); string(v1.requiredPaths)]);
manifest.files_created = cellstr(string(struct2cell(files)));
manifest.audit_status = 'PENDING';

manifestPath = fullfile(outDir, files.manifest);
summaryPath = fullfile(outDir, files.summary);
write_json_local(manifestPath, manifest);
write_summary_local(summaryPath, manifest, continuousBound, ...
    scopeFrontier, gapDecomposition, attainmentSummary, similarity, cfg);
manifest.path = string(manifestPath);
manifest.summaryPath = string(summaryPath);
end

function files = output_files_local(prefix)
files = struct();
files.continuous = [prefix 'transition_continuous_bound.csv'];
files.scopeFrontier = [prefix 'transition_scope_capped_frontier.csv'];
files.scopeSelections = [prefix ...
    'transition_scope_capped_city_selections.csv'];
files.decomposition = [prefix ...
    'transition_efficiency_gap_decomposition.csv'];
files.attainment = [prefix ...
    'transition_integrated_frontier_attainment.csv'];
files.attainmentSummary = [prefix ...
    'transition_integrated_frontier_attainment_summary.csv'];
files.similarity = [prefix 'transition_city_set_similarity.csv'];
files.substitutions = [prefix 'transition_city_substitution_table.csv'];
files.randomIntervals = [prefix 'transition_random_interval_summary.csv'];
files.manifest = [prefix 'transition_pareto_v2_manifest.json'];
files.summary = [prefix 'transition_pareto_v2_run_summary.md'];
files.executionLog = [prefix 'transition_pareto_v2_execution.log'];
files.auditChecks = [prefix 'transition_pareto_v2_audit_checks.csv'];
files.auditReport = [prefix 'transition_pareto_v2_audit_report.md'];
end

function write_json_local(path, manifest)
json = jsonencode(manifest, 'PrettyPrint', true);
fid = fopen(path, 'w');
if fid < 0
    error('m42_pareto_v2:ManifestOpenFailed', ...
        'Cannot write manifest: %s', path);
end
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, json, 'char');
fwrite(fid, newline, 'char');
clear cleanup;
end

function write_summary_local(path, manifest, continuousBound, ...
        scopeFrontier, gapDecomposition, attainmentSummary, similarity, cfg)
fid = fopen(path, 'w');
if fid < 0
    error('m42_pareto_v2:SummaryOpenFailed', ...
        'Cannot write run summary: %s', path);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '# 城市数量约束下的转型策略比较\n\n');
fprintf(fid, '- 运行时间：%s\n', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
fprintf(fid, '- 冻结输入：`%s`\n', manifest.source_transition_directory);
fprintf(fid, '- v1 结果：`%s`\n', manifest.source_v1_directory);
fprintf(fid, '- v2 输出：`%s`\n', manifest.output_directory);
fprintf(fid, '- 求解器：Gurobi MATLAB API\n');
fprintf(fid, '- 最优性表述：在设定数值容限内最优\n\n');

fprintf(fid, '=========\n\n## 结果规模\n\n');
fprintf(fid, '| 结果 | 行数 |\n|---|---:|\n');
fprintf(fid, '| 连续上界 | %d |\n', height(continuousBound));
fprintf(fid, '| 范围约束前沿 | %d |\n', height(scopeFrontier));
fprintf(fid, '| 缺口分解 | %d |\n', height(gapDecomposition));
fprintf(fid, '| IFAR 汇总 | %d |\n', height(attainmentSummary));
fprintf(fid, '| 城市集合相似性 | %d |\n', height(similarity));

fprintf(fid, '\n=========\n\n## ER=0.95 核心比较\n\n');
fprintf(fid, ['以下结果仅表示相对 carbon-flow reduction 与 ' ...
    'production-flow loss，不是绝对减排量或一般经济成本。\n\n']);
focus = gapDecomposition(abs(gapDecomposition.eta - cfg.mainEta) <= ...
    cfg.objectiveTolerance & string(gapDecomposition.strategy) == ...
    "carbon_burden_low_control", :);
fprintf(fid, ['| 年份 | 候选 CR | 范围约束 CR | 系统 CR | ' ...
    '范围相对缺口 | 系统相对缺口 |\n']);
fprintf(fid, '|---:|---:|---:|---:|---:|---:|\n');
for i = 1:height(focus)
    fprintf(fid, '| %d | %.8f | %.8f | %.8f | %.4f | %.4f |\n', ...
        focus.year(i), focus.candidate_carbon_reduction(i), ...
        focus.scope_capped_optimal_reduction(i), ...
        focus.unrestricted_optimal_reduction(i), ...
        focus.relative_scope_capped_gap(i), ...
        focus.relative_system_gap(i));
end

fprintf(fid, '\n=========\n\n## 科学边界\n\n');
fprintf(fid, ['范围约束基准只控制城市数量，不代表真实行政成本。' ...
    'IFAR 是固定 101 点预算网格的积分比率。每个预算点是独立静态组合，' ...
    '不是城市只能逐步加入的累计转型路径。技术比率基准不具有治理或公平含义。' ...
    '本模块不是 CGE 模型，也不是因果政策评估。\n']);
fprintf(fid, '\n审计状态：待 m43 完成。\n');
end
