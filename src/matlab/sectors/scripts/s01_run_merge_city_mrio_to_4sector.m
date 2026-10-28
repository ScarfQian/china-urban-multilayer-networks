function varargout = s01_run_merge_city_mrio_to_4sector(varargin)
% S01_RUN_MERGE_CITY_MRIO_TO_4SECTOR
% Thin entry script for the MRIO4 sector-merge pipeline.

moduleRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(moduleRoot, 'src'));
[varargout{1:nargout}] = m06_run_merge_city_mrio_to_4sector_impl(varargin{:});
end
