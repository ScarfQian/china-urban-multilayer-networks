function manifest = m36_write_transition_pareto_manifest_260810( ...
        inputs, prefixes, frontier, efficiencyGaps, cfg)
% M36_WRITE_TRANSITION_PARETO_MANIFEST_260810
% 写出独立精确前沿扩展的 manifest 与运行摘要

prefix = char(cfg.fileDatePrefix);
outDir = char(cfg.outputDir);
manifestPath = fullfile(outDir, ...
    [prefix 'transition_pareto_manifest.json']);
summaryPath = fullfile(outDir, ...
    [prefix 'transition_pareto_run_summary.md']);

createdFiles = [
    sprintf('%stransition_exact_prefix_curves_2015.csv', prefix)
    sprintf('%stransition_exact_prefix_curves_2020.csv', prefix)
    string([prefix 'transition_carbon_economic_ratio_orders.csv'])
    string([prefix 'transition_prefix_consistency_check.csv'])
    string([prefix 'transition_exact_frontier.csv'])
    string([prefix 'transition_exact_frontier_city_selections.csv'])
    string([prefix 'transition_strategy_efficiency_gaps.csv'])
    string([prefix 'transition_random_efficiency_gap_summary.csv'])
    string([prefix 'transition_efficiency_gap_key_eta_summary.csv'])
    string([prefix 'transition_pareto_manifest.json'])
    string([prefix 'transition_pareto_run_summary.md'])
    string([prefix 'transition_pareto_execution.log'])
    string([prefix 'transition_pareto_audit_report.md'])
    string([prefix 'transition_pareto_audit_checks.csv'])
    ];

inputFiles = strings(numel(inputs.requiredFiles), 1);
for i = 1:numel(inputs.requiredFiles)
    inputFiles(i) = fullfile(inputs.sourceDir, inputs.requiredFiles(i));
end

prefixRows = 0;
prefixGroups = 0;
for year = cfg.years
    key = sprintf('y%d', year);
    current = prefixes.(key);
    prefixRows = prefixRows + height(current);
    prefixGroups = prefixGroups + height(unique(current(:, ...
        {'year', 'strategy', 'repeat_id'}), 'rows'));
end

manifest = struct();
manifest.created_at = char(cfg.runTimestamp);
manifest.module = 'transition_strategy_exact_frontier_and_efficiency_gap';
manifest.module_root = char(cfg.moduleRoot);
manifest.source_transition_directory = char(cfg.sourceTransitionDir);
manifest.output_directory = outDir;
manifest.sample_mode = char(cfg.sampleMode);
manifest.years = cfg.years;
manifest.n_cities = cfg.nCities;
manifest.main_tau = cfg.mainTau;
manifest.er_grid = struct('start', cfg.erGrid(1), ...
    'end', cfg.erGrid(end), 'step', -0.001, ...
    'point_count', numel(cfg.erGrid));
manifest.key_eta = cfg.keyEta;
manifest.main_eta = cfg.mainEta;
manifest.random_repeats = cfg.randomRepeats;
manifest.solver = struct('name', 'gurobi', ...
    'matlab_api_path', which('gurobi'), ...
    'mip_gap_tolerance', cfg.mipGapTolerance, ...
    'feasibility_tolerance', cfg.feasibilityTolerance, ...
    'objective_tolerance', cfg.objectiveTolerance);
manifest.matlab_version = version;
manifest.strategies = cellstr(cfg.strategies);
manifest.technical_benchmark = struct( ...
    'name', char(cfg.technicalBenchmark), ...
    'definition', 'CB_share divided by PC_share with explicit zero handling', ...
    'interpretation', 'pure efficiency technical benchmark, not a governance strategy');
manifest.scientific_definition = struct( ...
    'economic_flow_share', 'PC_share', ...
    'carbon_flow_share', 'CB_share', ...
    'economic_loss', 'tau * sum(PC_share for selected cities)', ...
    'carbon_reduction', 'tau * sum(CB_share for selected cities)', ...
    'economic_retention', '1 - economic_loss');
