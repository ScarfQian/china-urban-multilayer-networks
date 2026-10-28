function layer = m06_build_carbon_layer_from_mrio17(city, carbonIntensity, alignment, yearValue, cfg)
% M06_BUILD_CARBON_LAYER_FROM_MRIO17
% Build the direct-trade embodied-carbon layer by applying city-sector
%   direct carbon intensity to the frozen MRIO4 intermediate-flow matrix.

N = city.numCities;
S = city.numSectors;
A = kron(speye(N), ones(1, S));
qVec = reshape(carbonIntensity.q', [], 1);
Zscaled = bsxfun(@times, double(city.Z), qVec);
W = A * sparse(Zscaled) * A';
W = full(W);
W(1:N+1:end) = 0;

edgeTable = matrix_to_edge_table_local(W, alignment.cityTable, alignment.distanceMatrixKm, alignment.sameProvinceMatrix, yearValue, "carbon", "raw");
save(fullfile(cfg.layerDir, "W_C_" + string(yearValue) + ".mat"), 'W');
writetable(edgeTable, fullfile(cfg.layerDir, "carbon_layer_edges_" + string(yearValue) + ".csv"));

layer = struct();
layer.year = yearValue;
layer.layer = "carbon";
layer.W = W;
layer.edgeTable = edgeTable;
layer.nonzeroEdgeCount = nnz(W > 0);
layer.totalWeight = sum(W, 'all');
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
