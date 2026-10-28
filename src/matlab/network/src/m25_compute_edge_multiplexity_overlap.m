function out = m25_compute_edge_multiplexity_overlap(inputs, cfg)
% M25_COMPUTE_EDGE_MULTIPLEXITY_OVERLAP
% 计算边复用度、层对 Jaccard 和层归一化 weighted overlap

overlapAll = table();
out = struct();
out.edgeSummaryByYear = struct();

for iYear = 1:numel(cfg.years)
    yearValue = cfg.years(iYear);
    fieldName = "y" + string(yearValue);
    Y = inputs.yearData.(fieldName);
    [W, A, mask] = layer_arrays_local(Y);
    multiplexity = double(A{1}) + double(A{2}) + double(A{3});
    multiplexity = multiplexity(mask);
    totalDyads = numel(multiplexity);
    rows = table();
    for m = 0:3
        count = sum(multiplexity == m);
        row = table(yearValue, m, count, count / totalDyads, ...
            'VariableNames', {'year','multiplexity_m','dyad_count','dyad_share'});
        rows = [rows; row]; %#ok<AGROW>
    end
    pathValue = fullfile(cfg.outputDir, "edge_multiplexity_summary_" + string(yearValue) + ".csv");
    writetable(rows, pathValue);
    out.edgeSummaryByYear.(fieldName) = rows;

    pairs = [1 2; 1 3; 2 3];
    for iPair = 1:size(pairs, 1)
        a = pairs(iPair, 1);
        b = pairs(iPair, 2);
        jaccard = sum(A{a}(mask) & A{b}(mask)) / max(sum(A{a}(mask) | A{b}(mask)), 1);
        weightedOverlap = sum(min(W{a}(mask) ./ max(sum(W{a}(mask)), eps), W{b}(mask) ./ max(sum(W{b}(mask)), eps)));
        overlapAll = [overlapAll; table(yearValue, cfg.layerCodes(a), cfg.layerCodes(b), ...
            cfg.layerNames(a), cfg.layerNames(b), jaccard, weightedOverlap, ...
            'VariableNames', {'year','layer_a_code','layer_b_code','layer_a','layer_b','jaccard_overlap','weighted_overlap_layer_normalized'})]; %#ok<AGROW>
    end
end

overlapPath = fullfile(cfg.outputDir, 'layer_pair_overlap_summary.csv');
writetable(overlapAll, overlapPath);
out.overlapSummary = overlapAll;
out.overlapPath = string(overlapPath);
end

function [W, A, mask] = layer_arrays_local(Y)
W = {double(Y.W_I), double(Y.W_E), double(Y.W_C)};
mask = ~eye(size(W{1}, 1));
A = cell(size(W));
for i = 1:numel(W)
    W{i}(~mask) = 0;
    A{i} = W{i} > 0;
end
end
