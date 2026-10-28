function out = m14_aggregate_city_to_province(cityMrio, mapping, varargin)
% M14_AGGREGATE_CITY_TO_PROVINCE
% 1. 把真实 2017 城市 MRIO 聚合回省级，用于检验 parser 与映射是否正确；
%   2. 把下推后的 2020 城市 MRIO 聚合回省级，用于检验是否满足精确省级约束。
% 输入：
%   cityMrio : 城市 canonical struct，至少包含 Z / Y / VA / IM / EX / X
%   mapping  : m03_build_city_province_mapping 的输出，或可转成该输出的输入
% 可选参数：
%   'TargetProv'  : 用于直接比较的省级 canonical struct
%   'Mode'        : 'strict' 或 'harmonized'，默认 'strict'
%   'ReportFile'  : 若提供，则把比较结果写成 CSV
%   'Validate'    : 是否做核算检查，默认 true
% 输出：
%   out.aggregated
%   out.Mapping
%   out.Diagnostics
%   out.ReportTable
% 注意事项：
%   1. strict 模式只报告原值聚合误差，不改任何数据；
%   2. harmonized 模式会额外给出“若先按省级总量做比例协调”的参考误差，但不会覆盖 strict 结果。

p = inputParser;
p.addRequired('cityMrio', @isstruct);
p.addRequired('mapping');
p.addParameter('TargetProv', struct(), @isstruct);
p.addParameter('Mode', "strict", @(x) any(strcmpi(string(x), ["strict","harmonized"])));
p.addParameter('ReportFile', "", @(x) ischar(x) || isstring(x));
p.addParameter('Validate', true, @(x) islogical(x) || isnumeric(x));
p.parse(cityMrio, mapping, varargin{:});
opt = p.Results;

city = normalize_city_canonical(cityMrio);
map = normalize_mapping_input(mapping, city);

Zp = map.A * city.Z * map.A';
Yp = map.A * city.Y * map.B';
Xp = map.A * city.X;
VAp = map.A * city.VA;
IMp = map.A * city.IM;
EXp = map.A * city.EX;
ERRp = map.A * city.error;

aggregated = struct();
aggregated.Z = Zp;
aggregated.Y = Yp;
aggregated.VA = VAp;
aggregated.IM = IMp;
aggregated.EX = EXp;
aggregated.X = Xp;
aggregated.error = ERRp;
aggregated.provinces = map.province_names;
aggregated.sectors = city.sectors;
aggregated.fd_labels = city.fd_labels;

Diagnostics = struct();
Diagnostics.maxAbsRowIdentity = max(abs(sum(Zp,2) + sum(Yp,2) + EXp + ERRp - Xp));
Diagnostics.maxAbsColIdentity = max(abs(sum(Zp,1)' + VAp + IMp - Xp));
Diagnostics.mode = string(opt.Mode);

reportTable = table();
if ~isempty(fieldnames(opt.TargetProv))
    target = normalize_prov_canonical(opt.TargetProv);
    reportTable = build_compare_report(aggregated, target, string(opt.Mode));
    Diagnostics.targetCompare = reportTable;
    if strcmpi(string(opt.Mode), "harmonized")
        Diagnostics.harmonizedReference = build_compare_report( ...
            harmonize_city_aggregate_to_target(aggregated, target), target, "harmonized");
    end
end

if logical(opt.Validate)
    if Diagnostics.maxAbsRowIdentity > 1e-4
        error('m14_aggregate_city_to_province:rowIdentityFailed', ...
            '城市聚合后的省级表行核算失败，maxAbs=%g。', Diagnostics.maxAbsRowIdentity);
    end
end

if strlength(strtrim(string(opt.ReportFile))) > 0 && ~isempty(reportTable)
    writetable(reportTable, string(opt.ReportFile));
end

out = struct();
out.aggregated = aggregated;
out.Mapping = map;
out.Diagnostics = Diagnostics;
out.ReportTable = reportTable;
end

function city = normalize_city_canonical(city)
required = ["Z","Y","VA","IM","EX","X"];
for i = 1:numel(required)
    if ~isfield(city, required(i))
        error('m14_aggregate_city_to_province:missingCityField', ...
            '城市 canonical struct 缺少字段 %s。', required(i));
    end
end
if ~isfield(city, 'error') || isempty(city.error)
    city.error = zeros(size(city.X));
end
if ~isfield(city, 'sectors') || isempty(city.sectors)
    city.sectors = strings(42,1);
    for i = 1:42
        city.sectors(i) = sprintf('Sector_%02d', i);
    end
end
if ~isfield(city, 'fd_labels') || isempty(city.fd_labels)
    city.fd_labels = ["FD_1";"FD_2";"FD_3";"FD_4";"FD_5"];
end
end

function map = normalize_mapping_input(mapping, city)
if isstruct(mapping) && isfield(mapping, 'A') && isfield(mapping, 'B')
    map = mapping;
    return;
end
numCities = size(city.Y, 2) / numel(city.fd_labels);
numSectors = size(city.Z, 1) / numCities;
map = m03_build_city_province_mapping(mapping, ...
    'NumCities', numCities, ...
    'NumSectors', numSectors, ...
    'NumFD', numel(city.fd_labels));
end

function target = normalize_prov_canonical(target)
required = ["Z","Y","VA","IM","EX","X"];
for i = 1:numel(required)
    if ~isfield(target, required(i))
        error('m14_aggregate_city_to_province:missingTargetField', ...
            'TargetProv 缺少字段 %s。', required(i));
    end
end
if ~isfield(target, 'error') || isempty(target.error)
    target.error = zeros(size(target.X));
end
end

function T = build_compare_report(agg, target, modeLabel)
metric = ["Z_inf"; "Y_inf"; "X_inf"; "VA_inf"; "IM_inf"; "EX_inf"; "error_inf"];
value = [ ...
    max(abs(agg.Z(:) - target.Z(:))); ...
    max(abs(agg.Y(:) - target.Y(:))); ...
    max(abs(agg.X(:) - target.X(:))); ...
    max(abs(agg.VA(:) - target.VA(:))); ...
    max(abs(agg.IM(:) - target.IM(:))); ...
    max(abs(agg.EX(:) - target.EX(:))); ...
    max(abs(agg.error(:) - target.error(:)))];
T = table(repmat(string(modeLabel), numel(metric), 1), metric, value, ...
    'VariableNames', {'mode','metric','value'});
end

function aggH = harmonize_city_aggregate_to_target(agg, target)
aggH = agg;
aggH.X = target.X;
aggH.VA = rescale_by_group(agg.VA, agg.X, target.X);
aggH.IM = rescale_by_group(agg.IM, agg.X, target.X);
aggH.EX = rescale_by_group(agg.EX, agg.X, target.X);
aggH.error = rescale_by_group(agg.error, agg.X, target.X);
end

function vecOut = rescale_by_group(vecIn, baseX, targetX)
scale = ones(size(baseX));
mask = abs(baseX) > 0;
scale(mask) = targetX(mask) ./ baseX(mask);
vecOut = vecIn .* scale;
end
