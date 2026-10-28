function out = m17_fit_y_hybrid_mixture_2012_2015(cfg)
% M17_FIT_Y_HYBRID_MIXTURE_2012_2015
% Train FD-specific lambda values on 2012 -> 2015 while reusing the current factorized model.

cfg = normalize_cfg(cfg);
ensure_dir(cfg.resultsDir);

city2012 = resolve_city_input(cfg.city2012);
city2015 = resolve_city_input(cfg.city2015);
mapping = resolve_mapping(cfg.mapping, city2015);
provTrain = m14_aggregate_city_to_province(cast_city(city2015), mapping, 'Validate', false).aggregated;

if isempty(cfg.pretrainedFactorizedParams)
    factorizedFit = fit_y_share_model_2012_2015(struct( ...
        'city2012', cfg.city2012, ...
        'city2015', cfg.city2015, ...
        'mapping', cfg.mapping, ...
        'resultsDir', cfg.resultsDir, ...
        'betaGrid', cfg.betaGrid, ...
        'gammaGrid', cfg.gammaGrid));
    factorizedParams = factorizedFit.params;
else
    factorizedParams = resolve_factorized_params(cfg.pretrainedFactorizedParams);
    factorizedFit = struct('params', factorizedParams);
end

targetX = double(city2015.X);
targetYCol = build_truth_y_col(city2015);
baselineY = m08_downscale_city_y_forecast_style_consistent_2017(city2012, provTrain, mapping, ...
    'NumericClass', 'double', ...
    'Validate', true);
factorizedY = m07_downscale_city_y_factorized_consistent_2017(city2012, provTrain, mapping, factorizedParams, ...
    'TargetX', targetX, ...
    'TargetYColByFD', targetYCol, ...
    'NumericClass', 'double', ...
    'Validate', true);

lambdaGrid = cfg.lambdaGrid(:)';
F = numel(city2015.fd_labels);
gridRows = [];
bestLambda = ones(F, 1);
trainMetricByFd = zeros(F, 1);
gridPath = fullfile(cfg.resultsDir, 'y_hybrid_lambda_grid_2012_2015.csv');
paramsPath = fullfile(cfg.resultsDir, 'y_hybrid_best_params.csv');
validationPath = fullfile(cfg.resultsDir, 'validation_backcast_2015_y_hybrid.csv');

for f = 1:F
    fprintf('Hybrid fit: FD %d/%d\n', f, F);
    if (f == 5 && strcmpi(cfg.fd5_mode, "baseline_only")) || ...
            (f == 4 && strcmpi(cfg.fd4_mode, "baseline_only"))
        bestLambda(f) = 1;
        trainMetricByFd(f) = NaN;
        gridRows = [gridRows; f, 1, NaN, NaN, NaN]; %#ok<AGROW>
        write_progress_tables(gridRows, bestLambda, factorizedParams, trainMetricByFd, cfg.fd4_mode, cfg.fd5_mode, gridPath, paramsPath);
        continue;
    end

    bestScore = inf;
    for lambda = lambdaGrid
        hybridParams = struct('lambda', fill_lambda(bestLambda, f, lambda, F), 'fd4_mode', cfg.fd4_mode, 'fd5_mode', cfg.fd5_mode);
        Yfd = build_single_fd_hybrid_matrix(double(baselineY.Y), double(factorizedY.Y), provTrain, mapping, ...
            hybridParams, f, cfg.epsilon, cfg.topSupportCount);
        M = evaluate_single_fd_metrics(Yfd, city2015.Y, mapping, f);
        gridRows = [gridRows; f, lambda, M.fd_WAPE, M.block_share_jsd, M.top_cell_hit_rate]; %#ok<AGROW>
        score = M.fd_WAPE + 1e-3 * M.block_share_jsd;
        if score < bestScore
            bestScore = score;
            bestLambda(f) = lambda;
            trainMetricByFd(f) = M.fd_WAPE;
        end
    end
    write_progress_tables(gridRows, bestLambda, factorizedParams, trainMetricByFd, cfg.fd4_mode, cfg.fd5_mode, gridPath, paramsPath);
end

