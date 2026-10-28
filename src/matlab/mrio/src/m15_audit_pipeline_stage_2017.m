function auditRow = m15_audit_pipeline_stage_2017(stageName, stagePayload, truthCity, mapping, varargin)
% M15_AUDIT_PIPELINE_STAGE_2017
% Write one machine-readable audit row for a specific pipeline stage.

p = inputParser;
p.addRequired('stageName', @(x) ischar(x) || isstring(x));
p.addRequired('stagePayload');
p.addRequired('truthCity', @(x) isstruct(x) && isfield(x, 'Z') && isfield(x, 'Y'));
p.addRequired('mapping', @(x) isstruct(x) && isfield(x, 'A'));
p.addParameter('ProvTarget', struct(), @isstruct);
p.addParameter('OutputPath', "", @(x) ischar(x) || isstring(x));
p.addParameter('Append', true, @(x) islogical(x) || isnumeric(x));
p.addParameter('Note', "", @(x) ischar(x) || isstring(x));
p.parse(stageName, stagePayload, truthCity, mapping, varargin{:});
opt = p.Results;

stageName = string(stageName);
truth = truthCity;
map = mapping;

if isstruct(stagePayload) && isfield(stagePayload, 'Z') && isfield(stagePayload, 'Y')
    auditRow = build_city_stage_row(stageName, stagePayload, truth, map, opt.ProvTarget, string(opt.Note));
elseif isstruct(stagePayload) && isfield(stagePayload, 'Z_row_target') && isfield(stagePayload, 'Y_row_by_fd')
    auditRow = build_target_stage_row(stageName, stagePayload, truth, map, opt.ProvTarget, string(opt.Note));
else
    error('m15_audit_pipeline_stage_2017:UnsupportedPayload', ...
        'stagePayload must be either a city-like struct or a target struct.');
end

outputPath = string(opt.OutputPath);
if strlength(strtrim(outputPath)) > 0
    if logical(opt.Append) && exist(outputPath, 'file')
        existing = readtable(outputPath, 'TextType', 'string');
        combined = [existing; auditRow]; %#ok<AGROW>
        writetable(combined, outputPath);
    else
        writetable(auditRow, outputPath);
    end
end
end

function auditRow = build_city_stage_row(stageName, stageCity, truth, map, provTarget, noteText)
stage = cast_city_struct_to_double(stageCity);
truth = cast_city_struct_to_double(truth);

