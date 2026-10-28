function out = m08_build_direct_emission_city17_from_raw_inventory(standardizedInput, cityMrio17Input, concordanceInput, outputCsv, varargin)
% M08_BUILD_DIRECT_EMISSION_CITY17_FROM_RAW_INVENTORY
% Convert standardized raw city inventory fields into final city × MRIO17 direct-emission totals.

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
Tcon.mrio17_target_codes = normalize_code_field_local(Tcon.mrio17_target_codes);

city = m02_load_city_mrio_package(cityMrio17Input);
cityIndexMap = build_city_index_map_local(city);
sectorCodes = resolve_sector_codes_local(city);
sectorNames = resolve_sector_names_local(city, sectorCodes);
citySectorShares = build_city_sector_share_table_local(city, sectorCodes);

useRows = Tstd(Tstd.production_direct_flag == 1 & Tstd.use_in_production_q == 1, :);
rows = cell(0, 12);
excludedHousehold = height(Tstd(Tstd.household_direct_flag == 1, :));
excludedIndirect = height(Tstd(Tstd.indirect_flag == 1, :));

for i = 1:height(useRows)
    fieldEn = string(useRows.field_en(i));
    concord = Tcon(strcmp(string(Tcon.field_en), fieldEn), :);
    if isempty(concord)
        error('m08_build_direct_emission_city17_from_raw_inventory:MissingConcordance', ...
            'Missing concordance row for field %s.', fieldEn);
    end

    targetCodes = strtrim(split(string(concord.mrio17_target_codes(1)), '|'));
    targetCodes = targetCodes(strlength(targetCodes) > 0);
    cityName = string(useRows.city_name_std(i));
    cityCode = double(useRows.city_code(i));
    cityIdx = resolve_city_index_local(cityIndexMap, cityName);
    allocValues = allocate_to_targets_local(useRows.value(i), cityIdx, targetCodes, citySectorShares, string(concord.allocation_basis(1)));

    for j = 1:numel(targetCodes)
        rows(end+1, :) = { ... %#ok<AGROW>
            useRows.year(i), ...
            double(useRows.province_code(i)), ...
            char(useRows.province_name_std(i)), ...
            cityCode, ...
            char(cityName), ...
            char(useRows.city_name_en(i)), ...
            char(targetCodes(j)), ...
            char(sectorNames(targetCodes(j))), ...
            allocValues(j), ...
            char(fieldEn), ...
            char(concord.allocation_basis(1)), ...
            'raw_inventory_based'};
    end
end

contrib = cell2table(rows, 'VariableNames', { ...
    'year','province_code','province_name','city_code','city_name_std','city_name_en', ...
    'mrio17_sector_code','mrio17_sector_name','co2_total','source_field_en','allocation_rule','source_basis'});
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
out.Diagnostics.household_rows_excluded = excludedHousehold;
out.Diagnostics.indirect_rows_excluded = excludedIndirect;
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
    text = string(value);
    if text == "<missing>"
        out(i) = "";
        continue;
    end
    if contains(text, "|")
        parts = split(text, '|');
        parts = strtrim(parts);
        for j = 1:numel(parts)
            numValue = str2double(parts(j));
            if ~isnan(numValue)
                parts(j) = compose("%02d", numValue);
            end
        end
        out(i) = strjoin(cellstr(parts), '|');
    else
        numValue = str2double(text);
        if ~isnan(numValue)
            out(i) = compose("%02d", numValue);
        else
            out(i) = text;
        end
    end
end
end

function map = build_city_index_map_local(city)
map = containers.Map('KeyType', 'char', 'ValueType', 'double');
for i = 1:numel(city.cities_cn)
    map(char(string(city.cities_cn(i)))) = i;
end
end

function idx = resolve_city_index_local(map, cityName)
if ~isKey(map, char(cityName))
    error('m08_build_direct_emission_city17_from_raw_inventory:MissingCityIndex', ...
        'City %s is missing from the MRIO17 package.', cityName);
end
idx = map(char(cityName));
end

