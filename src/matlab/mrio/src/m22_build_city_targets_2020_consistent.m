function targets = m22_build_city_targets_2020_consistent(citySource, prov2020, mapping, varargin)
% M22_BUILD_CITY_TARGETS_2020_CONSISTENT
% Build city-level 2020 targets from city2017_harm while preserving provincial 2020 totals exactly.

p = inputParser;
p.addRequired('citySource', @(x) isstruct(x) && isfield(x, 'Z') && isfield(x, 'Y'));
p.addRequired('prov2020', @(x) isstruct(x) && isfield(x, 'Z') && isfield(x, 'Y'));
p.addRequired('mapping', @(x) isstruct(x) && isfield(x, 'city_indices_by_province'));
p.addParameter('YMode', "hybrid", @(x) any(strcmpi(string(x), ["baseline","factorized","hybrid"])));
p.addParameter('FactorizedParams', struct(), @isstruct);
p.addParameter('HybridParams', struct(), @isstruct);
p.addParameter('ProxyTable', [], @(x) true);
p.addParameter('Eta', [1 1 1], @(x) isnumeric(x) && numel(x) == 3);
p.addParameter('NumericClass', "double", @(x) any(strcmpi(string(x), ["single","double"])));
p.addParameter('Epsilon', 1e-12, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.addParameter('NegativeTol', 1e-6, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.addParameter('TopSupportCount', 3, @(x) isnumeric(x) && isscalar(x) && x >= 1);
p.addParameter('Validate', true, @(x) islogical(x) || isnumeric(x));
p.parse(citySource, prov2020, mapping, varargin{:});
opt = p.Results;

city = cast_city_to_double(citySource);
prov = cast_prov_to_double(prov2020);
map = mapping;
NS = numel(city.X);
Nc = map.numCities;
F = map.numFD;
weightSpec = build_weight_spec_2020(city, opt.ProxyTable, opt.Eta, map, opt.Epsilon);

targets = struct();
targets.mode = string(opt.YMode);
targets.mapping = map;
targets.WeightSpec = weightSpec;
targets.X = cast(allocate_with_sector_share_2020(weightSpec.sector_share, prov.X, map), char(opt.NumericClass));
targets.VA = cast(allocate_with_sector_share_2020(weightSpec.sector_share, prov.VA, map), char(opt.NumericClass));
targets.IM = cast(allocate_with_sector_share_2020(weightSpec.sector_share, prov.IM, map), char(opt.NumericClass));
targets.EX = cast(allocate_with_sector_share_2020(weightSpec.sector_share, prov.EX, map), char(opt.NumericClass));
targets.error = cast(allocate_with_sector_share_2020(weightSpec.sector_share, prov.error, map), char(opt.NumericClass));

baselineYOut = m29_downscale_city_y_2020_baseline(city, prov, map, ...
    'WeightSpec', weightSpec, ...
    'ProxyTable', opt.ProxyTable, ...
    'Eta', opt.Eta, ...
    'NumericClass', char(opt.NumericClass), ...
    'Epsilon', opt.Epsilon, ...
    'Validate', logical(opt.Validate));
baselineYColByFD = build_y_col_by_fd(double(baselineYOut.Y), Nc, F);

switch lower(char(opt.YMode))
    case 'baseline'
        yOut = baselineYOut;
    case 'factorized'
        yOut = m30_downscale_city_y_2020_factorized(city, prov, map, opt.FactorizedParams, ...
            'TargetX', double(targets.X), ...
            'TargetYColByFD', baselineYColByFD, ...
            'ProxyTable', opt.ProxyTable, ...
            'NumericClass', char(opt.NumericClass), ...
            'Epsilon', opt.Epsilon, ...
            'Validate', logical(opt.Validate));
    case 'hybrid'
        yOut = m31_downscale_city_y_2020_hybrid(city, prov, map, opt.FactorizedParams, opt.HybridParams, ...
            'TargetX', double(targets.X), ...
            'TargetYColByFD', baselineYColByFD, ...
            'WeightSpec', weightSpec, ...
            'ProxyTable', opt.ProxyTable, ...
            'Eta', opt.Eta, ...
            'NumericClass', char(opt.NumericClass), ...
            'Epsilon', opt.Epsilon, ...
            'TopSupportCount', opt.TopSupportCount, ...
            'BaselineY', baselineYOut, ...
            'Validate', logical(opt.Validate));
    otherwise
        error('m22_build_city_targets_2020_consistent:UnknownYMode', ...
            'Unsupported YMode: %s', string(opt.YMode));
end

targets.YResult = yOut;
targets.Y_city = cast(double(yOut.Y), char(opt.NumericClass));
targets.Y_row_by_fd = cast(build_y_row_by_fd(double(targets.Y_city), F), char(opt.NumericClass));
targets.Y_col_by_fd = cast(build_y_col_by_fd(double(targets.Y_city), Nc, F), char(opt.NumericClass));

zRowTarget = double(targets.X) - sum(double(targets.Y_row_by_fd), 2) - double(targets.EX) - double(targets.error);
zColTarget = double(targets.X) - double(targets.VA) - double(targets.IM);
validate_nonnegative_2020(zRowTarget, 'Z_row_target', opt.NegativeTol);
validate_nonnegative_2020(zColTarget, 'Z_col_target', opt.NegativeTol);
targets.Z_row_target = cast(max(zRowTarget, 0), char(opt.NumericClass));
targets.Z_col_target = cast(max(zColTarget, 0), char(opt.NumericClass));
targets.prov_Z_row_target = double(map.A * double(targets.Z_row_target));
targets.prov_Z_col_target = double(map.A * double(targets.Z_col_target));

targets.Diagnostics = struct();
targets.Diagnostics.prov_X_inf = inf_gap_2020(map.A * double(targets.X), double(prov.X));
targets.Diagnostics.prov_VA_inf = inf_gap_2020(map.A * double(targets.VA), double(prov.VA));
targets.Diagnostics.prov_IM_inf = inf_gap_2020(map.A * double(targets.IM), double(prov.IM));
targets.Diagnostics.prov_EX_inf = inf_gap_2020(map.A * double(targets.EX), double(prov.EX));
targets.Diagnostics.prov_error_inf = inf_gap_2020(map.A * double(targets.error), double(prov.error));
targets.Diagnostics.prov_Y_inf = inf_gap_2020(map.A * double(targets.Y_city) * map.B', double(prov.Y));
targets.Diagnostics.prov_Z_row_inf = inf_gap_2020(double(targets.prov_Z_row_target), sum(double(prov.Z), 2));
targets.Diagnostics.prov_Z_col_inf = inf_gap_2020(double(targets.prov_Z_col_target), sum(double(prov.Z), 1)');
targets.Diagnostics.prov_Z_inf = max(targets.Diagnostics.prov_Z_row_inf, targets.Diagnostics.prov_Z_col_inf);
targets.Diagnostics.row_identity_max = max(abs(double(targets.X) - ...
    (double(targets.Z_row_target) + sum(double(targets.Y_row_by_fd), 2) + double(targets.EX) + double(targets.error))));
targets.Diagnostics.col_identity_max = max(abs(double(targets.X) - ...
    (double(targets.Z_col_target) + double(targets.VA) + double(targets.IM))));

if logical(opt.Validate)
    assert(targets.Diagnostics.prov_X_inf <= 1e-6, 'm22_build_city_targets_2020_consistent:ProvXMismatch', ...
        'City 2020 X targets do not aggregate back to provincial 2020 totals.');
    assert(targets.Diagnostics.prov_VA_inf <= 1e-6, 'm22_build_city_targets_2020_consistent:ProvVAMismatch', ...
        'City 2020 VA targets do not aggregate back to provincial 2020 totals.');
    assert(targets.Diagnostics.prov_IM_inf <= 1e-6, 'm22_build_city_targets_2020_consistent:ProvIMMismatch', ...
        'City 2020 IM targets do not aggregate back to provincial 2020 totals.');
    assert(targets.Diagnostics.prov_EX_inf <= 1e-6, 'm22_build_city_targets_2020_consistent:ProvEXMismatch', ...
        'City 2020 EX targets do not aggregate back to provincial 2020 totals.');
    assert(targets.Diagnostics.prov_Y_inf <= 1e-6, 'm22_build_city_targets_2020_consistent:ProvYMismatch', ...
        'City 2020 Y targets do not aggregate back to provincial 2020 totals.');
end
end

function city = cast_city_to_double(city)
fields = ["Z","Y","VA","IM","EX","X","error"];
for i = 1:numel(fields)
    if isfield(city, fields(i))
        city.(fields(i)) = double(city.(fields(i)));
    end
end
end

function prov = cast_prov_to_double(prov)
fields = ["Z","Y","VA","IM","EX","X","error"];
for i = 1:numel(fields)
    if isfield(prov, fields(i))
        prov.(fields(i)) = double(prov.(fields(i)));
    else
        prov.(fields(i)) = zeros(size(prov.X));
    end
end
end

function weightSpec = build_weight_spec_2020(city, proxyTable, eta, map, epsilon)
NS = numel(city.X);
Nc = map.numCities;
F = map.numFD;
weightSpec = struct();
weightSpec.city_sector = ones(NS, 1);
weightSpec.fd_city = ones(Nc, F);
if ~isempty(proxyTable)
    proxy = normalize_proxy_input_2020(proxyTable, Nc);
    sectorGroup = sector_group_key_2020(map.numSectors);
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
weightSpec.sector_share = build_sector_share_2020(city.X, weightSpec.city_sector, map, epsilon);
weightSpec.fd_city_share = build_fd_city_share_2020(city, weightSpec.fd_city, map, epsilon);
end

function proxy = normalize_proxy_input_2020(proxyInput, Nc)
proxy = struct();
proxy.city_group = ones(Nc, 3);
proxy.fd = ones(Nc, 5);
if isnumeric(proxyInput)
    if size(proxyInput, 1) ~= Nc || size(proxyInput, 2) < 3
        error('m22_build_city_targets_2020_consistent:InvalidProxyMatrix', ...
            'ProxyTable matrix should be Nc x 3 or wider.');
    end
    proxy.city_group = double(proxyInput(:, 1:3));
    if size(proxyInput, 2) >= 8
        proxy.fd = double(proxyInput(:, 4:8));
    end
    return;
end
if ~istable(proxyInput)
    error('m22_build_city_targets_2020_consistent:InvalidProxyType', ...
        'ProxyTable must be numeric or table.');
end
vars = lower(string(proxyInput.Properties.VariableNames));
proxy.city_group(:, 1) = find_proxy_column_2020(proxyInput, vars, ["g1","agri","primary","primary_gdp"], Nc);
proxy.city_group(:, 2) = find_proxy_column_2020(proxyInput, vars, ["g2","industry","secondary","industrial"], Nc);
proxy.city_group(:, 3) = find_proxy_column_2020(proxyInput, vars, ["g3","services","tertiary","retail"], Nc);
proxy.fd(:, 1) = find_proxy_column_2020(proxyInput, vars, ["fd1","rural","rural_cons"], Nc);
proxy.fd(:, 2) = find_proxy_column_2020(proxyInput, vars, ["fd2","urban","urban_cons"], Nc);
proxy.fd(:, 3) = find_proxy_column_2020(proxyInput, vars, ["fd3","gov","government"], Nc);
proxy.fd(:, 4) = find_proxy_column_2020(proxyInput, vars, ["fd4","fai","investment"], Nc);
proxy.fd(:, 5) = find_proxy_column_2020(proxyInput, vars, ["fd5","inventory","stock"], Nc);
end

function values = find_proxy_column_2020(tbl, vars, candidates, Nc)
values = ones(Nc, 1);
for i = 1:numel(candidates)
    idx = find(vars == lower(string(candidates(i))), 1, 'first');
    if ~isempty(idx)
        values = double(tbl{:, idx});
        return;
    end
end
end

function key = sector_group_key_2020(S)
key = ones(S, 1);
key(2:min(28, S)) = 2;
if S >= 29
    key(29:S) = 3;
end
end

function shareVec = build_sector_share_2020(baseVec, weight, map, epsilon)
shareVec = zeros(size(baseVec));
for pIdx = 1:map.numProvinces
    cities = map.city_indices_by_province{pIdx};
    for s = 1:map.numSectors
        cityRows = sector_rows_within_province_2020(cities, s, map.numSectors);
        base = max(double(baseVec(cityRows)), 0) .* max(double(weight(cityRows)), epsilon);
        if sum(base) <= epsilon
            base = max(double(weight(cityRows)), epsilon);
        end
        shareVec(cityRows) = base ./ sum(base);
    end
end
end

function fdShare = build_fd_city_share_2020(city, fdWeight, map, epsilon)
fdShare = zeros(size(fdWeight));
for qIdx = 1:map.numProvinces
    cities = map.city_indices_by_province{qIdx};
    for f = 1:map.numFD
        cols = fd_city_indices_2020(cities, f, map.numFD);
        base = max(sum(double(city.Y(:, cols)), 1)', 0) .* max(double(fdWeight(cities, f)), epsilon);
        if sum(base) <= epsilon
            base = max(double(fdWeight(cities, f)), epsilon);
        end
        fdShare(cities, f) = base ./ sum(base);
    end
end
end

function vec = allocate_with_sector_share_2020(sectorShare, provVec, map)
vec = zeros(size(sectorShare));
for pIdx = 1:map.numProvinces
    cities = map.city_indices_by_province{pIdx};
    provRows = province_sector_indices_2020(pIdx, map.numSectors);
    for s = 1:map.numSectors
        cityRows = sector_rows_within_province_2020(cities, s, map.numSectors);
        vec(cityRows) = double(provVec(provRows(s))) .* double(sectorShare(cityRows));
    end
end
end

function Yrow = build_y_row_by_fd(Y, F)
Yrow = zeros(size(Y, 1), F);
for f = 1:F
    cols = f:F:size(Y, 2);
    Yrow(:, f) = sum(double(Y(:, cols)), 2);
end
end

function Ycol = build_y_col_by_fd(Y, Nc, F)
Ycol = zeros(Nc, F);
for f = 1:F
    Ycol(:, f) = sum(double(Y(:, f:F:end)), 1)';
end
end

function validate_nonnegative_2020(vec, labelText, negativeTol)
if min(vec) < -negativeTol
    error('m22_build_city_targets_2020_consistent:NegativeTarget', ...
        '%s contains materially negative values.', labelText);
end
end

function idx = sector_rows_within_province_2020(cityIndices, sectorIdx, S)
idx = zeros(numel(cityIndices), 1);
for i = 1:numel(cityIndices)
    idx(i) = (cityIndices(i) - 1) * S + sectorIdx;
end
end

function idx = province_sector_indices_2020(provinceIdx, S)
idx = ((provinceIdx - 1) * S + 1):(provinceIdx * S);
idx = idx(:);
end

function idx = fd_city_indices_2020(cityIndices, fdIndex, F)
idx = zeros(numel(cityIndices), 1);
for i = 1:numel(cityIndices)
    idx(i) = (cityIndices(i)-1) * F + fdIndex;
end
end

function value = inf_gap_2020(A, B)
value = max(abs(double(A(:)) - double(B(:))));
end
