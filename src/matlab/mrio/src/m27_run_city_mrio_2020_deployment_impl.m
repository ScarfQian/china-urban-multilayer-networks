function out = m27_run_city_mrio_2020_deployment_impl(cfg)
% M27_RUN_CITY_MRIO_2020_DEPLOYMENT_IMPL
% Run the 2020 city MRIO deployment round under the accepted 2017 hybrid design.

if nargin < 1 || isempty(cfg)
    cfg = m26_config_2020_city_deployment();
end
cfg = normalize_runner_cfg(cfg);
ensure_dir_runner(cfg.resultsDir);
reset_file_runner(cfg.failureSummaryPath);
addpath(fullfile(cfg.rootDir, 'src'));
try
    if cfg.skipRegression
        regression = struct('ok', true, ...
            'validationPath', string(fullfile(cfg.resultsDir, 'validation_backcast_2017_hybrid_regression.csv')), ...
            'aggregationPath', string(fullfile(cfg.resultsDir, 'aggregation_check_2017_hybrid_regression.csv')));
    else
        regression = m25_run_regression_gate_2017_hybrid(cfg);
    end
    city2017Harm = resolve_city2017_harm(cfg);
    prov2020 = resolve_prov_2020(cfg.prov2020);
    mapping = resolve_mapping_2020(cfg.mapping, city2017Harm, prov2020);

    scenarioNames = ["baseline","factorized","hybrid"];
    scenarioResults = struct([]);
    for i = 1:numel(scenarioNames)
        resultI = run_single_2020_scenario(scenarioNames(i), city2017Harm, prov2020, mapping, cfg);
        if isempty(scenarioResults)
            scenarioResults = resultI;
        else
            scenarioResults(i) = resultI; %#ok<AGROW>
        end
    end

    compareOut = m24_compare_2020_y_scenarios(scenarioResults, mapping, ...
        'ComparisonPath', fullfile(cfg.resultsDir, 'scenario_comparison_2020_y_modes.csv'), ...
        'EnvelopePath', fullfile(cfg.resultsDir, 'scenario_envelope_2020_summary.csv'));

    out = struct();
    out.ok = true;
    out.regression = regression;
    out.scenarios = scenarioResults;
    out.comparison = compareOut;
    out.resultsDir = string(cfg.resultsDir);
catch ME
    write_failure_summary(cfg.failureSummaryPath, ME);
    rethrow(ME);
end
end

function cfg = normalize_runner_cfg(cfg)
required = ["rootDir","resultsDir","failureSummaryPath","regressionDir","city2017Raw","prov2017","prov2020","mapping", ...
    "hybridParams","factorizedParams","numericClass","epsilon","provTol","rowTol","colTol","maxIter","tolRow","tolCol","tolBlock","skipRegression"];
for i = 1:numel(required)
    if ~isfield(cfg, required(i))
        error('m27_run_city_mrio_2020_deployment_impl:MissingCfgField', ...
            'Missing required configuration field: %s', required(i));
    end
end
if ~isfield(cfg, 'zMode')
    cfg.zMode = "seed_fixed";
end
end

function result = run_single_2020_scenario(name, city2017Harm, prov2020, mapping, cfg)
stageAuditPath = fullfile(cfg.resultsDir, "stage_audit_2020_" + name + ".csv");
reset_file_runner(stageAuditPath);

targets = m22_build_city_targets_2020_consistent(city2017Harm, prov2020, mapping, ...
    'YMode', name, ...
    'FactorizedParams', cfg.factorizedParams, ...
    'HybridParams', cfg.hybridParams, ...
    'ProxyTable', cfg.proxyTable, ...
    'Eta', cfg.eta, ...
    'NumericClass', cfg.numericClass, ...
    'Epsilon', cfg.epsilon, ...
    'TopSupportCount', cfg.topSupportCount, ...
    'Validate', true);
    %#ok<NASGU>
m20_validate_targets_2020_consistency(targets, prov2020, mapping, 'Validate', true, 'Tol', cfg.provTol);
write_stage_row_2020(build_stage_row_from_targets("targets", targets, prov2020, mapping, ...
    "2020 " + name + " targets"), stageAuditPath, false);

