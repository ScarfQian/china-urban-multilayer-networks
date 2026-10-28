function seed = m23_build_seed_city_z_2020_consistent(citySource, prov2020, mapping, varargin)
% M23_BUILD_SEED_CITY_Z_2020_CONSISTENT
% Build a 2020 city Z seed from city2017_harm that aggregates exactly to provincial 2020 Z.

seed = m11_build_seed_city_z_forecast_style_consistent_2017(citySource, prov2020, mapping, varargin{:});
if isfield(seed, 'Diagnostics')
    seed.Diagnostics.mode2020 = "seed_2020_consistent";
end
end
