function inputs = m01_load_multilayer_inputs(cfg)
% M01_LOAD_MULTILAYER_INPUTS
% Load canonical MRIO4 packages, carbon4 tables, manifest sidecars, and
%   the external investment workbook as frozen release inputs.

requiredPaths = { ...
    cfg.cityMrio2015Path, ...
    cfg.cityMrio2020Path, ...
    cfg.directEmission2015Path, ...
    cfg.directEmission2020Path, ...
    cfg.carbonManifestPath, ...
    cfg.proxyFallbackPath, ...
    cfg.codebookCsv, ...
    cfg.investmentWorkbookPath};

for i = 1:numel(requiredPaths)
    if ~isfile(requiredPaths{i})
        error('m01_load_multilayer_inputs:MissingCanonicalInput', ...
            'Missing required canonical input: %s', string(requiredPaths{i}));
    end
end

inputs = struct();
inputs.cfg = cfg;
inputs.paths = struct( ...
    'cityMrio2015Path', string(cfg.cityMrio2015Path), ...
    'cityMrio2020Path', string(cfg.cityMrio2020Path), ...
    'directEmission2015Path', string(cfg.directEmission2015Path), ...
    'directEmission2020Path', string(cfg.directEmission2020Path), ...
    'carbonManifestPath', string(cfg.carbonManifestPath), ...
    'proxyFallbackPath', string(cfg.proxyFallbackPath), ...
    'cityCoveragePath', string(cfg.cityCoveragePath), ...
    'codebookCsv', string(cfg.codebookCsv), ...
    'investmentWorkbookPath', string(cfg.investmentWorkbookPath));

inputs.cityByYear = struct();
inputs.cityByYear.y2015 = m02_load_city_mrio_package(cfg.cityMrio2015Path);
inputs.cityByYear.y2020 = m02_load_city_mrio_package(cfg.cityMrio2020Path);

inputs.carbonByYear = struct();
inputs.carbonByYear.y2015 = readtable(cfg.directEmission2015Path, 'TextType', 'string');
inputs.carbonByYear.y2020 = readtable(cfg.directEmission2020Path, 'TextType', 'string');
inputs.proxyFallbackReport = readtable(cfg.proxyFallbackPath, 'TextType', 'string');

if isfile(cfg.cityCoveragePath)
    inputs.cityCoverageReport = readtable(cfg.cityCoveragePath, 'TextType', 'string');
else
    inputs.cityCoverageReport = table();
end

inputs.codebook = readtable(cfg.codebookCsv, 'TextType', 'string');
inputs.carbonManifest = jsondecode(fileread(cfg.carbonManifestPath));
inputs.investmentWorkbookPath = string(cfg.investmentWorkbookPath);
inputs.investmentSheets = struct('y2015', "DirectedNetwork_2015", 'y2020', "DirectedNetwork_2020");

check_city_shapes_local(inputs.cityByYear.y2015, inputs.cityByYear.y2020);
check_carbon_shapes_local(inputs.carbonByYear.y2015, 2015);
check_carbon_shapes_local(inputs.carbonByYear.y2020, 2020);
check_proxy_status_local(inputs.proxyFallbackReport);
end

function check_city_shapes_local(city2015, city2020)
if city2015.numCities ~= city2020.numCities
    error('m01_load_multilayer_inputs:CityCountMismatch', ...
        'MRIO4 packages disagree on numCities: %d vs %d.', ...
        city2015.numCities, city2020.numCities);
end
if city2015.numSectors ~= city2020.numSectors
    error('m01_load_multilayer_inputs:SectorCountMismatch', ...
        'MRIO4 packages disagree on numSectors: %d vs %d.', ...
        city2015.numSectors, city2020.numSectors);
end
if city2015.numFD ~= city2020.numFD
    error('m01_load_multilayer_inputs:FDCountMismatch', ...
        'MRIO4 packages disagree on numFD: %d vs %d.', ...
        city2015.numFD, city2020.numFD);
end
end

function check_carbon_shapes_local(T, expectedYear)
required = ["year","province_code","province_name","city_code","city_name_std","mrio4_sector_code","mrio4_sector_name","co2_total","source_basis"];
for i = 1:numel(required)
    if ~ismember(required(i), string(T.Properties.VariableNames))
        error('m01_load_multilayer_inputs:MissingCarbonColumn', ...
            'Carbon table for %d is missing column %s.', expectedYear, required(i));
    end
end

yearValues = unique(double(T.year));
if numel(yearValues) ~= 1 || yearValues ~= expectedYear
    error('m01_load_multilayer_inputs:UnexpectedCarbonYear', ...
        'Carbon table should contain only year %d.', expectedYear);
end
end

function check_proxy_status_local(proxyFallbackReport)
if isempty(proxyFallbackReport)
    error('m01_load_multilayer_inputs:MissingProxyReport', ...
        'Proxy fallback report is empty.');
end
if any(double(proxyFallbackReport.proxy_fallback_row_count) > 0)
    error('m01_load_multilayer_inputs:UnexpectedProxyFallback', ...
        'Final direct-emission package still contains proxy fallback rows.');
end
end
