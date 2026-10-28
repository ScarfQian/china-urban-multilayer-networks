function out = m25_run_regression_gate_2017_hybrid(cfg)
% M25_RUN_REGRESSION_GATE_2017_HYBRID
% Re-run the accepted 2017 hybrid validation before any 2020 deployment work begins.

cfg = normalize_regression_cfg(cfg);
ensure_dir_regression(cfg.regressionDir);

gateOut = m19_validate_backcast_2017_y_hybrid_impl(struct( ...
    'city2012', cfg.city2012, ...
    'city2015', cfg.city2015, ...
    'city2017Raw', cfg.city2017Raw, ...
    'prov2017', cfg.prov2017, ...
    'mapping', cfg.mapping, ...
    'resultsDir', cfg.regressionDir, ...
    'fd4_mode', cfg.hybridParams.fd4_mode, ...
    'fd5_mode', cfg.hybridParams.fd5_mode, ...
    'skipTrain', true, ...
    'pretrainedHybridParams', cfg.acceptedHybridParams, ...
    'pretrainedFactorizedParams', cfg.acceptedFactorizedParams, ...
    'factorizedValidationPath', study_path('metadata', 'comparisons', 'factorized_validation.csv'), ...
    'baselineValidationPath', study_path('metadata', 'comparisons', 'baseline_validation.csv')));

acceptedValidation = readtable(cfg.acceptedHybridValidation, 'TextType', 'string');
currentValidation = readtable(gateOut.outputFiles.validation2017, 'TextType', 'string');
acceptedAgg = readtable(cfg.acceptedHybridAggregation, 'TextType', 'string');
currentAgg = readtable(gateOut.outputFiles.aggregation2017, 'TextType', 'string');

validationDiff = compare_metric_tables(acceptedValidation, currentValidation, "metric", "value");
aggDiff = compare_metric_tables(acceptedAgg, currentAgg, "metric", "value");

validationOutPath = fullfile(cfg.resultsDir, 'validation_backcast_2017_hybrid_regression.csv');
aggregationOutPath = fullfile(cfg.resultsDir, 'aggregation_check_2017_hybrid_regression.csv');
writetable(currentValidation, validationOutPath);
writetable(currentAgg, aggregationOutPath);

assert(max(abs(validationDiff.delta), [], 'all') <= cfg.regressionMetricTol, ...
    'm25_run_regression_gate_2017_hybrid:ValidationRegression', ...
    '2017 hybrid validation deviates from the accepted baseline.');
assert(max(abs(aggDiff.delta), [], 'all') <= cfg.regressionAggTol, ...
    'm25_run_regression_gate_2017_hybrid:AggregationRegression', ...
    '2017 hybrid aggregation deviates from the accepted baseline.');

out = struct();
out.ok = true;
out.validationPath = string(validationOutPath);
out.aggregationPath = string(aggregationOutPath);
out.validationDiff = validationDiff;
out.aggregationDiff = aggDiff;
out.raw = gateOut;
end

function cfg = normalize_regression_cfg(cfg)
required = ["rootDir","resultsDir","regressionDir","city2012","city2015","city2017Raw","prov2017","mapping", ...
    "acceptedHybridValidation","acceptedHybridAggregation","acceptedHybridParams","acceptedFactorizedParams", ...
    "hybridParams","regressionMetricTol","regressionAggTol"];
for i = 1:numel(required)
    if ~isfield(cfg, required(i))
        error('m25_run_regression_gate_2017_hybrid:MissingCfgField', ...
            'Missing required configuration field: %s', required(i));
    end
end
end

function diffTable = compare_metric_tables(leftTable, rightTable, keyName, valueName)
keyVar = char(string(keyName));
valueVar = char(string(valueName));
leftTable = leftTable(:, {keyVar, valueVar});
rightTable = rightTable(:, {keyVar, valueVar});
leftTable.Properties.VariableNames = {'key','left_value'};
rightTable.Properties.VariableNames = {'key','right_value'};
joined = outerjoin(leftTable, rightTable, 'Keys', 'key', 'MergeKeys', true, 'Type', 'full');
joined.left_value = fillmissing(joined.left_value, 'constant', NaN);
joined.right_value = fillmissing(joined.right_value, 'constant', NaN);
joined.delta = double(joined.right_value) - double(joined.left_value);
diffTable = joined;
end

function ensure_dir_regression(dirPath)
if ~exist(dirPath, 'dir')
    mkdir(dirPath);
end
end
