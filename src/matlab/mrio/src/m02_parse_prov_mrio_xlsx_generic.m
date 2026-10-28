function out = m02_parse_prov_mrio_xlsx_generic(xlsxPath, varargin)
% M02_PARSE_PROV_MRIO_XLSX_GENERIC
% Parse provincial MRIO Excel workbooks for 2017 and 2020 into one canonical structure.

p = inputParser;
p.addRequired('xlsxPath', @(x) ischar(x) || isstring(x));
p.addParameter('MainSheet', "", @(x) ischar(x) || isstring(x));
p.addParameter('ProvinceSheet', "", @(x) ischar(x) || isstring(x));
p.addParameter('SectorSheet', "", @(x) ischar(x) || isstring(x));
p.addParameter('NumProvinces', 31, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.addParameter('NumSectors', 42, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.addParameter('NumFD', 5, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.addParameter('Validate', true, @(x) islogical(x) || isnumeric(x));
p.parse(xlsxPath, varargin{:});
opt = p.Results;

xlsxPath = string(xlsxPath);
sheetList = string(sheetnames(xlsxPath));
mainSheet = resolve_main_sheet_name(sheetList, opt.MainSheet);
provinceSheet = resolve_label_sheet_name(sheetList, opt.ProvinceSheet, ["Province"]);
sectorSheet = resolve_label_sheet_name(sheetList, opt.SectorSheet, ["Sector"]);

PS = opt.NumProvinces * opt.NumSectors;
PF = opt.NumProvinces * opt.NumFD;
layout = build_base_layout(PS, PF);
layout = detect_footer_and_header_layout(xlsxPath, mainSheet, layout);

provinces = parse_label_sheet_from_sheet(xlsxPath, provinceSheet, opt.NumProvinces, "Province");
sectors = parse_label_sheet_from_sheet(xlsxPath, sectorSheet, opt.NumSectors, "Sector");
fdLabels = default_fd_labels(opt.NumFD);
vaLabels = parse_va_labels(xlsxPath, mainSheet, layout);

Z = read_numeric_range(xlsxPath, mainSheet, layout.dataRowFirst, layout.zColFirst, layout.dataRowLast, layout.zColLast);
F = read_numeric_range(xlsxPath, mainSheet, layout.dataRowFirst, layout.fdColFirst, layout.dataRowLast, layout.fdColLast);
EX = read_numeric_range(xlsxPath, mainSheet, layout.dataRowFirst, layout.colEX, layout.dataRowLast, layout.colEX);
errorVec = read_numeric_range(xlsxPath, mainSheet, layout.dataRowFirst, layout.colERR, layout.dataRowLast, layout.colERR);
X = read_numeric_range(xlsxPath, mainSheet, layout.dataRowFirst, layout.colGO, layout.dataRowLast, layout.colGO);
IM = read_numeric_range(xlsxPath, mainSheet, layout.rowIM, layout.zColFirst, layout.rowIM, layout.zColLast)';
VAblock = read_numeric_range(xlsxPath, mainSheet, layout.rowVAStart, layout.zColFirst, layout.rowTVA, layout.zColLast);
VA = VAblock(end, :)';

MRIO = struct();
MRIO.Z = Z;
MRIO.F = F;
MRIO.Y = F;
MRIO.VA = VA;
MRIO.IM = IM;
MRIO.EX = EX;
MRIO.error = errorVec;
MRIO.X = X;

Meta = struct();
Meta.SourceWorkbook = char(xlsxPath);
Meta.MainSheet = char(mainSheet);
Meta.ProvinceSheet = char(provinceSheet);
Meta.SectorSheet = char(sectorSheet);
Meta.Province_Name = provinces(:);
Meta.Sector_Name = sectors(:);
Meta.F_Name = fdLabels(:);
Meta.VA_Name = vaLabels(:);

ParserInfo = struct();
ParserInfo.mainSheet = char(mainSheet);
ParserInfo.provinceSheet = char(provinceSheet);
ParserInfo.sectorSheet = char(sectorSheet);
ParserInfo.availableSheets = cellstr(sheetList);

Diagnostics = struct();
Diagnostics.sourcePath = char(xlsxPath);
Diagnostics.ParserInfo = ParserInfo;
Diagnostics.Layout = layout;
Diagnostics.maxAbsRowIdentity = max(abs(sum(Z, 2) + sum(F, 2) + EX + errorVec - X));
Diagnostics.maxAbsColIdentity = max(abs(sum(Z, 1)' + VA + IM - X));
Diagnostics.provinceCount = numel(provinces);
Diagnostics.sectorCount = numel(sectors);
Diagnostics.fdCount = numel(fdLabels);

if logical(opt.Validate)
    assert(layout.labelChecks.importRowOk, 'm02_parse_prov_mrio_xlsx_generic:ImportRowNotFound', ...
        'Failed to locate the provincial Import row on the selected sheet.');
    assert(layout.labelChecks.tvaRowOk, 'm02_parse_prov_mrio_xlsx_generic:TVARowNotFound', ...
        'Failed to locate the Total Value Added row on the selected sheet.');
    assert(layout.labelChecks.exColOk, 'm02_parse_prov_mrio_xlsx_generic:EXColumnNotFound', ...
        'Failed to locate the EX column on the selected sheet.');
    assert(layout.labelChecks.goColOk, 'm02_parse_prov_mrio_xlsx_generic:GOColumnNotFound', ...
        'Failed to locate the GO column on the selected sheet.');
    if Diagnostics.maxAbsRowIdentity > 1e-2
        error('m02_parse_prov_mrio_xlsx_generic:RowIdentityFailed', ...
            'The provincial workbook failed the row-side identity check. maxAbs=%g', ...
            Diagnostics.maxAbsRowIdentity);
    end
end

out = struct();
out.MRIO = MRIO;
out.Meta = Meta;
out.Diagnostics = Diagnostics;
out.ParserInfo = ParserInfo;

% Flat mirrors are returned for convenience in downstream standalone scripts.
out.Z = MRIO.Z;
out.F = MRIO.F;
out.Y = MRIO.Y;
out.VA = MRIO.VA;
out.IM = MRIO.IM;
out.EX = MRIO.EX;
out.error = MRIO.error;
out.X = MRIO.X;
out.provinces = Meta.Province_Name;
out.sectors = Meta.Sector_Name;
out.fd_labels = Meta.F_Name;
end

function layout = build_base_layout(PS, PF)
layout = struct();
layout.dataRowFirst = 5;
layout.dataRowLast = layout.dataRowFirst + PS - 1;
layout.zColFirst = 4;
layout.zColLast = layout.zColFirst + PS - 1;
layout.colTII = layout.zColLast + 1;
layout.fdColFirst = layout.colTII + 1;
layout.fdColLast = layout.fdColFirst + PF - 1;
layout.colEX = layout.fdColLast + 1;
layout.colTFU = layout.colEX + 1;
layout.colERR = layout.colTFU + 1;
layout.colGO = layout.colERR + 1;
layout.rowIM = layout.dataRowLast + 1;
layout.rowTII = layout.dataRowLast + 2;
layout.rowVAStart = layout.dataRowLast + 3;
layout.rowTVA = layout.dataRowLast + 7;
layout.rowTI = layout.dataRowLast + 8;
end

function layout = detect_footer_and_header_layout(xlsxPath, mainSheet, layout)
footerRange = sprintf('A%d:C%d', layout.dataRowLast + 1, layout.dataRowLast + 14);
footerCells = readcell(xlsxPath, 'Sheet', char(mainSheet), 'Range', footerRange);
footerText = lower(join_strings(footerCells));

rowOffset = find_label_row_offset(footerCells, @(s) any(strcmp(s, ["im","import"])) || contains(s, "import"));
tvaOffset = find_label_row_offset(footerCells, @(s) any(strcmp(s, ["tva","total value added"])) || contains(s, "total value added"));
tiOffset = find_label_row_offset(footerCells, @(s) strcmp(s, "ti") || contains(s, "total input"));

if ~isempty(rowOffset)
    layout.rowIM = layout.dataRowLast + rowOffset;
end
if ~isempty(tvaOffset)
    layout.rowTVA = layout.dataRowLast + tvaOffset;
end
if ~isempty(tiOffset)
    layout.rowTI = layout.dataRowLast + tiOffset;
end

vaStartOffset = find_label_row_offset(footerCells, @(s) startsWith(s, "va") || contains(s, "value added"));
if ~isempty(vaStartOffset)
    layout.rowVAStart = layout.dataRowLast + vaStartOffset;
end

headerRange = sprintf('%s4:%s4', xlcol(layout.fdColFirst), xlcol(layout.colGO));
headerCells = readcell(xlsxPath, 'Sheet', char(mainSheet), 'Range', headerRange);
headerText = lower(join_strings(headerCells));

layout.labelChecks = struct();
layout.labelChecks.importRowOk = ~isempty(rowOffset);
layout.labelChecks.tvaRowOk = ~isempty(tvaOffset);
layout.labelChecks.tiRowOk = ~isempty(tiOffset);
layout.labelChecks.exColOk = any(strcmp(headerText, "ex")) || any(contains(headerText, "export"));
layout.labelChecks.goColOk = any(strcmp(headerText, "go")) || any(contains(headerText, "gross output"));
layout.labelChecks.footerPreview = footerText;
layout.labelChecks.headerPreview = headerText;
end

function rowOffset = find_label_row_offset(cellBlock, matcher)
rowOffset = [];
for i = 1:size(cellBlock, 1)
    rowText = lower(join_strings(cellBlock(i, :)));
    if isempty(rowText)
        continue;
    end
    if any(arrayfun(matcher, rowText))
        rowOffset = i;
        return;
    end
end
end

function labels = parse_label_sheet_from_sheet(xlsxPath, sheetName, expectedLen, prefixText)
cellData = trim_empty_edges(readcell(xlsxPath, 'Sheet', char(sheetName)));
labels = parse_label_sheet(cellData, expectedLen, prefixText);
end

function labels = parse_label_sheet(cellData, expectedLen, prefixText)
rows = cellData(2:end, :);
labels = strings(0, 1);
for i = 1:size(rows, 1)
    rowText = join_strings(rows(i, :));
    if isempty(rowText)
        continue;
    end
    if numel(rowText) >= 2
        labels(end+1, 1) = rowText(2); %#ok<AGROW>
    else
        labels(end+1, 1) = rowText(1); %#ok<AGROW>
    end
end
if numel(labels) < expectedLen
    labels = strings(expectedLen, 1);
    for i = 1:expectedLen
        labels(i) = sprintf('%s_%03d', prefixText, i);
    end
else
    labels = labels(1:expectedLen);
end
end

function vaLabels = parse_va_labels(xlsxPath, mainSheet, layout)
rowCount = max(layout.rowTVA - layout.rowVAStart + 1, 1);
range = sprintf('A%d:C%d', layout.rowVAStart, layout.rowVAStart + rowCount - 1);
cells = readcell(xlsxPath, 'Sheet', char(mainSheet), 'Range', range);
vaLabels = strings(0, 1);
for i = 1:size(cells, 1)
    rowText = join_strings(cells(i, :));
    if isempty(rowText)
        continue;
    end
    vaLabels(end+1, 1) = rowText(1); %#ok<AGROW>
end
if isempty(vaLabels)
    vaLabels = ["VA001"; "VA002"; "VA003"; "VA004"; "TVA"];
end
end

function fdLabels = default_fd_labels(numFD)
base = ["Rural household consumption"; ...
    "Urban household consumption"; ...
    "Government consumption"; ...
    "Fixed capital formation"; ...
    "Changes in inventories"];
if numFD <= numel(base)
    fdLabels = base(1:numFD);
else
    fdLabels = strings(numFD, 1);
    fdLabels(1:numel(base)) = base;
    for i = numel(base)+1:numFD
        fdLabels(i) = sprintf('FD_%02d', i);
    end
end
end

function M = read_numeric_range(xlsxPath, sheetName, r1, c1, r2, c2)
range = sprintf('%s%d:%s%d', xlcol(c1), r1, xlcol(c2), r2);
M = readmatrix(xlsxPath, 'Sheet', char(sheetName), 'Range', range);
if isempty(M)
    M = zeros(r2-r1+1, c2-c1+1);
end
M = double(M);
M(isnan(M)) = 0;
end

function data = trim_empty_edges(data)
if isempty(data)
    return;
end
rowKeep = false(size(data, 1), 1);
for i = 1:size(data, 1)
    rowKeep(i) = any(~cellfun(@is_effectively_empty, data(i, :)));
end
colKeep = false(1, size(data, 2));
for j = 1:size(data, 2)
    colKeep(j) = any(~cellfun(@is_effectively_empty, data(:, j)));
end
data = data(rowKeep, colKeep);
end

function tf = is_effectively_empty(x)
tf = isempty(x) || (isstring(x) && all(strlength(x) == 0)) || (ischar(x) && isempty(strtrim(x)));
end

function values = join_strings(cellsIn)
values = strings(0, 1);
for i = 1:numel(cellsIn)
    x = cellsIn{i};
    if ischar(x) || isstring(x)
        txt = strtrim(string(x));
        if strlength(txt) > 0
            values(end+1, 1) = txt; %#ok<AGROW>
        end
    end
end
end

function sheet = resolve_main_sheet_name(allSheets, preferred)
preferred = string(preferred);
if strlength(strtrim(preferred)) > 0
    sheet = resolve_exact_sheet(allSheets, preferred);
    return;
end

priority = [ ...
    "Table_2017_consistent"; ...
    "English_Version"; ...
    "Table_2017"; ...
    "Table_2020_English Version"; ...
    "Table_2020"; ...
    "Table_2017_English Version"; ...
    "Table_2020_English"; ...
    "Table_2020_English version"];

for i = 1:numel(priority)
    hit = resolve_exact_sheet(allSheets, priority(i), false);
    if strlength(hit) > 0
        sheet = hit;
        return;
    end
end

lowerSheets = lower(allSheets);
maskConsistent = contains(lowerSheets, "consistent") & contains(lowerSheets, "table");
if any(maskConsistent)
    sheet = allSheets(find(maskConsistent, 1, 'first'));
    return;
end

maskEnglish = contains(lowerSheets, "english") & ~contains(lowerSheets, "province") & ~contains(lowerSheets, "sector");
if any(maskEnglish)
    sheet = allSheets(find(maskEnglish, 1, 'first'));
    return;
end

maskTable = contains(lowerSheets, "table") & ~contains(lowerSheets, "province") & ~contains(lowerSheets, "sector");
if any(maskTable)
    sheet = allSheets(find(maskTable, 1, 'first'));
    return;
end

error('m02_parse_prov_mrio_xlsx_generic:MainSheetNotFound', ...
    'Could not identify the main provincial MRIO sheet.');
end

function sheet = resolve_label_sheet_name(allSheets, preferred, candidates)
preferred = string(preferred);
if strlength(strtrim(preferred)) > 0
    sheet = resolve_exact_sheet(allSheets, preferred);
    return;
end

for i = 1:numel(candidates)
    hit = resolve_exact_sheet(allSheets, string(candidates(i)), false);
    if strlength(hit) > 0
        sheet = hit;
        return;
    end
end

lowerSheets = lower(allSheets);
for i = 1:numel(candidates)
    mask = contains(lowerSheets, lower(string(candidates(i))));
    if any(mask)
        sheet = allSheets(find(mask, 1, 'first'));
        return;
    end
end

error('m02_parse_prov_mrio_xlsx_generic:LabelSheetNotFound', ...
    'Could not identify the required label sheet.');
end

function sheet = resolve_exact_sheet(allSheets, target, hardFail)
if nargin < 3
    hardFail = true;
end
hit = allSheets(strcmpi(strtrim(allSheets), strtrim(string(target))));
if isempty(hit)
    if hardFail
        error('m02_parse_prov_mrio_xlsx_generic:SheetNotFound', ...
            'Required sheet "%s" was not found.', string(target));
    end
    sheet = "";
    return;
end
sheet = hit(1);
end

function out = xlcol(n)
out = '';
while n > 0
    r = mod(n - 1, 26);
    out = [char(65 + r), out]; %#ok<AGROW>
    n = floor((n - 1) / 26);
end
end
