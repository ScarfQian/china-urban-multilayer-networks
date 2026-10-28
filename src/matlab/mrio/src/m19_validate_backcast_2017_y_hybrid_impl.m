function out = m19_validate_backcast_2017_y_hybrid_impl(cfg)
% M19_VALIDATE_BACKCAST_2017_Y_HYBRID_IMPL
% Train the hybrid mixture on 2012 -> 2015 and test it on 2015 -> 2017.

cfg = normalize_cfg(cfg);
ensure_dir(cfg.resultsDir);

if cfg.skipTrain
    fitOut = struct();
    fitOut.hybridParams = resolve_hybrid_params(cfg.pretrainedHybridParams);
    fitOut.factorizedParams = resolve_factorized_params(cfg.pretrainedHybridParams, cfg.pretrainedFactorizedParams);
else
    fitOut = m17_fit_y_hybrid_mixture_2012_2015(struct( ...
        'city2012', cfg.city2012, ...
        'city2015', cfg.city2015, ...
        'mapping', cfg.mapping, ...
        'resultsDir', cfg.resultsDir, ...
        'betaGrid', cfg.betaGrid, ...
        'gammaGrid', cfg.gammaGrid, ...
        'lambdaGrid', cfg.lambdaGrid, ...
        'fd4_mode', cfg.fd4_mode, ...
        'fd5_mode', cfg.fd5_mode, ...
        'pretrainedFactorizedParams', cfg.pretrainedFactorizedParams));
end

truthCity = resolve_truth_city(cfg);
city2015 = resolve_city_input(cfg.city2015);
prov2017 = resolve_prov_input(cfg.prov2017);
mapping = resolve_mapping(cfg.mapping, truthCity, prov2017);

baseTargets = m10_build_city_targets_forecast_style_consistent_2017(city2015, prov2017, mapping, ...
    'ProxyTable', cfg.proxyTable, ...
    'Eta', cfg.eta, ...
    'NumericClass', cfg.numericClass, ...
    'Epsilon', cfg.epsilon, ...
    'Validate', true);

hybridYOut = m09_downscale_city_y_hybrid_consistent_2017(city2015, prov2017, mapping, ...
    fitOut.factorizedParams, fitOut.hybridParams, ...
    'TargetX', double(baseTargets.X), ...
    'TargetYColByFD', double(baseTargets.Y_col_by_fd), ...
    'WeightSpec', baseTargets.WeightSpec, ...
    'ProxyTable', cfg.proxyTable, ...
    'Eta', cfg.eta, ...
    'NumericClass', cfg.numericClass, ...
    'Epsilon', cfg.epsilon, ...
    'TopSupportCount', cfg.topSupportCount, ...
    'Validate', true);

targets = rebuild_targets_with_city_y(baseTargets, hybridYOut.Y, prov2017, mapping, cfg.epsilon);

stageAuditPath = fullfile(cfg.resultsDir, 'stage_audit_2017_y_hybrid.csv');
reset_file(stageAuditPath);
targetsAudit = m15_audit_pipeline_stage_2017("targets", targets, truthCity, mapping, ...
    'ProvTarget', prov2017, ...
    'OutputPath', stageAuditPath, ...
    'Append', false, ...
    'Note', "province-consistent targets with hybrid Y");
assert_targets_stage(targetsAudit, cfg.provTol);

seed = m11_build_seed_city_z_forecast_style_consistent_2017(city2015, prov2017, mapping, ...
    'NumericClass', cfg.numericClass, ...
    'Epsilon', cfg.epsilon, ...
    'Validate', true);
seedCity = build_stage_city_from_parts(seed.blocks, targets.Y_city, targets.VA, targets.IM, targets.EX, mapping, truthCity);
seedAudit = m15_audit_pipeline_stage_2017("seed", seedCity, truthCity, mapping, ...
    'ProvTarget', prov2017, ...
    'OutputPath', stageAuditPath, ...
    'Append', true, ...
    'Note', "province-consistent seed reused under hybrid Y");
assert_seed_stage(seedAudit, cfg.provTol);

zResult = m12_nested_ras_city_z(seed, targets.Z_row_target, targets.Z_col_target, ...
    'MaxIter', cfg.maxIter, ...
    'TolRow', cfg.tolRow, ...
    'TolCol', cfg.tolCol, ...
    'TolBlock', cfg.tolBlock);
