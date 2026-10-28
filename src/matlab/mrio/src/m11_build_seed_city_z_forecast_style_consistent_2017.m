function seed = m11_build_seed_city_z_forecast_style_consistent_2017(city2015, prov2017, mapping, varargin)
% M11_BUILD_SEED_CITY_Z_FORECAST_STYLE_CONSISTENT_2017
% Build a 2015-based city Z seed that aggregates exactly to official provincial 2017 Z.

p = inputParser;
p.addRequired('city2015', @(x) isstruct(x) && isfield(x, 'Z'));
p.addRequired('prov2017', @(x) isstruct(x) && isfield(x, 'Z'));
p.addRequired('mapping', @(x) isstruct(x) && isfield(x, 'city_indices_by_province'));
p.addParameter('NumericClass', "double", @(x) any(strcmpi(string(x), ["single","double"])));
p.addParameter('Epsilon', 1e-12, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.addParameter('Validate', true, @(x) islogical(x) || isnumeric(x));
p.parse(city2015, prov2017, mapping, varargin{:});
opt = p.Results;

city = city2015;
prov = prov2017;
map = mapping;
blocks = cell(map.numProvinces, map.numProvinces);

for pIdx = 1:map.numProvinces
    rowCities = map.city_indices_by_province{pIdx};
    rowIdx = city_sector_indices(rowCities, map.numSectors);
    npCity = numel(rowCities);
    provRows = province_sector_indices(pIdx, map.numSectors);
    for qIdx = 1:map.numProvinces
        colCities = map.city_indices_by_province{qIdx};
        colIdx = city_sector_indices(colCities, map.numSectors);
        nqCity = numel(colCities);
        provCols = province_sector_indices(qIdx, map.numSectors);

        rawBlock = double(city.Z(rowIdx, colIdx));
        block = zeros(size(rawBlock));
        for i = 1:map.numSectors
            rowLocal = i:map.numSectors:(npCity * map.numSectors);
            for j = 1:map.numSectors
                colLocal = j:map.numSectors:(nqCity * map.numSectors);
                slice = max(rawBlock(rowLocal, colLocal), 0);
                targetValue = double(prov.Z(provRows(i), provCols(j)));
                currentValue = sum(slice, 'all');
                if currentValue > opt.Epsilon
                    block(rowLocal, colLocal) = slice .* (targetValue / currentValue);
                else
                    block(rowLocal, colLocal) = allocate_uniform_slice(size(slice), targetValue);
                end
            end
        end
        blocks{pIdx, qIdx} = cast(block, char(opt.NumericClass));
    end
end

seed = struct();
seed.blocks = blocks;
seed.Mapping = map;
seed.targetZ = double(prov.Z);
seed.NumericClass = char(opt.NumericClass);
seed.Diagnostics = struct();
seed.Diagnostics.initialBlockInf = compute_block_error(blocks, map, double(prov.Z));
seed.Diagnostics.mode = "forecast_style_consistent_2017";

if logical(opt.Validate)
    assert(seed.Diagnostics.initialBlockInf <= 1e-6, ...
        'm11_build_seed_city_z_forecast_style_consistent_2017:ProvZMismatch', ...
        'The seed does not aggregate back to official prov2017 Z.');
end
end

function values = allocate_uniform_slice(sliceSize, targetValue)
if targetValue == 0
    values = zeros(sliceSize);
else
    values = ones(sliceSize) .* (targetValue / prod(sliceSize));
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

function blockInf = compute_block_error(blocks, map, provZ)
blockInf = 0;
for pIdx = 1:map.numProvinces
    npCity = numel(map.city_indices_by_province{pIdx});
    provRows = province_sector_indices(pIdx, map.numSectors);
    for qIdx = 1:map.numProvinces
        nqCity = numel(map.city_indices_by_province{qIdx});
        provCols = province_sector_indices(qIdx, map.numSectors);
        tmp = reshape(double(blocks{pIdx, qIdx}), [map.numSectors, npCity, map.numSectors, nqCity]);
        agg = squeeze(sum(sum(tmp, 2), 4));
        targetBlock = provZ(provRows, provCols);
        blockInf = max(blockInf, max(abs(agg(:) - targetBlock(:))));
    end
end
end