seed = m23_build_seed_city_z_2020_consistent(city2017Harm, prov2020, mapping, ...
    'NumericClass', cfg.numericClass, ...
    'Epsilon', cfg.epsilon, ...
    'Validate', true);
m21_validate_seed_2020_consistency(seed, prov2020, mapping, 'Validate', true, 'Tol', cfg.provTol);
write_stage_row_2020(build_stage_row_from_seed("seed", seed, prov2020, mapping, ...
    "2020 " + name + " seed"), stageAuditPath, true);

if strcmpi(string(cfg.zMode), "seed_fixed")
    zResult = struct();
    zResult.blocks = seed.blocks;
    zResult.Mapping = mapping;
    zResult.targetZ = prov2020.Z;
    zResult.Diagnostics = struct();
    zResult.Diagnostics.mode = "seed_fixed";
    zResult.Diagnostics.converged = true;
    zResult.Diagnostics.logTable = table();

    afterZCity = assemble_stage_city_2020(seed.blocks, targets.Y_city, targets.VA, targets.IM, targets.EX, mapping, city2017Harm, cfg);
    write_stage_row_2020(build_stage_row_from_city("after_z_solver", afterZCity, prov2020, mapping, ...
        "2020 " + name + " after Z stage (seed_fixed)"), stageAuditPath, true);

    afterYCity = assemble_stage_city_2020(seed.blocks, targets.YResult.Y, targets.VA, targets.IM, targets.EX, mapping, city2017Harm, cfg);
    write_stage_row_2020(build_stage_row_from_city("after_y_downscale", afterYCity, prov2020, mapping, ...
        "2020 " + name + " after Y downscale (seed_fixed Z)"), stageAuditPath, true);
else
    zResult = m12_nested_ras_city_z(seed, targets.Z_row_target, targets.Z_col_target, ...
        'MaxIter', cfg.maxIter, ...
        'TolRow', cfg.tolRow, ...
        'TolCol', cfg.tolCol, ...
        'TolBlock', cfg.tolBlock);
    afterZCity = build_city_from_parts_2020(zResult.blocks, targets.Y_city, targets.X, targets.VA, targets.IM, targets.EX, targets.error, mapping, city2017Harm);
    write_stage_row_2020(build_stage_row_from_city("after_z_solver", afterZCity, prov2020, mapping, ...
        "2020 " + name + " after Z solver"), stageAuditPath, true);

    afterYCity = build_city_from_parts_2020(zResult.blocks, targets.YResult.Y, targets.X, targets.VA, targets.IM, targets.EX, targets.error, mapping, city2017Harm);
    write_stage_row_2020(build_stage_row_from_city("after_y_downscale", afterYCity, prov2020, mapping, ...
        "2020 " + name + " after Y downscale"), stageAuditPath, true);
end

assemblyTargets = struct('X', targets.X, 'VA', targets.VA, 'IM', targets.IM, 'EX', targets.EX, ...
    'error', targets.error, 'mapping', mapping);
finalCity = m13_assemble_city_mrio_2020(zResult, targets.YResult, assemblyTargets, ...
    'OutputClass', cfg.numericClass, ...
    'ResidualTol', max(cfg.rowTol, cfg.colTol), ...
    'AllowResidualError', true, ...
    'XMode', "column_closed");
finalCity = attach_city_metadata_2020(finalCity, city2017Harm);
finalRow = build_stage_row_from_city("after_assembly", finalCity, prov2020, mapping, ...
    "2020 " + name + " final output (column_closed X)");
assert(finalRow.row_identity_max <= cfg.rowTol, ...
    'm27_run_city_mrio_2020_deployment_impl:RowIdentityFailed', ...
    'Scenario %s failed the row identity tolerance.', string(name));
assert(finalRow.col_identity_max <= cfg.colTol, ...
    'm27_run_city_mrio_2020_deployment_impl:ColIdentityFailed', ...
    'Scenario %s failed the column identity tolerance.', string(name));
