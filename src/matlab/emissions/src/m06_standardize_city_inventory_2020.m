function out = m06_standardize_city_inventory_2020(cfg)
% M06_STANDARDIZE_CITY_INVENTORY_2020
% Standardize the 2020 raw city inventory workbook to the 313-city codebook.

if nargin < 1 || isempty(cfg)
    rootDir = fileparts(fileparts(mfilename('fullpath')));
    cfg = struct();
    cfg.year = 2020;
    cfg.workbookPath = fullfile(rootDir, 'Data', 'raw_inventory', '2020.xlsx');
    cfg.cityMrio17Path = fullfile(fileparts(rootDir), 'sectors', 'Results', 'packages', 'city_mrio_2020_hybrid_17.mat');
    cfg.codebookCsv = study_path('metadata', 'city2pro_full_313.csv');
    cfg.resultsDir = study_path('generated', 'emissions', 'carbon_matching_17');
end
out = m04_standardize_city_inventory_generic(cfg);
end
