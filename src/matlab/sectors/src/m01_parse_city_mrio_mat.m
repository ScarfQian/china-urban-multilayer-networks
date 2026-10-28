function out = m01_parse_city_mrio_mat(matPath, varargin)
% M01_PARSE_CITY_MRIO_MAT
% 把城市 MRIO 的 MAT 文件统一解析为：
%   Z / Y / VA / IM / EX / X / error / cities / sectors / fd_labels
% 输入：
%   matPath : MAT 文件路径
% 可选参数：
%   'NumSectors' : 部门数，默认 42
%   'NumFD'      : 最终需求类别数，默认 5
%   'Validate'   : 是否做尺寸和核算检查，默认 true
% 输出：
%   out.Z, out.Y, out.VA, out.IM, out.EX, out.X, out.error
%   out.cities, out.cities_cn, out.city_ids, out.sectors, out.fd_labels
%   out.Meta, out.Diagnostics
% 注意事项：
%   1. 本函数优先识别 MRIO / F / Y / EX / X / VA / IM 等常见字段；
%   2. 若 X 缺失，则按 X = sum(Z,2) + sum(Y,2) + EX 重建；
%   3. 若 error 缺失，则默认补零；
%   4. 若 VA / IM 不是标准列向量，则会按“合计行 / 前 NS 个部门值”规则尽量提取。