assert(finalRow.prov_Z_inf <= cfg.provTol && finalRow.prov_Y_inf <= cfg.provTol && ...
    finalRow.prov_X_inf <= cfg.provTol && finalRow.prov_VA_inf <= cfg.provTol && ...
    finalRow.prov_IM_inf <= cfg.provTol && finalRow.prov_EX_inf <= cfg.provTol, ...
    'm27_run_city_mrio_2020_deployment_impl:ProvConsistencyFailed', ...
    'Scenario %s failed provincial aggregation checks.', string(name));
write_stage_row_2020(finalRow, stageAuditPath, true);

validationTable = build_validation_table_2020(finalRow);
validationPath = fullfile(cfg.resultsDir, "validation_city_mrio_2020_" + name + ".csv");
writetable(validationTable, validationPath);

aggregationPath = fullfile(cfg.resultsDir, "aggregation_check_2020_" + name + ".csv");
aggregationCheck = m14_aggregate_city_to_province(cast_city_double_runner(finalCity), mapping, ...
    'TargetProv', prov2020, ...
    'Mode', "strict", ...
    'ReportFile', aggregationPath, ...
    'Validate', false);

matPath = fullfile(cfg.resultsDir, "city_mrio_2020_" + name + ".mat");
cityHat = finalCity; %#ok<NASGU>
save(matPath, 'cityHat', 'targets', 'zResult');

result = struct();
result.name = string(name);
result.targets = targets;
result.seed = seed;
result.zResult = zResult;
result.finalCity = finalCity;
result.stageAuditPath = string(stageAuditPath);
result.validationPath = string(validationPath);
result.aggregationPath = string(aggregationPath);
result.matPath = string(matPath);
result.aggregationCheck = aggregationCheck;
result.validationTable = validationTable;
end

function city = assemble_stage_city_2020(blocks, Y, VA, IM, EX, mapping, templateCity, cfg)
zStage = struct('blocks', {blocks}, 'Mapping', mapping);
yStage = struct('Y', Y);
stageTargets = struct('VA', VA, 'IM', IM, 'EX', EX, 'mapping', mapping);
city = m13_assemble_city_mrio_2020(zStage, yStage, stageTargets, ...
    'OutputClass', cfg.numericClass, ...
    'ResidualTol', max(cfg.rowTol, cfg.colTol), ...
    'AllowResidualError', true, ...
    'XMode', "column_closed");
city = attach_city_metadata_2020(city, templateCity);
end

function city = resolve_city2017_harm(cfg)
harmOut = m16_harmonize_city2017_to_prov2017(cfg.city2017Raw, cfg.prov2017, cfg.mapping, ...
    'OutputDir', fullfile(cfg.resultsDir, 'truth_cache_2017_source'));
city = harmOut.city2017_harm;
end

function prov = resolve_prov_2020(provInput)
parsed = m02_parse_prov_mrio_xlsx_generic(provInput, 'Validate', false);
prov = struct();
prov.Z = double(parsed.MRIO.Z);
prov.Y = double(parsed.MRIO.Y);
prov.VA = double(parsed.MRIO.VA);
prov.IM = double(parsed.MRIO.IM);
prov.EX = double(parsed.MRIO.EX);
prov.error = double(parsed.MRIO.error);
prov.X = double(parsed.MRIO.X);
prov.provinces = string(parsed.Meta.Province_Name);
prov.sectors = string(parsed.Meta.Sector_Name);
prov.fd_labels = string(parsed.Meta.F_Name);
end

function mapping = resolve_mapping_2020(mappingInput, cityTruth, prov)
mapping = m03_build_city_province_mapping(mappingInput, ...
    'NumCities', numel(cityTruth.cities), ...
    'NumSectors', numel(cityTruth.sectors), ...
    'NumFD', numel(cityTruth.fd_labels), ...
    'ProvinceNames', prov.provinces, ...
    'CityNames', cityTruth.cities, ...
    'CityNamesCN', safe_city_cn_runner(cityTruth));
end

function labels = safe_city_cn_runner(city)
if isfield(city, 'cities_cn')
    labels = city.cities_cn;
else
    labels = strings(numel(city.cities), 1);
end
end

function city = build_city_from_parts_2020(blocks, Y, X, VA, IM, EX, errorVec, mapping, templateCity)
Z = assemble_blocks_to_matrix_runner(blocks, mapping, 'double');
city = struct();
city.Z = Z;
city.Y = double(Y);
city.X = double(X(:));
city.VA = double(VA(:));
city.IM = double(IM(:));
city.EX = double(EX(:));
city.error = double(errorVec(:));
city = attach_city_metadata_2020(city, templateCity);
end

