function city = m02_load_city_mrio_package(inputValue)
% M02_LOAD_CITY_MRIO_PACKAGE
% Load a city-MRIO package from raw MAT input or from a saved deployment MAT file
%   and normalize it into one canonical struct.

if isstruct(inputValue)
    city = normalize_city_struct(inputValue);
    return;
end

matPath = string(inputValue);
loaded = load(matPath);

if isfield(loaded, 'cityHat')
    city = normalize_city_struct(loaded.cityHat);
    return;
end
if isfield(loaded, 'city2017_harm')
    city = normalize_city_struct(loaded.city2017_harm);
    return;
end
if isfield(loaded, 'city')
    city = normalize_city_struct(loaded.city);
    return;
end
if isfield(loaded, 'MRIO') || isfield(loaded, 'Meta')
    city = normalize_city_struct(m01_parse_city_mrio_mat(matPath, 'Validate', false));
    return;
end

names = fieldnames(loaded);
for i = 1:numel(names)
    value = loaded.(names{i});
    if isstruct(value) && isfield(value, 'Z') && (isfield(value, 'Y') || isfield(value, 'F'))
        city = normalize_city_struct(value);
        return;
    end
end

error('m02_load_city_mrio_package:UnsupportedInput', ...
    'Unable to normalize city package from %s.', matPath);
end

function city = normalize_city_struct(city)
if ~isfield(city, 'Y') && isfield(city, 'F')
    city.Y = city.F;
end
required = ["Z","Y","VA","IM","EX","X"];
for i = 1:numel(required)
    if ~isfield(city, required(i))
        error('m02_load_city_mrio_package:MissingField', ...
            'City package is missing required field %s.', required(i));
    end
    city.(required(i)) = double(city.(required(i)));
end

if ~isfield(city, 'error') || isempty(city.error)
    city.error = zeros(size(city.X));
else
    city.error = double(city.error);
end

NS = size(city.Z, 1);
if isfield(city, 'sectors') && ~isempty(city.sectors)
    city.sectors = string(city.sectors(:));
    numSectors = numel(city.sectors);
else
    numSectors = 42;
    city.sectors = compose("Sector_%02d", (1:numSectors)');
end

if mod(NS, numSectors) ~= 0
    error('m02_load_city_mrio_package:InvalidDimensions', ...
        'Z rows %d cannot be divided by numSectors %d.', NS, numSectors);
end

numCities = NS / numSectors;
if ~isfield(city, 'cities') || isempty(city.cities)
    city.cities = compose("City_%03d", (1:numCities)');
else
    city.cities = string(city.cities(:));
end

if ~isfield(city, 'cities_cn') || isempty(city.cities_cn)
    city.cities_cn = strings(numCities, 1);
else
    city.cities_cn = string(city.cities_cn(:));
end

if ~isfield(city, 'fd_labels') || isempty(city.fd_labels)
    city.fd_labels = compose("FD_%d", (1:(size(city.Y, 2) / numCities))');
else
    city.fd_labels = string(city.fd_labels(:));
end

city.numCities = numCities;
city.numSectors = numSectors;
city.numFD = numel(city.fd_labels);
city.Diagnostics = local_diagnostics(city);
end

function diagOut = local_diagnostics(city)
diagOut = struct();
diagOut.row_identity_max = max(abs(city.X - (sum(city.Z, 2) + sum(city.Y, 2) + city.EX + city.error)));
diagOut.col_identity_max = max(abs(city.X - (sum(city.Z, 1)' + city.VA + city.IM)));
end
