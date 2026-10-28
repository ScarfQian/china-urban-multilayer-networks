function out = m06_build_city_y_hybrid_shares(baselineY, factorizedY, provTarget, mapping, hybridParams, varargin)
% M06_BUILD_CITY_Y_HYBRID_SHARES
% Mix province-consistent baseline and factorized Y shares block by block.

p = inputParser;
p.addRequired('baselineY', @(x) isnumeric(x));
p.addRequired('factorizedY', @(x) isnumeric(x));
p.addRequired('provTarget', @(x) isstruct(x) && isfield(x, 'Y'));
p.addRequired('mapping', @(x) isstruct(x) && isfield(x, 'city_indices_by_province'));
p.addRequired('hybridParams', @isstruct);
p.addParameter('Epsilon', 1e-12, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.addParameter('TopSupportCount', 3, @(x) isnumeric(x) && isscalar(x) && x >= 1);
p.addParameter('Validate', true, @(x) islogical(x) || isnumeric(x));
p.parse(baselineY, factorizedY, provTarget, mapping, hybridParams, varargin{:});
opt = p.Results;

map = mapping;
baseY = double(baselineY);
factY = double(factorizedY);
prov = provTarget;
params = normalize_hybrid_params(hybridParams, map.numFD);

if ~isequal(size(baseY), size(factY))
    error('m06_build_city_y_hybrid_shares:SizeMismatch', ...
        'baselineY and factorizedY must have the same size.');
end

NS = size(baseY, 1);
NF = size(baseY, 2);
Y = zeros(NS, NF);
blockRows = cell(map.numProvinces * map.numProvinces * map.numSectors * map.numFD, 1);
cursor = 1;

for pIdx = 1:map.numProvinces
    rowCities = map.city_indices_by_province{pIdx};
    rowIdx = city_sector_indices(rowCities, map.numSectors);
    npCity = numel(rowCities);
    provRows = province_sector_indices(pIdx, map.numSectors);
    for qIdx = 1:map.numProvinces
        colCities = map.city_indices_by_province{qIdx};
        for f = 1:map.numFD
            colIdx = fd_city_indices(colCities, f, map.numFD);
            provCol = (qIdx - 1) * map.numFD + f;
            baseBlock = baseY(rowIdx, colIdx);
            factBlock = factY(rowIdx, colIdx);
            block = zeros(size(baseBlock));

            for s = 1:map.numSectors
                rowLocal = s:map.numSectors:(npCity * map.numSectors);
                targetValue = double(prov.Y(provRows(s), provCol));
                shareBase = normalize_share(baseBlock(rowLocal, :), opt.Epsilon);
                shareFact = normalize_share(factBlock(rowLocal, :), opt.Epsilon);
                shareHybrid = mix_block_share(shareBase, shareFact, params, f, opt.TopSupportCount);
                block(rowLocal, :) = shareHybrid .* targetValue;
                metrics = m04_compute_block_share_metrics(shareHybrid(:), shareBase(:), 'Epsilon', opt.Epsilon);
                blockRows{cursor} = {pIdx, qIdx, s, f, params.lambda(f), targetValue, ...
                    metrics.l1_share_distance, metrics.js_divergence, metrics.hellinger_distance}; %#ok<AGROW>
                cursor = cursor + 1;
            end

            Y(rowIdx, colIdx) = block;
        end
    end
end

blockRows = blockRows(1:cursor-1);
Diagnostics = struct();
Diagnostics.prov_Y_inf = max(abs(map.A * Y * map.B' - double(prov.Y)), [], 'all');
Diagnostics.lambda = params.lambda;
Diagnostics.fd4_mode = string(params.fd4_mode);
Diagnostics.fd5_mode = string(params.fd5_mode);
Diagnostics.blockMixTable = cell2table(vertcat(blockRows{:}), ...
    'VariableNames', {'origin_province_id','destination_province_id','origin_sector_id','fd_id', ...
    'lambda_used','block_total','share_l1_vs_baseline','share_jsd_vs_baseline','share_hellinger_vs_baseline'});

if logical(opt.Validate)
    assert(Diagnostics.prov_Y_inf <= 1e-6, ...
        'm06_build_city_y_hybrid_shares:ProvYMismatch', ...
        'Hybrid Y does not aggregate back to provincial totals.');
end

out = struct();
out.Y = Y;
out.Diagnostics = Diagnostics;
out.Params = params;
end

function params = normalize_hybrid_params(params, F)
if ~isfield(params, 'lambda') || isempty(params.lambda)
    params.lambda = 0.5 * ones(F, 1);
else
    params.lambda = double(params.lambda(:));
end
if numel(params.lambda) ~= F
    error('m06_build_city_y_hybrid_shares:LambdaSizeMismatch', ...
        'lambda must have length equal to the number of FD categories.');
end
if ~isfield(params, 'fd4_mode') || strlength(string(params.fd4_mode)) == 0
    params.fd4_mode = "hybrid";
else
    params.fd4_mode = string(params.fd4_mode);
end
if ~isfield(params, 'fd5_mode') || strlength(string(params.fd5_mode)) == 0
    params.fd5_mode = "baseline_only";
else
    params.fd5_mode = string(params.fd5_mode);
end
end

function share = mix_block_share(shareBase, shareFact, params, fdIndex, topSupportCount)
switch fdIndex
    case 4
        if strcmpi(params.fd4_mode, "baseline_only")
            share = shareBase;
            return;
        end
    case 5
        switch lower(string(params.fd5_mode))
            case "baseline_only"
                share = shareBase;
                return;
            case "top_support_preserve"
                share = apply_top_support_preserve(shareBase, shareFact, params.lambda(fdIndex), topSupportCount);
                return;
        end
end

lambda = params.lambda(fdIndex);
share = lambda .* shareBase + (1 - lambda) .* shareFact;
share = share ./ sum(share, 'all');
end

function share = apply_top_support_preserve(shareBase, shareFact, lambda, topSupportCount)
destMass = sum(shareBase, 1);
[~, order] = sort(destMass, 'descend');
keep = false(size(destMass));
keep(order(1:min(topSupportCount, numel(order)))) = true;
mask = repmat(keep, size(shareBase, 1), 1);
mixed = lambda .* shareBase + (1 - lambda) .* shareFact;
mixed(~mask) = 0;
if sum(mixed, 'all') <= 0
    share = shareBase;
else
    share = mixed ./ sum(mixed, 'all');
end
end

function share = normalize_share(block, epsilon)
block = max(double(block), 0) + epsilon;
share = block ./ sum(block, 'all');
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

function idx = fd_city_indices(cityIndices, fdIndex, F)
idx = zeros(numel(cityIndices), 1);
for i = 1:numel(cityIndices)
    idx(i) = (cityIndices(i)-1) * F + fdIndex;
end
end