function city = attach_city_metadata_2020(city, templateCity)
if isfield(templateCity, 'cities'); city.cities = templateCity.cities; end
if isfield(templateCity, 'cities_cn'); city.cities_cn = templateCity.cities_cn; end
if isfield(templateCity, 'sectors'); city.sectors = templateCity.sectors; end
if isfield(templateCity, 'fd_labels'); city.fd_labels = templateCity.fd_labels; end
end

function Z = assemble_blocks_to_matrix_runner(blocks, mapping, outputClass)
NS = mapping.numCities * mapping.numSectors;
Z = zeros(NS, NS, outputClass);
for pIdx = 1:mapping.numProvinces
    rowIdx = city_sector_indices_runner(mapping.city_indices_by_province{pIdx}, mapping.numSectors);
    for qIdx = 1:mapping.numProvinces
        colIdx = city_sector_indices_runner(mapping.city_indices_by_province{qIdx}, mapping.numSectors);
        Z(rowIdx, colIdx) = double(blocks{pIdx, qIdx});
    end
end
end

function idx = city_sector_indices_runner(cityIndices, S)
idx = zeros(numel(cityIndices) * S, 1);
cursor = 1;
for i = 1:numel(cityIndices)
    rows = ((cityIndices(i)-1) * S + 1):(cityIndices(i) * S);
    idx(cursor:cursor+S-1) = rows;
    cursor = cursor + S;
end
end

function row = build_stage_row_from_targets(stageName, targets, prov, mapping, noteText)
row = table( ...
    string(stageName), ...
    "targets", ...
    double(targets.Diagnostics.prov_Z_inf), ...
    double(targets.Diagnostics.prov_Y_inf), ...
    double(targets.Diagnostics.prov_X_inf), ...
    double(targets.Diagnostics.prov_VA_inf), ...
    double(targets.Diagnostics.prov_IM_inf), ...
    double(targets.Diagnostics.prov_EX_inf), ...
    double(targets.Diagnostics.prov_error_inf), ...
    double(targets.Diagnostics.row_identity_max), ...
    double(targets.Diagnostics.col_identity_max), ...
    sum(double(targets.Z_row_target)), ...
    sum(double(targets.Y_city), 'all'), ...
    sum(double(targets.X)), ...
    sum(double(targets.VA)), ...
    sum(double(targets.IM)), ...
    sum(double(targets.EX)), ...
    sum(double(targets.error)), ...
    string(noteText), ...
    'VariableNames', stage_var_names_runner());
end

function row = build_stage_row_from_seed(stageName, seed, prov, mapping, noteText)
provZInf = compute_seed_gap_runner(seed.blocks, mapping, prov.Z);
row = table( ...
    string(stageName), ...
    "seed", ...
    provZInf, ...
    NaN, NaN, NaN, NaN, NaN, NaN, ...
    NaN, NaN, ...
    sum_blocks_total_runner(seed.blocks), ...
    NaN, NaN, NaN, NaN, NaN, NaN, ...
    string(noteText), ...
    'VariableNames', stage_var_names_runner());
end

