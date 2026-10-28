function varargout = s03_run_city_mrio_2020_deployment(varargin)
% S03_RUN_CITY_MRIO_2020_DEPLOYMENT
% s03 run city mrio 2020 deployment

moduleRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(moduleRoot, 'src'));
[varargout{1:nargout}] = m27_run_city_mrio_2020_deployment_impl(varargin{:});
end
