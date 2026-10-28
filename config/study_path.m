function pathValue = study_path(area, varargin)
% STUDY_PATH Resolve code, input and output locations for this study.
% Edit paths.json to use a different data directory or output directory.
root = fileparts(fileparts(mfilename('fullpath')));
settings = jsondecode(fileread(fullfile(root, 'config', 'paths.json')));
switch char(area)
    case 'root'
        base = root;
    case 'data'
        base = absolute_local(root, settings.data_directory);
    case 'raw'
        base = fullfile(absolute_local(root, settings.data_directory), 'raw');
    case 'metadata'
        base = fullfile(absolute_local(root, settings.data_directory), 'metadata');
    case 'prepared'
        base = fullfile(absolute_local(root, settings.data_directory), 'prepared');
    case 'generated'
        base = absolute_local(root, settings.output_directory);
    otherwise
        error('study_path:UnknownArea', 'Unknown path area: %s', area);
end
pathValue = string(fullfile(base, varargin{:}));
end

function value = absolute_local(root, value)
value = char(value);
if ~java.io.File(value).isAbsolute()
    value = fullfile(root, value);
end
end
