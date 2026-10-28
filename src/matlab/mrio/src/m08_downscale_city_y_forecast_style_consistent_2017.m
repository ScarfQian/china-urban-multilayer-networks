function out = m08_downscale_city_y_forecast_style_consistent_2017(city2015, prov2017, mapping, varargin)
% M08_DOWNSCALE_CITY_Y_FORECAST_STYLE_CONSISTENT_2017
% Build city-level Y from 2015 shares while preserving official provincial 2017 Y exactly.

p = inputParser;
p.addRequired('city2015', @(x) isstruct(x) && isfield(x, 'Y'));
p.addRequired('prov2017', @(x) isstruct(x) && isfield(x, 'Y'));
p.addRequired('mapping', @(x) isstruct(x) && isfield(x, 'city_indices_by_province'));
p.addParameter('WeightSpec', struct(), @isstruct);
p.addParameter('ProxyTable', [], @(x) true);
p.addParameter('Eta', [1 1 1], @(x) isnumeric(x) && numel(x) == 3);
p.addParameter('NumericClass', "double", @(x) any(strcmpi(string(x), ["single","double"])));
p.addParameter('Epsilon', 1e-12, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.addParameter('Validate', true, @(x) islogical(x) || isnumeric(x));
p.parse(city2015, prov2017, mapping, varargin{:});
opt = p.Results;

city = city2015;
prov = prov2017;
map = mapping;
NS = numel(city.X);
NF = size(city.Y, 2);
F = map.numFD;

if isempty(fieldnames(opt.WeightSpec))
    weightSpec = build_weight_spec(city, opt.ProxyTable, opt.Eta, map, opt.Epsilon);
else
    weightSpec = opt.WeightSpec;
end

Y = zeros(NS, NF, char(opt.NumericClass));
for pIdx = 1:map.numProvinces
    rowCities = map.city_indices_by_province{pIdx};
    rowIdx = city_sector_indices(rowCities, map.numSectors);
    npCity = numel(rowCities);
    provRows = province_sector_indices(pIdx, map.numSectors);
    for qIdx = 1:map.numProvinces
        colCities = map.city_indices_by_province{qIdx};
        colShareByFD = double(weightSpec.fd_city_share(colCities, :));
        for f = 1:F
            colIdx = fd_city_indices(colCities, f, F);
            provCol = (qIdx - 1) * F + f;
            block = zeros(numel(rowIdx), numel(colIdx));
            colShare = colShareByFD(:, f);
            for s = 1:map.numSectors
                rowLocal = s:map.numSectors:(npCity * map.numSectors);
                rowShare = double(weightSpec.sector_share(rowIdx(rowLocal)));
                shareBase = rowShare(:) * colShare(:)';
                shareBase = shareBase ./ sum(shareBase, 'all');
                targetValue = double(prov.Y(provRows(s), provCol));
                block(rowLocal, :) = shareBase .* targetValue;
            end
            Y(rowIdx, colIdx) = cast(block, char(opt.NumericClass));
        end
    end
end

out = struct();
out.Y = Y;
out.Diagnostics = struct();
out.Diagnostics.prov_Y_inf = inf_gap(map.A * double(Y) * map.B', double(prov.Y));
out.Diagnostics.mode = "forecast_style_consistent_2017";

if logical(opt.Validate)
    assert(out.Diagnostics.prov_Y_inf <= 1e-6, ...
        'm08_downscale_city_y_forecast_style_consistent_2017:ProvYMismatch', ...
        'The city Y matrix does not aggregate back to official prov2017 Y.');
end
end

function weightSpec = build_weight_spec(city, proxyTable, eta, map, epsilon)
NS = numel(city.X);
Nc = map.numCities;
F = map.numFD;
weightSpec = struct();
weightSpec.city_sector = ones(NS, 1);
weightSpec.fd_city = ones(Nc, F);

if ~isempty(proxyTable)
    proxy = normalize_proxy_input(proxyTable, Nc);
    sectorGroup = sector_group_key(map.numSectors);
    for cityIdx = 1:Nc
        rows = ((cityIdx - 1) * map.numSectors + 1):(cityIdx * map.numSectors);
        for s = 1:map.numSectors
            g = sectorGroup(s);
            weightSpec.city_sector(rows(s)) = max(proxy.city_group(cityIdx, g), eps) .^ eta(g);
        end
        for f = 1:F
            weightSpec.fd_city(cityIdx, f) = max(proxy.fd(cityIdx, f), eps);
        end
    end
end

weightSpec.sector_share = build_sector_share(city.X, weightSpec.city_sector, map, epsilon);
weightSpec.fd_city_share = build_fd_city_share(city, weightSpec.fd_city, map, epsilon);
end

function proxy = normalize_proxy_input(proxyInput, Nc)
proxy = struct();
proxy.city_group = ones(Nc, 3);
proxy.fd = ones(Nc, 5);

if isnumeric(proxyInput)
    if size(proxyInput, 1) ~= Nc || size(proxyInput, 2) < 3
        error('m08_downscale_city_y_forecast_style_consistent_2017:InvalidProxyMatrix', ...
            'ProxyTable matrix should be Nc x 3 or wider.');
    end
    proxy.city_group = double(proxyInput(:, 1:3));
    if size(proxyInput, 2) >= 8
        proxy.fd = double(proxyInput(:, 4:8));
    end
    return;
end

if ~istable(proxyInput)
    error('m08_downscale_city_y_forecast_style_consistent_2017:InvalidProxyType', ...
        'ProxyTable must be numeric or table.');
end

vars = lower(string(proxyInput.Properties.VariableNames));
proxy.city_group(:, 1) = find_proxy_column(proxyInput, vars, ["g1","agri","primary","primary_gdp"], Nc);
proxy.city_group(:, 2) = find_proxy_column(proxyInput, vars, ["g2","industry","secondary","industrial"], Nc);
proxy.city_group(:, 3) = find_proxy_column(proxyInput, vars, ["g3","services","tertiary","retail"], Nc);
proxy.fd(:, 1) = find_proxy_column(proxyInput, vars, ["fd1","rural","rural_cons"], Nc);
proxy.fd(:, 2) = find_proxy_column(proxyInput, vars, ["fd2","urban","urban_cons"], Nc);
proxy.fd(:, 3) = find_proxy_column(proxyInput, vars, ["fd3","gov","government"], Nc);
proxy.fd(:, 4) = find_proxy_column(proxyInput, vars, ["fd4","fai","investment"], Nc);
proxy.fd(:, 5) = find_proxy_column(proxyInput, vars, ["fd5","inventory","stock"], Nc);
end

function values = find_proxy_column(tbl, vars, candidates, Nc)
values = ones(Nc, 1);
for i = 1:numel(candidates)
    idx = find(vars == lower(string(candidates(i))), 1, 'first');
    if ~isempty(idx)
        values = double(tbl{:, idx});
        return;
    end
end
end

function key = sector_group_key(S)
key = ones(S, 1);
key(2:min(28, S)) = 2;
if S >= 29
    key(29:S) = 3;
end
end

function shareVec = build_sector_share(baseVec, weight, map, epsilon)
shareVec = zeros(size(baseVec));
for pIdx = 1:map.numProvinces
    cities = map.city_indices_by_province{pIdx};
    for s = 1:map.numSectors
        cityRows = sector_rows_within_province(cities, s, map.numSectors);
        base = max(double(baseVec(cityRows)), 0) .* max(double(weight(cityRows)), epsilon);
        if sum(base) <= epsilon
            base = max(double(weight(cityRows)), epsilon);
        end
        shareVec(cityRows) = base ./ sum(base);
    end
end
end

function fdShare = build_fd_city_share(city, fdWeight, map, epsilon)
fdShare = zeros(size(fdWeight));
for qIdx = 1:map.numProvinces
    cities = map.city_indices_by_province{qIdx};
    for f = 1:map.numFD
        cols = fd_city_indices(cities, f, map.numFD);
        base = max(sum(double(city.Y(:, cols)), 1)', 0) .* max(double(fdWeight(cities, f)), epsilon);
        if sum(base) <= epsilon
            base = max(double(fdWeight(cities, f)), epsilon);
        end
        fdShare(cities, f) = base ./ sum(base);
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

function value = inf_gap(A, B)
value = max(abs(double(A(:)) - double(B(:))));
end
