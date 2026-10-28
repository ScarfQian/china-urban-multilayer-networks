function out = m10_compute_cross_layer_metrics(layerBundle, singleOut, alignment, yearValue, cfg) %#ok<INUSD>
% M10_COMPUTE_CROSS_LAYER_METRICS
% Quantify edge-level similarity and node-level multilayer structure with
%   scale-robust overlap and participation definitions.

layerNames = ["investment","economic","carbon"];
layerMatrices = struct( ...
    'investment', double(layerBundle.investment.W), ...
    'economic', double(layerBundle.economic.W), ...
    'carbon', double(layerBundle.carbon.W));
layerTotals = [sum(layerMatrices.investment, 'all'), sum(layerMatrices.economic, 'all'), sum(layerMatrices.carbon, 'all')];
layerMatricesNorm = struct( ...
    'investment', normalize_matrix_local(layerMatrices.investment), ...
    'economic', normalize_matrix_local(layerMatrices.economic), ...
    'carbon', normalize_matrix_local(layerMatrices.carbon));

pairList = { ...
    ["investment","economic"], ...
    ["investment","carbon"], ...
    ["economic","carbon"]};
mask = ~eye(alignment.numCities);
similarityRows = cell(0, 5);

for i = 1:numel(pairList)
    pair = pairList{i};
    xRaw = layerMatrices.(pair(1))(mask);
    yRaw = layerMatrices.(pair(2))(mask);
    xNorm = layerMatricesNorm.(pair(1))(mask);
    yNorm = layerMatricesNorm.(pair(2))(mask);

    similarityRows(end + 1, :) = row_local(yearValue, pair(1), pair(2), "edge_weight_pearson", pearson_local(xRaw, yRaw)); %#ok<AGROW>
    similarityRows(end + 1, :) = row_local(yearValue, pair(1), pair(2), "edge_weight_spearman", spearman_local(xRaw, yRaw)); %#ok<AGROW>
    similarityRows(end + 1, :) = row_local(yearValue, pair(1), pair(2), "binary_overlap_raw", binary_overlap_local(xRaw, yRaw)); %#ok<AGROW>
    similarityRows(end + 1, :) = row_local(yearValue, pair(1), pair(2), "weighted_overlap_layer_normalized", weighted_overlap_local(xNorm, yNorm)); %#ok<AGROW>
    similarityRows(end + 1, :) = row_local(yearValue, pair(1), pair(2), "rank_overlap_spearman", rank_overlap_local(xNorm, yNorm)); %#ok<AGROW>
end

nodeMetrics = singleOut.nodeMetricsTable;
cityCode = double(alignment.cityTable.city_code);
cityName = string(alignment.cityTable.city_cn);
totalStrength = zeros(alignment.numCities, numel(layerNames));
pagerankScore = zeros(alignment.numCities, numel(layerNames));
outStrength = zeros(alignment.numCities, numel(layerNames));
for i = 1:numel(layerNames)
    hit = nodeMetrics.layer == layerNames(i);
    T = sortrows(nodeMetrics(hit, :), 'city_code');
    totalStrength(:, i) = double(T.total_strength);
    pagerankScore(:, i) = double(T.pagerank);
    outStrength(:, i) = double(T.out_strength);
end

for i = 1:numel(pairList)
    pair = pairList{i};
    idxA = find(layerNames == pair(1));
    idxB = find(layerNames == pair(2));
    similarityRows(end + 1, :) = row_local(yearValue, pair(1), pair(2), "node_total_strength_rank_spearman", ...
        spearman_local(totalStrength(:, idxA), totalStrength(:, idxB))); %#ok<AGROW>
    similarityRows(end + 1, :) = row_local(yearValue, pair(1), pair(2), "node_pagerank_rank_spearman", ...
        spearman_local(pagerankScore(:, idxA), pagerankScore(:, idxB))); %#ok<AGROW>
end

zStrength = zscore_matrix_local(totalStrength);
meanZ = mean(zStrength, 2);
roleMismatchIndex = sqrt(mean((zStrength - meanZ) .^ 2, 2));
participationRaw = participation_coefficient_local(totalStrength);

normalizedStrength = totalStrength ./ max(layerTotals, eps);
participationNormalized = participation_coefficient_local(normalizedStrength);