manifest.exact_frontier_scope = [ ...
    'Global optimum at each configured ER grid point; ' ...
    'not enumeration of every nondominated city combination.'];
manifest.interpretation_boundary = [ ...
    'Weighted-attenuation network stress test; not a CGE model and ' ...
    'not a causal policy evaluation.'];
manifest.upstream_modules_rerun = false;
manifest.final_freeze_modified = false;
manifest.prefix_group_count = prefixGroups;
manifest.prefix_row_count = prefixRows;
manifest.frontier_row_count = height(frontier);
manifest.efficiency_gap_row_count = height(efficiencyGaps);
manifest.input_files = cellstr(inputFiles);
manifest.files_created = cellstr(createdFiles);
manifest.audit_status = 'PENDING';

json = jsonencode(manifest, 'PrettyPrint', true);
fid = fopen(manifestPath, 'w');
if fid < 0
    error('m36_transition_manifest:OpenFailed', ...
        'Cannot write manifest: %s', manifestPath);
end
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, json, 'char');
fwrite(fid, newline, 'char');
clear cleanup;

write_summary_local(summaryPath, manifest, prefixes, frontier, efficiencyGaps, cfg);
manifest.path = string(manifestPath);
manifest.summaryPath = string(summaryPath);
end

function write_summary_local(path, manifest, prefixes, frontier, gaps, cfg)
fid = fopen(path, 'w');
if fid < 0
    error('m36_transition_manifest:SummaryOpenFailed', ...
        'Cannot write run summary: %s', path);
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# 转型策略精确约束前沿与效率缺口运行摘要\n\n');
fprintf(fid, '- 运行时间：%s\n', char(cfg.runTimestamp));
fprintf(fid, '- 冻结输入：`%s`\n', manifest.source_transition_directory);
fprintf(fid, '- 独立输出：`%s`\n', manifest.output_directory);
fprintf(fid, '- MATLAB：`%s`\n', manifest.matlab_version);
fprintf(fid, '- 求解器：Gurobi MATLAB API\n');
fprintf(fid, '- 审计状态：待 m37 独立审计完成\n\n');

fprintf(fid, '=========\n\n## 计算范围\n\n');
fprintf(fid, ['使用 2015 和 2020 年冻结治理指标中的 `PC_share` 与 ' ...
    '`CB_share`，固定 `tau=0.10`。每个排序按 `K=0...309` ' ...
    '生成 310 个完整前缀点；随机基准保留 50 个逐重复序列。\n\n']);
fprintf(fid, '| 年份 | 完整前缀行数 | 精确前沿点数 |\n');
fprintf(fid, '| ---: | ---: | ---: |\n');
for year = cfg.years
    key = sprintf('y%d', year);
    fprintf(fid, '| %d | %d | %d |\n', year, height(prefixes.(key)), ...
        sum(frontier.year == year));
end

fprintf(fid, '\n=========\n\n## 精确前沿与效率缺口\n\n');
fprintf(fid, ['每个 `ER=1.000:-0.001:0.900` 预算点均执行三级字典序' ...
    '二元规划：先最大化碳减排，再最小化实际经济损失，最后最小化干预城市数。' ...
    '效率缺口定义为同一 ER 预算下精确前沿减碳量减去策略最佳完整前缀减碳量。\n\n']);
fprintf(fid, '- 精确前沿行数：%d\n', height(frontier));
fprintf(fid, '- 逐策略效率缺口行数：%d\n', height(gaps));
fprintf(fid, '- Gurobi 相对间隙容限：`%.1e`\n', cfg.mipGapTolerance);
fprintf(fid, '- 可行性容限：`%.1e`\n', cfg.feasibilityTolerance);

fprintf(fid, '\n=========\n\n## 科学边界\n\n');
fprintf(fid, ['`carbon_economic_ratio` 仅是模型内纯效率技术基准，不是治理公平规则。' ...
    '“精确前沿”仅表示配置的 ER 网格点达到模型内全局最优，不表示枚举全部非支配组合。' ...
    '本模块仍是加权网络衰减压力测试，不是 CGE 模型，也不是因果政策评估。\n']);
end