hybridParams = struct('lambda', bestLambda, 'fd4_mode', cfg.fd4_mode, 'fd5_mode', cfg.fd5_mode);
bestHybrid = m06_build_city_y_hybrid_shares(baselineY.Y, factorizedY.Y, provTrain, mapping, hybridParams, 'Validate', true);
bestMetrics = evaluate_y_metrics(double(bestHybrid.Y), city2015.Y, city2015, mapping);

gridTable = array2table(gridRows, ...
    'VariableNames', {'fd_id','lambda','fd_WAPE','block_share_jsd','top_cell_hit_rate'});
paramsTable = table((1:F)', bestLambda(:), factorizedParams.beta(:), factorizedParams.gamma(:), ...
    repmat(string(cfg.fd4_mode), F, 1), repmat(string(cfg.fd5_mode), F, 1), trainMetricByFd(:), ...
    'VariableNames', {'fd_id','lambda','beta','gamma','fd4_mode','fd5_mode','train_fd_WAPE'});

writetable(gridTable, gridPath);
writetable(paramsTable, paramsPath);
writetable(struct_to_metric_table(bestMetrics), validationPath);

out = struct();
out.hybridParams = hybridParams;
out.factorizedParams = factorizedParams;
out.metrics = bestMetrics;
out.outputFiles = struct('grid', string(gridPath), 'params', string(paramsPath), 'validation2015', string(validationPath));
end

function cfg = normalize_cfg(cfg)
required = ["city2012","city2015","resultsDir"];
for i = 1:numel(required)
    if ~isfield(cfg, required(i))
        error('m17_fit_y_hybrid_mixture_2012_2015:MissingCfgField', ...
            'Missing required configuration field: %s', required(i));
    end
end
if ~isfield(cfg, 'mapping'); cfg.mapping = ""; end
if ~isfield(cfg, 'betaGrid'); cfg.betaGrid = 0:0.5:2; end
if ~isfield(cfg, 'gammaGrid'); cfg.gammaGrid = 0:0.5:2; end
if ~isfield(cfg, 'lambdaGrid'); cfg.lambdaGrid = 0:0.1:1; end
if ~isfield(cfg, 'fd4_mode'); cfg.fd4_mode = "hybrid"; end
if ~isfield(cfg, 'fd5_mode'); cfg.fd5_mode = "baseline_only"; end
if ~isfield(cfg, 'pretrainedFactorizedParams'); cfg.pretrainedFactorizedParams = []; end
if ~isfield(cfg, 'epsilon'); cfg.epsilon = 1e-12; end
if ~isfield(cfg, 'topSupportCount'); cfg.topSupportCount = 3; end
end

function city = resolve_city_input(inputValue)
if isstruct(inputValue) && isfield(inputValue, 'Z') && isfield(inputValue, 'Y')
    city = inputValue;
else
    city = m01_parse_city_mrio_mat(inputValue, 'Validate', false);
end
end

function mapping = resolve_mapping(mappingInput, city)
if isstruct(mappingInput) && isfield(mappingInput, 'A')
    mapping = mappingInput;
else
    mapping = m03_build_city_province_mapping(mappingInput, ...
        'NumCities', numel(city.cities), ...
        'NumSectors', numel(city.sectors), ...
        'NumFD', numel(city.fd_labels), ...
        'CityNames', city.cities, ...
        'CityNamesCN', safe_city_cn(city));
end
end

function labels = safe_city_cn(city)
if isfield(city, 'cities_cn')
    labels = city.cities_cn;
else
    labels = strings(numel(city.cities), 1);
end
end

function city = cast_city(city)
fields = ["Z","Y","VA","IM","EX","X","error"];
for i = 1:numel(fields)
    city.(fields(i)) = double(city.(fields(i)));
end
end

function params = resolve_factorized_params(inputValue)
if isstruct(inputValue)
    params = inputValue;
    return;
end
tbl = readtable(string(inputValue), 'TextType', 'string');
params = struct();
params.alpha = ones(42, 1);
params.beta = double(tbl.beta(:));
params.gamma = double(tbl.gamma(:));
end

