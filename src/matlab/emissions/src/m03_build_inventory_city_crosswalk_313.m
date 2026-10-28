function crosswalk = m03_build_inventory_city_crosswalk_313(rawCityTable, codebookCsv, cityMrio17Input, outputCsv)
% M03_BUILD_INVENTORY_CITY_CROSSWALK_313
% Build transparent aggregation/splitting rules between the raw inventory
%   workbook and the MRIO 313-city codebook.

if nargin < 4
    outputCsv = "";
end

rootDir = fileparts(fileparts(mfilename('fullpath')));
sectorMergeCodeDir = fullfile(fileparts(rootDir), 'sectors', 'src');
addpath(sectorMergeCodeDir);

codebook = readtable(codebookCsv, 'TextType', 'string');
city = m02_load_city_mrio_package(cityMrio17Input);
cityTotals = compute_city_totals_local(city);

rawCityTable = sortrows(rawCityTable, {'raw_province_name','raw_city_name'});
rows = cell(0, 11);
coveredTargets = strings(0, 1);

for i = 1:height(rawCityTable)
    rawProv = string(rawCityTable.raw_province_name(i));
    rawCity = string(rawCityTable.raw_city_name(i));
    rawCityEn = string(rawCityTable.raw_city_name_en(i));
    [targets, shares, rule] = resolve_targets_local(rawProv, rawCity, codebook, cityTotals);
    for j = 1:numel(targets)
        targetInfo = codebook(strcmp(codebook.city_cn, targets(j)), :);
        rows(end+1, :) = { ... %#ok<AGROW>
            rawCityTable.year(i), ...
            char(rawProv), ...
            char(rawCity), ...
            char(rawCityEn), ...
            char(targets(j)), ...
            targetInfo.city_code(1), ...
            targetInfo.province_code(1), ...
            char(targetInfo.province_name_std(1)), ...
            shares(j), ...
            char(rule), ...
            0};
    end
    coveredTargets = [coveredTargets; targets(:)]; %#ok<AGROW>
end

missingTargets = setdiff(string(codebook.city_cn), unique(coveredTargets));
for i = 1:numel(missingTargets)
    target = missingTargets(i);
    if target ~= "石河子"
        error('m03_build_inventory_city_crosswalk_313:UnexpectedMissingTarget', ...
            'Unexpected codebook city without raw source: %s', target);
    end
    targetInfo = codebook(strcmp(codebook.city_cn, target), :);
    rows(end+1, :) = { ... %#ok<AGROW>
        rawCityTable.year(1), ...
        "", ...
        "", ...
        "", ...
        char(target), ...
        targetInfo.city_code(1), ...
        targetInfo.province_code(1), ...
        char(targetInfo.province_name_std(1)), ...
        1, ...
        'missing_raw_zero_fill', ...
        1};
end

crosswalk = cell2table(rows, 'VariableNames', { ...
    'year','raw_province_name','raw_city_name','raw_city_name_en','target_city_name', ...
    'target_city_code','target_province_code','target_province_name','allocation_share', ...
    'mapping_rule','zero_fill_flag'});

if strlength(string(outputCsv)) > 0
    writetable(crosswalk, string(outputCsv));
end
end

function totals = compute_city_totals_local(city)
totals = table(string(city.cities_cn(:)), zeros(numel(city.cities_cn), 1), ...
    'VariableNames', {'city_cn','city_total_x'});
for i = 1:height(totals)
    rows = ((i - 1) * city.numSectors + 1):(i * city.numSectors);
    totals.city_total_x(i) = sum(double(city.X(rows)));
end
end

function [targets, shares, rule] = resolve_targets_local(rawProv, rawCity, codebook, cityTotals)
provAggregateTargets = containers.Map( ...
    {'云南', '西藏', '青海', '海南'}, ...
    {'云南', '西藏', '青海', '海南'});

if isKey(provAggregateTargets, char(rawProv))
    targets = string(provAggregateTargets(char(rawProv)));
    shares = 1;
    rule = "province_aggregate";
    return;
end

if rawCity == "湖北直辖县"
    targets = ["仙桃","潜江","天门","神农架地区"]';
    shares = split_shares_local(targets, cityTotals);
    rule = "raw_group_split_by_city_output";
    return;
end

if rawCity == "济南"
    targets = ["济南","莱芜"]';
    shares = split_shares_local(targets, cityTotals);
    rule = "administrative_merge_split_by_city_output";
    return;
end

if rawCity == "河南直辖县"
    targets = "济源";
    shares = 1;
    rule = "alias_to_jiyuan";
    return;
end

aliasMap = containers.Map( ...
    {'恩施', '克孜勒苏柯尔克孜'}, ...
    {'恩施州', '克孜'});
if isKey(aliasMap, char(rawCity))
    targets = string(aliasMap(char(rawCity)));
    shares = 1;
    rule = "alias_rename";
    return;
end

rawNorm = normalize_city_name_local(rawCity);
codeNorm = arrayfun(@normalize_city_name_local, string(codebook.city_cn));
hit = find(codeNorm == rawNorm, 1, 'first');
if isempty(hit)
    error('m03_build_inventory_city_crosswalk_313:UnmappedRawCity', ...
        'Unable to map raw inventory city %s (%s) into the 313-city codebook.', ...
        rawCity, rawProv);
end
targets = string(codebook.city_cn(hit));
shares = 1;
rule = "direct_match";
end

function shares = split_shares_local(targets, cityTotals)
weights = zeros(numel(targets), 1);
for i = 1:numel(targets)
    hit = find(string(cityTotals.city_cn) == string(targets(i)), 1, 'first');
    if isempty(hit)
        error('m03_build_inventory_city_crosswalk_313:MissingSplitTarget', ...
            'Split target %s is missing from the merged city MRIO package.', targets(i));
    end
    weights(i) = max(double(cityTotals.city_total_x(hit)), 0);
end
if sum(weights) <= 0
    shares = ones(numel(targets), 1) ./ numel(targets);
else
    shares = weights ./ sum(weights);
end
end

function out = normalize_city_name_local(in)
out = string(in);
out = strtrim(out);
suffixes = ["市","地区","盟","自治州","特别行政区","省直辖县级行政区划","自治区直辖县级行政区划"];
for i = 1:numel(suffixes)
    out = erase(out, suffixes(i));
end
end