function sectorCodes = resolve_sector_codes_local(city)
if isfield(city, 'sector_codes') && numel(city.sector_codes) == city.numSectors
    sectorCodes = string(city.sector_codes(:));
    for i = 1:numel(sectorCodes)
        value = strtrim(sectorCodes(i));
        numericValue = str2double(value);
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

function shareTable = build_city_sector_share_table_local(city, sectorCodes)
cityIdx = zeros(numel(city.cities_cn) * numel(sectorCodes), 1);
sectorCode = strings(numel(city.cities_cn) * numel(sectorCodes), 1);
share = zeros(numel(city.cities_cn) * numel(sectorCodes), 1);
cursor = 1;
for c = 1:numel(city.cities_cn)
    rows = ((c - 1) * city.numSectors + 1):(c * city.numSectors);
    x = max(double(city.X(rows)), 0);
    denom = sum(x);
    if denom <= 0
        localShare = ones(numel(sectorCodes), 1) ./ numel(sectorCodes);
    else
        localShare = x ./ denom;
    end
    n = numel(sectorCodes);
    cityIdx(cursor:cursor+n-1) = c;
    sectorCode(cursor:cursor+n-1) = sectorCodes;
    share(cursor:cursor+n-1) = localShare;
    cursor = cursor + n;
end
shareTable = table(cityIdx, sectorCode, share);
end

function allocValues = allocate_to_targets_local(value, cityIdx, targetCodes, shareTable, basis)
if numel(targetCodes) == 1 || basis == "direct_assign"
    allocValues = double(value);
    if numel(targetCodes) > 1
        allocValues = [double(value); zeros(numel(targetCodes)-1, 1)];
    end
    return;
end

hit = shareTable.cityIdx == cityIdx & ismember(shareTable.sectorCode, targetCodes);
sub = shareTable(hit, :);
weights = zeros(numel(targetCodes), 1);
for i = 1:numel(targetCodes)
    idx = find(sub.sectorCode == targetCodes(i), 1, 'first');
    if ~isempty(idx)
        weights(i) = sub.share(idx);
    end
end
if sum(weights) <= 0
    weights = ones(numel(targetCodes), 1) ./ numel(targetCodes);
else
    weights = weights ./ sum(weights);
end
allocValues = double(value) .* weights;
end

function finalTable = collapse_direct_rows_local(contrib, standardized, sectorCodes, sectorNames)
keyTable = contrib(:, {'year','province_code','province_name','city_code','city_name_std','city_name_en','mrio17_sector_code','mrio17_sector_name'});
[G, keys] = findgroups(keyTable);
value = splitapply(@sum, contrib.co2_total, G);
finalAgg = keys;
finalAgg.co2_total = value;
finalAgg.source_basis = repmat("raw_inventory_based", height(finalAgg), 1);

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
    'year','province_code','province_name','city_code','city_name_std','city_name_en','mrio17_sector_code','mrio17_sector_name','co2_total'});

for i = 1:height(finalTable)
    hit = double(finalAgg.city_code) == double(finalTable.city_code(i)) & ...
        string(finalAgg.mrio17_sector_code) == string(finalTable.mrio17_sector_code(i));
    if any(hit)
        row = finalAgg(find(hit, 1, 'first'), :);
        finalTable.year(i) = row.year;
        finalTable.province_code(i) = row.province_code;
        finalTable.province_name(i) = row.province_name;
        finalTable.city_code(i) = row.city_code;
        finalTable.city_name_en(i) = row.city_name_en;
        finalTable.co2_total(i) = row.co2_total;
    end
end
finalTable.source_basis = repmat("raw_inventory_based", height(finalTable), 1);
finalTable = sortrows(finalTable, {'province_code','city_name_std','mrio17_sector_code'});
end

function [minCount, maxCount] = sector_count_stats_local(T)
[G, ~] = findgroups(T.city_code);
counts = splitapply(@numel, T.mrio17_sector_code, G);
minCount = min(counts);
maxCount = max(counts);
end
