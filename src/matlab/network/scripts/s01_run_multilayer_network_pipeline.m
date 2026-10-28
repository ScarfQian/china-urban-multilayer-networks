function out = s01_run_multilayer_network_pipeline(cfg)
% S01_RUN_MULTILAYER_NETWORK_PIPELINE
% Run the city-level three-layer multilayer-network computation pipeline
%   from frozen MRIO4, carbon4, and investment-network release surfaces.

moduleRoot = fileparts(fileparts(mfilename('fullpath')));
codeRoot = fileparts(moduleRoot);
addpath(fullfile(moduleRoot, 'src'));
addpath(fullfile(codeRoot, 'sectors', 'src'));
addpath(fullfile(codeRoot, 'emissions', 'src'));

if nargin < 1 || isempty(cfg)
    cfg = default_cfg_local(moduleRoot);
end

ensure_dir_local(cfg.resultsDir);
ensure_dir_local(cfg.layerDir);
ensure_dir_local(cfg.backboneDir);
ensure_dir_local(cfg.communityDir);

inputs = m01_load_multilayer_inputs(cfg);
alignment = m02_align_city_lists(inputs, cfg);

singleSummaryAll = table();
topRankingsAll = table();
backboneSummaryAll = table();
qapDiagSmokeAll = table();
qapDiagFinalAll = table();
communitySummaryAll = table();
communitySummaryByVariantAll = table();
resilienceAucAll = table();
resilienceDiagnosticsAll = table();
attackOrdersAll = table();
transitionAucAll = table();
transitionTargetOrdersAll = table();
yearStates = struct([]);

for iYear = 1:numel(cfg.years)
    yearValue = cfg.years(iYear);
    yearField = "y" + string(yearValue);
    city = subset_city_package_local(inputs.cityByYear.(yearField), alignment.keepCityIdx);
    carbon = subset_carbon_table_local(inputs.carbonByYear.(yearField), alignment.cityTable.city_code);

    investmentLayer = m03_build_investment_layer(inputs, alignment, yearValue, cfg);
    economicLayer = m04_build_economic_layer_from_mrio17(city, alignment, yearValue, cfg);
    carbonIntensity = m05_build_carbon_intensity_city17(city, carbon, alignment, yearValue, cfg);
    carbonLayer = m06_build_carbon_layer_from_mrio17(city, carbonIntensity, alignment, yearValue, cfg);

    layerBundle = struct();
    layerBundle.investment = investmentLayer;
    layerBundle.economic = economicLayer;
    layerBundle.carbon = carbonLayer;
    layerBundle.carbonIntensity = carbonIntensity;

    validationOut = m07_validate_layer_construction(layerBundle, alignment, inputs, yearValue, cfg);
    backboneOut = m08_extract_backbones(layerBundle, alignment, yearValue, cfg);
    singleOut = m09_compute_single_layer_metrics(layerBundle, backboneOut, alignment, yearValue, cfg);
    crossOut = m10_compute_cross_layer_metrics(layerBundle, singleOut, alignment, yearValue, cfg);
    roleOut = m11_classify_multilayer_roles(singleOut, crossOut, alignment, yearValue, cfg);
    qapOut = m12_run_qap_models(layerBundle, alignment, yearValue, cfg);
    communityOut = m13_run_community_detection(backboneOut, alignment, yearValue, cfg);
    resilienceOut = m14_run_resilience_simulation(layerBundle, backboneOut, singleOut, roleOut, alignment, yearValue, cfg);
    transitionOut = m17_run_transition_stress_test(layerBundle, singleOut, roleOut, alignment, yearValue, cfg);

    singleSummaryAll = append_table_local(singleSummaryAll, singleOut.networkSummaryTable);
    topRankingsAll = append_table_local(topRankingsAll, singleOut.topRankingsTable);
    backboneSummaryAll = append_table_local(backboneSummaryAll, backboneOut.summaryTable);
    qapDiagSmokeAll = append_table_local(qapDiagSmokeAll, qapOut.smokeDiagnosticsTable);
    qapDiagFinalAll = append_table_local(qapDiagFinalAll, qapOut.finalDiagnosticsTable);
    communitySummaryAll = append_table_local(communitySummaryAll, communityOut.summaryTable);
    communitySummaryByVariantAll = append_table_local(communitySummaryByVariantAll, communityOut.summaryByVariantTable);
    resilienceAucAll = append_table_local(resilienceAucAll, resilienceOut.aucSummaryTable);
    resilienceDiagnosticsAll = append_table_local(resilienceDiagnosticsAll, resilienceOut.diagnosticsTable);
    attackOrdersAll = append_table_local(attackOrdersAll, resilienceOut.attackOrderTable);
    transitionAucAll = append_table_local(transitionAucAll, transitionOut.aucSummaryTable);
    transitionTargetOrdersAll = append_table_local(transitionTargetOrdersAll, transitionOut.targetOrderTable);

    yearState = struct();
    yearState.year = yearValue;
    yearState.validation = validationOut;
    yearState.backbones = backboneOut;
    yearState.single = singleOut;
    yearState.cross = crossOut;
    yearState.roles = roleOut;
    yearState.qap = qapOut;
    yearState.communities = communityOut;
    yearState.resilience = resilienceOut;
    yearState.transition = transitionOut;
    if isempty(yearStates)
        yearStates = yearState;
    else
        yearStates(end + 1) = yearState; %#ok<AGROW>
    end
