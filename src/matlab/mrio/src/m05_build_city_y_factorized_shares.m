function out = m05_build_city_y_factorized_shares(cityBase, targetX, targetYColByFD, mapping, params, varargin)
% M05_BUILD_CITY_Y_FACTORIZED_SHARES
% Build factorized origin and destination shares for Y allocation.

p = inputParser;
p.addRequired('cityBase', @(x) isstruct(x) && isfield(x, 'Y') && isfield(x, 'X'));
p.addRequired('targetX', @(x) isnumeric(x) && isvector(x));
p.addRequired('targetYColByFD', @(x) isnumeric(x));
p.addRequired('mapping', @(x) isstruct(x) && isfield(x, 'city_indices_by_province'));
p.addRequired('params', @isstruct);
p.addParameter('ProxyTable', [], @(x) true);
p.addParameter('Epsilon', 1e-12, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.parse(cityBase, targetX, targetYColByFD, mapping, params, varargin{:});
opt = p.Results;

city = cityBase;
map = mapping;
targetX = double(targetX(:));
F = map.numFD;
Nc = map.numCities;
S = map.numSectors;

if numel(targetX) ~= Nc * S
    error('m05_build_city_y_factorized_shares:TargetXSizeMismatch', ...
        'targetX length is incompatible with mapping.');
end
if ~isequal(size(targetYColByFD), [Nc, F])
    error('m05_build_city_y_factorized_shares:TargetYColSizeMismatch', ...
        'targetYColByFD must be Nc x F.');
end

params = normalize_params(params, S, F);
u = zeros(Nc * S, 1);
v = zeros(Nc, F);
histFDShare = build_hist_fd_city_share(city, map, opt.Epsilon);
proxyShare = build_proxy_fd_city_share(targetX, targetYColByFD, map, opt.ProxyTable, opt.Epsilon);

for pIdx = 1:map.numProvinces
    cities = map.city_indices_by_province{pIdx};
    for s = 1:S
        rows = sector_rows_within_province(cities, s, S);
        base = (max(targetX(rows), 0) + opt.Epsilon) .^ params.alpha(s);
        u(rows) = base ./ sum(base);
    end
end

for qIdx = 1:map.numProvinces
    cities = map.city_indices_by_province{qIdx};
    for f = 1:F
        histBase = max(histFDShare(cities, f), 0) + opt.Epsilon;
        proxyBase = max(proxyShare(cities, f), 0) + opt.Epsilon;
        weight = histBase .^ params.beta(f) .* proxyBase .^ params.gamma(f);
        v(cities, f) = weight ./ sum(weight);
    end
end

out = struct();
out.u = u;
out.v = v;
out.histFDShare = histFDShare;
out.proxyFDShare = proxyShare;
out.params = params;
end

function params = normalize_params(params, S, F)
if ~isfield(params, 'alpha') || isempty(params.alpha)
    params.alpha = ones(S, 1);
else
    params.alpha = double(params.alpha(:));
    if numel(params.alpha) == 1
        params.alpha = repmat(params.alpha, S, 1);
    end
end
if ~isfield(params, 'beta') || isempty(params.beta)
    params.beta = ones(F, 1);
else
    params.beta = double(params.beta(:));
end
if ~isfield(params, 'gamma') || isempty(params.gamma)
    params.gamma = zeros(F, 1);
else
    params.gamma = double(params.gamma(:));
end
end

function histFDShare = build_hist_fd_city_share(city, map, epsilon)
Nc = map.numCities;
F = map.numFD;
histFDShare = zeros(Nc, F);
for qIdx = 1:map.numProvinces
    cities = map.city_indices_by_province{qIdx};
    for f = 1:F
        cols = fd_city_indices(cities, f, F);
        base = sum(double(city.Y(:, cols)), 1)' + epsilon;
        histFDShare(cities, f) = base ./ sum(base);
    end
end
end

function proxyShare = build_proxy_fd_city_share(targetX, targetYColByFD, map, proxyTable, epsilon)
Nc = map.numCities;
F = map.numFD;
proxyShare = zeros(Nc, F);
extProxy = [];
if ~isempty(proxyTable)
    extProxy = normalize_proxy_table(proxyTable, Nc, F);
end

cityOutput = reshape(sum(reshape(targetX, map.numSectors, [])', 2), Nc, 1);
for qIdx = 1:map.numProvinces
    cities = map.city_indices_by_province{qIdx};
    outShare = normalize_positive(cityOutput(cities), epsilon);
    for f = 1:F
        fdShare = normalize_positive(targetYColByFD(cities, f), epsilon);
        base = sqrt(outShare .* fdShare);
        if ~isempty(extProxy)
            base = base .* normalize_positive(extProxy(cities, f), epsilon);
        end
        proxyShare(cities, f) = normalize_positive(base, epsilon);
    end
end
end

function proxy = normalize_proxy_table(proxyInput, Nc, F)
proxy = ones(Nc, F);
if isnumeric(proxyInput)
    if size(proxyInput, 1) ~= Nc || size(proxyInput, 2) < F
        error('m05_build_city_y_factorized_shares:InvalidProxyMatrix', ...
            'Numeric proxy must be Nc x F or wider.');
    end
    proxy = double(proxyInput(:, 1:F));
    return;
end
if ~istable(proxyInput)
    error('m05_build_city_y_factorized_shares:InvalidProxyType', ...
        'ProxyTable must be numeric or table.');
end
vars = lower(string(proxyInput.Properties.VariableNames));
for f = 1:F
    candidates = ["fd" + string(f), "proxy_fd" + string(f)];
    for i = 1:numel(candidates)
        idx = find(vars == lower(candidates(i)), 1, 'first');
        if ~isempty(idx)
            proxy(:, f) = double(proxyInput{:, idx});
            break;
        end
    end
end
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

function share = normalize_positive(vec, epsilon)
vec = max(double(vec(:)), 0) + epsilon;
share = vec ./ sum(vec);
end
