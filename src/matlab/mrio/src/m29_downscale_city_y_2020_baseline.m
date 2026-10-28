function out = m29_downscale_city_y_2020_baseline(citySource, prov2020, mapping, varargin)
% M29_DOWNSCALE_CITY_Y_2020_BASELINE
% Build the 2020 baseline city Y allocation from city2017_harm to provincial 2020 totals.

out = m08_downscale_city_y_forecast_style_consistent_2017(citySource, prov2020, mapping, varargin{:});
if isfield(out, 'Diagnostics')
    out.Diagnostics.mode2020 = "baseline";
end
end