function targetYCol = build_truth_y_col(city)
F = numel(city.fd_labels);
Nc = size(city.Y, 2) / F;
targetYCol = zeros(Nc, F);
for f = 1:F
    targetYCol(:, f) = sum(double(city.Y(:, f:F:end)), 1)';
end
end

function lambdaVec = fill_lambda(currentLambda, fdIndex, lambdaValue, F)
lambdaVec = currentLambda;
if numel(lambdaVec) ~= F
    lambdaVec = ones(F, 1);
end
lambdaVec(fdIndex) = lambdaValue;
end

function Yfd = build_single_fd_hybrid_matrix(baselineY, factorizedY, provTarget, map, hybridParams, fdIndex, epsilon, topSupportCount)
NS = size(baselineY, 1);
Nc = map.numCities;
S = map.numSectors;
Yfd = zeros(NS, Nc);
params = normalize_hybrid_params_local(hybridParams, map.numFD);

for pIdx = 1:map.numProvinces
    rowCities = map.city_indices_by_province{pIdx};
    rowIdx = city_sector_indices(rowCities, S);
    npCity = numel(rowCities);
    provRows = province_sector_indices(pIdx, S);
    for qIdx = 1:map.numProvinces
        colCities = map.city_indices_by_province{qIdx};
        colIdx = colCities(:);
        baseBlock = baselineY(rowIdx, fd_city_indices(colCities, fdIndex, map.numFD));
        factBlock = factorizedY(rowIdx, fd_city_indices(colCities, fdIndex, map.numFD));
        block = zeros(size(baseBlock));
        provCol = (qIdx - 1) * map.numFD + fdIndex;
        for s = 1:S
            rowLocal = s:S:(npCity * S);
            shareBase = normalize_share_local(baseBlock(rowLocal, :), epsilon);
            shareFact = normalize_share_local(factBlock(rowLocal, :), epsilon);
            shareHybrid = mix_single_fd_block(shareBase, shareFact, params, fdIndex, topSupportCount);
            targetValue = double(provTarget.Y(provRows(s), provCol));
            block(rowLocal, :) = shareHybrid .* targetValue;
        end
        Yfd(rowIdx, colIdx) = block;
    end
end
end

function params = normalize_hybrid_params_local(params, F)
if ~isfield(params, 'lambda') || isempty(params.lambda)
    params.lambda = 0.5 * ones(F, 1);
else
    params.lambda = double(params.lambda(:));
end
if ~isfield(params, 'fd4_mode') || strlength(string(params.fd4_mode)) == 0
    params.fd4_mode = "hybrid";
else
    params.fd4_mode = string(params.fd4_mode);
end
if ~isfield(params, 'fd5_mode') || strlength(string(params.fd5_mode)) == 0
    params.fd5_mode = "baseline_only";
else
    params.fd5_mode = string(params.fd5_mode);
end
end

function share = mix_single_fd_block(shareBase, shareFact, params, fdIndex, topSupportCount)
if fdIndex == 4 && strcmpi(string(params.fd4_mode), "baseline_only")
    share = shareBase;
    return;
end
if fdIndex == 5
    switch lower(char(params.fd5_mode))
        case 'baseline_only'
            share = shareBase;
            return;
        case 'top_support_preserve'
            share = apply_top_support_preserve_local(shareBase, shareFact, params.lambda(fdIndex), topSupportCount);
            return;
    end
end
share = params.lambda(fdIndex) .* shareBase + (1 - params.lambda(fdIndex)) .* shareFact;
share = share ./ sum(share, 'all');
end

function share = apply_top_support_preserve_local(shareBase, shareFact, lambda, topSupportCount)
destMass = sum(shareBase, 1);
[~, order] = sort(destMass, 'descend');
keep = false(size(destMass));
keep(order(1:min(topSupportCount, numel(order)))) = true;
mask = repmat(keep, size(shareBase, 1), 1);
mixed = lambda .* shareBase + (1 - lambda) .* shareFact;
mixed(~mask) = 0;
if sum(mixed, 'all') <= 0
    share = shareBase;
else
    share = mixed ./ sum(mixed, 'all');
end
end

function share = normalize_share_local(block, epsilon)
block = max(double(block), 0) + epsilon;
share = block ./ sum(block, 'all');
end

