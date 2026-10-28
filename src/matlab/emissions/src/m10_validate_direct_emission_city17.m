function report = m10_validate_direct_emission_city17(cfg)
% M10_VALIDATE_DIRECT_EMISSION_CITY17
% Summarize row counts, city coverage, sector coverage, exclusion checks,
%   and proxy label fixes for the final carbon17 outputs.

required = ["raw2015","raw2020","std2015","std2020","direct2015","direct2020","coverage","mappingCsv","proxyAlloc2015","proxyAlloc2020","outputCsv"];
for i = 1:numel(required)
    if ~isfield(cfg, required(i))
        error('m10_validate_direct_emission_city17:MissingCfgField', ...
            'Missing required configuration field: %s', required(i));
    end
end

raw2015 = resolve_table_local(cfg.raw2015);
raw2020 = resolve_table_local(cfg.raw2020);
std2015 = resolve_table_local(cfg.std2015);
std2020 = resolve_table_local(cfg.std2020);
direct2015 = resolve_table_local(cfg.direct2015);
direct2020 = resolve_table_local(cfg.direct2020);
coverage = resolve_table_local(cfg.coverage);
proxy2015 = resolve_table_local(cfg.proxyAlloc2015);
proxy2020 = resolve_table_local(cfg.proxyAlloc2020);
mapping = readtable(cfg.mappingCsv, 'TextType', 'string');
validSectorNames = string(unique(mapping.old));

rows = {};
rows(end+1, :) = metric_row_local(2015, "raw_long_row_count", height(raw2015), "Rows in raw long-format inventory table."); %#ok<AGROW>
rows(end+1, :) = metric_row_local(2020, "raw_long_row_count", height(raw2020), "Rows in raw long-format inventory table."); %#ok<AGROW>
rows(end+1, :) = metric_row_local(2015, "raw_unique_city_count", numel(unique(raw2015.raw_city_name)), "Unique raw inventory cities."); %#ok<AGROW>
rows(end+1, :) = metric_row_local(2020, "raw_unique_city_count", numel(unique(raw2020.raw_city_name)), "Unique raw inventory cities."); %#ok<AGROW>
rows(end+1, :) = metric_row_local(2015, "standardized_row_count", height(std2015), "Rows in standardized 313-city inventory table."); %#ok<AGROW>
rows(end+1, :) = metric_row_local(2020, "standardized_row_count", height(std2020), "Rows in standardized 313-city inventory table."); %#ok<AGROW>
rows(end+1, :) = metric_row_local(2015, "standardized_unique_city_count", numel(unique(std2015.city_code)), "Unique standardized inventory cities."); %#ok<AGROW>
rows(end+1, :) = metric_row_local(2020, "standardized_unique_city_count", numel(unique(std2020.city_code)), "Unique standardized inventory cities."); %#ok<AGROW>
rows(end+1, :) = metric_row_local(0, "coverage_city_count", height(coverage), "Rows in combined 313-city coverage report."); %#ok<AGROW>
rows(end+1, :) = metric_row_local(2015, "coverage_matched_city_count", sum(double(coverage.has_raw_2015) == 1), "Codebook cities with at least one raw source."); %#ok<AGROW>
rows(end+1, :) = metric_row_local(2020, "coverage_matched_city_count", sum(double(coverage.has_raw_2020) == 1), "Codebook cities with at least one raw source."); %#ok<AGROW>
rows(end+1, :) = metric_row_local(2015, "coverage_zero_fill_city_count", sum(double(coverage.zero_fill_2015) == 1), "Codebook cities filled with zeros due to missing raw source."); %#ok<AGROW>
rows(end+1, :) = metric_row_local(2020, "coverage_zero_fill_city_count", sum(double(coverage.zero_fill_2020) == 1), "Codebook cities filled with zeros due to missing raw source."); %#ok<AGROW>
rows(end+1, :) = metric_row_local(2015, "direct_output_row_count", height(direct2015), "Rows in final direct-emission city17 table."); %#ok<AGROW>
rows(end+1, :) = metric_row_local(2020, "direct_output_row_count", height(direct2020), "Rows in final direct-emission city17 table."); %#ok<AGROW>
rows(end+1, :) = metric_row_local(2015, "direct_output_unique_city_count", numel(unique(direct2015.city_code)), "Unique cities in final direct-emission city17 table."); %#ok<AGROW>
rows(end+1, :) = metric_row_local(2020, "direct_output_unique_city_count", numel(unique(direct2020.city_code)), "Unique cities in final direct-emission city17 table."); %#ok<AGROW>
[min2015, max2015] = sector_count_stats_local(direct2015);
[min2020, max2020] = sector_count_stats_local(direct2020);
rows(end+1, :) = metric_row_local(2015, "direct_output_min_sector_count_per_city", min2015, "Minimum MRIO17 sector rows per city."); %#ok<AGROW>
rows(end+1, :) = metric_row_local(2020, "direct_output_min_sector_count_per_city", min2020, "Minimum MRIO17 sector rows per city."); %#ok<AGROW>
rows(end+1, :) = metric_row_local(2015, "direct_output_max_sector_count_per_city", max2015, "Maximum MRIO17 sector rows per city."); %#ok<AGROW>
rows(end+1, :) = metric_row_local(2020, "direct_output_max_sector_count_per_city", max2020, "Maximum MRIO17 sector rows per city."); %#ok<AGROW>
rows(end+1, :) = metric_row_local(2015, "excluded_household_row_count", sum(double(std2015.household_direct_flag) == 1), "Household direct rows kept outside production-side q."); %#ok<AGROW>
rows(end+1, :) = metric_row_local(2020, "excluded_household_row_count", sum(double(std2020.household_direct_flag) == 1), "Household direct rows kept outside production-side q."); %#ok<AGROW>
rows(end+1, :) = metric_row_local(2015, "excluded_indirect_row_count", sum(double(std2015.indirect_flag) == 1), "Indirect rows kept outside production-side q."); %#ok<AGROW>
rows(end+1, :) = metric_row_local(2020, "excluded_indirect_row_count", sum(double(std2020.indirect_flag) == 1), "Indirect rows kept outside production-side q."); %#ok<AGROW>
rows(end+1, :) = metric_row_local(2015, "proxy_sector42_name_fixed", double(all(ismember(string(proxy2015.sector42_name), validSectorNames))), "Proxy allocation file uses valid sector42 labels."); %#ok<AGROW>
rows(end+1, :) = metric_row_local(2020, "proxy_sector42_name_fixed", double(all(ismember(string(proxy2020.sector42_name), validSectorNames))), "Proxy allocation file uses valid sector42 labels."); %#ok<AGROW>

report = cell2table(rows, 'VariableNames', {'year','metric','value','note'});
writetable(report, cfg.outputCsv);
end

function T = resolve_table_local(inputValue)
if istable(inputValue)
    T = inputValue;
else
    T = readtable(string(inputValue), 'TextType', 'string');
end
end

function row = metric_row_local(yearValue, metricName, value, note)
row = {yearValue, char(metricName), double(value), char(note)};
end

function [minCount, maxCount] = sector_count_stats_local(T)
[G, ~] = findgroups(T.city_code);
counts = splitapply(@numel, T.mrio17_sector_code, G);
minCount = min(counts);
maxCount = max(counts);
end
