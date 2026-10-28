function out = m12_run_raw_inventory_carbon4_pipeline_impl(cfg)
% M12_RUN_RAW_INVENTORY_CARBON4_PIPELINE_IMPL
% Generate raw-long, standardized-long, MRIO4-allocated, final direct-emission,
%   fallback, validation, and manifest outputs for the 4-sector carbon package.

if nargin < 1 || isempty(cfg)
    cfg = default_cfg_local();
end

ensure_dir_local(cfg.resultsDir);
addpath(cfg.codeDir);
addpath(cfg.sectorMergeCodeDir);

m07_build_inventory_to_mrio4_concordance(cfg.concordanceCsv);
std2015 = m05_standardize_city_inventory_2015(struct( ...
    'year', 2015, ...
    'workbookPath', cfg.raw2015Path, ...
    'cityMrio17Path', cfg.cityMrio2015_4, ...
    'codebookCsv', cfg.codebookCsv, ...
    'resultsDir', cfg.resultsDir));
std2020 = m06_standardize_city_inventory_2020(struct( ...
    'year', 2020, ...
    'workbookPath', cfg.raw2020Path, ...
    'cityMrio17Path', cfg.cityMrio2020_4, ...
    'codebookCsv', cfg.codebookCsv, ...
    'resultsDir', cfg.resultsDir));

coverage = build_coverage_report_local(std2015.crosswalkTable, std2020.crosswalkTable, cfg.codebookCsv);
coveragePath = fullfile(cfg.resultsDir, 'city_inventory_coverage_report.csv');
writetable(coverage, coveragePath);

allocated2015Path = fullfile(cfg.resultsDir, 'city_inventory_mrio4_allocated_2015.csv');
allocated2020Path = fullfile(cfg.resultsDir, 'city_inventory_mrio4_allocated_2020.csv');
direct2015Path = fullfile(cfg.resultsDir, 'direct_emission_city4_2015.csv');
direct2020Path = fullfile(cfg.resultsDir, 'direct_emission_city4_2020.csv');

direct2015 = m08_build_direct_emission_city4_from_raw_inventory(std2015.standardizedTable, cfg.cityMrio2015_4, cfg.concordanceCsv, ...
    direct2015Path, 'AllocatedOutputCsv', allocated2015Path);
direct2020 = m08_build_direct_emission_city4_from_raw_inventory(std2020.standardizedTable, cfg.cityMrio2020_4, cfg.concordanceCsv, ...
    direct2020Path, 'AllocatedOutputCsv', allocated2020Path);

proxyFallbackPath = fullfile(cfg.resultsDir, 'proxy_fallback_report.csv');
proxyFallbackReport = m13_build_proxy_fallback_report_city4(struct( ...
    'direct2015', direct2015.directEmissionTable, ...
    'direct2020', direct2020.directEmissionTable, ...
    'crosswalk2015', std2015.crosswalkTable, ...
    'crosswalk2020', std2020.crosswalkTable, ...
    'outputCsv', proxyFallbackPath));

validationCfg = struct();
validationCfg.raw2015 = std2015.rawLongPath;
validationCfg.raw2020 = std2020.rawLongPath;
validationCfg.std2015 = std2015.standardizedPath;
validationCfg.std2020 = std2020.standardizedPath;
validationCfg.direct2015 = direct2015Path;
validationCfg.direct2020 = direct2020Path;
validationCfg.coverage = coveragePath;
validationCfg.outputCsv = fullfile(cfg.resultsDir, 'direct_emission_city4_validation_report.csv');
validationReport = m10_validate_direct_emission_city4(validationCfg);

manifestPath = fullfile(cfg.resultsDir, 'post_mgras_release_manifest.json');
write_manifest_local(cfg, manifestPath, direct2015Path, direct2020Path, allocated2015Path, allocated2020Path, coveragePath, proxyFallbackPath);
write_readme_local(cfg, fullfile(cfg.docsDir, 'readme_carbon_matching_4.md'));

out = struct();
out.std2015 = std2015;
out.std2020 = std2020;
out.coveragePath = string(coveragePath);
out.allocated2015Path = string(allocated2015Path);
out.allocated2020Path = string(allocated2020Path);
out.direct2015 = direct2015;
out.direct2020 = direct2020;
out.proxyFallbackPath = string(proxyFallbackPath);
out.proxyFallbackReport = proxyFallbackReport;
out.validationReport = validationReport;
out.manifestPath = string(manifestPath);
end

function cfg = default_cfg_local()
rootDir = fileparts(fileparts(mfilename('fullpath')));
codeRoot = fileparts(rootDir);
cfg = struct();
cfg.rootDir = string(rootDir);
cfg.srcDir = string(fullfile(rootDir, 'src'));
cfg.docsDir = string(study_path('generated', 'emissions', 'documentation'));
cfg.codeDir = cfg.srcDir;
cfg.sectorMergeCodeDir = string(fullfile(codeRoot, 'sectors', 'src'));
cfg.resultsDir = string(study_path('generated', 'emissions', 'carbon_matching_4'));
cfg.raw2015Path = study_path('raw', 'emissions_2015.xlsx');
cfg.raw2020Path = study_path('raw', 'emissions_2020.xlsx');
cfg.codebookCsv = study_path('metadata', 'city2pro_full_313.csv');
cfg.concordanceCsv = string(fullfile(cfg.resultsDir, 'inventory_to_mrio4_concordance.csv'));
cfg.cityMrio2015_4 = input_path('mrio', 'city_mrio_2015_4.mat');
cfg.cityMrio2020_4 = input_path('mrio', 'city_mrio_2020_hybrid_4.mat');
end

