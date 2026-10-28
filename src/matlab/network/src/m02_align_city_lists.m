function alignment = m02_align_city_lists(inputs, cfg)
% M02_ALIGN_CITY_LISTS
% Align the frozen MRIO4, carbon4, and raw investment-network inputs to
%   one canonical 313-city order and build an explicit investment crosswalk.

city2015 = inputs.cityByYear.y2015;
city2020 = inputs.cityByYear.y2020;
carbon2015 = inputs.carbonByYear.y2015;
carbon2020 = inputs.carbonByYear.y2020;
codebook = inputs.codebook;

mrioCities = string(city2015.cities_cn(:));
if ~isequal(mrioCities, string(city2020.cities_cn(:)))
    error('m02_align_city_lists:MrioCityOrderMismatch', ...
        '2015 and 2020 MRIO4 packages do not share the same city order.');
end

[codebookAligned, codebookOrder] = align_codebook_local(codebook, mrioCities);
carbonCoverage = build_carbon_coverage_local(carbon2015, carbon2020);
cityTotals = compute_city_totals_local(city2015, codebookAligned);
investmentCrosswalk = build_investment_crosswalk_local(inputs.investmentWorkbookPath, codebookAligned, cityTotals, cfg);
sampleMask = build_sample_mask_local(codebookAligned, cfg);
coordinatesTable = build_target_coordinates_local(investmentCrosswalk, codebookAligned, sampleMask);
cityReportFull = build_city_alignment_report_local(codebookAligned, carbonCoverage, investmentCrosswalk, coordinatesTable, sampleMask, cfg.sampleMode);
% 中文说明：最终冻结输出只保留 pure-city 样本内城市；被排除的省级 proxy 单元单独写入 excluded_proxy_nodes.csv。
cityReport = cityReportFull(sampleMask, :);
cityReportPath = fullfile(cfg.resultsDir, 'city_alignment_report.csv');
writetable(cityReport, cityReportPath);

crosswalkPath = fullfile(cfg.resultsDir, 'investment_city_crosswalk.csv');
investmentCrosswalk.target_included_in_sample = double(ismember(double(investmentCrosswalk.target_city_code), double(codebookAligned.city_code(sampleMask))));
writetable(investmentCrosswalk, crosswalkPath);

sampleDefinitionReport = build_sample_definition_report_local(codebookAligned, sampleMask, cfg);
sampleDefinitionPath = fullfile(cfg.resultsDir, 'sample_definition_report.csv');
writetable(sampleDefinitionReport, sampleDefinitionPath);

excludedProxyNodes = codebookAligned(~sampleMask, {'city_id','city_code','city_cn','city_en','province_code','province_name_std'});
excludedProxyNodes.sample_mode = repmat(string(cfg.sampleMode), height(excludedProxyNodes), 1);
excludedProxyNodes.exclusion_reason = repmat("proxy_unit_excluded_in_pure_city_mode", height(excludedProxyNodes), 1);
excludedProxyPath = fullfile(cfg.resultsDir, 'excluded_proxy_nodes.csv');
writetable(excludedProxyNodes, excludedProxyPath);

