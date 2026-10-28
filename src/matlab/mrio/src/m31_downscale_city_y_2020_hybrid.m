function out = m31_downscale_city_y_2020_hybrid(citySource, prov2020, mapping, factorizedParams, hybridParams, varargin)
% M31_DOWNSCALE_CITY_Y_2020_HYBRID
% Build the 2020 hybrid city Y allocation using frozen lambdas from the accepted 2017 round.

out = m09_downscale_city_y_hybrid_consistent_2017(citySource, prov2020, mapping, factorizedParams, hybridParams, varargin{:});
if isfield(out, 'Diagnostics')
    out.Diagnostics.mode2020 = "hybrid";
end
end