p = inputParser;
p.addRequired('matPath', @(x) ischar(x) || isstring(x));
p.addParameter('NumSectors', 42, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.addParameter('NumFD', 5, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.addParameter('Validate', true, @(x) islogical(x) || isnumeric(x));
p.parse(matPath, varargin{:});
opt = p.Results;

matPath = string(matPath);
raw = load(matPath);
[core, meta] = resolve_city_payload(raw);

Z = double(resolve_required_field(core, ["Z"]));
if size(Z, 1) ~= size(Z, 2)
    error('m01_parse_city_mrio_mat:invalidZ', '城市 MRIO 的 Z 必须是方阵，但当前尺寸为 %d x %d。', size(Z,1), size(Z,2));
end

NS = size(Z, 1);
if mod(NS, opt.NumSectors) ~= 0
    error('m01_parse_city_mrio_mat:invalidNS', ...
        '城市 MRIO 的 Z 行数 %d 不能被 NumSectors=%d 整除，无法按“城市在外层、部门在内层”解释。', ...
        NS, opt.NumSectors);
end
numCities = NS / opt.NumSectors;
NF = numCities * opt.NumFD;

Yraw = resolve_required_field(core, ["Y", "F"]);
Y = double(Yraw);
if size(Y, 1) ~= NS || size(Y, 2) ~= NF
    error('m01_parse_city_mrio_mat:invalidY', ...
        '城市 MRIO 的 Y/F 尺寸应为 %d x %d，但当前为 %d x %d。', ...
        NS, NF, size(Y,1), size(Y,2));
end

EX = extract_account_vector(resolve_optional_field(core, ["EX", "Export"]), NS, 'EX');
if isempty(EX)
    error('m01_parse_city_mrio_mat:missingEX', '城市 MRIO 缺少 EX / Export 字段，无法重建总产出。');
end

X = extract_account_vector(resolve_optional_field(core, ["X", "GO", "Output"]), NS, 'X');
if isempty(X)
    X = sum(Z, 2) + sum(Y, 2) + EX;
end

VAraw = resolve_optional_field(core, ["VA", "ValueAdded", "V"]);
if isempty(VAraw)
    error('m01_parse_city_mrio_mat:missingVA', '城市 MRIO 缺少 VA 字段，无法形成 canonical struct。');
end
VA = extract_total_row_vector(VAraw, NS, 'VA');

IMraw = resolve_optional_field(core, ["IM", "Import", "M"]);
if isempty(IMraw)
    IM = zeros(NS, 1);
else
    IM = extract_account_vector(IMraw, NS, 'IM');
end

ERRraw = resolve_optional_field(core, ["error", "Error", "ERR"]);
if isempty(ERRraw)
    errorVec = zeros(NS, 1);
else
    errorVec = extract_account_vector(ERRraw, NS, 'error');
end

[cityIds, cities, citiesCn] = resolve_city_labels(meta, core, numCities);
sectors = resolve_sector_labels(meta, core, opt.NumSectors);
fdLabels = resolve_fd_labels(meta, core, opt.NumFD);

Diagnostics = struct();
Diagnostics.sourcePath = char(matPath);
Diagnostics.numCities = numCities;
Diagnostics.numSectors = opt.NumSectors;
Diagnostics.numFD = opt.NumFD;
Diagnostics.maxAbsRowIdentity = max(abs(sum(Z, 2) + sum(Y, 2) + EX - X));
Diagnostics.maxAbsColIdentity = max(abs(sum(Z, 1)' + VA + IM + errorVec - X));
Diagnostics.detectedFields = fieldnames(core);

if logical(opt.Validate)
    if Diagnostics.maxAbsRowIdentity > 1e-4
        error('m01_parse_city_mrio_mat:rowIdentityFailed', ...
            '城市 MRIO 行核算检查失败，maxAbs=%g。请检查 EX / Y / X 口径。', Diagnostics.maxAbsRowIdentity);
    end
end

out = struct();
out.Z = Z;
out.Y = Y;
out.VA = VA;
out.IM = IM;
out.EX = EX;
out.X = X;
out.error = errorVec;
out.city_ids = cityIds;
out.cities = cities;
out.cities_cn = citiesCn;
out.sectors = sectors;
out.fd_labels = fdLabels;
out.Meta = meta;
out.Diagnostics = Diagnostics;
end

function [core, meta] = resolve_city_payload(raw)
meta = struct();
if isfield(raw, 'MRIO') && isstruct(raw.MRIO)
    core = raw.MRIO;
    if isfield(raw, 'Meta') && isstruct(raw.Meta)
        meta = raw.Meta;
    end
    return;
end

names = fieldnames(raw);
for i = 1:numel(names)
    value = raw.(names{i});
    if isstruct(value) && has_any_field(value, ["Z", "Y", "F"])
        core = value;
        if isfield(raw, 'Meta') && isstruct(raw.Meta)
            meta = raw.Meta;
        end
        return;
    end
end

core = raw;
if isfield(raw, 'Meta') && isstruct(raw.Meta)
    meta = raw.Meta;
end
end

function value = resolve_required_field(S, candidates)
value = resolve_optional_field(S, candidates);
if isempty(value)
    error('m01_parse_city_mrio_mat:missingField', ...
        '城市 MRIO 缺少必需字段：%s。', strjoin(cellstr(candidates), ' / '));
end
end

function value = resolve_optional_field(S, candidates)
value = [];
if ~isstruct(S)
    return;
end
names = string(fieldnames(S));
lowerNames = lower(names);
for i = 1:numel(candidates)
    target = lower(string(candidates(i)));
    idx = find(lowerNames == target, 1, 'first');
    if ~isempty(idx)
        value = S.(names(idx));
        return;
    end
end
end

function tf = has_any_field(S, candidates)
tf = false;
if ~isstruct(S)
    return;
end
names = lower(string(fieldnames(S)));
for i = 1:numel(candidates)
    if any(names == lower(string(candidates(i))))
        tf = true;
        return;
    end
end
end

function vec = extract_account_vector(rawValue, targetLen, fieldLabel)
vec = [];
if isempty(rawValue)
    return;
end

arr = double(rawValue);
arr = squeeze(arr);
if isvector(arr)
    arr = arr(:);
    if numel(arr) >= targetLen
        vec = arr(1:targetLen);
        return;
    end
    error('m01_parse_city_mrio_mat:shortVector', ...
        '字段 %s 的长度只有 %d，无法提取前 %d 个部门值。', fieldLabel, numel(arr), targetLen);
end

if size(arr, 1) == 1 || size(arr, 2) == 1
    arr = arr(:);
    vec = arr(1:min(numel(arr), targetLen));
    if numel(vec) ~= targetLen
        error('m01_parse_city_mrio_mat:invalidVector', ...
            '字段 %s 无法被解释为长度 %d 的列向量。', fieldLabel, targetLen);
    end
    return;
end

if size(arr, 1) <= 10 && size(arr, 2) >= targetLen
    vec = arr(end, 1:targetLen)';
    return;
end

if size(arr, 2) <= 10 && size(arr, 1) >= targetLen
    vec = arr(1:targetLen, end);
    return;
end

error('m01_parse_city_mrio_mat:cannotParseField', ...
    '字段 %s 的尺寸为 %d x %d，当前无法稳健提取为长度 %d 的向量。', ...
    fieldLabel, size(arr,1), size(arr,2), targetLen);
end

function vec = extract_total_row_vector(rawValue, targetLen, fieldLabel)
arr = double(rawValue);
arr = squeeze(arr);
if isvector(arr)
    vec = arr(:);
    if numel(vec) ~= targetLen
        error('m01_parse_city_mrio_mat:invalidVA', ...
            '字段 %s 是向量，但长度为 %d，不等于目标长度 %d。', ...
            fieldLabel, numel(vec), targetLen);
    end
    return;
end

if size(arr, 1) <= 10 && size(arr, 2) >= targetLen
    vec = arr(end, 1:targetLen)';
    return;
end

if size(arr, 2) <= 10 && size(arr, 1) >= targetLen
    vec = arr(1:targetLen, end);
    return;
end

error('m01_parse_city_mrio_mat:invalidTotalRow', ...
    '字段 %s 的尺寸为 %d x %d，无法识别其合计行。', ...
    fieldLabel, size(arr,1), size(arr,2));
end

function [cityIds, labelsEn, labelsCn] = resolve_city_labels(meta, core, numCities)
cityIds = (1:numCities)';
labelsEn = strings(numCities, 1);
labelsCn = strings(numCities, 1);

value = resolve_optional_field(meta, ["City_Name"]);
if isempty(value)
    value = resolve_optional_field(core, ["City_Name"]);
end

if iscell(value) && ndims(value) == 2 && size(value, 1) >= numCities + 1 && size(value, 2) >= 3
    idCol = value(2:numCities+1, 1);
    enCol = value(2:numCities+1, 2);
    cnCol = value(2:numCities+1, 3);
    cityIds = parse_numeric_column(idCol, numCities);
    labelsEn = parse_text_column(enCol, numCities, "City");
    labelsCn = parse_text_column(cnCol, numCities, "城市");
    return;
end

labelsEn = resolve_label_vector(meta, core, ...
    ["City_Name", "CityName", "Region_Name", "RegionName", "City", "Cities"], numCities, "City");
labelsCn = labelsEn;
end

function labels = resolve_sector_labels(meta, core, numSectors)
labels = resolve_label_vector(meta, core, ...
    ["Sector_Name", "SectorName", "Sector", "Sectors"], numSectors, "Sector");
end

function labels = resolve_fd_labels(meta, core, numFD)
labels = resolve_label_vector(meta, core, ...
    ["F_Name", "FD_Name", "FDLabels", "FinalDemandLabels"], numFD, "FD");
end

function labels = resolve_label_vector(meta, core, candidates, expectedLen, prefixText)
labels = [];
source = {};
if isstruct(meta)
    source = [source; struct2cell(meta)]; %#ok<AGROW>
end
if isstruct(core)
    source = [source; struct2cell(core)]; %#ok<AGROW>
end

for i = 1:numel(candidates)
    value = resolve_optional_field(meta, candidates(i));
    if isempty(value)
        value = resolve_optional_field(core, candidates(i));
    end
    labels = try_parse_labels(value, expectedLen);
    if ~isempty(labels)
        return;
    end
end

for i = 1:numel(source)
    labels = try_parse_labels(source{i}, expectedLen);
    if ~isempty(labels)
        return;
    end
end

labels = strings(expectedLen, 1);
for i = 1:expectedLen
    labels(i) = sprintf('%s_%03d', prefixText, i);
end
end

function labels = try_parse_labels(value, expectedLen)
labels = [];
if isempty(value)
    return;
end

if isstring(value) || ischar(value) || iscellstr(value)
    vec = string(value);
    vec = vec(:);
    if numel(vec) == expectedLen
        labels = vec;
    end
    return;
end

if iscell(value)
    if ndims(value) == 2 && size(value, 1) >= expectedLen && size(value, 2) >= 2
        labels = parse_label_cell_matrix(value, expectedLen);
        if ~isempty(labels)
            return;
        end
    end
    mask = cellfun(@(x) ischar(x) || isstring(x), value);
    vec = string(value(mask));
    vec = vec(strlength(strtrim(vec)) > 0);
    vec = unique(vec, 'stable');
    if numel(vec) == expectedLen
        labels = vec(:);
    end
end
end

function labels = parse_label_cell_matrix(cellMat, expectedLen)
labels = [];
bestCol = [];
bestScore = -inf;
for j = 1:size(cellMat, 2)
    col = cellMat(:, j);
    textMask = cellfun(@(x) ischar(x) || isstring(x), col);
    txt = string(col(textMask));
    txt = strtrim(txt);
    txt = txt(strlength(txt) > 0);
    if numel(txt) > bestScore
        bestScore = numel(txt);
        bestCol = j;
    end
end

if isempty(bestCol)
    return;
end

col = cellMat(:, bestCol);
textMask = cellfun(@(x) ischar(x) || isstring(x), col);
txt = string(col(textMask));
txt = strtrim(txt);
txt = txt(strlength(txt) > 0);

if numel(txt) == expectedLen + 1
    txt = txt(2:end);
elseif numel(txt) > expectedLen
    txt = txt(end-expectedLen+1:end);
end

if numel(txt) == expectedLen
    labels = txt(:);
end
end

function ids = parse_numeric_column(col, expectedLen)
ids = (1:expectedLen)';
for i = 1:min(expectedLen, numel(col))
    x = col{i};
    if isnumeric(x) && isscalar(x)
        ids(i) = double(x);
    end
end
end

function labels = parse_text_column(col, expectedLen, prefixText)
labels = strings(expectedLen, 1);
for i = 1:min(expectedLen, numel(col))
    x = col{i};
    if ischar(x) || isstring(x)
        labels(i) = strtrim(string(x));
    end
end
mask = strlength(labels) == 0;
for i = find(mask)'
    labels(i) = sprintf('%s_%03d', prefixText, i);
end
end
