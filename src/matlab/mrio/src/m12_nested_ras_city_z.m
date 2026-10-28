function out = m12_nested_ras_city_z(seedInput, rowTarget, colTarget, varargin)
% M12_NESTED_RAS_CITY_Z
% m12 nested ras city z

p = inputParser;
p.addRequired('seedInput', @isstruct);
p.addRequired('rowTarget', @(x) isnumeric(x) && isvector(x));
p.addRequired('colTarget', @(x) isnumeric(x) && isvector(x));
p.addParameter('MaxIter', 200, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.addParameter('TolRow', 1e-6, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.addParameter('TolCol', 1e-6, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.addParameter('TolBlock', 1e-8, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.parse(seedInput, rowTarget, colTarget, varargin{:});
opt = p.Results;

if ~isfield(seedInput, 'blocks') || ~isfield(seedInput, 'Mapping') || ~isfield(seedInput, 'targetZ')
    error('m12_nested_ras_city_z:invalidSeed', ...
        'seedInput 必须来自 build_seed_city_z_2020，至少包含 blocks / Mapping / targetZ。');
end

blocks = seedInput.blocks;
map = seedInput.Mapping;
targetZ = double(seedInput.targetZ);
rowTarget = double(rowTarget(:));
colTarget = double(colTarget(:));

NS = numel(rowTarget);
if numel(colTarget) ~= NS
    error('m12_nested_ras_city_z:targetSizeMismatch', ...
        'rowTarget 长度为 %d，但 colTarget 长度为 %d。', NS, numel(colTarget));
end

Np = map.numProvinces;
S = map.numSectors;
logIter = zeros(opt.MaxIter, 4);
converged = false;

for iter = 1:opt.MaxIter
    rowSum = zeros(NS, 1);
    for pIdx = 1:Np
        rowIdx = city_sector_indices(map.city_indices_by_province{pIdx}, S);
        partial = zeros(numel(rowIdx), 1);
        for qIdx = 1:Np
            partial = partial + sum(double(blocks{pIdx, qIdx}), 2);
        end
        rowSum(rowIdx) = partial;
    end
    rowScale = safe_ratio(rowTarget, rowSum);
    blocks = apply_row_scaling(blocks, map, rowScale);

    colSum = zeros(NS, 1);
    for qIdx = 1:Np
        colIdx = city_sector_indices(map.city_indices_by_province{qIdx}, S);
        partial = zeros(numel(colIdx), 1);
        for pIdx = 1:Np
            partial = partial + sum(double(blocks{pIdx, qIdx}), 1)';
        end
        colSum(colIdx) = partial;
    end
    colScale = safe_ratio(colTarget, colSum);
    blocks = apply_col_scaling(blocks, map, colScale);

    blockErr = 0;
    for pIdx = 1:Np
        npCity = numel(map.city_indices_by_province{pIdx});
        provRows = province_sector_indices(pIdx, S);
        for qIdx = 1:Np
            nqCity = numel(map.city_indices_by_province{qIdx});
            provCols = province_sector_indices(qIdx, S);
            tmp = reshape(double(blocks{pIdx, qIdx}), [S, npCity, S, nqCity]);
            current = squeeze(sum(sum(tmp, 2), 4));
            scale = safe_ratio_matrix(targetZ(provRows, provCols), current);
            tmp = tmp .* reshape(scale, [S, 1, S, 1]);
            blocks{pIdx, qIdx} = cast(reshape(tmp, [npCity * S, nqCity * S]), class(blocks{pIdx, qIdx}));
            targetBlock = targetZ(provRows, provCols);
            blockErr = max(blockErr, max(abs(current(:) - targetBlock(:))));
        end
    end

    rowErr = compute_row_error(blocks, map, rowTarget);
    colErr = compute_col_error(blocks, map, colTarget);
    blockErrAfter = compute_block_error(blocks, map, targetZ);
    logIter(iter, :) = [iter, rowErr, colErr, blockErrAfter];

    if rowErr <= opt.TolRow && colErr <= opt.TolCol && blockErrAfter <= opt.TolBlock
        converged = true;
        logIter = logIter(1:iter, :);
        break;
    end
end

if ~converged
    logIter = logIter(1:opt.MaxIter, :);
end

out = struct();
out.blocks = blocks;
out.Mapping = map;
out.targetZ = targetZ;
out.Diagnostics = struct();
out.Diagnostics.converged = converged;
out.Diagnostics.logTable = array2table(logIter, ...
    'VariableNames', {'iter','row_err','col_err','block_err'});
end

function blocks = apply_row_scaling(blocks, map, rowScale)
Np = map.numProvinces;
S = map.numSectors;
for pIdx = 1:Np
    rowIdx = city_sector_indices(map.city_indices_by_province{pIdx}, S);
    npCity = numel(map.city_indices_by_province{pIdx});
    factor = reshape(rowScale(rowIdx), [S, npCity]);
    for qIdx = 1:Np
        nqCity = numel(map.city_indices_by_province{qIdx});
        tmp = reshape(double(blocks{pIdx, qIdx}), [S, npCity, S, nqCity]);
        tmp = tmp .* reshape(factor, [S, npCity, 1, 1]);
        blocks{pIdx, qIdx} = cast(reshape(tmp, [npCity * S, nqCity * S]), class(blocks{pIdx, qIdx}));
    end
end
end

function blocks = apply_col_scaling(blocks, map, colScale)
Np = map.numProvinces;
S = map.numSectors;
for qIdx = 1:Np
    colIdx = city_sector_indices(map.city_indices_by_province{qIdx}, S);
    nqCity = numel(map.city_indices_by_province{qIdx});
    factor = reshape(colScale(colIdx), [S, nqCity]);
    for pIdx = 1:Np
        npCity = numel(map.city_indices_by_province{pIdx});
        tmp = reshape(double(blocks{pIdx, qIdx}), [S, npCity, S, nqCity]);
        tmp = tmp .* reshape(factor, [1, 1, S, nqCity]);
        blocks{pIdx, qIdx} = cast(reshape(tmp, [npCity * S, nqCity * S]), class(blocks{pIdx, qIdx}));
    end
end
end

function err = compute_row_error(blocks, map, rowTarget)
Np = map.numProvinces;
S = map.numSectors;
err = 0;
for pIdx = 1:Np
    rowIdx = city_sector_indices(map.city_indices_by_province{pIdx}, S);
    partial = zeros(numel(rowIdx), 1);
    for qIdx = 1:Np
        partial = partial + sum(double(blocks{pIdx, qIdx}), 2);
    end
    err = max(err, max(abs(partial - rowTarget(rowIdx))));
end
end

function err = compute_col_error(blocks, map, colTarget)
Np = map.numProvinces;
S = map.numSectors;
err = 0;
for qIdx = 1:Np
    colIdx = city_sector_indices(map.city_indices_by_province{qIdx}, S);
    partial = zeros(numel(colIdx), 1);
    for pIdx = 1:Np
        partial = partial + sum(double(blocks{pIdx, qIdx}), 1)';
    end
    err = max(err, max(abs(partial - colTarget(colIdx))));
end
end

function blockErr = compute_block_error(blocks, map, targetZ)
Np = map.numProvinces;
S = map.numSectors;
blockErr = 0;
for pIdx = 1:Np
    npCity = numel(map.city_indices_by_province{pIdx});
    provRows = province_sector_indices(pIdx, S);
    for qIdx = 1:Np
        nqCity = numel(map.city_indices_by_province{qIdx});
        provCols = province_sector_indices(qIdx, S);
        tmp = reshape(double(blocks{pIdx, qIdx}), [S, npCity, S, nqCity]);
        agg = squeeze(sum(sum(tmp, 2), 4));
        targetBlock = targetZ(provRows, provCols);
        blockErr = max(blockErr, max(abs(agg(:) - targetBlock(:))));
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

function ratio = safe_ratio(target, current)
ratio = ones(size(target));
mask = abs(current) > 0;
ratio(mask) = target(mask) ./ current(mask);
ratio(~mask & abs(target) > 0) = 0;
end

function ratio = safe_ratio_matrix(target, current)
ratio = ones(size(target));
mask = abs(current) > 0;
ratio(mask) = target(mask) ./ current(mask);
ratio(~mask & abs(target) > 0) = 0;
end
