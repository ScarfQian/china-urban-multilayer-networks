function output = run_models(stage)
% RUN_MODELS Run one numerical stage of the intercity-network study.
% Examples: run_models('network'); run_models('frontier'); run_models('analysis').
% paths.json controls inputs and outputs. No figures are generated.
if nargin == 0
    stage = 'analysis';
end
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root, 'config'));
models = fullfile(root, 'src', 'matlab');
switch char(stage)
    case 'mrio'
        activate_local(models, 'mrio');
        output = s03_run_city_mrio_2020_deployment();
    case 'sectors'
        activate_local(models, 'sectors');
        output = s01_run_merge_city_mrio_to_4sector();
    case 'emissions'
        activate_local(models, 'sectors');
        activate_local(models, 'emissions');
        output = s01_run_raw_inventory_carbon4_pipeline();
    case 'network'
        activate_local(models, 'network');
        output = s01_run_multilayer_network_pipeline();
    case 'targeting'
        activate_local(models, 'network');
        output = s02_run_transition_extension_pipeline();
    case 'cross_layer'
        activate_local(models, 'network');
        output = s03_run_multilayer_extension_pipeline();
    case 'frontier'
        activate_local(models, 'network');
        output = s04_run_transition_pareto_extension_pipeline_260810();
    case 'city_counts'
        activate_local(models, 'network');
        output = s05_run_transition_pareto_completion_pipeline_260810();
    case {'all', 'analysis'}
        stages = {'network','targeting','cross_layer','frontier','city_counts'};
        if strcmp(char(stage), 'all')
            stages = [{'mrio','sectors','emissions'}, stages];
        end
        output = struct();
        for i = 1:numel(stages)
            output.(stages{i}) = run_models(stages{i});
        end
    otherwise
        error('run_models:UnknownStage', 'Unknown model stage: %s', stage);
end
end

function activate_local(models, name)
base = fullfile(models, name);
addpath(fullfile(base, 'src'));
addpath(fullfile(base, 'scripts'));
end
