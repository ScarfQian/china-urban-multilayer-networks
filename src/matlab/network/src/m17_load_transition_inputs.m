function inputs = m17_load_transition_inputs(cfg)
% M17_LOAD_TRANSITION_INPUTS
% 读取低碳转型扩展所需的三层矩阵、角色表、节点指标和样本定义

sourceDir = char(cfg.sourceResultsDir);
requiredRootFiles = ["multilayer_results_manifest.json", "sample_definition_report.csv", ...
    "role_type_classification_2015.csv", "role_type_classification_2020.csv", ...
    "multilayer_node_metrics_2015.csv", "multilayer_node_metrics_2020.csv", ...
    "top_city_rankings_by_layer.csv", "table_network_summary_paper.csv", ...
    "table_multilayer_roles_paper.csv", "attack_city_orders.csv"];
for iFile = 1:numel(requiredRootFiles)
    assert_file_local(fullfile(sourceDir, char(requiredRootFiles(iFile))));
end

manifestPath = fullfile(sourceDir, 'multilayer_results_manifest.json');
manifest = jsondecode(fileread(manifestPath));
sampleReport = readtable(fullfile(sourceDir, 'sample_definition_report.csv'), 'TextType', 'string');
assert_sample_local(sampleReport, cfg);

inputs = struct();
inputs.sourceResultsDir = string(sourceDir);
inputs.outputDir = cfg.outputDir;
inputs.manifest = manifest;
inputs.sampleReport = sampleReport;
inputs.topRankings = readtable(fullfile(sourceDir, 'top_city_rankings_by_layer.csv'), 'TextType', 'string');
inputs.networkSummaryPaper = readtable(fullfile(sourceDir, 'table_network_summary_paper.csv'), 'TextType', 'string');
inputs.rolesPaper = readtable(fullfile(sourceDir, 'table_multilayer_roles_paper.csv'), 'TextType', 'string');
inputs.attackOrders = readtable(fullfile(sourceDir, 'attack_city_orders.csv'), 'TextType', 'string');

if isfield(manifest, 'parameters') && isfield(manifest.parameters, 'random_attack_repeats')
    inputs.randomRepeatsFromManifest = double(manifest.parameters.random_attack_repeats);
elseif isfield(manifest, 'parameters') && isfield(manifest.parameters, 'transition_random_repeats')
    inputs.randomRepeatsFromManifest = double(manifest.parameters.transition_random_repeats);
else
    inputs.randomRepeatsFromManifest = double(cfg.randomRepeats);
end

yearData = struct();
for iYear = 1:numel(cfg.years)
    yearValue = cfg.years(iYear);
    fieldName = "y" + string(yearValue);
    roleTable = readtable(fullfile(sourceDir, "role_type_classification_" + string(yearValue) + ".csv"), 'TextType', 'string');
    nodeTable = readtable(fullfile(sourceDir, "multilayer_node_metrics_" + string(yearValue) + ".csv"), 'TextType', 'string');
    singleTable = readtable(fullfile(sourceDir, "single_layer_node_metrics_" + string(yearValue) + ".csv"), 'TextType', 'string');
    validationTable = readtable(fullfile(sourceDir, "layer_construction_validation_" + string(yearValue) + ".csv"), 'TextType', 'string');

    cityTable = unique(nodeTable(:, {'city_code', 'city_name'}), 'rows', 'stable');
    assert_city_table_local(cityTable, roleTable, cfg, yearValue);

    layerDir = fullfile(sourceDir, 'layers');
    W_I = load_matrix_local(fullfile(layerDir, "W_I_" + string(yearValue) + ".mat"), cfg, yearValue, "investment");
    W_E = load_matrix_local(fullfile(layerDir, "W_E_" + string(yearValue) + ".mat"), cfg, yearValue, "economic");
    W_C = load_matrix_local(fullfile(layerDir, "W_C_" + string(yearValue) + ".mat"), cfg, yearValue, "carbon");

    yearStruct = struct();
    yearStruct.year = yearValue;
    yearStruct.cityTable = cityTable;
    yearStruct.roleTable = roleTable;
    yearStruct.nodeMetrics = nodeTable;
    yearStruct.singleLayerMetrics = singleTable;
    yearStruct.layerValidation = validationTable;
    yearStruct.W_I = W_I;
    yearStruct.W_E = W_E;
    yearStruct.W_C = W_C;
    yearData.(fieldName) = yearStruct;
end
inputs.yearData = yearData;
end

function assert_file_local(pathValue)
if ~exist(pathValue, 'file')
    error('m17_load_transition_inputs:MissingFile', 'Required revised input is missing: %s', pathValue);
end
end

function assert_sample_local(sampleReport, cfg)
if isempty(sampleReport) || height(sampleReport) < 1
    error('m17_load_transition_inputs:EmptySampleReport', 'sample_definition_report.csv is empty.');
end
if ~strcmpi(string(sampleReport.sample_mode(1)), string(cfg.sampleMode))
    error('m17_load_transition_inputs:WrongSampleMode', 'Expected sample_mode=%s, found %s.', cfg.sampleMode, sampleReport.sample_mode(1));
end
if double(sampleReport.included_nodes(1)) ~= double(cfg.expectedCities)
    error('m17_load_transition_inputs:WrongCityCount', 'Expected %d included nodes, found %d.', cfg.expectedCities, sampleReport.included_nodes(1));
end
end

function assert_city_table_local(cityTable, roleTable, cfg, yearValue)
codes = double(cityTable.city_code);
if numel(unique(codes)) ~= cfg.expectedCities
    error('m17_load_transition_inputs:CityCountMismatch', 'Year %d has %d unique cities, expected %d.', yearValue, numel(unique(codes)), cfg.expectedCities);
end
bad = intersect(codes, double(cfg.excludedProxyCodes(:)));
if ~isempty(bad)
    error('m17_load_transition_inputs:ProxyNodeFound', 'Year %d still contains proxy node(s): %s.', yearValue, strjoin(string(bad), ','));
end
[foundRole, ~] = ismember(codes, double(roleTable.city_code));
if ~all(foundRole)
    error('m17_load_transition_inputs:RoleCityMismatch', 'Year %d role table misses %d cities.', yearValue, sum(~foundRole));
end
end

function W = load_matrix_local(pathValue, cfg, yearValue, layerName)
assert_file_local(pathValue);
S = load(pathValue);
if isfield(S, 'W')
    W = double(S.W);
else
    names = fieldnames(S);
    W = double(S.(names{1}));
end
if ~isequal(size(W), [cfg.expectedCities, cfg.expectedCities])
    error('m17_load_transition_inputs:WrongMatrixSize', 'Year %d %s matrix has size %dx%d, expected %dx%d.', ...
        yearValue, layerName, size(W, 1), size(W, 2), cfg.expectedCities, cfg.expectedCities);
end
if any(~isfinite(W), 'all') || any(W < -cfg.auditTolerance, 'all')
    error('m17_load_transition_inputs:InvalidMatrix', 'Year %d %s matrix contains non-finite or negative values.', yearValue, layerName);
end
W(W < 0) = 0;
end
