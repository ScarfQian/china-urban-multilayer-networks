function out = m09_compute_single_layer_metrics(layerBundle, backbones, alignment, yearValue, cfg)
% M09_COMPUTE_SINGLE_LAYER_METRICS
% Compute node and network metrics for each city-to-city layer before
%   moving to cross-layer analysis.

layerNames = ["investment","economic","carbon"];
nodeRows = cell(0, 12);
summaryRows = cell(0, 12);
topRows = cell(0, 7);

for i = 1:numel(layerNames)
    layerName = layerNames(i);
    W = double(layerBundle.(layerName).W);
    inStrength = sum(W, 1)';
    outStrength = sum(W, 2);
    totalStrength = inStrength + outStrength;
    pagerankScore = pagerank_weighted_local(W, cfg.pagerankAlpha, 1e-10, 500);
    betweennessScore = weighted_betweenness_local(W, cfg.computeBetweenness);

    totalRank = rank_desc_local(totalStrength);
    pagerankRank = rank_desc_local(pagerankScore);
    for iCity = 1:alignment.numCities
        nodeRows(end + 1, :) = { ... %#ok<AGROW>
            yearValue, ...
            char(layerName), ...
            'raw', ...
            alignment.cityTable.city_code(iCity), ...
            char(alignment.cityTable.city_cn(iCity)), ...
            inStrength(iCity), ...
            outStrength(iCity), ...
            totalStrength(iCity), ...
            pagerankScore(iCity), ...
            betweennessScore(iCity), ...
            totalRank(iCity), ...
            pagerankRank(iCity)};
    end

    reciprocityBinary = reciprocity_binary_local(W);
    reciprocityWeighted = reciprocity_weighted_local(W);
    edgeCount = nnz(W > 0);
    density = edgeCount / max(alignment.numCities * (alignment.numCities - 1), 1);
    outHhi = concentration_hhi_local(outStrength);
    inHhi = concentration_hhi_local(inStrength);
    [~, topTotalIdx] = max(totalStrength);
    [~, topPageRankIdx] = max(pagerankScore);
    summaryRows(end + 1, :) = { ... %#ok<AGROW>
        yearValue, ...
        char(layerName), ...
        'raw', ...
        edgeCount, ...
        density, ...
        reciprocityBinary, ...
        reciprocityWeighted, ...
        sum(W, 'all'), ...
        outHhi, ...
        inHhi, ...
        char(alignment.cityTable.city_cn(topTotalIdx)), ...
        char(alignment.cityTable.city_cn(topPageRankIdx))};

    topRows = [topRows; top_ranking_rows_local(yearValue, layerName, "total_strength", totalStrength, alignment.cityTable); ... %#ok<AGROW>
        top_ranking_rows_local(yearValue, layerName, "pagerank", pagerankScore, alignment.cityTable)];
end

nodeMetricsTable = cell2table(nodeRows, 'VariableNames', { ...
    'year','layer','variant','city_code','city_name','in_strength','out_strength','total_strength','pagerank','weighted_betweenness','rank_total_strength','rank_pagerank'});
networkSummaryTable = cell2table(summaryRows, 'VariableNames', { ...
    'year','layer','variant','edge_count','density','reciprocity_binary','reciprocity_weighted','total_weight','out_hhi','in_hhi','top_total_strength_city','top_pagerank_city'});
topRankingsTable = cell2table(topRows, 'VariableNames', { ...
    'year','layer','metric','rank','city_code','city_name','value'});

writetable(nodeMetricsTable, fullfile(cfg.resultsDir, "single_layer_node_metrics_" + string(yearValue) + ".csv"));

out = struct();
out.year = yearValue;
out.nodeMetricsTable = nodeMetricsTable;
out.networkSummaryTable = networkSummaryTable;
out.topRankingsTable = topRankingsTable;
out.backboneReference = backbones;
end

function rows = top_ranking_rows_local(yearValue, layerName, metricName, values, cityTable)
[sortedValues, order] = sort(values, 'descend');
keepN = min(20, numel(order));
rows = cell(keepN, 7);
for i = 1:keepN
    idx = order(i);
    rows(i, :) = {yearValue, char(layerName), char(metricName), i, cityTable.city_code(idx), char(cityTable.city_cn(idx)), sortedValues(i)};
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

function score = weighted_betweenness_local(W, doCompute)
N = size(W, 1);
score = nan(N, 1);
if ~doCompute
    return;
end
try
    dg = digraph(W);
    cost = 1 ./ max(dg.Edges.Weight, eps);
    score = centrality(dg, 'betweenness', 'Cost', cost);
catch
    score(:) = NaN;
end
end

function r = rank_desc_local(x)
[~, order] = sort(x, 'descend');
r = zeros(size(x));
r(order) = 1:numel(x);
end

function val = reciprocity_binary_local(W)
binaryW = W > 0;
val = nnz(binaryW & binaryW') / max(nnz(binaryW), 1);
end

function val = reciprocity_weighted_local(W)
val = sum(min(W, W'), 'all') / max(sum(W, 'all'), eps);
end

function val = concentration_hhi_local(v)
if sum(v) <= 0
    val = 0;
else
    share = v ./ sum(v);
    val = sum(share .^ 2);
end
end
