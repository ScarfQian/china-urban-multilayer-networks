function mapping = m03_build_city_province_mapping(mappingInput, varargin)
% M03_BUILD_CITY_PROVINCE_MAPPING
% 构造：
%   R ∈ {0,1}^{31×Nc}, A = kron(R, eye(S)), B = kron(R, eye(F))
% 输入：
%   mappingInput :
%       1) 长度为 Nc 的数值 city2prov 向量
%       2) 含城市-省份信息的 table
%       3) CSV / XLSX / MAT 文件路径
%       4) 直接传入 city canonical struct，由函数尝试根据城市名启发式识别省份
% 可选参数：
%   'NumCities'     : 城市数；若未提供则尽量自动识别
%   'NumProvinces'  : 省份数，默认 31
%   'NumSectors'    : 部门数，默认 42
%   'NumFD'         : 最终需求类别数，默认 5
%   'ProvinceNames' : 省份标签；未提供则用标准 31 省名称
%   'CityNames'     : MRIO 顺序下的城市英文名，用于把表格按 MRIO 顺序重排
%   'CityNamesCN'   : MRIO 顺序下的城市中文名，用于把表格按 MRIO 顺序重排
% 输出：
%   mapping.city2prov
%   mapping.R, mapping.A, mapping.B
%   mapping.city_indices_by_province
%   mapping.province_names
%   mapping.Diagnostics

