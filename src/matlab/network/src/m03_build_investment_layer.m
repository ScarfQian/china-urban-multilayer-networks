function layer = m03_build_investment_layer(inputs, alignment, yearValue, cfg)
% M03_BUILD_INVESTMENT_LAYER
% Aggregate the external directed investment network into the canonical
%   313-city order used by the multilayer-network pipeline.

sheetName = "DirectedNetwork_" + string(yearValue);
rawTable = readtable(inputs.investmentWorkbookPath, 'Sheet', sheetName, 'TextType', 'string');

required = ["InvestmentFrequency","InvestorCityCode","InvesteeCityCode"];
for i = 1:numel(required)
    if ~ismember(required(i), string(rawTable.Properties.VariableNames))
        error('m03_build_investment_layer:MissingColumn', ...
            'Investment sheet %s is missing column %s.', sheetName, required(i));
    end
end

sourceCodes = double(rawTable.InvestorCityCode);
targetCodes = double(rawTable.InvesteeCityCode);
weights = double(rawTable.InvestmentFrequency);

N = alignment.numCities;
W = zeros(N, N);
splitLookup = build_split_lookup_local(alignment.investmentCrosswalk, alignment.cityCodeToIndex);
excludedRawCodes = double(alignment.excludedRawInvestmentCodes(:));
excludedBySampleEdgeCount = 0;
excludedBySampleWeight = 0;
for i = 1:numel(weights)
    if (~isKey(splitLookup, sourceCodes(i)) || ~isKey(splitLookup, targetCodes(i))) && ...
            (ismember(sourceCodes(i), excludedRawCodes) || ismember(targetCodes(i), excludedRawCodes))
        excludedBySampleEdgeCount = excludedBySampleEdgeCount + 1;
        excludedBySampleWeight = excludedBySampleWeight + weights(i);
        continue;
    end
    srcSpec = resolve_split_spec_local(sourceCodes(i), splitLookup);
    dstSpec = resolve_split_spec_local(targetCodes(i), splitLookup);
    for a = 1:numel(srcSpec.idx)
        for b = 1:numel(dstSpec.idx)
            W(srcSpec.idx(a), dstSpec.idx(b)) = W(srcSpec.idx(a), dstSpec.idx(b)) + ...
                weights(i) * srcSpec.share(a) * dstSpec.share(b);
        end
    end
end
collapsedDiagonalWeight = sum(diag(W));
collapsedDiagonalEdges = nnz(diag(W));
W(1:N+1:end) = 0;

edgeTable = matrix_to_edge_table_local(W, alignment.cityTable, alignment.distanceMatrixKm, alignment.sameProvinceMatrix, yearValue, "investment", "raw");
save(fullfile(cfg.layerDir, "W_I_" + string(yearValue) + ".mat"), 'W');
writetable(edgeTable, fullfile(cfg.layerDir, "investment_layer_edges_" + string(yearValue) + ".csv"));

layer = struct();
layer.year = yearValue;
layer.layer = "investment";
layer.W = W;
layer.edgeTable = edgeTable;
layer.rawEdgeCount = height(rawTable);
layer.collapsedDiagonalWeight = collapsedDiagonalWeight;
layer.collapsedDiagonalEdges = collapsedDiagonalEdges;
layer.excludedBySampleEdgeCount = excludedBySampleEdgeCount;
layer.excludedBySampleWeight = excludedBySampleWeight;
layer.nonzeroEdgeCount = nnz(W > 0);
layer.totalWeight = sum(W, 'all');
end

function splitLookup = build_split_lookup_local(crosswalk, cityCodeToIndex)
[G, keys] = findgroups(double(crosswalk.raw_city_code));
splitLookup = containers.Map('KeyType', 'double', 'ValueType', 'any');
for i = 1:numel(keys)
    hit = G == i;
    targetCodes = double(crosswalk.target_city_code(hit));
    targetIdx = zeros(numel(targetCodes), 1);
    for j = 1:numel(targetCodes)
        targetIdx(j) = cityCodeToIndex(targetCodes(j));
    end
    splitLookup(keys(i)) = struct( ...
        'idx', targetIdx(:), ...
        'share', double(crosswalk.allocation_share(hit)));
end
end

function spec = resolve_split_spec_local(rawCode, splitLookup)
if ~isKey(splitLookup, rawCode)
    error('m03_build_investment_layer:MissingCrosswalkKey', ...
        'Raw investment city code %d is missing from the crosswalk.', rawCode);
end
spec = splitLookup(rawCode);
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
