function out = m18_summarize_y_hybrid_results(cfg)
% M18_SUMMARIZE_Y_HYBRID_RESULTS
% Compare hybrid results against current factorized and forecast-style-consistent baselines.

cfg = normalize_cfg(cfg);
ensure_dir(cfg.resultsDir);

hybridMetrics = load_metric_table(cfg.hybridValidationPath, cfg.truthYAbsSum, cfg.numYElements);
factorizedMetrics = load_metric_table(cfg.factorizedValidationPath, cfg.truthYAbsSum, cfg.numYElements);
baselineMetrics = load_metric_table(cfg.baselineValidationPath, cfg.truthYAbsSum, cfg.numYElements);

metricList = [ ...
    "Y_WAPE"; "Y_MAE"; "Y_RMSE"; "block_share_jsd"; "top_cell_hit_rate"; ...
    "fd1_WAPE"; "fd2_WAPE"; "fd3_WAPE"; "fd4_WAPE"; "fd5_WAPE"; ...
    "Z_MAE"; "X_MAE"; "VA_MAE"; "IM_MAE"; "EX_MAE"];

hybridValue = nan(numel(metricList), 1);
factorizedValue = nan(numel(metricList), 1);
baselineValue = nan(numel(metricList), 1);
deltaFactorized = nan(numel(metricList), 1);
deltaBaseline = nan(numel(metricList), 1);
lowerIsBetter = true(numel(metricList), 1);
lowerIsBetter(metricList == "top_cell_hit_rate") = false;

for i = 1:numel(metricList)
    hybridValue(i) = lookup_metric(hybridMetrics, metricList(i));
    factorizedValue(i) = lookup_metric(factorizedMetrics, metricList(i));
    baselineValue(i) = lookup_metric(baselineMetrics, metricList(i));
    deltaFactorized(i) = hybridValue(i) - factorizedValue(i);
    deltaBaseline(i) = hybridValue(i) - baselineValue(i);
end

hybridBetterThanFactorized = nan(numel(metricList), 1);
hybridBetterThanBaseline = nan(numel(metricList), 1);
for i = 1:numel(metricList)
    if ~isnan(hybridValue(i)) && ~isnan(factorizedValue(i))
        hybridBetterThanFactorized(i) = compare_metric(hybridValue(i), factorizedValue(i), lowerIsBetter(i));
    end
    if ~isnan(hybridValue(i)) && ~isnan(baselineValue(i))
        hybridBetterThanBaseline(i) = compare_metric(hybridValue(i), baselineValue(i), lowerIsBetter(i));
    end
end

comparisonTable = table(metricList, hybridValue, factorizedValue, baselineValue, ...
    deltaFactorized, deltaBaseline, lowerIsBetter, hybridBetterThanFactorized, hybridBetterThanBaseline, ...
    'VariableNames', {'metric','hybrid','factorized','forecast_style_consistent', ...
    'delta_vs_factorized','delta_vs_forecast_style_consistent', ...
    'lower_is_better','hybrid_better_than_factorized','hybrid_better_than_forecast_style_consistent'});

comparisonPath = fullfile(cfg.resultsDir, 'y_hybrid_by_fd_comparison.csv');
writetable(comparisonTable, comparisonPath);

out = struct();
out.comparisonTable = comparisonTable;
out.hybridMetrics = hybridMetrics;
out.factorizedMetrics = factorizedMetrics;
out.baselineMetrics = baselineMetrics;
out.outputFiles = struct('byFDComparison', string(comparisonPath));
end

function cfg = normalize_cfg(cfg)
required = ["resultsDir","hybridValidationPath","truthYAbsSum","numYElements"];
for i = 1:numel(required)
    if ~isfield(cfg, required(i))
        error('m18_summarize_y_hybrid_results:MissingCfgField', ...
            'Missing required configuration field: %s', required(i));
    end
end
if ~isfield(cfg, 'factorizedValidationPath'); cfg.factorizedValidationPath = ""; end
if ~isfield(cfg, 'baselineValidationPath'); cfg.baselineValidationPath = ""; end
end

function T = load_metric_table(pathValue, truthYAbsSum, numYElements)
T = table(strings(0,1), zeros(0,1), 'VariableNames', {'metric','value'});
if isempty(pathValue) || strlength(string(pathValue)) == 0 || ~exist(pathValue, 'file')
    return;
end
raw = readtable(pathValue, 'TextType', 'string');
if ~ismember("metric", raw.Properties.VariableNames) || ~ismember("value", raw.Properties.VariableNames)
    error('m18_summarize_y_hybrid_results:InvalidMetricTable', ...
        'Validation file %s must contain metric and value columns.', string(pathValue));
end
T = raw(:, {'metric','value'});
if ~any(T.metric == "Y_WAPE") && any(T.metric == "Y_MAE")
    yMae = lookup_metric(T, "Y_MAE");
    yWape = yMae * double(numYElements) / max(double(truthYAbsSum), eps);
    T = [T; table("Y_WAPE", yWape, 'VariableNames', {'metric','value'})]; %#ok<AGROW>
end
end

function value = lookup_metric(T, metricName)
idx = find(T.metric == metricName, 1, 'first');
if isempty(idx)
    value = NaN;
else
    value = double(T.value(idx));
end
end

function tf = compare_metric(lhs, rhs, lowerIsBetter)
if lowerIsBetter
    tf = double(lhs < rhs);
else
    tf = double(lhs > rhs);
end
end

function ensure_dir(dirPath)
if ~exist(dirPath, 'dir')
    mkdir(dirPath);
end
end
