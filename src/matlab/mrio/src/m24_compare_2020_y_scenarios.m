function out = m24_compare_2020_y_scenarios(scenarios, mapping, varargin)
% M24_COMPARE_2020_Y_SCENARIOS
% Compare baseline, factorized, and hybrid 2020 outputs and summarize their uncertainty envelope.

p = inputParser;
p.addRequired('scenarios', @(x) isstruct(x) && numel(x) >= 1);
p.addRequired('mapping', @isstruct);
p.addParameter('ComparisonPath', "", @(x) ischar(x) || isstring(x));
p.addParameter('EnvelopePath', "", @(x) ischar(x) || isstring(x));
p.parse(scenarios, mapping, varargin{:});
opt = p.Results;

comparisonRows = cell(numel(scenarios), 1);
cityOutputMatrix = zeros(mapping.numCities, numel(scenarios));
provOutputMatrix = zeros(mapping.numProvinces, numel(scenarios));
totals = zeros(numel(scenarios), 3);

for i = 1:numel(scenarios)
    S = scenarios(i);
    city = cast_city_compare(S.finalCity);
    provAgg = S.aggregationCheck.aggregated;
    cityTotals = reshape(sum(reshape(double(city.X), mapping.numSectors, [])', 2), mapping.numCities, 1);
    provTotals = double(mapping.A * double(city.X));
    cityOutputMatrix(:, i) = cityTotals;
    provOutputMatrix(:, i) = reshape(sum(reshape(provTotals, mapping.numSectors, [])', 2), mapping.numProvinces, 1);
    totals(i, :) = [sum(city.X), sum(city.VA), sum(city.Y, 'all')];

    comparisonRows{i} = { ...
        string(S.name), ...
        lookup_agg_metric(S.aggregationCheck.ReportTable, "Z_inf"), ...
        lookup_agg_metric(S.aggregationCheck.ReportTable, "Y_inf"), ...
        lookup_agg_metric(S.aggregationCheck.ReportTable, "X_inf"), ...
        lookup_agg_metric(S.aggregationCheck.ReportTable, "VA_inf"), ...
        lookup_agg_metric(S.aggregationCheck.ReportTable, "IM_inf"), ...
        lookup_agg_metric(S.aggregationCheck.ReportTable, "EX_inf"), ...
        lookup_agg_metric(S.aggregationCheck.ReportTable, "error_inf"), ...
        max(abs(double(city.X) - (sum(double(city.Z), 2) + sum(double(city.Y), 2) + double(city.EX) + double(city.error)))), ...
        max(abs(double(city.X) - (sum(double(city.Z), 1)' + double(city.VA) + double(city.IM)))), ...
        sum(double(city.Z), 'all'), ...
        sum(double(city.Y), 'all'), ...
        sum(double(city.X)), ...
        sum(double(city.VA)), ...
        sum(double(city.IM)), ...
        sum(double(city.EX)), ...
        mean(cityTotals), std(cityTotals), quantile_local(cityTotals, 0.05), quantile_local(cityTotals, 0.95), ...
        mean(provOutputMatrix(:, i)), std(provOutputMatrix(:, i)), quantile_local(provOutputMatrix(:, i), 0.05), quantile_local(provOutputMatrix(:, i), 0.95)};
end

comparisonTable = cell2table(vertcat(comparisonRows{:}), ...
    'VariableNames', {'scenario','prov_Z_inf','prov_Y_inf','prov_X_inf','prov_VA_inf','prov_IM_inf','prov_EX_inf','prov_error_inf', ...
    'row_identity_max','col_identity_max','total_Z','total_Y','total_X','total_VA','total_IM','total_EX', ...
    'city_output_mean','city_output_std','city_output_p05','city_output_p95', ...
    'province_output_mean','province_output_std','province_output_p05','province_output_p95'});

cityRange = max(cityOutputMatrix, [], 2) - min(cityOutputMatrix, [], 2);
provRange = max(provOutputMatrix, [], 2) - min(provOutputMatrix, [], 2);
envelopeTable = table( ...
    ["total_city_output_range";"total_city_va_range";"total_city_Y_range"; ...
    "province_output_spread_mean";"province_output_spread_max";"province_output_spread_p95"; ...
    "city_output_spread_mean";"city_output_spread_max";"city_output_spread_p95"], ...
    [range(totals(:,1)); range(totals(:,2)); range(totals(:,3)); ...
    mean(provRange); max(provRange); quantile_local(provRange, 0.95); ...
    mean(cityRange); max(cityRange); quantile_local(cityRange, 0.95)], ...
    'VariableNames', {'metric','value'});

write_if_requested(comparisonTable, string(opt.ComparisonPath));
write_if_requested(envelopeTable, string(opt.EnvelopePath));

out = struct();
out.comparisonTable = comparisonTable;
out.envelopeTable = envelopeTable;
end

function city = cast_city_compare(city)
fields = ["Z","Y","VA","IM","EX","X","error"];
for i = 1:numel(fields)
    city.(fields(i)) = double(city.(fields(i)));
end
end

function value = lookup_agg_metric(reportTable, metricName)
idx = find(string(reportTable.metric) == string(metricName), 1, 'first');
if isempty(idx)
    value = NaN;
else
    value = double(reportTable.value(idx));
end
end

function q = quantile_local(vec, p)
vec = sort(double(vec(:)));
if isempty(vec)
    q = NaN;
    return;
end
if numel(vec) == 1
    q = vec;
    return;
end
pos = 1 + (numel(vec)-1) * p;
lo = floor(pos);
hi = ceil(pos);
if lo == hi
    q = vec(lo);
else
    q = vec(lo) + (pos - lo) * (vec(hi) - vec(lo));
end
end

function write_if_requested(T, pathValue)
if strlength(strtrim(pathValue)) == 0
    return;
end
writetable(T, pathValue);
end
