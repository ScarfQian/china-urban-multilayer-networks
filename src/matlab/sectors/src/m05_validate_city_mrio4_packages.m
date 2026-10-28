function validationTable = m05_validate_city_mrio4_packages(packageInputs, outputCsv)
% M05_VALIDATE_CITY_MRIO4_PACKAGES
% Validate merged MRIO4 city packages and confirm accounting identities after aggregation.

if nargin < 2
    outputCsv = "";
end

rows = cell(0, 10);
for i = 1:numel(packageInputs)
    pkg = packageInputs(i);
    if isfield(pkg, 'city')
        city = pkg.city;
        pathText = string(pkg.path);
        nameText = string(pkg.name);
    elseif isstruct(pkg) && isfield(pkg, 'path')
        pathText = string(pkg.path);
        if isfield(pkg, 'name')
            nameText = string(pkg.name);
        else
            nameText = string(erase(pathText, ".mat"));
        end
        city = m02_load_city_mrio_package(pathText);
    else
        pathText = string(pkg);
        nameText = string(erase(pathText, ".mat"));
        city = m02_load_city_mrio_package(pathText);
    end

    city = m02_load_city_mrio_package(city);
    rows(end+1, :) = { ... %#ok<AGROW>
        char(nameText), ...
        char(pathText), ...
        city.numCities, ...
        city.numSectors, ...
        city.numFD, ...
        max(abs(double(city.X) - (sum(double(city.Z), 2) + sum(double(city.Y), 2) + double(city.EX) + double(city.error)))), ...
        max(abs(double(city.X) - (sum(double(city.Z), 1)' + double(city.VA) + double(city.IM)))), ...
        sum(double(city.Z), 'all'), ...
        sum(double(city.Y), 'all'), ...
        sum(double(city.X))};
end

validationTable = cell2table(rows, 'VariableNames', { ...
    'package_name','package_path','num_cities','num_sectors','num_fd', ...
    'row_identity_max','col_identity_max','total_Z','total_Y','total_X'});

if strlength(string(outputCsv)) > 0
    writetable(validationTable, string(outputCsv));
end
end