function coverage = build_coverage_report_local(cross2015, cross2020, codebookCsv)
codebook = readtable(codebookCsv, 'TextType', 'string');
rows = cell(height(codebook), 10);
for i = 1:height(codebook)
    cityCode = codebook.city_code(i);
    hit15 = cross2015.target_city_code == cityCode;
    hit20 = cross2020.target_city_code == cityCode;
    rows(i, :) = { ...
        cityCode, char(codebook.city_cn(i)), codebook.province_code(i), char(codebook.province_name_std(i)), ...
        double(any(hit15 & cross2015.zero_fill_flag == 0)), ...
        numel(unique(string(cross2015.raw_city_name(hit15 & string(cross2015.raw_city_name) ~= "")))), ...
        collapse_strings_local(cross2015.mapping_rule(hit15)), ...
        double(any(hit20 & cross2020.zero_fill_flag == 0)), ...
        numel(unique(string(cross2020.raw_city_name(hit20 & string(cross2020.raw_city_name) ~= "")))), ...
        collapse_strings_local(cross2020.mapping_rule(hit20))};
end
coverage = cell2table(rows, 'VariableNames', { ...
    'city_code','city_name_std','province_code','province_name_std', ...
    'has_raw_2015','raw_source_count_2015','mapping_rule_2015', ...
    'has_raw_2020','raw_source_count_2020','mapping_rule_2020'});
coverage.zero_fill_2015 = contains(string(coverage.mapping_rule_2015), "missing_raw_zero_fill");
coverage.zero_fill_2020 = contains(string(coverage.mapping_rule_2020), "missing_raw_zero_fill");
end

function write_manifest_local(cfg, manifestPath, direct2015Path, direct2020Path, allocated2015Path, allocated2020Path, coveragePath, proxyFallbackPath)
manifest = struct();
manifest.generated_at = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
manifest.executor = 'codex';
manifest.package = 'carbon_matching_4';
manifest.boundary = 'raw inventory aggregate fields mapped directly to MRIO4 sectors';
manifest.inputs = struct('raw2015', char(cfg.raw2015Path), 'raw2020', char(cfg.raw2020Path), ...
    'cityMrio2015_4', char(cfg.cityMrio2015_4), 'cityMrio2020_4', char(cfg.cityMrio2020_4));
manifest.outputs = struct('direct2015', char(direct2015Path), 'direct2020', char(direct2020Path), ...
    'allocated2015', char(allocated2015Path), 'allocated2020', char(allocated2020Path), ...
    'coverage', char(coveragePath), 'proxyFallback', char(proxyFallbackPath));
manifest.zero_fill_rule = 'Cities present in MRIO but missing from raw inventory are assigned zero direct emissions and reported in proxy_fallback_report.csv.';
jsonText = jsonencode(manifest, 'PrettyPrint', true);
fid = fopen(manifestPath, 'w');
fprintf(fid, '%s\n', jsonText);
fclose(fid);
end

function write_readme_local(cfg, readmePath)
ensure_dir_local(fileparts(readmePath));
fid = fopen(readmePath, 'w');
fprintf(fid, '# MRIO4 carbon matching package\n\n');
fprintf(fid, '- Date: 2026-04-27\n');
fprintf(fid, '- Executor: Codex\n');
fprintf(fid, '- Scope: copied 4-sector branch only. Accepted MGRAS outputs are frozen inputs.\n\n');
fprintf(fid, '## Sector rule\n\n');
fprintf(fid, 'The final production-side direct-emission package uses raw inventory aggregate columns directly: agriculture, industrial_total, transport_total, and service. Industrial subcomponents and transport submodes are diagnostic only in this branch.\n\n');
fprintf(fid, '## Zero-fill rule\n\n');
fprintf(fid, 'If a city exists in the MRIO city list but has no matched raw inventory row, its production-side direct emissions are set to zero. This follows the input-output accounting treatment that missing direct-emission observations contribute no direct-emission coefficient, and the case is explicitly reported rather than proxied.\n\n');
fprintf(fid, '## Output root\n\n`%s`\n', char(cfg.resultsDir));
fclose(fid);
end

function out = collapse_strings_local(values)
u = unique(string(values));
u = u(strlength(u) > 0);
if isempty(u)
    out = "";
elseif numel(u) == 1
    out = u(1);
else
    out = strjoin(cellstr(u), '|');
end
end

function ensure_dir_local(dirPath)
if ~exist(dirPath, 'dir')
    mkdir(dirPath);
end
end
