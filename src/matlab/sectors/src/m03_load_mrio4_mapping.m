function mapping = m03_load_mrio4_mapping(csvPath)
% M03_LOAD_MRIO4_MAPPING
% Load the 42-to-4 sector mapping used by the MRIO4 carbon-matching design.

T = readtable(csvPath, 'TextType', 'string');
varNames = lower(string(T.Properties.VariableNames));

oldIdxCol = resolve_var(varNames, ["no1","old_code","sector42_code"]);
oldNameCol = resolve_var(varNames, ["old","old_name","sector42_name"]);
newIdxCol = resolve_var(varNames, ["no2","new_code","sector4_code"]);
newNameCol = resolve_var(varNames, ["new","new_name","sector4_name"]);

oldCode = double(T{:, oldIdxCol});
newCode = double(T{:, newIdxCol});
oldName = string(T{:, oldNameCol});
newName = string(T{:, newNameCol});

numOld = max(oldCode);
numNew = max(newCode);
M = sparse(newCode, oldCode, 1, numNew, numOld);

sector4Names = strings(numNew, 1);
for i = 1:numNew
    hit = find(newCode == i, 1, 'first');
    sector4Names(i) = newName(hit);
end

sector42Names = strings(numOld, 1);
for i = 1:numOld
    hit = find(oldCode == i, 1, 'first');
    sector42Names(i) = oldName(hit);
end

mapping = struct();
mapping.table = T;
mapping.mergeMatrix = M;
mapping.old_codes = oldCode;
mapping.new_codes = newCode;
mapping.sector42_codes = compose("%02d", (1:numOld)');
mapping.sector4_codes = compose("%02d", (1:numNew)');
mapping.sector42_names = sector42Names;
mapping.sector4_names = sector4Names;
mapping.numOld = numOld;
mapping.numNew = numNew;
end

function idx = resolve_var(varNames, candidates)
idx = [];
for i = 1:numel(candidates)
    hit = find(varNames == lower(string(candidates(i))), 1, 'first');
    if ~isempty(hit)
        idx = hit;
        return;
    end
end
error('m03_load_mrio4_mapping:MissingColumn', ...
    'Missing required mapping column. Candidates: %s', strjoin(cellstr(candidates), ', '));
end