afterZCity = build_stage_city_from_parts(zResult.blocks, targets.Y_city, targets.VA, targets.IM, targets.EX, mapping, truthCity);
m15_audit_pipeline_stage_2017("after_z_solver", afterZCity, truthCity, mapping, ...
    'ProvTarget', prov2017, ...
    'OutputPath', stageAuditPath, ...
    'Append', true, ...
    'Note', "Z solved under hybrid Y targets");

afterYCity = build_stage_city_from_parts(zResult.blocks, hybridYOut.Y, targets.VA, targets.IM, targets.EX, mapping, truthCity);
yAudit = m15_audit_pipeline_stage_2017("after_y_downscale", afterYCity, truthCity, mapping, ...
    'ProvTarget', prov2017, ...
    'OutputPath', stageAuditPath, ...
    'Append', true, ...
    'Note', "hybrid Y allocation");
assert_y_stage(yAudit, cfg.provTol);

assemblyTargets = struct('VA', targets.VA, 'IM', targets.IM, 'EX', targets.EX, 'mapping', mapping);
finalCity = m13_assemble_city_mrio_2020(zResult, hybridYOut, assemblyTargets, ...
    'OutputClass', cfg.numericClass, ...
    'AllowResidualError', true);
finalCity = attach_city_metadata(finalCity, truthCity);
m15_audit_pipeline_stage_2017("after_assembly", finalCity, truthCity, mapping, ...
    'ProvTarget', prov2017, ...
    'OutputPath', stageAuditPath, ...
    'Append', true, ...
    'Note', "final hybrid Y output");

validationTable = build_backcast_metrics(finalCity, truthCity, mapping);
validationPath = fullfile(cfg.resultsDir, 'validation_backcast_2017_y_hybrid.csv');
writetable(validationTable, validationPath);

aggregationPath = fullfile(cfg.resultsDir, 'aggregation_check_2017_y_hybrid.csv');
aggregationCheck = m14_aggregate_city_to_province(cast_city_to_double(finalCity), mapping, ...
    'TargetProv', prov2017, ...
    'Mode', "strict", ...
    'ReportFile', aggregationPath, ...
    'Validate', false);

topProblemTable = build_y_problem_block_table(finalCity.Y, truthCity.Y, mapping);
topProblemTable = sortrows(topProblemTable, {'block_share_jsd','block_WAPE','block_abs_error'}, {'descend','descend','descend'});
topProblemTable = topProblemTable(1:min(cfg.topProblemCount, height(topProblemTable)), :);
topProblemPath = fullfile(cfg.resultsDir, 'y_hybrid_top_problem_blocks.csv');
writetable(topProblemTable, topProblemPath);

summaryOut = m18_summarize_y_hybrid_results(struct( ...
    'resultsDir', cfg.resultsDir, ...
    'hybridValidationPath', validationPath, ...
    'factorizedValidationPath', cfg.factorizedValidationPath, ...
    'baselineValidationPath', cfg.baselineValidationPath, ...
    'truthYAbsSum', sum(abs(double(truthCity.Y(:)))), ...
    'numYElements', numel(truthCity.Y)));

out = struct();
out.fit = fitOut;
out.hybridParams = fitOut.hybridParams;
out.factorizedParams = fitOut.factorizedParams;
out.validation2017 = validationTable;
out.aggregationCheck = aggregationCheck;
out.summary = summaryOut;
out.outputFiles = struct( ...
    'validation2017', string(validationPath), ...
    'aggregation2017', string(aggregationPath), ...
    'stageAudit2017', string(stageAuditPath), ...
    'topProblemBlocks', string(topProblemPath), ...
    'comparison', string(summaryOut.outputFiles.byFDComparison));
end

function cfg = normalize_cfg(cfg)
required = ["city2012","city2015","prov2017","resultsDir"];
for i = 1:numel(required)
    if ~isfield(cfg, required(i))
        error('m19_validate_backcast_2017_y_hybrid_impl:MissingCfgField', ...
            'Missing required configuration field: %s', required(i));
    end
