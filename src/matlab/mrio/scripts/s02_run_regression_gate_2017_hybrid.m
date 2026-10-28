function varargout = s02_run_regression_gate_2017_hybrid(varargin)
% S02_RUN_REGRESSION_GATE_2017_HYBRID
% s02 run regression gate 2017 hybrid

moduleRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(moduleRoot, 'src'));
[varargout{1:nargout}] = m25_run_regression_gate_2017_hybrid(varargin{:});
end