rowIdentity = max(abs(stage.X - (sum(stage.Z, 2) + sum(stage.Y, 2) + stage.EX)));
colIdentity = max(abs(stage.X - (sum(stage.Z, 1)' + stage.VA + stage.IM + stage.error)));

[provZ, provY, provX, provVA, provIM, provEX, provError] = aggregate_city_stage(stage, map);
[provZG, provYG, provXG, provVAG, provIMG, provEXG, provErrorG] = compare_optional_prov(provTarget, provZ, provY, provX, provVA, provIM, provEX, provError);

auditRow = table( ...
    stageName, ...
    "city", ...
    inf_gap(stage.Z, truth.Z), ...
    inf_gap(stage.Y, truth.Y), ...
    inf_gap(stage.X, truth.X), ...
    inf_gap(stage.VA, truth.VA), ...
    inf_gap(stage.IM, truth.IM), ...
    inf_gap(stage.EX, truth.EX), ...
    inf_gap(stage.error, truth.error), ...
    rowIdentity, ...
    colIdentity, ...
    provZG, ...
    provYG, ...
    provXG, ...
    provVAG, ...
    provIMG, ...
    provEXG, ...
    provErrorG, ...
    noteText, ...
    'VariableNames', {'stage','payload_kind','Z_inf','Y_inf','X_inf','VA_inf','IM_inf','EX_inf','error_inf', ...
    'row_identity_max','col_identity_max','prov_Z_inf','prov_Y_inf','prov_X_inf','prov_VA_inf','prov_IM_inf','prov_EX_inf','prov_error_inf','note'});
end

function auditRow = build_target_stage_row(stageName, targets, truth, map, provTarget, noteText)
truthZRow = sum(double(truth.Z), 2);
truthZCol = sum(double(truth.Z), 1)';
truthYRow = build_truth_y_row_fd(truth);
truthYCol = build_truth_y_col_fd(truth);

Zinf = max([max(abs(double(targets.Z_row_target(:)) - truthZRow)), max(abs(double(targets.Z_col_target(:)) - truthZCol))]);
Yinf = max([max(abs(double(targets.Y_row_by_fd) - truthYRow), [], 'all'), ...
    max(abs(double(targets.Y_col_by_fd) - truthYCol), [], 'all')]);

provTarget = normalize_optional_prov(provTarget);
rowIdentity = max(abs(double(targets.X(:)) - ...
    (double(targets.Z_row_target(:)) + sum(double(targets.Y_row_by_fd), 2) + double(targets.EX(:)))));
colIdentity = max(abs(double(targets.X(:)) - ...
    (double(targets.Z_col_target(:)) + double(targets.VA(:)) + double(targets.IM(:)))));

[provZInf, provYInf, provXInf, provVAInf, provIMInf, provEXInf] = ...
    resolve_target_prov_metrics(targets, map, provTarget);

auditRow = table( ...
    stageName, ...
    "targets", ...
    Zinf, ...
    Yinf, ...
    inf_gap(double(targets.X(:)), double(truth.X(:))), ...
    inf_gap(double(targets.VA(:)), double(truth.VA(:))), ...
    inf_gap(double(targets.IM(:)), double(truth.IM(:))), ...
    inf_gap(double(targets.EX(:)), double(truth.EX(:))), ...
    NaN, ...
    rowIdentity, ...
    colIdentity, ...
    provZInf, ...
    provYInf, ...
    provXInf, ...
    provVAInf, ...
    provIMInf, ...
    provEXInf, ...
    NaN, ...
    noteText, ...
    'VariableNames', {'stage','payload_kind','Z_inf','Y_inf','X_inf','VA_inf','IM_inf','EX_inf','error_inf', ...
    'row_identity_max','col_identity_max','prov_Z_inf','prov_Y_inf','prov_X_inf','prov_VA_inf','prov_IM_inf','prov_EX_inf','prov_error_inf','note'});
end

function [provZInf, provYInf, provXInf, provVAInf, provIMInf, provEXInf] = resolve_target_prov_metrics(targets, map, provTarget)
provZInf = NaN;
provYInf = NaN;
provXInf = NaN;
provVAInf = NaN;
provIMInf = NaN;
provEXInf = NaN;

if isfield(targets, 'Diagnostics')
    diagFields = string(fieldnames(targets.Diagnostics));
    if any(diagFields == "prov_Z_inf"); provZInf = double(targets.Diagnostics.prov_Z_inf); end
    if any(diagFields == "prov_Y_inf"); provYInf = double(targets.Diagnostics.prov_Y_inf); end
    if any(diagFields == "prov_X_inf"); provXInf = double(targets.Diagnostics.prov_X_inf); end
    if any(diagFields == "prov_VA_inf"); provVAInf = double(targets.Diagnostics.prov_VA_inf); end
    if any(diagFields == "prov_IM_inf"); provIMInf = double(targets.Diagnostics.prov_IM_inf); end
    if any(diagFields == "prov_EX_inf"); provEXInf = double(targets.Diagnostics.prov_EX_inf); end
end

if isempty(fieldnames(provTarget))
    return;
end

if isnan(provXInf)
    provXInf = inf_gap(map.A * double(targets.X(:)), double(provTarget.X(:)));
end
if isnan(provVAInf)
    provVAInf = inf_gap(map.A * double(targets.VA(:)), double(provTarget.VA(:)));
end
if isnan(provIMInf)
    provIMInf = inf_gap(map.A * double(targets.IM(:)), double(provTarget.IM(:)));
end
if isnan(provEXInf)
    provEXInf = inf_gap(map.A * double(targets.EX(:)), double(provTarget.EX(:)));
end

if isnan(provYInf) && isfield(targets, 'Y_city') && ~isempty(targets.Y_city)
    provYInf = inf_gap(map.A * double(targets.Y_city) * map.B', double(provTarget.Y));
end
if isnan(provZInf) && isfield(targets, 'prov_Z_row_target') && isfield(provTarget, 'Z')
    provZRowTruth = sum(double(provTarget.Z), 2);
    provZColTruth = sum(double(provTarget.Z), 1)';
    provZInf = max([inf_gap(double(targets.prov_Z_row_target(:)), provZRowTruth(:)), ...
        inf_gap(double(targets.prov_Z_col_target(:)), provZColTruth(:))]);
end
end

function Yrow = build_truth_y_row_fd(city)
F = numel(city.fd_labels);
Yrow = zeros(numel(city.X), F);
for f = 1:F
    Yrow(:, f) = sum(double(city.Y(:, f:F:end)), 2);
end
end

function Ycol = build_truth_y_col_fd(city)
F = numel(city.fd_labels);
Nc = size(city.Y, 2) / F;
Ycol = zeros(Nc, F);
for f = 1:F
    Ycol(:, f) = sum(double(city.Y(:, f:F:end)), 1)';
end
end

function [provZ, provY, provX, provVA, provIM, provEX, provError] = aggregate_city_stage(city, map)
provZ = double(map.A * city.Z * map.A');
provY = double(map.A * city.Y * map.B');
provX = double(map.A * city.X);
provVA = double(map.A * city.VA);
provIM = double(map.A * city.IM);
provEX = double(map.A * city.EX);
provError = double(map.A * city.error);
end

function [provZG, provYG, provXG, provVAG, provIMG, provEXG, provErrorG] = compare_optional_prov(provTarget, provZ, provY, provX, provVA, provIM, provEX, provError)
provTarget = normalize_optional_prov(provTarget);
if isempty(fieldnames(provTarget))
    provZG = NaN;
    provYG = NaN;
    provXG = NaN;
    provVAG = NaN;
    provIMG = NaN;
    provEXG = NaN;
    provErrorG = NaN;
    return;
end
provZG = inf_gap(provZ, double(provTarget.Z));
provYG = inf_gap(provY, double(provTarget.Y));
provXG = inf_gap(provX, double(provTarget.X));
provVAG = inf_gap(provVA, double(provTarget.VA));
provIMG = inf_gap(provIM, double(provTarget.IM));
provEXG = inf_gap(provEX, double(provTarget.EX));
provErrorG = inf_gap(provError, double(provTarget.error));
end

function provTarget = normalize_optional_prov(provTarget)
if isempty(provTarget)
    provTarget = struct();
end
end

function value = inf_gap(A, B)
value = max(abs(double(A(:)) - double(B(:))));
end

function city = cast_city_struct_to_double(city)
fields = ["Z","Y","VA","IM","EX","X","error"];
for i = 1:numel(fields)
    city.(fields(i)) = double(city.(fields(i)));
end
end