p = inputParser;
p.addRequired('mappingInput');
p.addParameter('NumCities', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
p.addParameter('NumProvinces', 31, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.addParameter('NumSectors', 42, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.addParameter('NumFD', 5, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.addParameter('ProvinceNames', strings(0,1));
p.addParameter('CityNames', strings(0,1));
p.addParameter('CityNamesCN', strings(0,1));
p.parse(mappingInput, varargin{:});
opt = p.Results;

provinceNames = string(opt.ProvinceNames);
if isempty(provinceNames)
    provinceNames = default_province_names();
end

cityNames = string(opt.CityNames);
cityNamesCN = string(opt.CityNamesCN);

[city2prov, inferredCities, details] = resolve_mapping_input(mappingInput, opt.NumCities, provinceNames, cityNames, cityNamesCN);
if ~isempty(opt.NumCities) && inferredCities ~= opt.NumCities
    error('m03_build_city_province_mapping:cityCountMismatch', ...
        '映射推断出的城市数为 %d，但你要求的 NumCities=%d。', inferredCities, opt.NumCities);
end

Nc = inferredCities;
R = sparse(city2prov(:), 1:Nc, 1, opt.NumProvinces, Nc);
A = kron(R, speye(opt.NumSectors));
B = kron(R, speye(opt.NumFD));

cityIndicesByProvince = cell(opt.NumProvinces, 1);
for pIdx = 1:opt.NumProvinces
    cityIndicesByProvince{pIdx} = find(city2prov == pIdx);
end

Diagnostics = struct();
Diagnostics.sourceType = details.sourceType;
Diagnostics.cityCount = Nc;
Diagnostics.provinceCount = opt.NumProvinces;
Diagnostics.sourceNote = details.sourceNote;
Diagnostics.provinceCounts = accumarray(city2prov(:), 1, [opt.NumProvinces, 1]);

mapping = struct();
mapping.city2prov = city2prov(:);
mapping.R = R;
mapping.A = A;
mapping.B = B;
mapping.numCities = Nc;
mapping.numProvinces = opt.NumProvinces;
mapping.numSectors = opt.NumSectors;
mapping.numFD = opt.NumFD;
mapping.province_names = provinceNames(:);
mapping.city_indices_by_province = cityIndicesByProvince;
mapping.Diagnostics = Diagnostics;
end

function [city2prov, numCities, details] = resolve_mapping_input(mappingInput, numCitiesHint, provinceNames, cityNames, cityNamesCN)
details = struct('sourceType', "", 'sourceNote', "");

if isnumeric(mappingInput)
    city2prov = normalize_city2prov(mappingInput, numCitiesHint, numel(provinceNames));
    numCities = numel(city2prov);
    details.sourceType = "numeric_vector";
    details.sourceNote = "直接使用数值 city2prov 向量。";
    return;
end

if isstring(mappingInput) || ischar(mappingInput)
    pathText = string(mappingInput);
    [~,~,ext] = fileparts(char(pathText));
    switch lower(ext)
        case '.csv'
            tbl = readtable(pathText, 'TextType', 'string');
        case {'.xlsx', '.xls'}
            tbl = readtable(pathText, 'TextType', 'string');
        case '.mat'
            raw = load(pathText);
            [city2prov, numCities, details] = resolve_mapping_input(raw, numCitiesHint, provinceNames, cityNames, cityNamesCN);
            details.sourceType = "mat_file";
            details.sourceNote = "从 MAT 文件中提取映射。";
            return;
        otherwise
            error('m03_build_city_province_mapping:unsupportedFile', ...
                '不支持的映射文件类型：%s。请提供 csv / xlsx / mat / 数值向量 / 表格。', ext);
    end
    [city2prov, numCities, details] = resolve_mapping_input(tbl, numCitiesHint, provinceNames, cityNames, cityNamesCN);
    details.sourceType = "table_file";
    details.sourceNote = "从表格文件中提取映射。";
    return;
end

if istable(mappingInput)
    city2prov = parse_mapping_table(mappingInput, provinceNames, cityNames, cityNamesCN);
    city2prov = normalize_city2prov(city2prov, numCitiesHint, numel(provinceNames));
    numCities = numel(city2prov);
    details.sourceType = "table";
    details.sourceNote = "从显式城市-省份表格中提取映射。";
    return;
end

if isstruct(mappingInput)
    if isfield(mappingInput, 'city2prov')
        city2prov = normalize_city2prov(mappingInput.city2prov, numCitiesHint, numel(provinceNames));
        numCities = numel(city2prov);
        details.sourceType = "struct_city2prov";
        details.sourceNote = "直接使用 struct.city2prov。";
        return;
    end
    if isfield(mappingInput, 'cities')
        cityNames = string(mappingInput.cities);
    elseif isfield(mappingInput, 'Meta') && isstruct(mappingInput.Meta) && isfield(mappingInput.Meta, 'City_Name')
        cityNames = string(mappingInput.Meta.City_Name);
    else
        names = fieldnames(mappingInput);
        if numel(names) == 1 && isstruct(mappingInput.(names{1}))
            [city2prov, numCities, details] = resolve_mapping_input(mappingInput.(names{1}), numCitiesHint, provinceNames, cityNames, cityNamesCN);
            return;
        end
        error('m03_build_city_province_mapping:missingCityNames', ...
            '当前 struct 中既没有 city2prov，也没有可用于启发式识别的城市名称。');
    end
    if isempty(cityNamesCN) && isfield(mappingInput, 'cities_cn')
        cityNamesCN = string(mappingInput.cities_cn);
    end
    city2prov = infer_city2prov_from_names(cityNames, cityNamesCN, provinceNames);
    city2prov = normalize_city2prov(city2prov, numCitiesHint, numel(provinceNames));
    numCities = numel(city2prov);
    details.sourceType = "heuristic_city_names";
    details.sourceNote = "根据城市标签启发式识别省份；若结果不可靠，请改用显式 city2prov 表。";
    return;
end

error('m03_build_city_province_mapping:unsupportedInput', ...
    '无法识别 mappingInput 类型。请提供数值向量、表格、文件路径或含城市标签的 struct。');
end

function city2prov = parse_mapping_table(tbl, provinceNames, cityNames, cityNamesCN)
varNames = lower(string(tbl.Properties.VariableNames));
provIdCandidates = ["province_id","prov_id","province_idx","prov_idx","city2prov"];
provCodeCandidates = ["province_code","prov_code"];
provNameCandidates = ["province","province_name","prov_name","province_cn","province_en"];
cityNameCandidates = ["city_name_std","city_name","city_cn","city_en","city","city_std"];

hitId = find(ismember(varNames, provIdCandidates), 1, 'first');
if ~isempty(hitId)
    rawProv = double(tbl{:, hitId});
    if ~isempty(cityNames) || ~isempty(cityNamesCN)
        city2prov = align_mapping_to_city_order(tbl, rawProv, cityNames, cityNamesCN, provinceNames, cityNameCandidates);
    else
        city2prov = rawProv;
    end
    return;
end

hitCode = find(ismember(varNames, provCodeCandidates), 1, 'first');
if ~isempty(hitCode)
    rawCode = double(tbl{:, hitCode});
    rawProv = zeros(height(tbl), 1);
    for i = 1:height(tbl)
        rawProv(i) = province_code_to_mrio_index(rawCode(i));
    end
    if ~isempty(cityNames) || ~isempty(cityNamesCN)
        city2prov = align_mapping_to_city_order(tbl, rawProv, cityNames, cityNamesCN, provinceNames, cityNameCandidates);
    else
        city2prov = rawProv;
    end
    return;
end

hitName = find(ismember(varNames, provNameCandidates), 1, 'first');
if isempty(hitName)
    error('m03_build_city_province_mapping:missingProvinceField', ...
        '映射表缺少省份字段。请提供 province_id / province_name 一类字段。');
end

provNames = string(tbl{:, hitName});
rawProv = zeros(height(tbl), 1);
for i = 1:height(tbl)
    rawProv(i) = match_province_name(provNames(i), provinceNames);
end

if ~isempty(cityNames) || ~isempty(cityNamesCN)
    city2prov = align_mapping_to_city_order(tbl, rawProv, cityNames, cityNamesCN, provinceNames, cityNameCandidates);
else
    city2prov = rawProv;
end
end

function city2prov = infer_city2prov_from_names(cityNames, cityNamesCN, provinceNames)
if isempty(cityNames)
    cityNames = strings(0,1);
end
if isempty(cityNamesCN)
    cityNamesCN = strings(size(cityNames));
end
cityNames = cityNames(:);
cityNamesCN = cityNamesCN(:);
city2prov = zeros(numel(cityNames), 1);
for i = 1:numel(cityNames)
    city2prov(i) = match_city_name_to_province(cityNames(i), cityNamesCN(i), provinceNames);
end
end

function city2prov = align_mapping_to_city_order(tbl, rawProv, cityNames, cityNamesCN, provinceNames, cityNameCandidates)
varNames = lower(string(tbl.Properties.VariableNames));
hitCity = find(ismember(varNames, cityNameCandidates), 1, 'first');
if isempty(hitCity)
    error('m03_build_city_province_mapping:missingCityField', ...
        '映射表缺少城市名称字段。请提供 city_name_std / city_name / city_cn / city_en 一类字段。');
end

tblCity = string(tbl{:, hitCity});
tblCityNorm = normalize_city_name(tblCity);
city2prov = zeros(numel(cityNames), 1);

if isempty(cityNamesCN)
    cityNamesCN = strings(size(cityNames));
end

for i = 1:numel(cityNames)
    rawEn = cityNames(i);
    rawCn = cityNamesCN(i);
    candidates = unique([normalize_city_name(rawCn); normalize_city_name(rawEn)], 'stable');
    candidates = candidates(strlength(candidates) > 0);
    idx = [];
    for j = 1:numel(candidates)
        idx = find(tblCityNorm == candidates(j), 1, 'first');
        if ~isempty(idx)
            city2prov(i) = rawProv(idx);
            break;
        end
    end
    if city2prov(i) == 0
        city2prov(i) = match_city_name_to_province(rawEn, rawCn, provinceNames);
    end
end
end

function idx = match_province_name(rawName, provinceNames)
nameText = normalize_geo_name(rawName);
idx = 0;
for i = 1:numel(provinceNames)
    provText = normalize_geo_name(provinceNames(i));
    if strlength(provText) == 0
        continue;
    end
    if contains(nameText, provText)
        idx = i;
        return;
    end
end
aliases = province_alias_table();
for i = 1:size(aliases, 1)
    if contains(nameText, aliases{i,2})
        idx = aliases{i,1};
        return;
    end
end
error('m03_build_city_province_mapping:provinceNotMatched', ...
    '无法把城市或地区标签 "%s" 匹配到 31 省中的某一个。请提供显式 city2prov 映射。', string(rawName));
end

function idx = match_city_name_to_province(rawNameEn, rawNameCn, provinceNames)
candidateNames = unique([normalize_city_name(rawNameCn); normalize_city_name(rawNameEn)], 'stable');
candidateNames = candidateNames(strlength(candidateNames) > 0);

aliases = city_province_alias_table();
for i = 1:size(aliases, 1)
    if any(candidateNames == aliases{i,1})
        idx = aliases{i,2};
        return;
    end
end

for i = 1:numel(candidateNames)
    idx = try_match_province_name(candidateNames(i), provinceNames);
    if idx > 0
        return;
    end
end

error('m03_build_city_province_mapping:provinceNotMatched', ...
    '无法把城市或地区标签 "%s / %s" 匹配到 31 省中的某一个。请检查 city2prov 映射文件。', ...
    string(rawNameEn), string(rawNameCn));
end

function idx = try_match_province_name(rawName, provinceNames)
idx = 0;
nameText = normalize_geo_name(rawName);
for i = 1:numel(provinceNames)
    provText = normalize_geo_name(provinceNames(i));
    if strlength(provText) == 0
        continue;
    end
    if contains(nameText, provText)
        idx = i;
        return;
    end
end
aliases = province_alias_table();
for i = 1:size(aliases, 1)
    if contains(nameText, aliases{i,2})
        idx = aliases{i,1};
        return;
    end
end
end

function nameText = normalize_geo_name(rawName)
nameText = lower(strtrim(string(rawName)));
nameText = erase(nameText, ["省","市","自治区","回族","维吾尔","壮族","特别行政区","地区","盟","自治州","自治县","县","区","市辖区","州"," "]);
end

function nameText = normalize_city_name(rawName)
nameText = lower(strtrim(string(rawName)));
nameText = erase(nameText, ["省","市","自治区","回族","维吾尔","壮族","特别行政区","地区","盟","自治州","自治县","县","区","市辖区","州","藏族","土家族","苗族","蒙古族","哈萨克","傣族","景颇族","傈僳族","朝鲜族","柯尔克孜"," "]);
end

function city2prov = normalize_city2prov(city2prov, numCitiesHint, numProvinces)
city2prov = double(city2prov(:));
if any(isnan(city2prov)) || any(abs(city2prov - round(city2prov)) > 0)
    error('m03_build_city_province_mapping:invalidIndices', 'city2prov 必须是 1..%d 的整数向量。', numProvinces);
end
if any(city2prov < 1) || any(city2prov > numProvinces)
    error('m03_build_city_province_mapping:outOfRange', 'city2prov 中存在超出 1..%d 的省份编号。', numProvinces);
end
if ~isempty(numCitiesHint) && numel(city2prov) ~= numCitiesHint
    error('m03_build_city_province_mapping:lengthMismatch', ...
        'city2prov 长度为 %d，但期待的城市数是 %d。', numel(city2prov), numCitiesHint);
end
end

function idx = province_code_to_mrio_index(codeValue)
codeValue = double(codeValue);
prefix = floor(codeValue / 10000);
switch prefix
    case 11
        idx = 1;
    case 12
        idx = 2;
    case 13
        idx = 3;
    case 14
        idx = 4;
    case 15
        idx = 5;
    case 21
        idx = 6;
    case 22
        idx = 7;
    case 23
        idx = 8;
    case 31
        idx = 9;
    case 32
        idx = 10;
    case 33
        idx = 11;
    case 34
        idx = 12;
    case 35
        idx = 13;
    case 36
        idx = 14;
    case 37
        idx = 15;
    case 41
        idx = 16;
    case 42
        idx = 17;
    case 43
        idx = 18;
    case 44
        idx = 19;
    case 45
        idx = 20;
    case 46
        idx = 21;
    case 50
        idx = 22;
    case 51
        idx = 23;
    case 52
        idx = 24;
    case 53
        idx = 25;
    case 54
        idx = 26;
    case 61
        idx = 27;
    case 62
        idx = 28;
    case 63
        idx = 29;
    case 64
        idx = 30;
    case 65
        idx = 31;
    otherwise
        error('m03_build_city_province_mapping:invalidProvinceCode', ...
            '无法把 province_code=%g 映射到 MRIO 的 31 省顺序。', codeValue);
end
end

function names = default_province_names()
names = ["Beijing"; "Tianjin"; "Hebei"; "Shanxi"; "Inner Mongolia"; ...
    "Liaoning"; "Jilin"; "Heilongjiang"; "Shanghai"; "Jiangsu"; ...
    "Zhejiang"; "Anhui"; "Fujian"; "Jiangxi"; "Shandong"; ...
    "Henan"; "Hubei"; "Hunan"; "Guangdong"; "Guangxi"; ...
    "Hainan"; "Chongqing"; "Sichuan"; "Guizhou"; "Yunnan"; ...
    "Tibet"; "Shaanxi"; "Gansu"; "Qinghai"; "Ningxia"; "Xinjiang"];
end

function aliases = province_alias_table()
aliases = {
    1,  "beijing";
    2,  "tianjin";
    3,  "hebei";
    4,  "shanxi";
    5,  "innermongolia";
    6,  "liaoning";
    7,  "jilin";
    8,  "heilongjiang";
    9,  "shanghai";
    10, "jiangsu";
    11, "zhejiang";
    12, "anhui";
    13, "fujian";
    14, "jiangxi";
    15, "shandong";
    16, "henan";
    17, "hubei";
    18, "hunan";
    19, "guangdong";
    20, "guangxi";
    21, "hainan";
    22, "chongqing";
    23, "sichuan";
    24, "guizhou";
    25, "yunnan";
    26, "tibet";
    27, "shaanxi";
    28, "gansu";
    29, "qinghai";
    30, "ningxia";
    31, "xinjiang";
    5,  "neimenggu";
    5,  "内蒙古";
    5,  "内蒙";
    26, "西藏";
    31, "新疆";
    30, "宁夏";
    20, "广西";
    27, "陕西";
    29, "青海";
    24, "贵州";
    23, "四川";
    17, "湖北";
    18, "湖南";
    7,  "吉林";
    8,  "黑龙江";
    15, "山东";
    16, "河南";
    27, "shanxi1";
    4,  "shanxi2"
    };
end

function aliases = city_province_alias_table()
aliases = {
    "兴安", 5;
    "锡林郭勒", 5;
    "阿拉善", 5;
    "延边", 7;
    "大兴安岭", 8;
    "莱芜", 15;
    "济源", 16;
    "恩施", 17;
    "恩施州", 17;
    "仙桃", 17;
    "神农架", 17;
    "天门", 17;
    "潜江", 17;
    "湘西", 18;
    "海南", 21;
    "甘孜", 23;
    "阿坝", 23;
    "凉山", 23;
    "毕节", 24;
    "铜仁", 24;
    "黔东南", 24;
    "黔南", 24;
    "黔西南", 24;
    "云南", 25;
    "西藏", 26;
    "临夏", 28;
    "甘南", 28;
    "青海", 29;
    "吐鲁番", 31;
    "哈密", 31;
    "昌吉", 31;
    "伊犁", 31;
    "阿勒泰", 31;
    "博尔塔拉", 31;
    "巴音郭楞", 31;
    "阿克苏", 31;
    "喀什", 31;
    "和田", 31;
    "石河子", 31;
    "克孜", 31;
    "塔城", 31
    };
end
