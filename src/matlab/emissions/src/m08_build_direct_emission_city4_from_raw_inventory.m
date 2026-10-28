function out = m08_build_direct_emission_city4_from_raw_inventory(standardizedInput, cityMrio4Input, concordanceInput, outputCsv, varargin)
% M08_BUILD_DIRECT_EMISSION_CITY4_FROM_RAW_INVENTORY
% Build final city x MRIO4 direct-emission totals from raw aggregate inventory fields.

p = inputParser;
p.addParameter('AllocatedOutputCsv', "", @(x) ischar(x) || isstring(x));
p.parse(varargin{:});
opt = p.Results;

rootDir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(fileparts(rootDir), 'sectors', 'src'));

if istable(standardizedInput)
    Tstd = standardizedInput;
else
    Tstd = readtable(string(standardizedInput), 'TextType', 'string');
end
if istable(concordanceInput)
    Tcon = concordanceInput;
else
    Tcon = readtable(string(concordanceInput), 'TextType', 'string');
end
Tcon.field_en = string(Tcon.field_en);
Tcon.mrio4_target_code = normalize_code_field_local(Tcon.mrio4_target_code);

city = m02_load_city_mrio_package(cityMrio4Input);
sectorCodes = resolve_sector_codes_local(city);
sectorNames = resolve_sector_names_local(city, sectorCodes);

useCon = Tcon(double(Tcon.use_in_production_q) == 1, :);
useFields = string(useCon.field_en);
useRows = Tstd(ismember(string(Tstd.field_en), useFields), :);
rows = cell(0, 12);

for i = 1:height(useRows)
    fieldEn = string(useRows.field_en(i));
    concord = useCon(strcmp(string(useCon.field_en), fieldEn), :);
    if isempty(concord)
        error('m08_build_direct_emission_city4_from_raw_inventory:MissingConcordance', ...
            'Missing MRIO4 concordance row for field %s.', fieldEn);
    end
    targetCode = string(concord.mrio4_target_code(1));
    if ~ismember(targetCode, sectorCodes)
        error('m08_build_direct_emission_city4_from_raw_inventory:MissingSector', ...
            'MRIO4 sector %s is missing from the city MRIO4 package.', targetCode);
    end
    rows(end+1, :) = { ... %#ok<AGROW>
        useRows.year(i), ...
        double(useRows.province_code(i)), ...
        char(useRows.province_name_std(i)), ...
        double(useRows.city_code(i)), ...
        char(useRows.city_name_std(i)), ...
        char(useRows.city_name_en(i)), ...
        char(targetCode), ...
        char(sectorNames(targetCode)), ...
        double(useRows.value(i)), ...
        char(fieldEn), ...
        char(concord.allocation_basis(1)), ...
        'raw_inventory_based'};
end

contrib = cell2table(rows, 'VariableNames', { ...
    'year','province_code','province_name','city_code','city_name_std','city_name_en', ...
    'mrio4_sector_code','mrio4_sector_name','co2_total','source_field_en','allocation_rule','source_basis'});
finalTable = collapse_direct_rows_local(contrib, Tstd, sectorCodes, sectorNames);

if nargin >= 4 && strlength(string(outputCsv)) > 0
    writetable(finalTable, string(outputCsv));
end
if strlength(string(opt.AllocatedOutputCsv)) > 0
    writetable(contrib, string(opt.AllocatedOutputCsv));
end

out = struct();
out.directEmissionTable = finalTable;
out.contributionTable = contrib;
out.Diagnostics = struct();
out.Diagnostics.input_rows = height(Tstd);
out.Diagnostics.production_rows_used = height(useRows);
out.Diagnostics.household_rows_excluded = height(Tstd(double(Tstd.household_direct_flag) == 1, :));
out.Diagnostics.indirect_rows_excluded = height(Tstd(double(Tstd.indirect_flag) == 1, :));
out.Diagnostics.unique_city_count = numel(unique(finalTable.city_code));
[out.Diagnostics.min_sector_count_per_city, out.Diagnostics.max_sector_count_per_city] = sector_count_stats_local(finalTable);
end

function out = normalize_code_field_local(values)
out = strings(numel(values), 1);
for i = 1:numel(values)
    value = values(i);
    if ismissing(value)
        out(i) = "";
        continue;
    end
    numValue = str2double(string(value));
    if ~isnan(numValue)
        out(i) = compose("%02d", numValue);
    else
        out(i) = string(value);
    end
end
end

function sectorCodes = resolve_sector_codes_local(city)
if isfield(city, 'sector_codes') && numel(city.sector_codes) == city.numSectors
    sectorCodes = string(city.sector_codes(:));
    for i = 1:numel(sectorCodes)
        numericValue = str2double(strtrim(sectorCodes(i)));
        if ~isnan(numericValue)
            sectorCodes(i) = compose("%02d", numericValue);
        end
    end
else
    sectorCodes = compose("%02d", (1:city.numSectors)');
end
end

function names = resolve_sector_names_local(city, sectorCodes)
if isfield(city, 'sectors') && numel(city.sectors) == numel(sectorCodes)
    labels = string(city.sectors(:));
else
    labels = sectorCodes;
end
names = containers.Map(cellstr(sectorCodes), cellstr(labels));
end

function finalTable = collapse_direct_rows_local(contrib, standardized, sectorCodes, sectorNames)
keyTable = contrib(:, {'year','province_code','province_name','city_code','city_name_std','city_name_en','mrio4_sector_code','mrio4_sector_name'});
[G, keys] = findgroups(keyTable);
value = splitapply(@sum, contrib.co2_total, G);
finalAgg = keys;
finalAgg.co2_total = value;

cityMeta = unique(standardized(:, {'year','province_code','province_name_std','city_code','city_name_std','city_name_en'}), 'rows');
baseRows = cell(height(cityMeta) * numel(sectorCodes), 9);
cursor = 1;
for c = 1:height(cityMeta)
    for s = 1:numel(sectorCodes)
        baseRows(cursor, :) = {double(cityMeta.year(c)), double(cityMeta.province_code(c)), ...
            char(cityMeta.province_name_std(c)), double(cityMeta.city_code(c)), ...
            char(cityMeta.city_name_std(c)), char(cityMeta.city_name_en(c)), ...
            char(sectorCodes(s)), char(sectorNames(sectorCodes(s))), 0};
        cursor = cursor + 1;
    end
end

finalTable = cell2table(baseRows, 'VariableNames', { ...
    'year','province_code','province_name','city_code','city_name_std','city_name_en','mrio4_sector_code','mrio4_sector_name','co2_total'});

for i = 1:height(finalTable)
    hit = double(finalAgg.city_code) == double(finalTable.city_code(i)) & ...
        string(finalAgg.mrio4_sector_code) == string(finalTable.mrio4_sector_code(i));
    if any(hit)
        row = finalAgg(find(hit, 1, 'first'), :);
        finalTable.co2_total(i) = row.co2_total;
    end
end
finalTable.source_basis = repmat("raw_inventory_based", height(finalTable), 1);
finalTable = sortrows(finalTable, {'province_code','city_name_std','mrio4_sector_code'});
end

function [minCount, maxCount] = sector_count_stats_local(T)
[G, ~] = findgroups(T.city_code);
counts = splitapply(@numel, T.mrio4_sector_code, G);
minCount = min(counts);
maxCount = max(counts);
end
