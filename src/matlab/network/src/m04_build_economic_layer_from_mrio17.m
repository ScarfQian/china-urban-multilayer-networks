function layer = m04_build_economic_layer_from_mrio17(city, alignment, yearValue, cfg)
% M04_BUILD_ECONOMIC_LAYER_FROM_MRIO17
% Aggregate the city-sector intermediate-flow matrix into a directed
%   city-to-city economic layer.

N = city.numCities;
S = city.numSectors;
A = kron(speye(N), ones(1, S));
W = A * sparse(double(city.Z)) * A';
W = full(W);
W(1:N+1:end) = 0;

edgeTable = matrix_to_edge_table_local(W, alignment.cityTable, alignment.distanceMatrixKm, alignment.sameProvinceMatrix, yearValue, "economic", "raw");
save(fullfile(cfg.layerDir, "W_E_" + string(yearValue) + ".mat"), 'W');
writetable(edgeTable, fullfile(cfg.layerDir, "economic_layer_edges_" + string(yearValue) + ".csv"));

layer = struct();
layer.year = yearValue;
layer.layer = "economic";
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
