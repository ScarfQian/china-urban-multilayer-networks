function out = m08_extract_backbones(layerBundle, alignment, yearValue, cfg)
% M08_EXTRACT_BACKBONES
% Build raw, cumulative-flow-share, and density-matched backbones for the
%   investment, economic, and carbon layers.

layerSpecs = { ...
    struct('field', "investment", 'short', "I"), ...
    struct('field', "economic", 'short', "E"), ...
    struct('field', "carbon", 'short', "C")};

N = alignment.numCities;
referenceEdgeCount = nnz(layerBundle.investment.W > 0);
summaryRows = cell(0, 8);
out = struct();
out.summaryTable = table();

for i = 1:numel(layerSpecs)
    spec = layerSpecs{i};
    Wraw = double(layerBundle.(spec.field).W);
    Wcum = cumulative_backbone_local(Wraw, cfg.backboneCumulativeShare);
    if spec.field == "investment"
        Wdensity = Wraw;
    else
        Wdensity = density_matched_backbone_local(Wraw, referenceEdgeCount);
    end

    edgeRaw = matrix_to_edge_table_local(Wraw, alignment.cityTable, alignment.distanceMatrixKm, alignment.sameProvinceMatrix, yearValue, spec.field, "raw");
    edgeCum = matrix_to_edge_table_local(Wcum, alignment.cityTable, alignment.distanceMatrixKm, alignment.sameProvinceMatrix, yearValue, spec.field, "cumulative_flow_share");
    edgeDensity = matrix_to_edge_table_local(Wdensity, alignment.cityTable, alignment.distanceMatrixKm, alignment.sameProvinceMatrix, yearValue, spec.field, "density_matched");
    edgeAll = [edgeRaw; edgeCum; edgeDensity];

    writetable(edgeAll, fullfile(cfg.backboneDir, "backbone_edges_" + spec.short + "_" + string(yearValue) + ".csv"));

    summaryRows(end + 1, :) = summary_row_local(yearValue, spec.field, "raw", Wraw, Wraw); %#ok<AGROW>
    summaryRows(end + 1, :) = summary_row_local(yearValue, spec.field, "cumulative_flow_share", Wcum, Wraw); %#ok<AGROW>
    summaryRows(end + 1, :) = summary_row_local(yearValue, spec.field, "density_matched", Wdensity, Wraw); %#ok<AGROW>

    out.(spec.field) = struct( ...
        'raw', Wraw, ...
        'cumulativeFlowShare', Wcum, ...
        'densityMatched', Wdensity, ...
        'edgeTable', edgeAll);
end

out.summaryTable = cell2table(summaryRows, 'VariableNames', { ...
    'year','layer','variant','edge_count','density','flow_retained','reference_total_weight','variant_total_weight'});
end

function Wkeep = cumulative_backbone_local(W, shareTarget)
Wkeep = zeros(size(W));
[srcIdx, dstIdx, weight] = find(W);
if isempty(weight)
    return;
end
[sortedWeight, order] = sort(weight, 'descend');
cumShare = cumsum(sortedWeight) ./ max(sum(sortedWeight), eps);
keepMask = cumShare <= shareTarget;
if ~any(keepMask)
    keepMask(1) = true;
end
keepMask(find(cumShare >= shareTarget, 1, 'first')) = true;
sel = order(keepMask);
linearIdx = sub2ind(size(W), srcIdx(sel), dstIdx(sel));
Wkeep(linearIdx) = W(linearIdx);
end

function Wkeep = density_matched_backbone_local(W, targetEdgeCount)
Wkeep = zeros(size(W));
[srcIdx, dstIdx, weight] = find(W);
if isempty(weight) || targetEdgeCount <= 0
    return;
end
[~, order] = sort(weight, 'descend');
keepN = min(targetEdgeCount, numel(order));
sel = order(1:keepN);
linearIdx = sub2ind(size(W), srcIdx(sel), dstIdx(sel));
Wkeep(linearIdx) = W(linearIdx);
end

function row = summary_row_local(yearValue, layerName, variantName, Wvariant, Wreference)
edgeCount = nnz(Wvariant > 0);
N = size(Wvariant, 1);
density = edgeCount / max(N * (N - 1), 1);
referenceWeight = sum(Wreference, 'all');
variantWeight = sum(Wvariant, 'all');
flowRetained = variantWeight / max(referenceWeight, eps);
row = {yearValue, char(layerName), char(variantName), edgeCount, density, flowRetained, referenceWeight, variantWeight};
end

function edgeTable = matrix_to_edge_table_local(W, cityTable, distanceMatrix, sameProvinceMatrix, yearValue, layerName, variantName)
[srcIdx, dstIdx, weight] = find(W);
edgeTable = table( ...
    repmat(yearValue, numel(weight), 1), ...
    repmat(string(layerName), numel(weight), 1), ...
    repmat(string(variantName), numel(weight), 1), ...
    double(cityTable.city_code(srcIdx)), ...
    string(cityTable.city_cn(srcIdx)), ...
    double(cityTable.city_code(dstIdx)), ...
    string(cityTable.city_cn(dstIdx)), ...
    double(weight), ...
    distanceMatrix(sub2ind(size(distanceMatrix), srcIdx, dstIdx)), ...
    sameProvinceMatrix(sub2ind(size(sameProvinceMatrix), srcIdx, dstIdx)), ...
    'VariableNames', {'year','layer','variant','source_city_code','source_city_name','target_city_code','target_city_name','weight','distance_km','same_province'});
end
