function out = m13_assemble_city_mrio_2020(zResult, yResult, targets, varargin)
% M13_ASSEMBLE_CITY_MRIO_2020
% m13 assemble city mrio 2020

p = inputParser;
p.addRequired('zResult', @isstruct);
p.addRequired('yResult', @isstruct);
p.addRequired('targets', @isstruct);
p.addParameter('OutputClass', "single", @(x) any(strcmpi(string(x), ["single","double"])));
p.addParameter('ResidualTol', 1e-6, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.addParameter('AllowResidualError', true, @(x) islogical(x) || isnumeric(x));
p.addParameter('XMode', "target", @(x) any(strcmpi(string(x), ["target","column_closed"])));
p.parse(zResult, yResult, targets, varargin{:});
opt = p.Results;

if ~isfield(zResult, 'blocks') || ~isfield(zResult, 'Mapping')
    error('m13_assemble_city_mrio_2020:invalidZResult', ...
        'zResult 必须包含 blocks 和 Mapping。');
end
if ~isfield(yResult, 'Y')
    error('m13_assemble_city_mrio_2020:invalidYResult', ...
        'yResult 必须包含 Y。');
end

map = zResult.Mapping;
NS = map.numCities * map.numSectors;
Nc = map.numCities;
F = map.numFD;
Z = assemble_z_blocks(zResult.blocks, map, char(opt.OutputClass));
Y = cast(yResult.Y, char(opt.OutputClass));
if ~isequal(size(Y), [NS, Nc * F])
    error('m13_assemble_city_mrio_2020:invalidYSize', ...
        'Y 的尺寸应为 %d x %d，但当前为 %d x %d。', NS, Nc*F, size(Y,1), size(Y,2));
end

VA = cast(targets.VA(:), char(opt.OutputClass));
IM = cast(targets.IM(:), char(opt.OutputClass));
EX = cast(targets.EX(:), char(opt.OutputClass));
if isfield(targets, 'error') && ~isempty(targets.error)
    errorTarget = cast(targets.error(:), char(opt.OutputClass));
else
    errorTarget = zeros(NS, 1, char(opt.OutputClass));
end
% 2020 部署轮沿用省级表 parser 与聚合校验口径：
% 行侧把 error 视为显式补差项；列侧不再把 error 并入投入端。
rowNoError = sum(double(Z), 2) + sum(double(Y), 2) + double(EX);
colSide = sum(double(Z), 1)' + double(VA) + double(IM);

if strcmpi(string(opt.XMode), "column_closed")
    % deployment 轮不再把城市级 X target 当作最终硬约束；
    % 最终 X 由列侧核算闭合，error 由行侧残差显式承接。
    X = cast(colSide, char(opt.OutputClass));
    errorVec = cast(double(X) - rowNoError, char(opt.OutputClass));
    rowResidual = double(X) - (rowNoError + double(errorVec));
    colResidual = double(X) - colSide;
else
    rowSide = rowNoError + double(errorTarget);
    if isfield(targets, 'X') && ~isempty(targets.X)
        X = cast(targets.X(:), char(opt.OutputClass));
        rowResidual = double(X) - rowSide;
        colResidual = double(X) - colSide;
    else
        X = cast(rowSide, char(opt.OutputClass));
        rowResidual = double(X) - rowSide;
        colResidual = double(X) - colSide;
    end

    if max(abs(colResidual)) <= opt.ResidualTol && max(abs(rowResidual)) <= opt.ResidualTol
        errorVec = errorTarget;
    else
        if logical(opt.AllowResidualError)
            % 若仍有微小行侧残差，只允许把它写回 error。
            % 列侧残差不能靠 error 修补，因此保留在诊断中显式暴露。
            errorVec = cast(double(errorTarget) + rowResidual, char(opt.OutputClass));
        else
            error('m13_assemble_city_mrio_2020:balanceNotReached', ...
                '城市 MRIO 组装后仍有 residual，rowMax=%g, colMax=%g，且 AllowResidualError=false。', ...
                max(abs(rowResidual)), max(abs(colResidual)));
        end
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

if isfield(targets, 'mapping') && isfield(targets.mapping, 'province_names')
    out.provinces = targets.mapping.province_names;
end
if isfield(targets, 'mapping')
    out.numCities = targets.mapping.numCities;
end

out.Diagnostics = struct();
out.Diagnostics.maxAbsResidual = max([max(abs(rowResidual)), max(abs(colResidual))]);
out.Diagnostics.maxAbsRowIdentity = max(abs(double(X) - (sum(double(Z),2) + sum(double(Y),2) + double(EX) + double(errorVec))));
out.Diagnostics.maxAbsColIdentity = max(abs(double(X) - (sum(double(Z),1)' + double(VA) + double(IM))));
if isfield(targets, 'X') && ~isempty(targets.X)
    out.Diagnostics.maxAbsTargetXGap = max(abs(double(X) - double(targets.X(:))));
end
out.Diagnostics.xMode = char(opt.XMode);
out.Diagnostics.outputClass = char(opt.OutputClass);
end

function Z = assemble_z_blocks(blocks, map, outputClass)
NS = map.numCities * map.numSectors;
Z = zeros(NS, NS, outputClass);
for pIdx = 1:map.numProvinces
    rowIdx = city_sector_indices(map.city_indices_by_province{pIdx}, map.numSectors);
    for qIdx = 1:map.numProvinces
        colIdx = city_sector_indices(map.city_indices_by_province{qIdx}, map.numSectors);
        Z(rowIdx, colIdx) = cast(blocks{pIdx, qIdx}, outputClass);
    end
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
