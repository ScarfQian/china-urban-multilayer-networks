function reportTable = m13_build_proxy_fallback_report_city4(cfg)
% M13_BUILD_PROXY_FALLBACK_REPORT_CITY4
% Summarize proxy and zero-fill status for final city4 direct-emission outputs.

required = ["direct2015","direct2020","crosswalk2015","crosswalk2020","outputCsv"];
for i = 1:numel(required)
    if ~isfield(cfg, required(i))
        error('m13_build_proxy_fallback_report_city4:MissingCfgField', ...
            'Missing required configuration field: %s', required(i));
    end
end
reportTable = [ ...
    build_rows_local(2015, cfg.direct2015, cfg.crosswalk2015); ...
    build_rows_local(2020, cfg.direct2020, cfg.crosswalk2020)];
writetable(reportTable, cfg.outputCsv);
end

function row = build_rows_local(yearValue, directInput, crosswalkInput)
directTable = resolve_table_local(directInput);
crosswalkTable = resolve_table_local(crosswalkInput);
sourceBasis = string(directTable.source_basis);
rawMask = sourceBasis == "raw_inventory_based";
proxyMask = ~rawMask;
zeroFillMask = double(crosswalkTable.zero_fill_flag) == 1;
row = table();
row.year = yearValue;
row.raw_inventory_row_count = sum(rawMask);
row.proxy_fallback_row_count = sum(proxyMask);
row.raw_inventory_city_count = numel(unique(directTable.city_code(rawMask)));
row.proxy_fallback_city_count = numel(unique(directTable.city_code(proxyMask)));
row.proxy_fallback_cities = collapse_strings_local(string(directTable.city_name_std(proxyMask)));
row.proxy_fallback_sector_count = numel(unique(string(directTable.mrio4_sector_code(proxyMask))));
row.proxy_fallback_sectors = collapse_strings_local(string(directTable.mrio4_sector_code(proxyMask)));
row.fallback_reason_summary = collapse_strings_local(sourceBasis(proxyMask));
row.zero_fill_city_count = sum(zeroFillMask);
row.zero_fill_cities = collapse_strings_local(string(crosswalkTable.target_city_name(zeroFillMask)));
row.zero_fill_reason_summary = collapse_strings_local(string(crosswalkTable.mapping_rule(zeroFillMask)));
if row.proxy_fallback_row_count == 0 && strlength(row.fallback_reason_summary) == 0
    row.fallback_reason_summary = "none";
end
end

function T = resolve_table_local(inputValue)
if istable(inputValue)
    T = inputValue;
else
    T = readtable(string(inputValue), 'TextType', 'string');
end
end

function out = collapse_strings_local(values)
u = unique(strtrim(string(values)));
u = u(strlength(u) > 0);
if isempty(u)
    out = "";
elseif numel(u) == 1
    out = u(1);
else
    out = strjoin(cellstr(u), '|');
end
end
