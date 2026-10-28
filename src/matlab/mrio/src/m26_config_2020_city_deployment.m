function cfg = m26_config_2020_city_deployment(varargin)
% M26_CONFIG_2020_CITY_DEPLOYMENT
% Centralize all fixed paths, tolerances, and frozen 2017 hybrid parameters for 2020 deployment.

p = inputParser;
p.addParameter('RootDir', "", @(x) ischar(x) || isstring(x));
p.addParameter('ResultsTag', "2020_city_deployment_0422", @(x) ischar(x) || isstring(x));
p.parse(varargin{:});
opt = p.Results;

if strlength(string(opt.RootDir)) == 0
    rootDir = fileparts(fileparts(mfilename('fullpath')));
else
    rootDir = string(opt.RootDir);
end

cfg = struct();
cfg.rootDir = rootDir;
cfg.srcDir = fullfile(rootDir, 'src');
cfg.codeDir = cfg.srcDir;
cfg.legacyCodeDir = fullfile(rootDir, 'Code');
cfg.resultsDir = study_path('generated', 'mrio', string(opt.ResultsTag));
cfg.regressionDir = fullfile(cfg.resultsDir, 'regression_gate_2017');
cfg.failureSummaryPath = fullfile(cfg.resultsDir, 'deployment_failure_summary.csv');

cfg.city2012 = study_path('raw', 'city_mrio_2012.mat');
cfg.city2015 = study_path('raw', 'city_mrio_2015.mat');
cfg.city2017Raw = study_path('raw', 'city_mrio_2017.mat');
cfg.prov2017 = study_path('raw', 'province_mrio_2017.xlsx');
cfg.prov2020 = study_path('raw', 'province_mrio_2020.xlsx');
cfg.mapping = study_path('metadata', 'city2pro.xlsx');
cfg.acceptedHybridDir = study_path('metadata', '2017_y_hybrid_0422');
cfg.acceptedHybridValidation = fullfile(cfg.acceptedHybridDir, 'validation_backcast_2017_y_hybrid.csv');
cfg.acceptedHybridAggregation = fullfile(cfg.acceptedHybridDir, 'aggregation_check_2017_y_hybrid.csv');
cfg.acceptedHybridParams = fullfile(cfg.acceptedHybridDir, 'y_hybrid_best_params.csv');
% The accepted hybrid parameter table also contains the fixed beta and gamma.
cfg.acceptedFactorizedParams = cfg.acceptedHybridParams;
cfg.numericClass = "double";
cfg.epsilon = 1e-12;
cfg.provTol = 1e-6;
cfg.rowTol = 1e-6;
cfg.colTol = 1e-10;
cfg.maxIter = 200;
cfg.tolRow = 1e-6;
cfg.tolCol = 1e-6;
cfg.tolBlock = 1e-8;
cfg.zMode = "seed_fixed";
cfg.regressionMetricTol = 1e-9;
cfg.regressionAggTol = 1e-6;

cfg.proxyTable = [];
cfg.eta = [1 1 1];
cfg.topSupportCount = 3;
cfg.skipRegression = false;

cfg.factorizedParams = struct();
cfg.factorizedParams.alpha = ones(42, 1);
cfg.factorizedParams.beta = [0; 0; 0; 0.5; 0.5];
cfg.factorizedParams.gamma = [1.5; 1.5; 1.5; 0.5; 0.5];

cfg.hybridParams = struct();
cfg.hybridParams.lambda = [0.2; 0.2; 0.0; 0.0; 1.0];
cfg.hybridParams.fd4_mode = "hybrid";
cfg.hybridParams.fd5_mode = "baseline_only";
end