end

singleSummaryPath = fullfile(cfg.resultsDir, 'single_layer_network_summary.csv');
topRankingsPath = fullfile(cfg.resultsDir, 'top_city_rankings_by_layer.csv');
backboneSummaryPath = fullfile(cfg.resultsDir, 'backbone_summary.csv');
qapDiagPath = fullfile(cfg.resultsDir, 'qap_model_diagnostics.csv');
qapDiagFinalPath = fullfile(cfg.resultsDir, 'qap_model_diagnostics_final.csv');
communitySummaryPath = fullfile(cfg.resultsDir, 'community_summary.csv');
communitySummaryByVariantPath = fullfile(cfg.resultsDir, 'community_summary_by_variant.csv');
aucSummaryPath = fullfile(cfg.resultsDir, 'resilience_auc_summary.csv');
resilienceDiagnosticsPath = fullfile(cfg.resultsDir, 'resilience_diagnostics.csv');
attackOrdersPath = fullfile(cfg.resultsDir, 'attack_city_orders.csv');
transitionAucPath = fullfile(cfg.resultsDir, 'transition_stress_auc_summary.csv');
transitionTargetOrdersPath = fullfile(cfg.resultsDir, 'transition_target_city_orders.csv');

writetable(singleSummaryAll, singleSummaryPath);
writetable(topRankingsAll, topRankingsPath);
writetable(backboneSummaryAll, backboneSummaryPath);
writetable(qapDiagSmokeAll, qapDiagPath);
writetable(qapDiagFinalAll, qapDiagFinalPath);
writetable(communitySummaryAll, communitySummaryPath);
writetable(communitySummaryByVariantAll, communitySummaryByVariantPath);
writetable(resilienceAucAll, aucSummaryPath);
writetable(resilienceDiagnosticsAll, resilienceDiagnosticsPath);
writetable(attackOrdersAll, attackOrdersPath);
writetable(transitionAucAll, transitionAucPath);
writetable(transitionTargetOrdersAll, transitionTargetOrdersPath);

runState = struct();
runState.inputs = inputs;
runState.alignment = alignment;
runState.years = yearStates;
runState.summaryFiles = struct( ...
    'singleSummaryPath', string(singleSummaryPath), ...
    'topRankingsPath', string(topRankingsPath), ...
    'backboneSummaryPath', string(backboneSummaryPath), ...
    'qapDiagPath', string(qapDiagPath), ...
    'qapDiagFinalPath', string(qapDiagFinalPath), ...
    'communitySummaryPath', string(communitySummaryPath), ...
    'communitySummaryByVariantPath', string(communitySummaryByVariantPath), ...
    'aucSummaryPath', string(aucSummaryPath), ...
    'resilienceDiagnosticsPath', string(resilienceDiagnosticsPath), ...
    'attackOrdersPath', string(attackOrdersPath), ...
    'transitionAucPath', string(transitionAucPath), ...
    'transitionTargetOrdersPath', string(transitionTargetOrdersPath));

paperOut = m16_write_paper_tables(runState, cfg);
runState.paperTables = paperOut;

manifestOut = m15_write_multilayer_manifest(runState, cfg);

out = struct();
out.cfg = cfg;
out.inputs = inputs;
out.alignment = alignment;
out.years = yearStates;
out.manifest = manifestOut;
end

function cfg = default_cfg_local(moduleRoot)
codeRoot = fileparts(moduleRoot);
baseResultsDir = study_path('generated', 'network');
resultsDir = fullfile(baseResultsDir, 'revised_mrio4');

