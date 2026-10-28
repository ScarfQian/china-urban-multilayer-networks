function varargout = s01_validate_backcast_2017_y_hybrid(varargin)
% S01_VALIDATE_BACKCAST_2017_Y_HYBRID
% s01 validate backcast 2017 y hybrid

moduleRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(moduleRoot, 'src'));
[varargout{1:nargout}] = m19_validate_backcast_2017_y_hybrid_impl(varargin{:});
end
