function out = m06_run_merge_city_mrio_to_4sector_impl(cfg)
% M06_RUN_MERGE_CITY_MRIO_TO_4SECTOR_IMPL
% Generate canonical MRIO4 city packages for post-MGRAS carbon matching and networks.

if nargin < 1 || isempty(cfg)
    cfg = default_cfg_local();
end

ensure_dir_local(cfg.resultsDir);
addpath(cfg.codeDir);

spec = [ ...
    struct('name', "city_mrio_2015_4", 'inputPath', string(cfg.city2015Path), 'required', true); ...
    struct('name', "city_mrio_2020_hybrid_4", 'inputPath', string(cfg.city2020HybridPath), 'required', true); ...
    struct('name', "city_mrio_2020_baseline_4", 'inputPath', string(cfg.city2020BaselinePath), 'required', false); ...
    struct('name', "city_mrio_2020_factorized_4", 'inputPath', string(cfg.city2020FactorizedPath), 'required', false)];

packages = struct([]);
for i = 1:numel(spec)
    srcPath = spec(i).inputPath;
    if ~isfile(srcPath)
        if spec(i).required
            error('m06_run_merge_city_mrio_to_4sector_impl:MissingInput', ...
                'Missing required merge input: %s', srcPath);
        end
        continue;
    end
    merged = m04_merge_city_mrio_to_4sector(srcPath, cfg.mappingCsv);
    outPath = fullfile(cfg.resultsDir, spec(i).name + ".mat");
    city = merged; %#ok<NASGU>
    save(outPath, 'city');
    packages = append_package_local(packages, spec(i).name, outPath, merged); %#ok<AGROW>
end

validationPath = fullfile(cfg.resultsDir, 'city_mrio4_packages_validation.csv');
validationTable = m05_validate_city_mrio4_packages(packages, validationPath);

out = struct();
out.packages = packages;
out.validationTable = validationTable;
out.validationPath = string(validationPath);
end

function cfg = default_cfg_local()
rootDir = fileparts(fileparts(mfilename('fullpath')));
codeRoot = fileparts(rootDir);
cfg = struct();
cfg.rootDir = string(rootDir);
cfg.srcDir = string(fullfile(rootDir, 'src'));
cfg.codeDir = cfg.srcDir;
cfg.resultsDir = string(study_path('generated', 'sectors', 'packages'));
cfg.mappingCsv = string(study_path('metadata', 'mrio42_to_mrio4_mapping.csv'));
cfg.city2015Path = study_path('raw', 'city_mrio_2015.mat');
cfg.city2020HybridPath = string(study_path('generated', 'mrio', '2020_city_deployment_0422', 'city_mrio_2020_hybrid.mat'));
cfg.city2020BaselinePath = string(study_path('generated', 'mrio', '2020_city_deployment_0422', 'city_mrio_2020_baseline.mat'));
cfg.city2020FactorizedPath = string(study_path('generated', 'mrio', '2020_city_deployment_0422', 'city_mrio_2020_factorized.mat'));
end

function ensure_dir_local(dirPath)
if ~exist(dirPath, 'dir')
    mkdir(dirPath);
end
end

function packages = append_package_local(packages, name, outPath, city)
item = struct();
item.name = string(name);
item.path = string(outPath);
item.city = city;
if isempty(packages)
    packages = item;
else
    packages(end+1) = item; %#ok<AGROW>
end
end