cfg = struct();
cfg.moduleRoot = string(moduleRoot);
cfg.codeRoot = string(codeRoot);
cfg.srcDir = string(fullfile(moduleRoot, 'src'));
cfg.baseResultsDir = string(baseResultsDir);
cfg.resultsDir = string(resultsDir);
cfg.layerDir = string(fullfile(resultsDir, 'layers'));
cfg.backboneDir = string(fullfile(resultsDir, 'backbones'));
cfg.communityDir = string(fullfile(resultsDir, 'communities'));
cfg.docsDir = string(study_path('generated', 'network', 'documentation'));
cfg.years = [2015, 2020];
cfg.randomSeed = 20260424;
cfg.sampleMode = "pure_city";
cfg.proxyUnitCodes = [460000, 530000, 540000, 630000];
cfg.directMunicipalityCodes = [110000, 120000, 310000, 500000];
cfg.backboneCumulativeShare = 0.95;
cfg.qapNumPermutations = 200;
cfg.qapNumPermutationsFinal = 4999;
cfg.randomAttackRepeats = 50;
cfg.transitionTauValues = [0.05, 0.10, 0.20];
cfg.transitionPhiValues = 0:0.01:1;
cfg.transitionRandomRepeats = 50;
cfg.transitionEpsilon = 1e-12;
cfg.computeBetweenness = false;
cfg.computeEfficiency = false;
cfg.efficiencyRetentionStatus = "diagnostic_only";
cfg.maxCommunityIter = 50;
cfg.communityGammaValues = [0.5, 1.0, 1.5, 2.0];
cfg.communityCollapseThreshold = 0.85;
cfg.pagerankAlpha = 0.85;
cfg.roleTopQuantile = 0.90;
cfg.bridgeTopQuantile = 0.85;
cfg.distanceFloorKm = 1;
cfg.zeroTolerance = 1e-12;

cfg.cityMrio2015Path = input_path('mrio', 'city_mrio_2015_4.mat');
cfg.cityMrio2020Path = input_path('mrio', 'city_mrio_2020_hybrid_4.mat');
cfg.directEmission2015Path = input_path('emissions', 'direct_emission_city4_2015.csv');
cfg.directEmission2020Path = input_path('emissions', 'direct_emission_city4_2020.csv');
cfg.carbonManifestPath = input_path('emissions', 'post_mgras_release_manifest.json');
cfg.proxyFallbackPath = input_path('emissions', 'proxy_fallback_report.csv');
cfg.cityCoveragePath = input_path('emissions', 'city_inventory_coverage_report.csv');
cfg.codebookCsv = study_path('metadata', 'city2pro_full_313.csv');
cfg.investmentWorkbookPath = study_path('raw', 'Directed intercity investment network dataset.xlsx');
end

function out = append_table_local(out, in)
if isempty(in) || height(in) == 0
    return;
end
if isempty(out)
    out = in;
else
    out = [out; in]; %#ok<AGROW>
end
end

function ensure_dir_local(dirPath)
if ~exist(dirPath, 'dir')
    mkdir(dirPath);
end
end

function city = subset_city_package_local(cityFull, keepCityIdx)
keepCityIdx = keepCityIdx(:);
if numel(keepCityIdx) == cityFull.numCities
    city = cityFull;
    return;
end

rowIdx = block_indices_local(keepCityIdx, cityFull.numSectors);
fdIdx = block_indices_local(keepCityIdx, cityFull.numFD);

city = cityFull;
city.Z = double(cityFull.Z(rowIdx, rowIdx));
city.Y = double(cityFull.Y(rowIdx, fdIdx));
if isfield(city, 'F')
    city.F = city.Y;
end
city.VA = double(cityFull.VA(rowIdx));
city.IM = double(cityFull.IM(rowIdx));
city.EX = double(cityFull.EX(rowIdx));
city.X = double(cityFull.X(rowIdx));
if isfield(cityFull, 'error') && ~isempty(cityFull.error)
    city.error = double(cityFull.error(rowIdx));
else
    city.error = zeros(size(city.X));
end
if isfield(cityFull, 'cities')
    city.cities = string(cityFull.cities(keepCityIdx));
end
if isfield(cityFull, 'cities_cn')
    city.cities_cn = string(cityFull.cities_cn(keepCityIdx));
end
city.numCities = numel(keepCityIdx);
city.Diagnostics = subset_city_diagnostics_local(city);
end

function carbon = subset_carbon_table_local(carbonFull, keepCityCodes)
keepMask = ismember(double(carbonFull.city_code), double(keepCityCodes(:)));
carbon = carbonFull(keepMask, :);
end

function idx = block_indices_local(entityIdx, blockSize)
entityIdx = double(entityIdx(:));
idx = zeros(numel(entityIdx) * blockSize, 1);
cursor = 1;
for i = 1:numel(entityIdx)
    block = ((entityIdx(i) - 1) * blockSize + 1):(entityIdx(i) * blockSize);
    idx(cursor:(cursor + blockSize - 1)) = block(:);
    cursor = cursor + blockSize;
end
end

function diagOut = subset_city_diagnostics_local(city)
diagOut = struct();
diagOut.row_identity_max = max(abs(city.X - (sum(city.Z, 2) + sum(city.Y, 2) + city.EX + city.error)));
diagOut.col_identity_max = max(abs(city.X - (sum(city.Z, 1)' + city.VA + city.IM)));
end
