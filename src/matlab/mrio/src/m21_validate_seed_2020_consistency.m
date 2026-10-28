function auditRow = m21_validate_seed_2020_consistency(seed, provTarget, mapping, varargin)
% M21_VALIDATE_SEED_2020_CONSISTENCY
% Check whether the 2020 city seed aggregates exactly to provincial 2020 Z blocks.

p = inputParser;
p.addRequired('seed', @isstruct);
p.addRequired('provTarget', @isstruct);
p.addRequired('mapping', @isstruct);
p.addParameter('StageName', "seed", @(x) ischar(x) || isstring(x));
p.addParameter('Note', "", @(x) ischar(x) || isstring(x));
p.addParameter('OutputPath', "", @(x) ischar(x) || isstring(x));
p.addParameter('Append', true, @(x) islogical(x) || isnumeric(x));
p.addParameter('Tol', 1e-6, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.addParameter('Validate', true, @(x) islogical(x) || isnumeric(x));
p.parse(seed, provTarget, mapping, varargin{:});
opt = p.Results;

provZInf = compute_seed_block_gap(seed.blocks, mapping, double(provTarget.Z));
totalZ = sum_blocks_total(seed.blocks);
auditRow = table( ...
    string(opt.StageName), ...
    "seed", ...
    provZInf, ...
    totalZ, ...
    string(opt.Note), ...
    'VariableNames', {'stage','payload_kind','prov_Z_inf','total_Z','note'});

write_seed_row(auditRow, string(opt.OutputPath), logical(opt.Append));

if logical(opt.Validate)
    assert(auditRow.prov_Z_inf <= opt.Tol, ...
        'm21_validate_seed_2020_consistency:ProvZFailed', ...
        '2020 seed failed prov_Z_inf tolerance.');
end
end

function gap = compute_seed_block_gap(blocks, map, provZ)
gap = 0;
for pIdx = 1:map.numProvinces
    npCity = numel(map.city_indices_by_province{pIdx});
    provRows = province_sector_indices_seed_2020(pIdx, map.numSectors);
    for qIdx = 1:map.numProvinces
        nqCity = numel(map.city_indices_by_province{qIdx});
        provCols = province_sector_indices_seed_2020(qIdx, map.numSectors);
        tmp = reshape(double(blocks{pIdx, qIdx}), [map.numSectors, npCity, map.numSectors, nqCity]);
        agg = squeeze(sum(sum(tmp, 2), 4));
        targetBlock = provZ(provRows, provCols);
        gap = max(gap, max(abs(agg(:) - targetBlock(:))));
    end
end
end

function totalZ = sum_blocks_total(blocks)
totalZ = 0;
for i = 1:numel(blocks)
    totalZ = totalZ + sum(double(blocks{i}), 'all');
end
end

function idx = province_sector_indices_seed_2020(provinceIdx, S)
idx = ((provinceIdx - 1) * S + 1):(provinceIdx * S);
idx = idx(:);
end

function write_seed_row(row, outputPath, appendMode)
if strlength(strtrim(outputPath)) == 0
    return;
end
if appendMode && exist(outputPath, 'file')
    existing = readtable(outputPath, 'TextType', 'string');
    writetable([existing; row], outputPath); %#ok<AGROW>
else
    writetable(row, outputPath);
end
end