function row = build_stage_row_from_city(stageName, city, prov, mapping, noteText)
city = cast_city_double_runner(city);
provAgg = m14_aggregate_city_to_province(city, mapping, 'TargetProv', prov, 'Mode', "strict", 'Validate', false);
row = table( ...
    string(stageName), ...
    "city", ...
    lookup_agg_metric_runner(provAgg.ReportTable, "Z_inf"), ...
    lookup_agg_metric_runner(provAgg.ReportTable, "Y_inf"), ...
    lookup_agg_metric_runner(provAgg.ReportTable, "X_inf"), ...
    lookup_agg_metric_runner(provAgg.ReportTable, "VA_inf"), ...
    lookup_agg_metric_runner(provAgg.ReportTable, "IM_inf"), ...
    lookup_agg_metric_runner(provAgg.ReportTable, "EX_inf"), ...
    lookup_agg_metric_runner(provAgg.ReportTable, "error_inf"), ...
    max(abs(double(city.X) - (sum(double(city.Z), 2) + sum(double(city.Y), 2) + double(city.EX) + double(city.error)))), ...
    max(abs(double(city.X) - (sum(double(city.Z), 1)' + double(city.VA) + double(city.IM)))), ...
    sum(double(city.Z), 'all'), ...
    sum(double(city.Y), 'all'), ...
    sum(double(city.X)), ...
    sum(double(city.VA)), ...
    sum(double(city.IM)), ...
    sum(double(city.EX)), ...
    sum(double(city.error)), ...
    string(noteText), ...
    'VariableNames', stage_var_names_runner());
end

function names = stage_var_names_runner()
names = {'stage','payload_kind','prov_Z_inf','prov_Y_inf','prov_X_inf','prov_VA_inf','prov_IM_inf','prov_EX_inf', ...
    'prov_error_inf','row_identity_max','col_identity_max','total_Z','total_Y','total_X','total_VA','total_IM','total_EX','total_error','note'};
end

function write_stage_row_2020(row, outputPath, appendMode)
if appendMode && exist(outputPath, 'file')
    existing = readtable(outputPath, 'TextType', 'string');
    writetable([existing; row], outputPath); %#ok<AGROW>
else
    writetable(row, outputPath);
end
end

function validationTable = build_validation_table_2020(stageRow)
metric = ["prov_Z_inf";"prov_Y_inf";"prov_X_inf";"prov_VA_inf";"prov_IM_inf";"prov_EX_inf";"prov_error_inf"; ...
    "row_identity_max";"col_identity_max";"total_Z";"total_Y";"total_X";"total_VA";"total_IM";"total_EX";"total_error"];
value = [stageRow.prov_Z_inf;stageRow.prov_Y_inf;stageRow.prov_X_inf;stageRow.prov_VA_inf;stageRow.prov_IM_inf;stageRow.prov_EX_inf;stageRow.prov_error_inf; ...
    stageRow.row_identity_max;stageRow.col_identity_max;stageRow.total_Z;stageRow.total_Y;stageRow.total_X;stageRow.total_VA;stageRow.total_IM;stageRow.total_EX;stageRow.total_error];
validationTable = table(metric, value);
end

function gap = compute_seed_gap_runner(blocks, mapping, provZ)
gap = 0;
for pIdx = 1:mapping.numProvinces
    npCity = numel(mapping.city_indices_by_province{pIdx});
    provRows = ((pIdx - 1) * mapping.numSectors + 1):(pIdx * mapping.numSectors);
    for qIdx = 1:mapping.numProvinces
        nqCity = numel(mapping.city_indices_by_province{qIdx});
        provCols = ((qIdx - 1) * mapping.numSectors + 1):(qIdx * mapping.numSectors);
        tmp = reshape(double(blocks{pIdx, qIdx}), [mapping.numSectors, npCity, mapping.numSectors, nqCity]);
        agg = squeeze(sum(sum(tmp, 2), 4));
        targetBlock = provZ(provRows, provCols);
        gap = max(gap, max(abs(agg(:) - targetBlock(:))));
    end
end
end

function totalZ = sum_blocks_total_runner(blocks)
totalZ = 0;
for i = 1:numel(blocks)
    totalZ = totalZ + sum(double(blocks{i}), 'all');
end
end

function value = lookup_agg_metric_runner(reportTable, metricName)
idx = find(string(reportTable.metric) == string(metricName), 1, 'first');
if isempty(idx)
    value = NaN;
else
    value = double(reportTable.value(idx));
end
end

function city = cast_city_double_runner(city)
fields = ["Z","Y","VA","IM","EX","X","error"];
for i = 1:numel(fields)
    city.(fields(i)) = double(city.(fields(i)));
end
end

function reset_file_runner(filePath)
if exist(filePath, 'file')
    delete(filePath);
end
end

function ensure_dir_runner(dirPath)
if ~exist(dirPath, 'dir')
    mkdir(dirPath);
end
end

function write_failure_summary(filePath, ME)
T = table(string(ME.identifier), string(ME.message), datetime("now"), ...
    'VariableNames', {'identifier','message','timestamp'});
writetable(T, filePath);
end