cityTable = codebookAligned(sampleMask, :);
coordinatesTableFiltered = coordinatesTable(sampleMask, :);
distanceMatrix = build_distance_matrix_local(coordinatesTableFiltered);
sameProvinceMatrix = double(cityTable.province_code == cityTable.province_code');
investmentCrosswalkFiltered = investmentCrosswalk(investmentCrosswalk.target_included_in_sample == 1, :);
excludedRawInvestmentCodes = setdiff(unique(double(investmentCrosswalk.raw_city_code)), unique(double(investmentCrosswalkFiltered.raw_city_code)));

alignment = struct();
alignment.cityNames = mrioCities;
alignment.cityNamesEn = string(city2015.cities(:));
alignment.fullCityTable = codebookAligned;
alignment.cityTable = cityTable;
alignment.codebookOrder = codebookOrder;
alignment.keepCityIdx = find(sampleMask);
alignment.sampleMask = sampleMask;
alignment.sampleMode = string(cfg.sampleMode);
alignment.excludedProxyNodes = excludedProxyNodes;
alignment.excludedProxyNodesPath = string(excludedProxyPath);
alignment.sampleDefinitionReport = sampleDefinitionReport;
alignment.sampleDefinitionPath = string(sampleDefinitionPath);
alignment.excludedRawInvestmentCodes = excludedRawInvestmentCodes(:);
alignment.cityCodeToIndex = containers.Map(num2cell(double(cityTable.city_code)), num2cell((1:height(cityTable))'));
alignment.cityNameToIndex = containers.Map(cellstr(cityTable.city_cn), num2cell((1:height(cityTable))'));
alignment.numCities = height(cityTable);
alignment.numSectors = city2015.numSectors;
alignment.numFD = city2015.numFD;
alignment.sectorCodes = (1:city2015.numSectors)';
alignment.investmentCrosswalk = investmentCrosswalkFiltered;
alignment.investmentCrosswalkFull = investmentCrosswalk;
alignment.coordinatesTable = coordinatesTableFiltered;
alignment.distanceMatrixKm = distanceMatrix;
alignment.sameProvinceMatrix = sameProvinceMatrix;
alignment.cityReport = cityReport;
alignment.cityReportFull = cityReportFull;
alignment.cityReportPath = string(cityReportPath);
alignment.investmentCrosswalkPath = string(crosswalkPath);
end

function [codebookAligned, orderIdx] = align_codebook_local(codebook, mrioCities)
[isFound, orderIdx] = ismember(mrioCities, string(codebook.city_cn));
if ~all(isFound)
    missing = strjoin(cellstr(mrioCities(~isFound)), ', ');
    error('m02_align_city_lists:CodebookMissingCity', ...
        'Codebook is missing MRIO cities: %s', missing);
end
codebookAligned = codebook(orderIdx, :);
end

function sampleMask = build_sample_mask_local(codebookAligned, cfg)
cityCodes = double(codebookAligned.city_code);
candidateProxyMask = ismember(cityCodes, double(cfg.proxyUnitCodes(:)));
candidateProxyMask = candidateProxyMask & ~ismember(cityCodes, double(cfg.directMunicipalityCodes(:)));
sampleMask = true(height(codebookAligned), 1);
if string(cfg.sampleMode) == "pure_city"
    sampleMask(candidateProxyMask) = false;
elseif string(cfg.sampleMode) ~= "regional_313"
    error('m02_align_city_lists:UnsupportedSampleMode', ...
        'Unsupported sample_mode %s. Expected regional_313 or pure_city.', string(cfg.sampleMode));
end
end

function carbonCoverage = build_carbon_coverage_local(carbon2015, carbon2020)
carbonCoverage = struct();
carbonCoverage.codes2015 = unique(double(carbon2015.city_code));
carbonCoverage.codes2020 = unique(double(carbon2020.city_code));
carbonCoverage.sectors2015 = unique(double(carbon2015.mrio4_sector_code));
carbonCoverage.sectors2020 = unique(double(carbon2020.mrio4_sector_code));
carbonCoverage.sourceBasis2015 = unique(string(carbon2015.source_basis));
carbonCoverage.sourceBasis2020 = unique(string(carbon2020.source_basis));
end

function crosswalk = build_investment_crosswalk_local(workbookPath, codebookAligned, cityTotals, cfg) %#ok<INUSD>
sheetNames = ["DirectedNetwork_2015","DirectedNetwork_2020"];
rawNodes = table();
for i = 1:numel(sheetNames)
    T = readtable(workbookPath, 'Sheet', sheetNames(i), 'TextType', 'string');
    src = table( ...
        double(T.InvestorCityCode), string(T.InvestorCityName_CN), string(T.InvestorCityName_EN), ...
        double(T.InvestorCity_LNG), double(T.InvestorCity_LAT), ...
        repmat(extractAfter(sheetNames(i), "DirectedNetwork_"), height(T), 1), ...
        'VariableNames', {'raw_city_code','raw_city_name_cn','raw_city_name_en','lng','lat','source_year'});
    dst = table( ...
        double(T.InvesteeCityCode), string(T.InvesteeCityName_CN), string(T.InvesteeCityName_EN), ...
        double(T.InvesteeCity_LNG), double(T.InvesteeCity_LAT), ...
        repmat(extractAfter(sheetNames(i), "DirectedNetwork_"), height(T), 1), ...
        'VariableNames', {'raw_city_code','raw_city_name_cn','raw_city_name_en','lng','lat','source_year'});
    rawNodes = [rawNodes; src; dst]; %#ok<AGROW>
end

rawNodes = normalize_missing_local(rawNodes);
[G, rawCodes] = findgroups(double(rawNodes.raw_city_code));
uniqueNodes = table(rawCodes, 'VariableNames', {'raw_city_code'});
uniqueNodes.raw_city_name_cn = strings(height(uniqueNodes), 1);
uniqueNodes.raw_city_name_en = strings(height(uniqueNodes), 1);
uniqueNodes.lng = splitapply(@nanmean, rawNodes.lng, G);
uniqueNodes.lat = splitapply(@nanmean, rawNodes.lat, G);
uniqueNodes.source_years = strings(height(uniqueNodes), 1);
for iGroup = 1:height(uniqueNodes)
    hit = (G == iGroup);
    uniqueNodes.raw_city_name_cn(iGroup) = first_nonempty_local(rawNodes.raw_city_name_cn(hit));
    uniqueNodes.raw_city_name_en(iGroup) = first_nonempty_local(rawNodes.raw_city_name_en(hit));
    uniqueNodes.source_years(iGroup) = collapse_years_local(rawNodes.source_year(hit));
end
uniqueNodes = sortrows(uniqueNodes, 'raw_city_code');

rows = cell(0, 13);
for i = 1:height(uniqueNodes)
    [targetRows, shares, ruleName] = resolve_investment_target_local(uniqueNodes(i, :), codebookAligned, cityTotals, cfg);
    for j = 1:height(targetRows)
        rows(end + 1, :) = { ... %#ok<AGROW>
            uniqueNodes.raw_city_code(i), ...
            char(uniqueNodes.raw_city_name_cn(i)), ...
            char(uniqueNodes.raw_city_name_en(i)), ...
            uniqueNodes.lng(i), ...
            uniqueNodes.lat(i), ...
            char(uniqueNodes.source_years(i)), ...
            shares(j), ...
            targetRows.city_code(j), ...
            char(targetRows.city_cn(j)), ...
            char(targetRows.city_en(j)), ...
            targetRows.province_code(j), ...
            char(targetRows.province_name_std(j)), ...
            char(ruleName)};
    end
end

crosswalk = cell2table(rows, 'VariableNames', { ...
    'raw_city_code','raw_city_name_cn','raw_city_name_en','lng','lat','source_years','allocation_share', ...
    'target_city_code','target_city_name','target_city_name_en','target_province_code','target_province_name','mapping_rule'});
end

function row = normalize_missing_local(row)
row.raw_city_name_cn = replace(string(row.raw_city_name_cn), "<missing>", "");
row.raw_city_name_en = replace(string(row.raw_city_name_en), "<missing>", "");
end

function yearsText = collapse_years_local(yearValues)
yearsText = strjoin(cellstr(unique(string(yearValues))), '|');
end

function out = first_nonempty_local(values)
values = string(values);
values = values(strlength(strtrim(values)) > 0);
if isempty(values)
    out = "";
else
    out = values(1);
end
end

function [targetRows, shares, ruleName] = resolve_investment_target_local(rawRow, codebookAligned, cityTotals, cfg) %#ok<INUSD>
codebookCodes = double(codebookAligned.city_code);
rawCode = double(rawRow.raw_city_code);
rawName = string(rawRow.raw_city_name_cn);

if rawCode == 370100 || rawName == "济南市"
    targetRows = codebookAligned(ismember(string(codebookAligned.city_cn), ["济南","莱芜"]), :);
    if height(targetRows) ~= 2
        error('m02_align_city_lists:MissingJinanSplitTargets', ...
            'The canonical codebook must contain both 济南 and 莱芜.');
    end
    shares = split_shares_local(string(targetRows.city_cn), cityTotals);
    ruleName = "administrative_merge_split_by_city_output";
    return;
end

idx = find(codebookCodes == rawCode, 1, 'first');
if ~isempty(idx)
    targetRows = codebookAligned(idx, :);
    shares = 1;
    ruleName = "direct_code_match";
    return;
end

provincePrefix = floor(rawCode / 10000);
if ismember(provincePrefix, [46, 53, 54, 63])
    targetCode = provincePrefix * 10000;
    idx = find(codebookCodes == targetCode, 1, 'first');
    if isempty(idx)
        error('m02_align_city_lists:MissingProvinceAggregateTarget', ...
            'Missing province-aggregate target for raw investment city code %d.', rawCode);
    end
    targetRows = codebookAligned(idx, :);
    shares = 1;
    ruleName = "province_aggregate";
    return;
end

xpccMap = containers.Map( ...
    {'659002','659003','659004','659005','659006','659007','659008','659009','659010','659011'}, ...
    {'652900','653100','652300','654300','652800','652700','654000','653200','654200','650500'});
key = sprintf('%d', rawCode);
if isKey(xpccMap, key)
    targetCode = str2double(xpccMap(key));
    idx = find(codebookCodes == targetCode, 1, 'first');
    targetRows = codebookAligned(idx, :);
    shares = 1;
    ruleName = "xpcc_to_prefecture";
    return;
end

aliasMap = containers.Map( ...
    {'北京市','天津市','上海市','重庆市'}, ...
    {'北京','天津','上海','重庆'});
if isKey(aliasMap, char(rawName))
    targetName = string(aliasMap(char(rawName)));
    idx = find(string(codebookAligned.city_cn) == targetName, 1, 'first');
    targetRows = codebookAligned(idx, :);
    shares = 1;
    ruleName = "municipality_name_match";
    return;
end

normRaw = normalize_city_name_local(rawName);
normTargets = arrayfun(@normalize_city_name_local, string(codebookAligned.city_cn));
idx = find(normTargets == normRaw, 1, 'first');
if ~isempty(idx)
    targetRows = codebookAligned(idx, :);
    shares = 1;
    ruleName = "normalized_name_match";
    return;
end

error('m02_align_city_lists:UnmappedInvestmentCity', ...
    'Unable to map raw investment city %d (%s) into the canonical 313-city list.', ...
    rawCode, rawName);
end

function shares = split_shares_local(targetNames, cityTotals)
weights = zeros(numel(targetNames), 1);
for i = 1:numel(targetNames)
    hit = find(string(cityTotals.city_name) == string(targetNames(i)), 1, 'first');
    if isempty(hit)
        error('m02_align_city_lists:MissingSplitWeight', ...
            'Split target %s is missing from city totals.', targetNames(i));
    end
    weights(i) = max(double(cityTotals.city_total_x(hit)), 0);
end
if sum(weights) <= 0
    shares = ones(numel(targetNames), 1) ./ numel(targetNames);
else
    shares = weights ./ sum(weights);
end
end

function out = normalize_city_name_local(in)
out = string(in);
out = strtrim(out);
ethnicTerms = ["蒙古族","回族","藏族","维吾尔族","朝鲜族","土家族","苗族","侗族","布依族", ...
    "哈尼族","傣族","白族","景颇族","傈僳族","羌族","彝族","壮族","柯尔克孜族","哈萨克族","黎族"];
for i = 1:numel(ethnicTerms)
    out = erase(out, ethnicTerms(i));
end
suffixes = ["市","地区","盟","自治州","自治县","林区","特别行政区","省直辖县级行政区划","自治区直辖县级行政区划"];
for i = 1:numel(suffixes)
    out = erase(out, suffixes(i));
end
end

function coordinatesTable = build_target_coordinates_local(investmentCrosswalk, codebookAligned, sampleMask)
[G, targetCodes] = findgroups(double(investmentCrosswalk.target_city_code));
meanLng = splitapply(@nanmean, double(investmentCrosswalk.lng), G);
meanLat = splitapply(@nanmean, double(investmentCrosswalk.lat), G);
rawCount = splitapply(@numel, investmentCrosswalk.raw_city_code, G);
ruleText = strings(numel(targetCodes), 1);
for iGroup = 1:numel(targetCodes)
    ruleText(iGroup) = collapse_strings_local(investmentCrosswalk.mapping_rule(G == iGroup));
end

coordinatesTable = codebookAligned(:, {'city_id','city_en','city_cn','province_id','province_en','province_name_std','province_code','city_code'});
[isFound, idx] = ismember(double(coordinatesTable.city_code), targetCodes);
coordinatesTable.coordinate_lng = nan(height(coordinatesTable), 1);
coordinatesTable.coordinate_lat = nan(height(coordinatesTable), 1);
coordinatesTable.raw_investment_city_count = zeros(height(coordinatesTable), 1);
coordinatesTable.investment_mapping_rules = strings(height(coordinatesTable), 1);
coordinatesTable.has_investment_coordinate = zeros(height(coordinatesTable), 1);
coordinatesTable.coordinate_lng(isFound) = meanLng(idx(isFound));
coordinatesTable.coordinate_lat(isFound) = meanLat(idx(isFound));
coordinatesTable.raw_investment_city_count(isFound) = rawCount(idx(isFound));
coordinatesTable.investment_mapping_rules(isFound) = ruleText(idx(isFound));
coordinatesTable.has_investment_coordinate(isFound) = double(~isnan(coordinatesTable.coordinate_lng(isFound)) & ~isnan(coordinatesTable.coordinate_lat(isFound)));
coordinatesTable.included_in_sample = double(sampleMask(:));

if any(coordinatesTable.has_investment_coordinate == 0 & sampleMask(:))
    missingCities = strjoin(cellstr(coordinatesTable.city_cn(coordinatesTable.has_investment_coordinate == 0 & sampleMask(:))), ', ');
    error('m02_align_city_lists:MissingInvestmentCoordinates', ...
        'Missing investment coordinates after alignment for: %s', missingCities);
end
end

function txt = collapse_strings_local(values)
u = unique(string(values));
u = u(strlength(u) > 0);
if isempty(u)
    txt = "";
elseif numel(u) == 1
    txt = u(1);
else
    txt = strjoin(cellstr(u), '|');
end
end

function D = build_distance_matrix_local(coordinatesTable)
lat = deg2rad(double(coordinatesTable.coordinate_lat(:)));
lon = deg2rad(double(coordinatesTable.coordinate_lng(:)));
N = numel(lat);
D = zeros(N, N);
earthRadiusKm = 6371;
for i = 1:N
    dlat = lat - lat(i);
    dlon = lon - lon(i);
    a = sin(dlat / 2).^2 + cos(lat(i)) .* cos(lat) .* sin(dlon / 2).^2;
    c = 2 * atan2(sqrt(a), sqrt(max(1 - a, 0)));
    D(i, :) = earthRadiusKm * c;
end
end

function cityReport = build_city_alignment_report_local(codebookAligned, carbonCoverage, investmentCrosswalk, coordinatesTable, sampleMask, sampleMode)
investment2015 = contains(investmentCrosswalk.source_years, "2015");
investment2020 = contains(investmentCrosswalk.source_years, "2020");

targetCodes2015 = unique(double(investmentCrosswalk.target_city_code(investment2015)));
targetCodes2020 = unique(double(investmentCrosswalk.target_city_code(investment2020)));
targetCodesAll = double(investmentCrosswalk.target_city_code);

candidateProxyMask = double(ismember(double(codebookAligned.city_code), [460000, 530000, 540000, 630000]));
rows = cell(height(codebookAligned), 20);
for i = 1:height(codebookAligned)
    cityCode = double(codebookAligned.city_code(i));
    hit = targetCodesAll == cityCode;
    rows(i, :) = { ...
        char(string(sampleMode)), ...
        codebookAligned.city_id(i), ...
        cityCode, ...
        char(codebookAligned.city_cn(i)), ...
        char(codebookAligned.city_en(i)), ...
        codebookAligned.province_code(i), ...
        char(codebookAligned.province_name_std(i)), ...
        1, ...
        1, ...
        double(ismember(cityCode, carbonCoverage.codes2015)), ...
        double(ismember(cityCode, carbonCoverage.codes2020)), ...
        double(ismember(cityCode, targetCodes2015)), ...
        double(ismember(cityCode, targetCodes2020)), ...
        sum(hit), ...
        char(collapse_strings_local(investmentCrosswalk.mapping_rule(hit))), ...
        coordinatesTable.coordinate_lng(i), ...
        coordinatesTable.coordinate_lat(i), ...
        candidateProxyMask(i), ...
        double(sampleMask(i)), ...
        double(codebookAligned.city_code(i) == codebookAligned.province_code(i))};
    end

cityReport = cell2table(rows, 'VariableNames', { ...
    'sample_mode','city_id','city_code','city_name_std','city_name_en','province_code','province_name_std', ...
    'in_mrio_2015','in_mrio_2020','in_carbon_2015','in_carbon_2020','in_investment_2015','in_investment_2020', ...
    'investment_raw_city_count','investment_mapping_rules','coordinate_lng','coordinate_lat', ...
    'candidate_proxy_unit','included_in_sample','city_code_equals_province_code'});
cityReport.shihezi_zero_fill_flag = double(cityReport.city_name_std == "石河子");
end

function cityTotals = compute_city_totals_local(city, codebookAligned)
N = city.numCities;
S = city.numSectors;
Xmat = reshape(double(city.X), [S, N])';
cityTotals = table(string(codebookAligned.city_cn), sum(Xmat, 2), 'VariableNames', {'city_name','city_total_x'});
end

function report = build_sample_definition_report_local(codebookAligned, sampleMask, cfg)
cityCodes = double(codebookAligned.city_code);
candidateProxyMask = ismember(cityCodes, double(cfg.proxyUnitCodes(:))) & ...
    ~ismember(cityCodes, double(cfg.directMunicipalityCodes(:)));
directMunicipalityMask = ismember(cityCodes, double(cfg.directMunicipalityCodes(:)));
report = table( ...
    string(cfg.sampleMode), ...
    height(codebookAligned), ...
    sum(sampleMask), ...
    sum(candidateProxyMask), ...
    sum(~sampleMask), ...
    sum(directMunicipalityMask & sampleMask), ...
    string(strjoin(compose('%d', cityCodes(~sampleMask)), '|')), ...
    'VariableNames', {'sample_mode','total_canonical_nodes','included_nodes','candidate_proxy_unit_count', ...
    'excluded_proxy_unit_count','retained_direct_municipality_count','excluded_proxy_codes'});
end