multilayerNodeMetrics = table( ...
    repmat(yearValue, alignment.numCities, 1), ...
    cityCode, ...
    cityName, ...
    totalStrength(:, 1), totalStrength(:, 2), totalStrength(:, 3), ...
    normalizedStrength(:, 1), normalizedStrength(:, 2), normalizedStrength(:, 3), ...
    outStrength(:, 1), outStrength(:, 2), outStrength(:, 3), ...
    pagerankScore(:, 1), pagerankScore(:, 2), pagerankScore(:, 3), ...
    roleMismatchIndex, participationRaw, participationNormalized, participationNormalized, ...
    'VariableNames', {'year','city_code','city_name', ...
    'investment_total_strength','economic_total_strength','carbon_total_strength', ...
    'investment_strength_layer_normalized','economic_strength_layer_normalized','carbon_strength_layer_normalized', ...
    'investment_out_strength','economic_out_strength','carbon_out_strength', ...
    'investment_pagerank','economic_pagerank','carbon_pagerank', ...
    'role_mismatch_index','participation_raw_deprecated','participation_normalized','participation_coefficient'});

similarityTable = cell2table(similarityRows, 'VariableNames', {'year','layer_a','layer_b','metric','value'});

writetable(similarityTable, fullfile(cfg.resultsDir, "cross_layer_similarity_" + string(yearValue) + ".csv"));
writetable(multilayerNodeMetrics, fullfile(cfg.resultsDir, "multilayer_node_metrics_" + string(yearValue) + ".csv"));

out = struct();
out.year = yearValue;
out.similarityTable = similarityTable;
out.multilayerNodeMetrics = multilayerNodeMetrics;
end

function row = row_local(yearValue, layerA, layerB, metricName, metricValue)
row = {yearValue, char(layerA), char(layerB), char(metricName), double(metricValue)};
end

function Wnorm = normalize_matrix_local(W)
totalWeight = sum(W, 'all');
if totalWeight <= 0
    Wnorm = zeros(size(W));
else
    Wnorm = W ./ totalWeight;
end
end

function val = binary_overlap_local(x, y)
maskX = x > 0;
maskY = y > 0;
val = sum(maskX & maskY) / max(sum(maskX | maskY), 1);
end

function val = weighted_overlap_local(x, y)
val = sum(min(x, y)) / max(sum(max(x, y)), eps);
end

function val = rank_overlap_local(x, y)
mask = (x > 0) | (y > 0);
if nnz(mask) <= 1
    val = NaN;
    return;
end
val = spearman_local(x(mask), y(mask));
end

function Z = zscore_matrix_local(X)
mu = mean(X, 1);
sigma = std(X, 0, 1);
sigma(sigma == 0) = 1;
Z = (X - mu) ./ sigma;
end

function coeff = participation_coefficient_local(strengthMatrix)
numCities = size(strengthMatrix, 1);
numLayers = size(strengthMatrix, 2);
strengthAcrossLayers = sum(strengthMatrix, 2);
coeff = zeros(numCities, 1);
for iCity = 1:numCities
    if strengthAcrossLayers(iCity) <= 0
        coeff(iCity) = 0;
    else
        share = strengthMatrix(iCity, :) ./ strengthAcrossLayers(iCity);
        coeff(iCity) = (numLayers / max(numLayers - 1, 1)) * (1 - sum(share .^ 2));
    end
end
end

function r = spearman_local(x, y)
r = pearson_local(rank_average_local(x), rank_average_local(y));
end

function r = pearson_local(x, y)
x = double(x(:));
y = double(y(:));
mask = isfinite(x) & isfinite(y);
x = x(mask);
y = y(mask);
if isempty(x) || std(x) == 0 || std(y) == 0
    r = NaN;
    return;
end
r = sum((x - mean(x)) .* (y - mean(y))) / sqrt(sum((x - mean(x)).^2) * sum((y - mean(y)).^2));
end

function r = rank_average_local(x)
x = double(x(:));
[sortedX, order] = sort(x, 'ascend');
r = zeros(size(x));
i = 1;
while i <= numel(sortedX)
    j = i;
    while j < numel(sortedX) && sortedX(j + 1) == sortedX(i)
        j = j + 1;
    end
    r(order(i:j)) = (i + j) / 2;
    i = j + 1;
end
end
