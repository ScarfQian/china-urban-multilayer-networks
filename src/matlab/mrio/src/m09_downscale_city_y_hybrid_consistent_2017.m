function out = m09_downscale_city_y_hybrid_consistent_2017(cityBase, provTarget, mapping, factorizedParams, hybridParams, varargin)
% M09_DOWNSCALE_CITY_Y_HYBRID_CONSISTENT_2017
% Build province-consistent city Y by mixing the current baseline and factorized share models.

p = inputParser;
p.addRequired('cityBase', @(x) isstruct(x) && isfield(x, 'Y') && isfield(x, 'X'));
p.addRequired('provTarget', @(x) isstruct(x) && isfield(x, 'Y'));
p.addRequired('mapping', @(x) isstruct(x) && isfield(x, 'city_indices_by_province'));
p.addRequired('factorizedParams', @isstruct);
p.addRequired('hybridParams', @isstruct);
p.addParameter('TargetX', [], @(x) isempty(x) || isnumeric(x));
p.addParameter('TargetYColByFD', [], @(x) isempty(x) || isnumeric(x));
p.addParameter('WeightSpec', struct(), @isstruct);
p.addParameter('ProxyTable', [], @(x) true);
p.addParameter('Eta', [1 1 1], @(x) isnumeric(x) && numel(x) == 3);
p.addParameter('BaselineY', [], @(x) isempty(x) || isnumeric(x) || isstruct(x));
p.addParameter('FactorizedY', [], @(x) isempty(x) || isnumeric(x) || isstruct(x));
p.addParameter('NumericClass', "double", @(x) any(strcmpi(string(x), ["single","double"])));
p.addParameter('Epsilon', 1e-12, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.addParameter('TopSupportCount', 3, @(x) isnumeric(x) && isscalar(x) && x >= 1);
p.addParameter('Validate', true, @(x) islogical(x) || isnumeric(x));
p.parse(cityBase, provTarget, mapping, factorizedParams, hybridParams, varargin{:});
opt = p.Results;

baselineOut = normalize_y_input(opt.BaselineY);
if isempty(baselineOut)
    baselineOut = m08_downscale_city_y_forecast_style_consistent_2017(cityBase, provTarget, mapping, ...
        'WeightSpec', opt.WeightSpec, ...
        'ProxyTable', opt.ProxyTable, ...
        'Eta', opt.Eta, ...
        'NumericClass', char(opt.NumericClass), ...
        'Epsilon', opt.Epsilon, ...
        'Validate', logical(opt.Validate));
end

factorizedOut = normalize_y_input(opt.FactorizedY);
if isempty(factorizedOut)
    factorizedOut = m07_downscale_city_y_factorized_consistent_2017(cityBase, provTarget, mapping, factorizedParams, ...
        'TargetX', opt.TargetX, ...
        'TargetYColByFD', opt.TargetYColByFD, ...
        'ProxyTable', opt.ProxyTable, ...
        'NumericClass', char(opt.NumericClass), ...
        'Epsilon', opt.Epsilon, ...
        'Validate', logical(opt.Validate));
end

hybridCore = m06_build_city_y_hybrid_shares(double(baselineOut.Y), double(factorizedOut.Y), provTarget, mapping, hybridParams, ...
    'Epsilon', opt.Epsilon, ...
    'TopSupportCount', opt.TopSupportCount, ...
    'Validate', logical(opt.Validate));

out = struct();
out.Y = cast(hybridCore.Y, char(opt.NumericClass));
out.Baseline = baselineOut;
out.Factorized = factorizedOut;
out.Params = hybridCore.Params;
out.Diagnostics = hybridCore.Diagnostics;
out.Diagnostics.prov_Y_inf = max(abs(mapping.A * double(out.Y) * mapping.B' - double(provTarget.Y)), [], 'all');

if logical(opt.Validate)
    assert(out.Diagnostics.prov_Y_inf <= 1e-6, ...
        'm09_downscale_city_y_hybrid_consistent_2017:ProvYMismatch', ...
        'Hybrid Y does not aggregate back to provincial totals.');
end
end

function out = normalize_y_input(inputValue)
out = [];
if isempty(inputValue)
    return;
end
if isnumeric(inputValue)
    out = struct('Y', double(inputValue), 'Diagnostics', struct());
    return;
end
if isstruct(inputValue) && isfield(inputValue, 'Y')
    out = inputValue;
    return;
end
error('m09_downscale_city_y_hybrid_consistent_2017:InvalidYInput', ...
    'BaselineY / FactorizedY must be empty, a numeric matrix, or a struct with field Y.');
end
