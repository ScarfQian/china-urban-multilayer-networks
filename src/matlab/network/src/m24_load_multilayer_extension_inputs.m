function inputs = m24_load_multilayer_extension_inputs(cfg)
% M24_LOAD_MULTILAYER_EXTENSION_INPUTS
% 读取 multilayer extension 所需矩阵、角色、节点指标、社群、韧性和转型输出

sourceDir = char(cfg.sourceResultsDir);
transitionDir = char(cfg.transitionResultsDir);
assert_file_local(fullfile(sourceDir, 'sample_definition_report.csv'));
assert_file_local(fullfile(sourceDir, 'table_resilience_auc_paper.csv'));
assert_file_local(fullfile(sourceDir, 'multilayer_results_manifest.json'));
assert_file_local(fullfile(transitionDir, 'transition_stress_auc_summary.csv'));

sampleReport = readtable(fullfile(sourceDir, 'sample_definition_report.csv'), 'TextType', 'string');
if string(sampleReport.sample_mode(1)) ~= string(cfg.sampleMode) || double(sampleReport.included_nodes(1)) ~= double(cfg.expectedCities)
    error('m24_load_multilayer_extension_inputs:SampleMismatch', ...
        'Expected pure-city sample with %d cities.', cfg.expectedCities);
end

inputs = struct();
inputs.sourceResultsDir = string(sourceDir);
inputs.transitionResultsDir = string(transitionDir);
inputs.outputDir = cfg.outputDir;
inputs.sampleReport = sampleReport;
inputs.manifest = jsondecode(fileread(fullfile(sourceDir, 'multilayer_results_manifest.json')));
inputs.resilienceAuc = readtable(fullfile(sourceDir, 'table_resilience_auc_paper.csv'), 'TextType', 'string');
inputs.transitionAuc = readtable(fullfile(transitionDir, 'transition_stress_auc_summary.csv'), 'TextType', 'string');
inputs.yearData = struct();

for iYear = 1:numel(cfg.years)
    yearValue = cfg.years(iYear);
    fieldName = "y" + string(yearValue);
    roleTable = readtable(fullfile(sourceDir, "role_type_classification_" + string(yearValue) + ".csv"), 'TextType', 'string');
    nodeMetrics = readtable(fullfile(sourceDir, "multilayer_node_metrics_" + string(yearValue) + ".csv"), 'TextType', 'string');
    communityLabels = readtable(fullfile(sourceDir, "community_labels_" + string(yearValue) + ".csv"), 'TextType', 'string');

    cityTable = unique(nodeMetrics(:, {'city_code', 'city_name'}), 'rows', 'stable');
    cityTable.city_code = double(cityTable.city_code);
    cityTable.city_name = string(cityTable.city_name);
    assert_city_sample_local(cityTable, cfg, yearValue);

    layerDir = fullfile(sourceDir, 'layers');
    W_I = load_W_local(fullfile(layerDir, "W_I_" + string(yearValue) + ".mat"), cfg, yearValue, "investment");
    W_E = load_W_local(fullfile(layerDir, "W_E_" + string(yearValue) + ".mat"), cfg, yearValue, "production");
    W_C = load_W_local(fullfile(layerDir, "W_C_" + string(yearValue) + ".mat"), cfg, yearValue, "carbon");

    yearStruct = struct();
    yearStruct.year = yearValue;
    yearStruct.cityTable = cityTable;
    yearStruct.roleTable = align_by_city_local(roleTable, cityTable);
    yearStruct.nodeMetrics = align_by_city_local(nodeMetrics, cityTable);
    yearStruct.communityLabels = communityLabels;
    yearStruct.W_I = W_I;
    yearStruct.W_E = W_E;
    yearStruct.W_C = W_C;
    inputs.yearData.(fieldName) = yearStruct;
end
end

function assert_file_local(pathValue)
if ~exist(pathValue, 'file')
    error('m24_load_multilayer_extension_inputs:MissingFile', 'Required file missing: %s', pathValue);
end
end

function assert_city_sample_local(cityTable, cfg, yearValue)
codes = double(cityTable.city_code);
if numel(unique(codes)) ~= double(cfg.expectedCities)
    error('m24_load_multilayer_extension_inputs:CityCountMismatch', ...
        'Year %d has %d cities, expected %d.', yearValue, numel(unique(codes)), cfg.expectedCities);
end
bad = intersect(codes, double(cfg.excludedProxyCodes(:)));
if ~isempty(bad)
    error('m24_load_multilayer_extension_inputs:ProxyNodeFound', ...
        'Year %d contains proxy node(s): %s.', yearValue, strjoin(string(bad), ','));
end
end

function W = load_W_local(pathValue, cfg, yearValue, layerName)
assert_file_local(pathValue);
S = load(pathValue);
if isfield(S, 'W')
    W = double(S.W);
else
    names = fieldnames(S);
    W = double(S.(names{1}));
end
if ~isequal(size(W), [cfg.expectedCities, cfg.expectedCities])
    error('m24_load_multilayer_extension_inputs:MatrixSizeMismatch', ...
        'Year %d %s matrix size is %dx%d.', yearValue, layerName, size(W, 1), size(W, 2));
end
if any(~isfinite(W), 'all') || any(W < -cfg.auditTolerance, 'all')
    error('m24_load_multilayer_extension_inputs:InvalidMatrix', ...
        'Year %d %s matrix contains invalid values.', yearValue, layerName);
end
W(W < 0) = 0;
W(1:size(W, 1)+1:end) = 0;
end

function aligned = align_by_city_local(T, cityTable)
[found, idx] = ismember(double(cityTable.city_code), double(T.city_code));
if ~all(found)
    error('m24_load_multilayer_extension_inputs:CityMissing', ...
        'Auxiliary table misses %d cities.', sum(~found));
end
aligned = T(idx, :);
end
