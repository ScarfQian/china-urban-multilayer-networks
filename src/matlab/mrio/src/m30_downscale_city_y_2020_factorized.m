function out = m30_downscale_city_y_2020_factorized(citySource, prov2020, mapping, factorizedParams, varargin)
% M30_DOWNSCALE_CITY_Y_2020_FACTORIZED
% Build the 2020 factorized city Y allocation using frozen 2017 factorized parameters.

out = m07_downscale_city_y_factorized_consistent_2017(citySource, prov2020, mapping, factorizedParams, varargin{:});
if isfield(out, 'Diagnostics')
    out.Diagnostics.mode2020 = "factorized";
end
end
