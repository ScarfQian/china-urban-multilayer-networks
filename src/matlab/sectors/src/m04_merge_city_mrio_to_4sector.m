function out = m04_merge_city_mrio_to_4sector(cityInput, mappingInput)
% M04_MERGE_CITY_MRIO_TO_4SECTOR
% Merge a 42-sector city MRIO package into agriculture / industry / transport / service.

city42 = m02_load_city_mrio_package(cityInput);
mapping4 = m03_load_mrio4_mapping(mappingInput);
M = full(mapping4.mergeMatrix);

if city42.numSectors ~= mapping4.numOld
    error('m04_merge_city_mrio_to_4sector:SectorCountMismatch', ...
        'Input city package has %d sectors, but mapping expects %d.', ...
        city42.numSectors, mapping4.numOld);
end

numCities = city42.numCities;
numFD = city42.numFD;
S42 = mapping4.numOld;
S4 = mapping4.numNew;
NS4 = numCities * S4;

Z4 = zeros(NS4, NS4);
Y4 = zeros(NS4, size(city42.Y, 2));
VA4 = zeros(NS4, 1);
IM4 = zeros(NS4, 1);
EX4 = zeros(NS4, 1);
ERR4 = zeros(NS4, 1);
X4 = zeros(NS4, 1);

row42 = cell(numCities, 1);
row4 = cell(numCities, 1);
for c = 1:numCities
    row42{c} = ((c - 1) * S42 + 1):(c * S42);
    row4{c} = ((c - 1) * S4 + 1):(c * S4);
    Y4(row4{c}, :) = M * city42.Y(row42{c}, :);
    VA4(row4{c}) = M * city42.VA(row42{c});
    IM4(row4{c}) = M * city42.IM(row42{c});
    EX4(row4{c}) = M * city42.EX(row42{c});
    ERR4(row4{c}) = M * city42.error(row42{c});
    X4(row4{c}) = M * city42.X(row42{c});
end

for i = 1:numCities
    r42 = row42{i};
    r4 = row4{i};
    for j = 1:numCities
        c42 = row42{j};
        c4 = row4{j};
        Z4(r4, c4) = M * city42.Z(r42, c42) * M';
    end
end

out = struct();
out.Z = Z4;
out.Y = Y4;
out.F = Y4;
out.VA = VA4;
out.IM = IM4;
out.EX = EX4;
out.error = ERR4;
out.X = X4;
out.cities = city42.cities;
out.cities_cn = city42.cities_cn;
out.sectors = mapping4.sector4_names;
out.sector_codes = mapping4.sector4_codes;
out.fd_labels = city42.fd_labels;
out.numCities = numCities;
out.numSectors = S4;
out.numFD = numFD;
out.merge_mapping = mapping4.table;
out.Diagnostics = struct();
out.Diagnostics.row_identity_max = max(abs(X4 - (sum(Z4, 2) + sum(Y4, 2) + EX4 + ERR4)));
out.Diagnostics.col_identity_max = max(abs(X4 - (sum(Z4, 1)' + VA4 + IM4)));
out.Diagnostics.total_Z = sum(Z4, 'all');
out.Diagnostics.total_Y = sum(Y4, 'all');
out.Diagnostics.total_X = sum(X4);
end