end
projectRoot = fileparts(fileparts(mfilename('fullpath')));
if ~isfield(cfg, 'mapping'); cfg.mapping = ""; end
if ~isfield(cfg, 'city2017Truth'); cfg.city2017Truth = []; end
if ~isfield(cfg, 'city2017Raw'); cfg.city2017Raw = []; end
if ~isfield(cfg, 'proxyTable'); cfg.proxyTable = []; end
if ~isfield(cfg, 'eta'); cfg.eta = [1 1 1]; end
if ~isfield(cfg, 'numericClass'); cfg.numericClass = "double"; end
if ~isfield(cfg, 'epsilon'); cfg.epsilon = 1e-12; end
if ~isfield(cfg, 'provTol'); cfg.provTol = 1e-6; end
if ~isfield(cfg, 'maxIter'); cfg.maxIter = 200; end
if ~isfield(cfg, 'tolRow'); cfg.tolRow = 1e-6; end
if ~isfield(cfg, 'tolCol'); cfg.tolCol = 1e-6; end
if ~isfield(cfg, 'tolBlock'); cfg.tolBlock = 1e-8; end
if ~isfield(cfg, 'betaGrid'); cfg.betaGrid = 0:0.5:2; end
if ~isfield(cfg, 'gammaGrid'); cfg.gammaGrid = 0:0.5:2; end
if ~isfield(cfg, 'lambdaGrid'); cfg.lambdaGrid = 0:0.1:1; end
if ~isfield(cfg, 'fd4_mode'); cfg.fd4_mode = "hybrid"; end
if ~isfield(cfg, 'fd5_mode'); cfg.fd5_mode = "baseline_only"; end
if ~isfield(cfg, 'topSupportCount'); cfg.topSupportCount = 3; end
if ~isfield(cfg, 'topProblemCount'); cfg.topProblemCount = 200; end
if ~isfield(cfg, 'pretrainedFactorizedParams')
    cfg.pretrainedFactorizedParams = fullfile(projectRoot, 'Results', '2017_y_factorized_0422', 'y_factorized_model_params.csv');
end
if ~isfield(cfg, 'pretrainedHybridParams')
    cfg.pretrainedHybridParams = fullfile(cfg.resultsDir, 'y_hybrid_best_params.csv');
end
if ~isfield(cfg, 'factorizedValidationPath')
    cfg.factorizedValidationPath = fullfile(projectRoot, 'Results', '2017_y_factorized_0422', 'validation_backcast_2017_y_factorized.csv');
end
if ~isfield(cfg, 'baselineValidationPath')
    cfg.baselineValidationPath = fullfile(projectRoot, 'Results', '2017_backcast_tiers_0421', 'forecast_style_consistent', 'validation_backcast_2017_forecast_style_consistent.csv');
end
if ~isfield(cfg, 'skipTrain'); cfg.skipTrain = false; end
end

function truthCity = resolve_truth_city(cfg)
if ~isempty(cfg.city2017Truth)
    truthCity = resolve_city_input(cfg.city2017Truth);
    return;
end
if isempty(cfg.city2017Raw) || isempty(cfg.mapping)
    error('m19_validate_backcast_2017_y_hybrid_impl:MissingTruthInput', ...
        'Provide cfg.city2017Truth or cfg.city2017Raw + cfg.mapping.');
end
harmOut = m16_harmonize_city2017_to_prov2017(cfg.city2017Raw, cfg.prov2017, cfg.mapping, ...
    'OutputDir', fullfile(cfg.resultsDir, 'truth_cache'));
truthCity = harmOut.city2017_harm;
end

function city = resolve_city_input(inputValue)
if isstruct(inputValue) && isfield(inputValue, 'Z') && isfield(inputValue, 'Y')
    city = inputValue;
    return;
end
city = m01_parse_city_mrio_mat(inputValue, 'Validate', false);
end

function prov = resolve_prov_input(provInput)
if isstruct(provInput) && isfield(provInput, 'Z') && isfield(provInput, 'Y')
    prov = provInput;
    return;
end
parsed = m02_parse_prov_mrio_xlsx_generic(provInput, 'Validate', false);
prov = struct();
prov.Z = parsed.MRIO.Z;
prov.Y = parsed.MRIO.Y;
prov.VA = parsed.MRIO.VA;
prov.IM = parsed.MRIO.IM;
prov.EX = parsed.MRIO.EX;
prov.error = parsed.MRIO.error;
prov.X = parsed.MRIO.X;
prov.provinces = string(parsed.Meta.Province_Name);
prov.sectors = string(parsed.Meta.Sector_Name);
prov.fd_labels = string(parsed.Meta.F_Name);
end

function mapping = resolve_mapping(mappingInput, truthCity, prov)
if isstruct(mappingInput) && isfield(mappingInput, 'A')
    mapping = mappingInput;
    return;
