function value = input_path(kind, name)
% INPUT_PATH Locate prepared model inputs or outputs of the preparation stages.
% Prepared files take precedence so models can be run without rebuilding MRIO.
prepared = study_path('prepared', kind, name);
if isfile(prepared)
    value = prepared;
    return;
end
switch char(kind)
    case 'mrio'
        value = study_path('generated', 'sectors', 'packages', name);
    case 'emissions'
        value = study_path('generated', 'emissions', 'carbon_matching_4', name);
    otherwise
        error('input_path:UnknownKind', 'Unknown input kind: %s', kind);
end
end
