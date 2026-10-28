function targets = m10_build_city_targets_forecast_style_consistent_2017(city2015, prov2017, mapping, varargin)
% M10_BUILD_CITY_TARGETS_FORECAST_STYLE_CONSISTENT_2017
% Build city-level forecast-style targets that aggregate exactly back to official provincial 2017 totals.

p = inputParser;
p.addRequired('city2015', @(x) isstruct(x) && isfield(x, 'Z') && isfield(x, 'Y'));
p.addRequired('prov2017', @(x) isstruct(x) && isfield(x, 'Z') && isfield(x, 'Y'));
p.addRequired('mapping', @(x) isstruct(x) && isfield(x, 'city_indices_by_province'));
p.addParameter('ProxyTable', [], @(x) true);
p.addParameter('Eta', [1 1 1], @(x) isnumeric(x) && numel(x) == 3);
p.addParameter('NumericClass', "double", @(x) any(strcmpi(string(x), ["single","double"])));
p.addParameter('Epsilon', 1e-12, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.addParameter('NegativeTol', 1e-6, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.addParameter('Validate', true, @(x) islogical(x) || isnumeric(x));
p.parse(city2015, prov2017, mapping, varargin{:});
opt = p.Results;

city = city2015;
prov = prov2017;
map = mapping;
NS = numel(city.X);
Nc = map.numCities;
F = map.numFD;

weightSpec = build_weight_spec(city, opt.ProxyTable, opt.Eta, map);
targets = struct();
targets.mode = "forecast_style_consistent_2017";
targets.mapping = map;
targets.WeightSpec = weightSpec;

targets.X = cast(allocate_with_sector_share(weightSpec.sector_share, prov.X, map), char(opt.NumericClass));
targets.VA = cast(allocate_with_sector_share(weightSpec.sector_share, prov.VA, map), char(opt.NumericClass));
targets.IM = cast(allocate_with_sector_share(weightSpec.sector_share, prov.IM, map), char(opt.NumericClass));
targets.EX = cast(allocate_with_sector_share(weightSpec.sector_share, prov.EX, map), char(opt.NumericClass));

yOut = m08_downscale_city_y_forecast_style_consistent_2017(city, prov, map, ...
    'WeightSpec', weightSpec, ...
    'NumericClass', char(opt.NumericClass), ...
    'Epsilon', opt.Epsilon, ...
    'Validate', logical(opt.Validate));
targets.Y_city = cast(yOut.Y, char(opt.NumericClass));

targets.Y_row_by_fd = zeros(NS, F, char(opt.NumericClass));
targets.Y_col_by_fd = zeros(Nc, F, char(opt.NumericClass));
for f = 1:F
    targets.Y_row_by_fd(:, f) = cast(sum(double(targets.Y_city(:, f:F:end)), 2), char(opt.NumericClass));
    targets.Y_col_by_fd(:, f) = cast(sum(double(targets.Y_city(:, f:F:end)), 1)', char(opt.NumericClass));
end

zRowTarget = double(targets.X) - sum(double(targets.Y_row_by_fd), 2) - double(targets.EX);
zColTarget = double(targets.X) - double(targets.VA) - double(targets.IM);
validate_nonnegative_targets(zRowTarget, 'Z_row_target', opt.NegativeTol);
validate_nonnegative_targets(zColTarget, 'Z_col_target', opt.NegativeTol);
targets.Z_row_target = cast(max(zRowTarget, 0), char(opt.NumericClass));
targets.Z_col_target = cast(max(zColTarget, 0), char(opt.NumericClass));

provZRow = double(map.A * double(targets.Z_row_target));
provZCol = double(map.A * double(targets.Z_col_target));
targets.prov_Z_row_target = provZRow;
targets.prov_Z_col_target = provZCol;
provZRowTruth = sum(double(prov.Z), 2);
provZColTruth = sum(double(prov.Z), 1)';

targets.Diagnostics = struct();
targets.Diagnostics.prov_X_inf = inf_gap(map.A * double(targets.X), double(prov.X));
targets.Diagnostics.prov_VA_inf = inf_gap(map.A * double(targets.VA), double(prov.VA));
targets.Diagnostics.prov_IM_inf = inf_gap(map.A * double(targets.IM), double(prov.IM));
targets.Diagnostics.prov_EX_inf = inf_gap(map.A * double(targets.EX), double(prov.EX));
targets.Diagnostics.prov_Y_inf = inf_gap(map.A * double(targets.Y_city) * map.B', double(prov.Y));
targets.Diagnostics.prov_Z_inf = max([inf_gap(provZRow, provZRowTruth), inf_gap(provZCol, provZColTruth)]);
targets.Diagnostics.prov_Z_row_target = provZRow;
targets.Diagnostics.prov_Z_col_target = provZCol;
targets.Diagnostics.rowGap = max(abs(double(targets.X) - ...
    (double(targets.Z_row_target) + sum(double(targets.Y_row_by_fd), 2) + double(targets.EX))));
targets.Diagnostics.colGap = max(abs(double(targets.X) - ...
    (double(targets.Z_col_target) + double(targets.VA) + double(targets.IM))));

if logical(opt.Validate)
    assert(targets.Diagnostics.prov_X_inf <= 1e-6, ...
        'm10_build_city_targets_forecast_style_consistent_2017:ProvXMismatch', ...
        'City X targets do not aggregate back to official prov2017.');
    assert(targets.Diagnostics.prov_VA_inf <= 1e-6, ...
        'm10_build_city_targets_forecast_style_consistent_2017:ProvVAMismatch', ...
        'City VA targets do not aggregate back to official prov2017.');
    assert(targets.Diagnostics.prov_IM_inf <= 1e-6, ...
        'm10_build_city_targets_forecast_style_consistent_2017:ProvIMMismatch', ...
        'City IM targets do not aggregate back to official prov2017.');
    assert(targets.Diagnostics.prov_EX_inf <= 1e-6, ...
        'm10_build_city_targets_forecast_style_consistent_2017:ProvEXMismatch', ...
        'City EX targets do not aggregate back to official prov2017.');
    assert(targets.Diagnostics.prov_Y_inf <= 1e-6, ...
        'm10_build_city_targets_forecast_style_consistent_2017:ProvYMismatch', ...
        'City Y targets do not aggregate back to official prov2017.');
end
end

function weightSpec = build_weight_spec(city, proxyTable, eta, map)
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

weightSpec.sector_share = build_sector_share(city.X, weightSpec.city_sector, map, eps);
weightSpec.fd_city_share = build_fd_city_share(city, weightSpec.fd_city, map, eps);
end

function proxy = normalize_proxy_input(proxyInput, Nc)
proxy = struct();
proxy.city_group = ones(Nc, 3);
proxy.fd = ones(Nc, 5);

if isnumeric(proxyInput)
    if size(proxyInput, 1) ~= Nc || size(proxyInput, 2) < 3
        error('m10_build_city_targets_forecast_style_consistent_2017:InvalidProxyMatrix', ...
            'ProxyTable matrix should be Nc x 3 or wider.');
    end
    proxy.city_group = double(proxyInput(:, 1:3));
    if size(proxyInput, 2) >= 8
        proxy.fd = double(proxyInput(:, 4:8));
    end
    return;
end

if ~istable(proxyInput)
    error('m10_build_city_targets_forecast_style_consistent_2017:InvalidProxyType', ...
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

function vec = allocate_with_sector_share(sectorShare, provVec, map)
vec = zeros(size(sectorShare));
for pIdx = 1:map.numProvinces
    cities = map.city_indices_by_province{pIdx};
    provRows = province_sector_indices(pIdx, map.numSectors);
    for s = 1:map.numSectors
        cityRows = sector_rows_within_province(cities, s, map.numSectors);
        vec(cityRows) = double(provVec(provRows(s))) .* double(sectorShare(cityRows));
    end
end
end

function validate_nonnegative_targets(vec, labelText, negativeTol)
minValue = min(vec);
if minValue < -negativeTol
    error('m10_build_city_targets_forecast_style_consistent_2017:NegativeTarget', ...
        '%s contains materially negative values.', labelText);
end
end

function idx = sector_rows_within_province(cityIndices, sectorIdx, S)
idx = zeros(numel(cityIndices), 1);
for i = 1:numel(cityIndices)
    idx(i) = (cityIndices(i) - 1) * S + sectorIdx;
end
end

function idx = province_sector_indices(provinceIdx, S)
idx = ((provinceIdx - 1) * S + 1):(provinceIdx * S);
idx = idx(:);
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