end
mapping = m03_build_city_province_mapping(mappingInput, ...
    'NumCities', numel(truthCity.cities), ...
    'NumSectors', numel(truthCity.sectors), ...
    'NumFD', numel(truthCity.fd_labels), ...
    'ProvinceNames', string(prov.provinces), ...
    'CityNames', truthCity.cities, ...
    'CityNamesCN', safe_city_cn_labels(truthCity));
end

function labels = safe_city_cn_labels(city)
if isfield(city, 'cities_cn')
    labels = string(city.cities_cn);
else
    labels = strings(numel(city.cities), 1);
end
end

function params = resolve_hybrid_params(pathValue)
tbl = readtable(string(pathValue), 'TextType', 'string');
params = struct();
params.lambda = double(tbl.lambda(:));
params.fd4_mode = string(tbl.fd4_mode(1));
params.fd5_mode = string(tbl.fd5_mode(1));
end

function params = resolve_factorized_params(primaryPath, fallbackPath)
sourcePath = string(primaryPath);
if ~exist(sourcePath, 'file')
    sourcePath = string(fallbackPath);
end
tbl = readtable(sourcePath, 'TextType', 'string');
params = struct();
params.alpha = ones(42, 1);
params.beta = double(tbl.beta(:));
params.gamma = double(tbl.gamma(:));
end

function targets = rebuild_targets_with_city_y(baseTargets, Ycity, provTarget, mapping, epsilon)
targets = baseTargets;
targets.Y_city = double(Ycity);
F = mapping.numFD;
NS = numel(baseTargets.X);
Nc = mapping.numCities;
targets.Y_row_by_fd = zeros(NS, F);
targets.Y_col_by_fd = zeros(Nc, F);
for f = 1:F
    cols = f:F:size(targets.Y_city, 2);
    targets.Y_row_by_fd(:, f) = sum(double(targets.Y_city(:, cols)), 2);
    targets.Y_col_by_fd(:, f) = sum(double(targets.Y_city(:, cols)), 1)';
end
zRowTarget = double(targets.X) - sum(double(targets.Y_row_by_fd), 2) - double(targets.EX);
zColTarget = double(targets.X) - double(targets.VA) - double(targets.IM);
if min(zRowTarget) < -1e-6 || min(zColTarget) < -1e-6
    error('m19_validate_backcast_2017_y_hybrid_impl:NegativeZTarget', ...
        'Hybrid Y produces materially negative Z row/col targets.');
