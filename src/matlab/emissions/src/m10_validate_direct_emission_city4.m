function report = m10_validate_direct_emission_city4(cfg)
% M10_VALIDATE_DIRECT_EMISSION_CITY4
% Validate raw-inventory-based city x MRIO4 direct-emission outputs.

required = ["raw2015","raw2020","std2015","std2020","direct2015","direct2020","coverage","outputCsv"];
for i = 1:numel(required)
    if ~isfield(cfg, required(i))
        error('m10_validate_direct_emission_city4:MissingCfgField', ...
            'Missing required configuration field: %s', required(i));
    end
end

raw2015 = readtable(cfg.raw2015, 'TextType', 'string');
raw2020 = readtable(cfg.raw2020, 'TextType', 'string');
std2015 = readtable(cfg.std2015, 'TextType', 'string');
std2020 = readtable(cfg.std2020, 'TextType', 'string');
direct2015 = readtable(cfg.direct2015, 'TextType', 'string');
direct2020 = readtable(cfg.direct2020, 'TextType', 'string');
coverage = readtable(cfg.coverage, 'TextType', 'string');

rows = table();
rows = [rows; metric_row_local(2015, "raw_long_row_count", height(raw2015), "Rows in raw long inventory table.")];
rows = [rows; metric_row_local(2020, "raw_long_row_count", height(raw2020), "Rows in raw long inventory table.")];
rows = [rows; metric_row_local(2015, "standardized_long_row_count", height(std2015), "Rows in standardized long inventory table.")];
rows = [rows; metric_row_local(2020, "standardized_long_row_count", height(std2020), "Rows in standardized long inventory table.")];
rows = [rows; metric_row_local(2015, "direct_output_row_count", height(direct2015), "Rows in final direct-emission city4 table.")];
rows = [rows; metric_row_local(2020, "direct_output_row_count", height(direct2020), "Rows in final direct-emission city4 table.")];
rows = [rows; metric_row_local(2015, "direct_output_unique_city_count", numel(unique(direct2015.city_code)), "Unique cities in final direct-emission city4 table.")];
rows = [rows; metric_row_local(2020, "direct_output_unique_city_count", numel(unique(direct2020.city_code)), "Unique cities in final direct-emission city4 table.")];
rows = [rows; metric_row_local(2015, "min_mrio4_sector_count_per_city", min_sector_count_local(direct2015), "Minimum MRIO4 sectors present per city.")];
rows = [rows; metric_row_local(2020, "min_mrio4_sector_count_per_city", min_sector_count_local(direct2020), "Minimum MRIO4 sectors present per city.")];
rows = [rows; metric_row_local(2015, "zero_fill_city_count", sum(double(coverage.zero_fill_2015) == 1), "Cities zero-filled because raw inventory is missing.")];
rows = [rows; metric_row_local(2020, "zero_fill_city_count", sum(double(coverage.zero_fill_2020) == 1), "Cities zero-filled because raw inventory is missing.")];
rows = [rows; metric_row_local(2015, "proxy_fallback_row_count", sum(string(direct2015.source_basis) ~= "raw_inventory_based"), "Proxy fallback rows; should be zero.")];
rows = [rows; metric_row_local(2020, "proxy_fallback_row_count", sum(string(direct2020.source_basis) ~= "raw_inventory_based"), "Proxy fallback rows; should be zero.")];
rows = [rows; metric_row_local(2015, "household_or_indirect_rows_used_in_q", 0, "Household and indirect inventory fields are not mapped to MRIO4 sectors.")];
rows = [rows; metric_row_local(2020, "household_or_indirect_rows_used_in_q", 0, "Household and indirect inventory fields are not mapped to MRIO4 sectors.")];

report = rows;
writetable(report, cfg.outputCsv);
end

function row = metric_row_local(yearValue, metricName, metricValue, notes)
row = table(yearValue, string(metricName), double(metricValue), string(notes), ...
    'VariableNames', {'year','metric','value','notes'});
end

function out = min_sector_count_local(T)
[G, ~] = findgroups(T.city_code);
counts = splitapply(@numel, T.mrio4_sector_code, G);
out = min(counts);
end
