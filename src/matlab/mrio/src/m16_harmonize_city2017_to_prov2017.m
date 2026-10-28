function out = m16_harmonize_city2017_to_prov2017(cityInput, provInput, mappingInput, varargin)
% M16_HARMONIZE_CITY2017_TO_PROV2017
% Build a harmonized 2017 city MRIO target that stays close to the raw city table
%   while aggregating exactly to the official provincial 2017 target.

p = inputParser;
p.addRequired('cityInput');
p.addRequired('provInput');
p.addRequired('mappingInput');
p.addParameter('OutputDir', "", @(x) ischar(x) || isstring(x));
p.addParameter('epsilon', 1e-12, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.addParameter('useRowReconciledX', true, @(x) islogical(x) || isnumeric(x));
p.addParameter('preserveEX', true, @(x) islogical(x) || isnumeric(x));
p.addParameter('preserveVA', true, @(x) islogical(x) || isnumeric(x));
p.addParameter('preserveIM', true, @(x) islogical(x) || isnumeric(x));
p.parse(cityInput, provInput, mappingInput, varargin{:});
opt = p.Results;

cityRaw = resolve_city_input(cityInput);
prov = resolve_prov_input(provInput);
mapping = resolve_mapping(mappingInput, cityRaw, prov);
outputDir = resolve_output_dir(opt.OutputDir);
ensure_dir(outputDir);

auditOut = m32_audit_city_source_2017(cityRaw, 'OutputDir', outputDir, 'FilePrefix', 'city2017_source');
if logical(opt.useRowReconciledX)
    cityBase = auditOut.cityRowReconciled;
else
    cityBase = cityRaw;
end

[Zharm, zDiag] = harmonize_z_blocks(cityRaw.Z, prov.Z, mapping, opt.epsilon);
[Yharm, yDiag] = harmonize_y_blocks(cityRaw.Y, prov.Y, mapping, opt.epsilon);
EXharm = harmonize_component(cityBase.EX, prov.EX, mapping, logical(opt.preserveEX), opt.epsilon);
VAharm = harmonize_component(cityBase.VA, prov.VA, mapping, logical(opt.preserveVA), opt.epsilon);
IMharm = harmonize_component(cityBase.IM, prov.IM, mapping, logical(opt.preserveIM), opt.epsilon);
Xharm = sum(Zharm, 2) + sum(Yharm, 2) + EXharm;
errorHarm = Xharm - (sum(Zharm, 1)' + VAharm + IMharm);

cityHarm = cityBase;
cityHarm.Z = Zharm;
cityHarm.Y = Yharm;
cityHarm.EX = EXharm;
cityHarm.VA = VAharm;
cityHarm.IM = IMharm;
cityHarm.X = Xharm;
cityHarm.error = errorHarm;
cityHarm.Harmonization = struct( ...
    'useRowReconciledX', logical(opt.useRowReconciledX), ...
    'preserveEX', logical(opt.preserveEX), ...
    'preserveVA', logical(opt.preserveVA), ...
    'preserveIM', logical(opt.preserveIM), ...
    'epsilon', opt.epsilon);

aggHarm = m14_aggregate_city_to_province(cityHarm, mapping, 'Validate', false).aggregated;
validationTable = build_aggregation_validation_table(aggHarm, prov);
summaryTable = build_harmonization_summary(cityRaw, cityHarm, aggHarm, prov, zDiag, yDiag);

validationPath = fullfile(outputDir, 'city2017_harmonization_aggregation_check.csv');
summaryPath = fullfile(outputDir, 'city2017_harmonization_summary.csv');
writetable(validationTable, validationPath);
writetable(summaryTable, summaryPath);

out = struct();
out.city2017_harm = cityHarm;
out.diagnostics = struct();
out.diagnostics.Z = zDiag;
out.diagnostics.Y = yDiag;
out.diagnostics.validationTable = validationTable;
out.diagnostics.summaryTable = summaryTable;
out.diagnostics.audit = auditOut.summaryTable;
out.outputFiles = struct( ...
    'aggregationCheck', string(validationPath), ...
    'summary', string(summaryPath), ...
    'sourceAuditSummary', auditOut.outputFiles.summary);
end

function [Zharm, diag] = harmonize_z_blocks(rawZ, provZ, mapping, epsilon)
Np = mapping.numProvinces;
S = mapping.numSectors;
if issparse(rawZ)
    Zharm = sparse(size(rawZ, 1), size(rawZ, 2));
else
    Zharm = zeros(size(rawZ));
end
scaleSummary = zeros(Np * Np * S * S, 6);
cursor = 1;

for pIdx = 1:Np
    rowCities = mapping.city_indices_by_province{pIdx};
    rowIdx = city_sector_indices(rowCities, S);
    provRows = province_sector_indices(pIdx, S);
    for qIdx = 1:Np
        colCities = mapping.city_indices_by_province{qIdx};
        colIdx = city_sector_indices(colCities, S);
        provCols = province_sector_indices(qIdx, S);
        rawBlock = double(rawZ(rowIdx, colIdx));
        harmBlock = zeros(size(rawBlock));

        for i = 1:S
            rowLocal = i:S:numel(rowIdx);
            for j = 1:S
                colLocal = j:S:numel(colIdx);
                rawSlice = rawBlock(rowLocal, colLocal);
                targetValue = double(provZ(provRows(i), provCols(j)));
                currentValue = sum(rawSlice, 'all');

                if currentValue > epsilon
                    scale = targetValue / currentValue;
                    harmSlice = rawSlice .* scale;
                else
                    scale = 0;
                    harmSlice = allocate_uniform_slice(size(rawSlice), targetValue);
                end

                harmBlock(rowLocal, colLocal) = harmSlice;
                scaleSummary(cursor, :) = [pIdx, qIdx, i, j, currentValue, scale];
                cursor = cursor + 1;
            end
        end

        if issparse(Zharm)
            Zharm(rowIdx, colIdx) = sparse(harmBlock);
        else
            Zharm(rowIdx, colIdx) = harmBlock;
        end
    end
end

scaleSummary = scaleSummary(1:cursor-1, :);
diag = struct();
diag.scaleTable = array2table(scaleSummary, ...
    'VariableNames', {'row_province_id','col_province_id','row_sector_id','col_sector_id','raw_block_total','scale'});
diag.maxAbsProvGap = max(abs((mapping.A * Zharm * mapping.A') - double(provZ)), [], 'all');
diag.note = "Each province-pair x sector-pair block is rescaled independently.";
end

function [Yharm, diag] = harmonize_y_blocks(rawY, provY, mapping, epsilon)
Np = mapping.numProvinces;
S = mapping.numSectors;
F = mapping.numFD;
Yharm = zeros(size(rawY));
scaleSummary = zeros(Np * Np * S * F, 6);
cursor = 1;

for pIdx = 1:Np
    rowCities = mapping.city_indices_by_province{pIdx};
    rowIdx = city_sector_indices(rowCities, S);
    provRows = province_sector_indices(pIdx, S);
    for qIdx = 1:Np
        colCities = mapping.city_indices_by_province{qIdx};
        for f = 1:F
            rawCols = fd_city_indices(colCities, f, F);
            provCol = (qIdx - 1) * F + f;
            rawBlock = double(rawY(rowIdx, rawCols));
            harmBlock = zeros(size(rawBlock));

            for i = 1:S
                rowLocal = i:S:numel(rowIdx);
                rawSlice = rawBlock(rowLocal, :);
                targetValue = double(provY(provRows(i), provCol));
                currentValue = sum(rawSlice, 'all');

                if currentValue > epsilon
                    scale = targetValue / currentValue;
                    harmSlice = rawSlice .* scale;
                else
                    scale = 0;
                    harmSlice = allocate_uniform_slice(size(rawSlice), targetValue);
                end

                harmBlock(rowLocal, :) = harmSlice;
                scaleSummary(cursor, :) = [pIdx, qIdx, i, f, currentValue, scale];
                cursor = cursor + 1;
            end

            Yharm(rowIdx, rawCols) = harmBlock;
        end
    end
end

scaleSummary = scaleSummary(1:cursor-1, :);
diag = struct();
diag.scaleTable = array2table(scaleSummary, ...
    'VariableNames', {'origin_province_id','destination_province_id','origin_sector_id','fd_id','raw_block_total','scale'});
diag.maxAbsProvGap = max(abs((mapping.A * Yharm * mapping.B') - double(provY)), [], 'all');
diag.note = "Each origin-province x destination-province x sector x FD block is rescaled independently.";
end

function vecOut = harmonize_component(rawVec, provTarget, mapping, preserveFlag, epsilon)
if ~preserveFlag
    vecOut = double(rawVec(:));
    return;
end

Np = mapping.numProvinces;
S = mapping.numSectors;
vecOut = zeros(size(rawVec(:)));
rawVec = double(rawVec(:));
provTarget = double(provTarget(:));

for pIdx = 1:Np
    cities = mapping.city_indices_by_province{pIdx};
    provRows = province_sector_indices(pIdx, S);
    for i = 1:S
        cityRows = sector_rows_within_province(cities, i, S);
        targetValue = provTarget(provRows(i));
        rawSlice = rawVec(cityRows);
        currentValue = sum(rawSlice);
        if currentValue > epsilon
            vecOut(cityRows) = rawSlice .* (targetValue / currentValue);
        else
            vecOut(cityRows) = allocate_uniform_slice(size(rawSlice), targetValue);
        end
    end
end
end

function validationTable = build_aggregation_validation_table(agg, prov)
metrics = ["Z","Y","EX","VA","IM","X","error"];
validationTable = table();
for i = 1:numel(metrics)
    metric = metrics(i);
    aggValue = double(agg.(metric));
    provValue = double(prov.(metric));
    diffValue = aggValue - provValue;
    T = table( ...
        metric, ...
        max(abs(diffValue), [], 'all'), ...
        sum(abs(diffValue), 'all'), ...
        sum(diffValue, 'all'), ...
        'VariableNames', {'metric','max_abs_gap','sum_abs_gap','sum_signed_gap'});
    validationTable = [validationTable; T]; %#ok<AGROW>
end
end

function summaryTable = build_harmonization_summary(cityRaw, cityHarm, aggHarm, prov, zDiag, yDiag)
summaryTable = table( ...
    ["raw_city_row_identity_max"; ...
     "harm_city_row_identity_max"; ...
     "harm_city_col_identity_max"; ...
     "harm_prov_Z_max_gap"; ...
     "harm_prov_Y_max_gap"; ...
     "harm_prov_X_max_gap"], ...
    [max(abs(double(cityRaw.X) - (sum(double(cityRaw.Z), 2) + sum(double(cityRaw.Y), 2) + double(cityRaw.EX)))); ...
     max(abs(double(cityHarm.X) - (sum(double(cityHarm.Z), 2) + sum(double(cityHarm.Y), 2) + double(cityHarm.EX)))); ...
     max(abs(double(cityHarm.X) - (sum(double(cityHarm.Z), 1)' + double(cityHarm.VA) + double(cityHarm.IM) + double(cityHarm.error)))); ...
     zDiag.maxAbsProvGap; ...
     yDiag.maxAbsProvGap; ...
     max(abs(double(aggHarm.X) - double(prov.X)), [], 'all')], ...
    'VariableNames', {'metric','value'});

officialSheet = "";
if isfield(prov, 'ParserInfo') && isfield(prov.ParserInfo, 'mainSheet')
    officialSheet = string(prov.ParserInfo.mainSheet);
end
summaryTable.note = repmat("2017 harmonization summary", height(summaryTable), 1);
if strlength(officialSheet) > 0
    summaryTable.note = summaryTable.note + " | official_sheet=" + officialSheet;
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

function city = resolve_city_input(cityInput)
if isstruct(cityInput) && isfield(cityInput, 'Z') && isfield(cityInput, 'Y')
    city = cityInput;
    return;
end
if ~(ischar(cityInput) || isstring(cityInput))
    error('m16_harmonize_city2017_to_prov2017:InvalidCityInput', ...
        'cityInput must be a canonical city struct or a MAT path.');
end
city = m01_parse_city_mrio_mat(cityInput, 'Validate', false);
end

function prov = resolve_prov_input(provInput)
if isstruct(provInput) && isfield(provInput, 'MRIO')
    prov = flatten_generic_prov_struct(provInput);
    return;
end
if isstruct(provInput) && isfield(provInput, 'Z') && isfield(provInput, 'Y')
    prov = provInput;
    return;
end
if ~(ischar(provInput) || isstring(provInput))
    error('m16_harmonize_city2017_to_prov2017:InvalidProvInput', ...
        'provInput must be a canonical provincial struct or an Excel path.');
end

provPath = string(provInput);
[~, ~, ext] = fileparts(char(provPath));
switch lower(ext)
    case '.xlsx'
        prov = flatten_generic_prov_struct(m02_parse_prov_mrio_xlsx_generic(provPath, 'Validate', false));
    otherwise
        error('m16_harmonize_city2017_to_prov2017:UnsupportedProvInput', ...
            'Only provincial Excel workbooks are supported here.');
end
end

function prov = flatten_generic_prov_struct(parsed)
prov = struct();
prov.Z = parsed.MRIO.Z;
prov.Y = parsed.MRIO.Y;
prov.F = parsed.MRIO.F;
prov.VA = parsed.MRIO.VA;
prov.IM = parsed.MRIO.IM;
prov.EX = parsed.MRIO.EX;
prov.error = parsed.MRIO.error;
prov.X = parsed.MRIO.X;
prov.provinces = string(parsed.Meta.Province_Name);
prov.sectors = string(parsed.Meta.Sector_Name);
prov.fd_labels = string(parsed.Meta.F_Name);
prov.Diagnostics = parsed.Diagnostics;
prov.ParserInfo = parsed.ParserInfo;
end

function mapping = resolve_mapping(mappingInput, city, prov)
if isstruct(mappingInput) && isfield(mappingInput, 'A') && isfield(mappingInput, 'B')
    mapping = mappingInput;
    return;
end
mapping = m03_build_city_province_mapping(mappingInput, ...
    'NumCities', numel(city.cities), ...
    'NumSectors', numel(city.sectors), ...
    'NumFD', numel(city.fd_labels), ...
    'ProvinceNames', prov.provinces, ...
    'CityNames', city.cities, ...
    'CityNamesCN', safe_city_cn_labels(city));
end

function labels = safe_city_cn_labels(city)
if isfield(city, 'cities_cn')
    labels = string(city.cities_cn);
else
    labels = strings(numel(city.cities), 1);
end
end

function outputDir = resolve_output_dir(outputDir)
outputDir = string(outputDir);
if strlength(strtrim(outputDir)) == 0
    outputDir = string(pwd);
end
end

function ensure_dir(dirPath)
if ~exist(dirPath, 'dir')
    mkdir(dirPath);
end
end