end
targets.Z_row_target = max(zRowTarget, 0);
targets.Z_col_target = max(zColTarget, 0);
targets.prov_Z_row_target = double(mapping.A * double(targets.Z_row_target));
targets.prov_Z_col_target = double(mapping.A * double(targets.Z_col_target));
targets.Diagnostics.prov_X_inf = max(abs(mapping.A * double(targets.X) - double(provTarget.X)));
targets.Diagnostics.prov_VA_inf = max(abs(mapping.A * double(targets.VA) - double(provTarget.VA)));
targets.Diagnostics.prov_IM_inf = max(abs(mapping.A * double(targets.IM) - double(provTarget.IM)));
targets.Diagnostics.prov_EX_inf = max(abs(mapping.A * double(targets.EX) - double(provTarget.EX)));
targets.Diagnostics.prov_Y_inf = max(abs(mapping.A * double(targets.Y_city) * mapping.B' - double(provTarget.Y)), [], 'all');
targets.Diagnostics.prov_Z_inf = max([ ...
    max(abs(double(targets.prov_Z_row_target) - sum(double(provTarget.Z), 2))), ...
    max(abs(double(targets.prov_Z_col_target) - sum(double(provTarget.Z), 1)'))]);
targets.Diagnostics.rowGap = max(abs(double(targets.X) - ...
    (double(targets.Z_row_target) + sum(double(targets.Y_row_by_fd), 2) + double(targets.EX))));
targets.Diagnostics.colGap = max(abs(double(targets.X) - ...
    (double(targets.Z_col_target) + double(targets.VA) + double(targets.IM))));
targets.Diagnostics.hybridYProvInf = targets.Diagnostics.prov_Y_inf;
targets.Diagnostics.hybridEpsilon = epsilon;
end

function city = build_stage_city_from_parts(blocks, Y, VA, IM, EX, mapping, templateCity)
Z = assemble_blocks_to_matrix(blocks, mapping, 'double');
X = sum(Z, 2) + sum(double(Y), 2) + double(EX(:));
errorVec = X - (sum(Z, 1)' + double(VA(:)) + double(IM(:)));
city = struct('Z', Z, 'Y', double(Y), 'VA', double(VA(:)), 'IM', double(IM(:)), ...
    'EX', double(EX(:)), 'X', X, 'error', errorVec);
city = attach_city_metadata(city, templateCity);
end

function Z = assemble_blocks_to_matrix(blocks, mapping, outputClass)
NS = mapping.numCities * mapping.numSectors;
Z = zeros(NS, NS, outputClass);
for pIdx = 1:mapping.numProvinces
    rowIdx = city_sector_indices(mapping.city_indices_by_province{pIdx}, mapping.numSectors);
    for qIdx = 1:mapping.numProvinces
        colIdx = city_sector_indices(mapping.city_indices_by_province{qIdx}, mapping.numSectors);
        Z(rowIdx, colIdx) = double(blocks{pIdx, qIdx});
    end
end
end

function idx = city_sector_indices(cityIndices, S)
idx = zeros(numel(cityIndices) * S, 1);
cursor = 1;
for i = 1:numel(cityIndices)
    rows = ((cityIndices(i)-1) * S + 1):(cityIndices(i) * S);
    idx(cursor:cursor+S-1) = rows;
    cursor = cursor + S;
end
end

function city = attach_city_metadata(city, template)
if isfield(template, 'cities'); city.cities = template.cities; end
if isfield(template, 'cities_cn'); city.cities_cn = template.cities_cn; end
if isfield(template, 'sectors'); city.sectors = template.sectors; end
if isfield(template, 'fd_labels'); city.fd_labels = template.fd_labels; end
end

function assert_targets_stage(auditRow, tol)
if auditRow.prov_X_inf > tol || auditRow.prov_VA_inf > tol || auditRow.prov_IM_inf > tol || ...
        auditRow.prov_EX_inf > tol || auditRow.prov_Y_inf > tol
    error('m19_validate_backcast_2017_y_hybrid_impl:TargetsStageFailed', ...
        'The targets stage is not province-consistent enough. Abort before solver.');
end
end

function assert_seed_stage(auditRow, tol)
if auditRow.prov_Z_inf > tol
    error('m19_validate_backcast_2017_y_hybrid_impl:SeedStageFailed', ...
        'The seed stage is not province-consistent enough. Abort before solver.');
end
end

function assert_y_stage(auditRow, tol)
if auditRow.prov_Y_inf > tol
    error('m19_validate_backcast_2017_y_hybrid_impl:YStageFailed', ...
        'The Y stage is not province-consistent enough. Abort before assembly.');
end
end

function metrics = build_backcast_metrics(hat, truth, mapping)
Ymetrics = evaluate_y_metrics(hat.Y, truth.Y, truth, mapping);
metric = [ ...
    "Y_WAPE"; "Y_MAE"; "Y_RMSE"; "block_share_jsd"; "top_cell_hit_rate"; ...
    "fd1_WAPE"; "fd2_WAPE"; "fd3_WAPE"; "fd4_WAPE"; "fd5_WAPE"; ...
    "Z_MAE"; "X_MAE"; "VA_MAE"; "IM_MAE"; "EX_MAE"];
value = [ ...
    Ymetrics.Y_WAPE; Ymetrics.Y_MAE; Ymetrics.Y_RMSE; Ymetrics.block_share_jsd; Ymetrics.top_cell_hit_rate; ...
    Ymetrics.fd1_WAPE; Ymetrics.fd2_WAPE; Ymetrics.fd3_WAPE; Ymetrics.fd4_WAPE; Ymetrics.fd5_WAPE; ...
    mean(abs(double(hat.Z(:)) - double(truth.Z(:)))); ...
    mean(abs(double(hat.X(:)) - double(truth.X(:)))); ...
    mean(abs(double(hat.VA(:)) - double(truth.VA(:)))); ...
    mean(abs(double(hat.IM(:)) - double(truth.IM(:)))); ...
    mean(abs(double(hat.EX(:)) - double(truth.EX(:))))];
metrics = table(metric, value);
end

function M = evaluate_y_metrics(Yhat, Ytruth, truthCity, mapping)
pred = double(Yhat);
truth = double(Ytruth);
absErr = abs(pred - truth);
truthAbs = abs(truth);
M = struct();
M.Y_WAPE = sum(absErr(:)) / max(sum(truthAbs(:)), eps);
M.Y_MAE = mean(absErr(:));
M.Y_RMSE = sqrt(mean((pred(:) - truth(:)).^2));
for f = 1:numel(truthCity.fd_labels)
    cols = f:numel(truthCity.fd_labels):size(truth, 2);
    M.("fd" + string(f) + "_WAPE") = sum(absErr(:, cols), 'all') / max(sum(truthAbs(:, cols), 'all'), eps);
end
shareMetrics = evaluate_block_share_metrics(pred, truth, mapping);
M.block_share_jsd = shareMetrics.block_share_jsd;
M.top_cell_hit_rate = shareMetrics.top_cell_hit_rate;
end

function out = evaluate_block_share_metrics(pred, truth, map)
jsd = zeros(map.numProvinces^2 * map.numSectors * map.numFD, 1);
hit = zeros(size(jsd));
cursor = 1;
for pIdx = 1:map.numProvinces
    rowCities = map.city_indices_by_province{pIdx};
    rowIdx = city_sector_indices(rowCities, map.numSectors);
    npCity = numel(rowCities);
    for qIdx = 1:map.numProvinces
        colCities = map.city_indices_by_province{qIdx};
        for s = 1:map.numSectors
            rowLocal = s:map.numSectors:(npCity * map.numSectors);
            for f = 1:map.numFD
                colIdx = fd_city_indices(colCities, f, map.numFD);
                m = m04_compute_block_share_metrics(reshape(pred(rowIdx(rowLocal), colIdx), [], 1), ...
                    reshape(truth(rowIdx(rowLocal), colIdx), [], 1));
                jsd(cursor) = m.js_divergence;
                hit(cursor) = m.top1_hit;
                cursor = cursor + 1;
            end
        end
    end
end
out = struct('block_share_jsd', mean(jsd(1:cursor-1)), 'top_cell_hit_rate', mean(hit(1:cursor-1)));
end

function T = build_y_problem_block_table(Yhat, Ytruth, map)
rows = {};
pred = double(Yhat);
truth = double(Ytruth);
for pIdx = 1:map.numProvinces
    rowCities = map.city_indices_by_province{pIdx};
    rowIdx = city_sector_indices(rowCities, map.numSectors);
    npCity = numel(rowCities);
    for qIdx = 1:map.numProvinces
        colCities = map.city_indices_by_province{qIdx};
        for s = 1:map.numSectors
            rowLocal = s:map.numSectors:(npCity * map.numSectors);
            for f = 1:map.numFD
                colIdx = fd_city_indices(colCities, f, map.numFD);
                predBlock = reshape(pred(rowIdx(rowLocal), colIdx), [], 1);
                truthBlock = reshape(truth(rowIdx(rowLocal), colIdx), [], 1);
                M = m04_compute_block_share_metrics(predBlock, truthBlock);
                rows(end+1, :) = {pIdx, qIdx, s, f, ... %#ok<AGROW>
                    sum(predBlock), sum(truthBlock), sum(abs(predBlock - truthBlock)), ...
                    sum(abs(predBlock - truthBlock)) / max(sum(abs(truthBlock)), eps), ...
                    M.js_divergence, M.hellinger_distance, M.top1_hit, M.top3_overlap};
            end
        end
    end
end
T = cell2table(rows, 'VariableNames', {'origin_province_id','destination_province_id','origin_sector_id','fd_id', ...
    'block_total_hat','block_total_truth','block_abs_error','block_WAPE','block_share_jsd', ...
    'block_share_hellinger','top1_hit','top3_overlap'});
end

function city = cast_city_to_double(city)
fields = ["Z","Y","VA","IM","EX","X","error"];
for i = 1:numel(fields)
    if isfield(city, fields(i))
        city.(fields(i)) = double(city.(fields(i)));
    end
end
end

function idx = fd_city_indices(cityIndices, fdIndex, F)
idx = zeros(numel(cityIndices), 1);
for i = 1:numel(cityIndices)
    idx(i) = (cityIndices(i)-1) * F + fdIndex;
end
end

function reset_file(filePath)
if exist(filePath, 'file')
    delete(filePath);
end
end

function ensure_dir(dirPath)
if ~exist(dirPath, 'dir')
    mkdir(dirPath);
end
end
