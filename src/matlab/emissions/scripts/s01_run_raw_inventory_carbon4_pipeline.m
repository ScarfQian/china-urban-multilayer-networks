function varargout = s01_run_raw_inventory_carbon4_pipeline(varargin)
% S01_RUN_RAW_INVENTORY_CARBON4_PIPELINE
% Thin entry script for the raw-inventory-based MRIO4 carbon package.

moduleRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(moduleRoot, 'src'));
[varargout{1:nargout}] = m12_run_raw_inventory_carbon4_pipeline_impl(varargin{:});
end
