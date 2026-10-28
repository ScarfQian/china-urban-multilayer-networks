function out = m28_compute_supra_centrality_versatility(inputs, geometryOut, cfg)
% M28_COMPUTE_SUPRA_CENTRALITY_VERSATILITY
% 构造三层 supra-adjacency 并计算城市 versatility

sensitivityAll = table();
out = struct();
out.byYear = struct();

for iYear = 1:numel(cfg.years)
    yearValue = cfg.years(iYear);
    fieldName = "y" + string(yearValue);
    Y = inputs.yearData.(fieldName);
    cityTable = Y.cityTable;
    layerMatrices = {normalize_matrix_local(Y.W_I), normalize_matrix_local(Y.W_E), normalize_matrix_local(Y.W_C)};
    M = Y.nodeMetrics;
    layerStrength = [double(M.investment_total_strength), double(M.economic_total_strength), double(M.carbon_total_strength)];
    layerPagerank = [double(M.investment_pagerank), double(M.economic_pagerank), double(M.carbon_pagerank)];

    rows = table();
    for iOmega = 1:numel(cfg.omegaValues)
        omega = double(cfg.omegaValues(iOmega));
        supraW = supra_matrix_local(layerMatrices, omega);
        centrality = pagerank_weighted_local(supraW, cfg.pagerankAlpha, cfg.pagerankTolerance, cfg.pagerankMaxIter);
        centralityCopies = reshape(centrality, height(cityTable), 3);
        versatility = sum(centralityCopies, 2);
        versatilityRank = rank_desc_local(versatility);

        T = table();
        T.year = repmat(yearValue, height(cityTable), 1);
        T.omega = repmat(omega, height(cityTable), 1);
        T.city_code = double(cityTable.city_code);
        T.city_name = string(cityTable.city_name);
        T.investment_copy_centrality = centralityCopies(:, 1);
        T.production_copy_centrality = centralityCopies(:, 2);
        T.carbon_copy_centrality = centralityCopies(:, 3);
        T.versatility = versatility;
        T.versatility_rank = versatilityRank;
        T.dominant_layer = geometryOut.byYear.(fieldName).dominant_layer;
        rows = [rows; T]; %#ok<AGROW>

        sensitivityAll = [sensitivityAll; sensitivity_rows_local(yearValue, omega, versatility, layerStrength, layerPagerank, cfg)]; %#ok<AGROW>
    end

    pathValue = fullfile(cfg.outputDir, "supra_centrality_" + string(yearValue) + ".csv");
    writetable(rows, pathValue);
    out.byYear.(fieldName) = rows;
end

sensitivityPath = fullfile(cfg.outputDir, 'supra_centrality_omega_sensitivity.csv');
writetable(sensitivityAll, sensitivityPath);
out.sensitivityTable = sensitivityAll;
out.sensitivityPath = string(sensitivityPath);
end

function Wnorm = normalize_matrix_local(W)
W = double(W);
W(1:size(W, 1)+1:end) = 0;
total = sum(W, 'all');
if total <= 0
    Wnorm = zeros(size(W));
else
    Wnorm = W ./ total;
end
end

function supraW = supra_matrix_local(layerMatrices, omega)
N = size(layerMatrices{1}, 1);
supraW = zeros(3 * N, 3 * N);
for i = 1:3
    rowIdx = (i - 1) * N + (1:N);
    for j = 1:3
        colIdx = (j - 1) * N + (1:N);
        if i == j
            supraW(rowIdx, colIdx) = layerMatrices{i};
        else
            supraW(rowIdx, colIdx) = omega * eye(N);
        end
    end
end
end

function score = pagerank_weighted_local(W, alpha, tol, maxIter)
N = size(W, 1);
outStrength = sum(W, 2);
P = zeros(N, N);
for i = 1:N
    if outStrength(i) > 0
        P(i, :) = W(i, :) ./ outStrength(i);
    else
        P(i, :) = 1 / N;
    end
end
score = ones(N, 1) / N;
teleport = ones(N, 1) / N;
for iter = 1:maxIter
    newScore = alpha * (P' * score) + (1 - alpha) * teleport;
    if norm(newScore - score, 1) <= tol
        score = newScore;
        break;
    end
    score = newScore;
end
score = score ./ max(sum(score), eps);
end

function r = rank_desc_local(x)
[~, order] = sort(x, 'descend');
r = zeros(size(x));
r(order) = 1:numel(x);
end

function rows = sensitivity_rows_local(yearValue, omega, versatility, layerStrength, layerPagerank, cfg)
rows = table();
for iLayer = 1:3
    rows = [rows; table(yearValue, omega, cfg.layerNames(iLayer), "total_strength", ...
        spearman_local(versatility, layerStrength(:, iLayer)), ...
        'VariableNames', {'year','omega','reference_layer','reference_metric','rank_correlation_spearman'})]; %#ok<AGROW>
    rows = [rows; table(yearValue, omega, cfg.layerNames(iLayer), "pagerank", ...
        spearman_local(versatility, layerPagerank(:, iLayer)), ...
        'VariableNames', {'year','omega','reference_layer','reference_metric','rank_correlation_spearman'})]; %#ok<AGROW>
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
else
    r = sum((x - mean(x)) .* (y - mean(y))) / sqrt(sum((x - mean(x)).^2) * sum((y - mean(y)).^2));
end
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