function M = evaluate_single_fd_metrics(Yhybrid, Ytruth, mapping, fdIndex)
cols = fdIndex:mapping.numFD:size(Ytruth, 2);
truth = double(Ytruth(:, cols));
if size(Yhybrid, 2) == size(truth, 2)
    pred = double(Yhybrid);
else
    pred = double(Yhybrid(:, cols));
end
absErr = abs(pred - truth);
truthAbs = abs(truth);
M = struct();
M.fd_WAPE = sum(absErr(:)) / max(sum(truthAbs(:)), eps);
shareMetrics = evaluate_block_share_metrics_single_fd(pred, truth, mapping);
M.block_share_jsd = shareMetrics.block_share_jsd;
M.top_cell_hit_rate = shareMetrics.top_cell_hit_rate;
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
    cols = f:numel(truthCity.fd_labels):size(truth,2);
    M.("fd" + string(f) + "_WAPE") = sum(absErr(:, cols), 'all') / max(sum(truthAbs(:, cols), 'all'), eps);
end
shareMetrics = evaluate_block_share_metrics_all_fd(pred, truth, mapping);
M.block_share_jsd = shareMetrics.block_share_jsd;
M.top_cell_hit_rate = shareMetrics.top_cell_hit_rate;
M.prov_Y_inf = max(abs(mapping.A * pred * mapping.B' - mapping.A * truth * mapping.B'), [], 'all');
end

function out = evaluate_block_share_metrics_single_fd(pred, truth, map)
jsd = zeros(map.numProvinces^2 * map.numSectors, 1);
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
            m = m04_compute_block_share_metrics(reshape(pred(rowIdx(rowLocal), colCities), [], 1), ...
                reshape(truth(rowIdx(rowLocal), colCities), [], 1));
            jsd(cursor) = m.js_divergence;
            hit(cursor) = m.top1_hit;
            cursor = cursor + 1;
        end
    end
end
out = struct('block_share_jsd', mean(jsd(1:cursor-1)), 'top_cell_hit_rate', mean(hit(1:cursor-1)));
end

function out = evaluate_block_share_metrics_all_fd(pred, truth, map)
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

function idx = city_sector_indices(cityIndices, S)
idx = zeros(numel(cityIndices) * S, 1);
cursor = 1;
for i = 1:numel(cityIndices)
    rows = ((cityIndices(i)-1) * S + 1):(cityIndices(i) * S);
    idx(cursor:cursor+S-1) = rows;
    cursor = cursor + S;
end
end

function idx = province_sector_indices(provinceIdx, S)
idx = ((provinceIdx - 1) * S + 1):(provinceIdx * S);
idx = idx(:);
end

function idx = fd_city_indices(cityIndices, fdIndex, F)
idx = zeros(numel(cityIndices), 1);
for i = 1:numel(cityIndices)
    idx(i) = (cityIndices(i)-1) * F + fdIndex;
end
end

function T = struct_to_metric_table(S)
names = string(fieldnames(S));
values = zeros(numel(names), 1);
for i = 1:numel(names)
    values(i) = double(S.(names(i)));
end
T = table(names, values, 'VariableNames', {'metric','value'});
end

function write_progress_tables(gridRows, bestLambda, factorizedParams, trainMetricByFd, fd4Mode, fd5Mode, gridPath, paramsPath)
if isempty(gridRows)
    return;
end
F = numel(bestLambda);
gridTable = array2table(gridRows, ...
    'VariableNames', {'fd_id','lambda','fd_WAPE','block_share_jsd','top_cell_hit_rate'});
paramsTable = table((1:F)', bestLambda(:), factorizedParams.beta(:), factorizedParams.gamma(:), ...
    repmat(string(fd4Mode), F, 1), repmat(string(fd5Mode), F, 1), trainMetricByFd(:), ...
    'VariableNames', {'fd_id','lambda','beta','gamma','fd4_mode','fd5_mode','train_fd_WAPE'});
writetable(gridTable, gridPath);
writetable(paramsTable, paramsPath);
end

function ensure_dir(dirPath)
if ~exist(dirPath, 'dir')
    mkdir(dirPath);
end
end
