function out = m02_parse_city_inventory_workbook(workbookPath)
% M02_PARSE_CITY_INVENTORY_WORKBOOK
% Parse one raw city inventory workbook into canonical wide and long tables.

catalog = m01_inventory_field_catalog();
yearValue = infer_year_local(workbookPath);

emissionCells = readcell(workbookPath, 'Sheet', '二氧化碳排放(万吨)');
socialCells = readcell(workbookPath, 'Sheet', '社会经济数据');

emissionHeader = emissionCells(1, :);
emissionBody = emissionCells(2:end, :);
emissionBody = emissionBody(~cellfun(@isempty, emissionBody(:, 2)), :);

socialHeader = socialCells(1, :);
socialBody = socialCells(2:end, :);
socialBody = socialBody(~cellfun(@isempty, socialBody(:, 2)), :);

emissionWide = cell2table(emissionBody, 'VariableNames', matlab.lang.makeUniqueStrings( ...
    matlab.lang.makeValidName(build_header_names_local(emissionHeader))));
socialWide = cell2table(socialBody, 'VariableNames', matlab.lang.makeUniqueStrings( ...
    matlab.lang.makeValidName(build_header_names_local(socialHeader))));

rawLong = build_raw_long_local(emissionBody, emissionHeader, catalog, yearValue);
cityTable = unique(rawLong(:, {'year','raw_province_name','raw_city_name','raw_city_name_en'}), 'rows');

socialTable = table( ...
    repmat(yearValue, size(socialBody, 1), 1), ...
    string(column_values_local(socialBody, 1)), ...
    string(column_values_local(socialBody, 2)), ...
    string(column_values_local(socialBody, 3)), ...
    numeric_column_local(socialBody, 4), ...
    numeric_column_local(socialBody, 5), ...
    numeric_column_local(socialBody, 6), ...
    'VariableNames', {'year','raw_province_name','raw_city_name','raw_city_name_en', ...
    'permanent_population_10k','gdp_100m_rmb','gdp_per_capita_10k_rmb'});

out = struct();
out.year = yearValue;
out.workbookPath = string(workbookPath);
out.emissionWideTable = emissionWide;
out.socialWideTable = socialWide;
out.rawLongTable = rawLong;
out.cityTable = cityTable;
out.socialTable = socialTable;
out.catalog = catalog;
end

function yearValue = infer_year_local(workbookPath)
fileName = char(string(workbookPath));
[~, baseName, ~] = fileparts(fileName);
tokens = regexp(baseName, '(20\d{2})', 'tokens', 'once');
if isempty(tokens)
    error('m02_parse_city_inventory_workbook:MissingYear', ...
        'Unable to infer year from workbook path: %s', workbookPath);
end
yearValue = str2double(tokens{1});
end

function names = build_header_names_local(headerRow)
names = strings(1, numel(headerRow));
for i = 1:numel(headerRow)
    value = string(headerRow{i});
    value = strtrim(extractBefore(value + newline, newline));
    if strlength(value) == 0
        value = "col_" + string(i);
    end
    names(i) = value;
end
end

function out = build_raw_long_local(body, headerRow, catalog, yearValue)
rawFieldCn = strings(0, 1);
fieldEn = strings(0, 1);
fieldGroup = strings(0, 1);
productionDirectFlag = zeros(0, 1);
householdDirectFlag = zeros(0, 1);
indirectFlag = zeros(0, 1);
totalCheckFlag = zeros(0, 1);
value = zeros(0, 1);
rawProvince = strings(0, 1);
rawCity = strings(0, 1);
rawCityEn = strings(0, 1);

for col = 4:numel(headerRow)
    rawHeader = strtrim(extractBefore(string(headerRow{col}) + newline, newline));
    hit = find(catalog.raw_field_cn == rawHeader, 1, 'first');
    if isempty(hit)
        continue;
    end

    n = size(body, 1);
    rawFieldCn = [rawFieldCn; repmat(rawHeader, n, 1)]; %#ok<AGROW>
    fieldEn = [fieldEn; repmat(catalog.field_en(hit), n, 1)]; %#ok<AGROW>
    fieldGroup = [fieldGroup; repmat(catalog.field_group(hit), n, 1)]; %#ok<AGROW>
    productionDirectFlag = [productionDirectFlag; repmat(double(catalog.production_direct_flag(hit)), n, 1)]; %#ok<AGROW>
    householdDirectFlag = [householdDirectFlag; repmat(double(catalog.household_direct_flag(hit)), n, 1)]; %#ok<AGROW>
    indirectFlag = [indirectFlag; repmat(double(catalog.indirect_flag(hit)), n, 1)]; %#ok<AGROW>
    totalCheckFlag = [totalCheckFlag; repmat(double(catalog.total_check_flag(hit)), n, 1)]; %#ok<AGROW>
    value = [value; numeric_column_local(body, col)]; %#ok<AGROW>
    rawProvince = [rawProvince; string(column_values_local(body, 1))]; %#ok<AGROW>
    rawCity = [rawCity; string(column_values_local(body, 2))]; %#ok<AGROW>
    rawCityEn = [rawCityEn; string(column_values_local(body, 3))]; %#ok<AGROW>
end

out = table( ...
    repmat(yearValue, numel(value), 1), ...
    rawProvince, rawCity, rawCityEn, rawFieldCn, fieldEn, fieldGroup, ...
    productionDirectFlag, householdDirectFlag, indirectFlag, totalCheckFlag, value, ...
    'VariableNames', {'year','raw_province_name','raw_city_name','raw_city_name_en', ...
    'raw_field_cn','field_en','field_group','production_direct_flag','household_direct_flag', ...
    'indirect_flag','total_check_flag','value'});
end

function values = column_values_local(body, col)
values = body(:, col);
end

function values = numeric_column_local(body, col)
n = size(body, 1);
values = zeros(n, 1);
for i = 1:n
    x = body{i, col};
    if isempty(x)
        values(i) = 0;
    elseif isnumeric(x)
        values(i) = double(x);
    else
        temp = str2double(string(x));
        if isnan(temp)
            values(i) = 0;
        else
            values(i) = temp;
        end
    end
end
end
