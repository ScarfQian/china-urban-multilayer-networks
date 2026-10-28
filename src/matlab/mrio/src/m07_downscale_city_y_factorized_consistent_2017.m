function out = m07_downscale_city_y_factorized_consistent_2017(cityBase, provTarget, mapping, params, varargin)
% M07_DOWNSCALE_CITY_Y_FACTORIZED_CONSISTENT_2017
% Build province-consistent Y using a factorized share model.

p = inputParser;
p.addRequired('cityBase', @(x) isstruct(x) && isfield(x, 'Y') && isfield(x, 'X'));
p.addRequired('provTarget', @(x) isstruct(x) && isfield(x, 'Y') && isfield(x, 'X'));
p.addRequired('mapping', @(x) isstruct(x) && isfield(x, 'city_indices_by_province'));
p.addRequired('params', @isstruct);
p.addParameter('TargetX', [], @(x) isempty(x) || isnumeric(x));
p.addParameter('TargetYColByFD', [], @(x) isempty(x) || isnumeric(x));
p.addParameter('ProxyTable', [], @(x) true);
p.addParameter('NumericClass', "double", @(x) any(strcmpi(string(x), ["single","double"])));
p.addParameter('Epsilon', 1e-12, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.addParameter('Validate', true, @(x) islogical(x) || isnumeric(x));
p.parse(cityBase, provTarget, mapping, params, varargin{:});
opt = p.Results;

map = mapping;
F = map.numFD;
Nc = map.numCities;
S = map.numSectors;
NS = Nc * S;

if isempty(opt.TargetX)
    targetX = allocate_with_sector_share(build_sector_share_from_x(cityBase.X, map, opt.Epsilon), provTarget.X, map);
else
    targetX = double(opt.TargetX(:));
end

if isempty(opt.TargetYColByFD)
    targetYColByFD = build_target_y_col_from_prov(cityBase, provTarget, map, opt.Epsilon);
else
    targetYColByFD = double(opt.TargetYColByFD);
end

shares = m05_build_city_y_factorized_shares(cityBase, targetX, targetYColByFD, map, params, ...
    'ProxyTable', opt.ProxyTable, ...
    'Epsilon', opt.Epsilon);

Y = zeros(NS, Nc * F, char(opt.NumericClass));
for pIdx = 1:map.numProvinces
    rowCities = map.city_indices_by_province{pIdx};
    rowIdx = city_sector_indices(rowCities, S);
    provRows = province_sector_indices(pIdx, S);
    for qIdx = 1:map.numProvinces
        colCities = map.city_indices_by_province{qIdx};
        for f = 1:F
            colIdx = fd_city_indices(colCities, f, F);
            provCol = (qIdx - 1) * F + f;
            block = zeros(numel(rowIdx), numel(colIdx));
            destShare = shares.v(colCities, f);
            for s = 1:S
                rowLocal = s:S:numel(rowIdx);
                rowShare = shares.u(rowIdx(rowLocal));
                shareBase = rowShare(:) * destShare(:)';
                shareBase = shareBase ./ sum(shareBase, 'all');
                block(rowLocal, :) = shareBase .* double(provTarget.Y(provRows(s), provCol));
            end
            Y(rowIdx, colIdx) = cast(block, char(opt.NumericClass));
        end
    end
end

out = struct();
out.Y = Y;
out.Shares = shares;
out.Diagnostics = struct();
out.Diagnostics.prov_Y_inf = max(abs((map.A * double(Y) * map.B') - double(provTarget.Y)), [], 'all');

if logical(opt.Validate)
    assert(out.Diagnostics.prov_Y_inf <= 1e-6, ...
        'm07_downscale_city_y_factorized_consistent_2017:ProvYMismatch', ...
        'Factorized Y does not aggregate back to provincial 2017.');
end
end

function share = build_sector_share_from_x(baseX, map, epsilon)
share = zeros(size(baseX));
for pIdx = 1:map.numProvinces
    cities = map.city_indices_by_province{pIdx};
    for s = 1:map.numSectors
        rows = sector_rows_within_province(cities, s, map.numSectors);
        vec = max(double(baseX(rows)), 0) + epsilon;
        share(rows) = vec ./ sum(vec);
    end
end
end

function targetYCol = build_target_y_col_from_prov(cityBase, provTarget, map, epsilon)
Nc = map.numCities;
F = map.numFD;
targetYCol = zeros(Nc, F);
histFDShare = build_hist_fd_city_share(cityBase, map, epsilon);
for qIdx = 1:map.numProvinces
    cities = map.city_indices_by_province{qIdx};
    for f = 1:F
        provTotal = sum(double(provTarget.Y(:, (qIdx - 1) * F + f)));
        targetYCol(cities, f) = provTotal .* histFDShare(cities, f);
    end
end
end

function histFDShare = build_hist_fd_city_share(city, map, epsilon)
Nc = map.numCities;
F = map.numFD;
histFDShare = zeros(Nc, F);
for qIdx = 1:map.numProvinces
    cities = map.city_indices_by_province{qIdx};
    for f = 1:F
        cols = fd_city_indices(cities, f, map.numFD);
        vec = sum(double(city.Y(:, cols)), 1)' + epsilon;
        histFDShare(cities, f) = vec ./ sum(vec);
    end
end
end

function vec = allocate_with_sector_share(sectorShare, provVec, map)
vec = zeros(size(sectorShare));
for pIdx = 1:map.numProvinces
    cities = map.city_indices_by_province{pIdx};
    provRows = province_sector_indices(pIdx, map.numSectors);
    for s = 1:map.numSectors
        cityRows = sector_rows_within_province(cities, s, map.numSectors);
        vec(cityRows) = double(provVec(provRows(s))) .* sectorShare(cityRows);
    end
end
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

function idx = sector_rows_within_province(cityIndices, sectorIdx, S)
idx = zeros(numel(cityIndices), 1);
for i = 1:numel(cityIndices)
    idx(i) = (cityIndices(i) - 1) * S + sectorIdx;
end
end

function idx = fd_city_indices(cityIndices, fdIndex, F)
idx = zeros(numel(cityIndices), 1);
for i = 1:numel(cityIndices)
    idx(i) = (cityIndices(i)-1) * F + fdIndex;
end
end
