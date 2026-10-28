function out = m05_build_carbon_intensity_city17(city, carbonTable, alignment, yearValue, cfg)
% M05_BUILD_CARBON_INTENSITY_CITY17
% Align the final city × MRIO4 direct-emission package with MRIO4
%   sectoral output and compute explicit city-sector carbon intensities.

N = city.numCities;
S = city.numSectors;
cityIndexMap = alignment.cityCodeToIndex;

E = zeros(N, S);
sectorNameMap = containers.Map('KeyType', 'double', 'ValueType', 'char');
for i = 1:height(carbonTable)
    cityCode = double(carbonTable.city_code(i));
    sectorCode = double(carbonTable.mrio4_sector_code(i));
    cityIdx = cityIndexMap(cityCode);
    E(cityIdx, sectorCode) = double(carbonTable.co2_total(i));
    if ~isKey(sectorNameMap, sectorCode)
        sectorNameMap(sectorCode) = char(string(carbonTable.mrio4_sector_name(i)));
    end
end

Xmat = reshape(double(city.X), [S, N])';
zeroOutputMask = Xmat <= cfg.zeroTolerance;
positiveEmissionZeroOutputMask = zeroOutputMask & (E > cfg.zeroTolerance);

q = zeros(N, S);
q(~zeroOutputMask) = E(~zeroOutputMask) ./ Xmat(~zeroOutputMask);
q(zeroOutputMask) = 0;

rows = cell(N * S, 12);
counter = 0;
for iCity = 1:N
    for iSector = 1:S
        counter = counter + 1;
        if isKey(sectorNameMap, iSector)
            sectorName = string(sectorNameMap(iSector));
        else
            sectorName = "Sector_" + compose("%02d", iSector);
        end
        rows(counter, :) = { ...
            yearValue, ...
            alignment.cityTable.province_code(iCity), ...
            char(alignment.cityTable.province_name_std(iCity)), ...
            alignment.cityTable.city_code(iCity), ...
            char(alignment.cityTable.city_cn(iCity)), ...
            iSector, ...
            char(sectorName), ...
            Xmat(iCity, iSector), ...
            E(iCity, iSector), ...
            q(iCity, iSector), ...
            double(zeroOutputMask(iCity, iSector)), ...
            double(positiveEmissionZeroOutputMask(iCity, iSector))};
    end
end

intensityTable = cell2table(rows, 'VariableNames', { ...
    'year','province_code','province_name','city_code','city_name','mrio4_sector_code','mrio4_sector_name', ...
    'output_x','direct_emission_co2','carbon_intensity','zero_output_flag','positive_emission_zero_output_flag'});
intensityTable.zero_output_zero_fill_flag = double(intensityTable.zero_output_flag == 1 & intensityTable.direct_emission_co2 == 0);
intensityTable.zero_output_positive_emission_handling = repmat("q_set_to_zero_and_flagged", height(intensityTable), 1);

outputCsv = fullfile(cfg.layerDir, "city_sector_carbon_intensity_" + string(yearValue) + ".csv");
writetable(intensityTable, outputCsv);

out = struct();
out.year = yearValue;
out.E = E;
out.X = Xmat;
out.q = q;
out.table = intensityTable;
out.outputCsv = string(outputCsv);
out.zeroOutputCount = sum(zeroOutputMask, 'all');
out.zeroOutputZeroFillCount = sum(zeroOutputMask & E == 0, 'all');
out.positiveEmissionZeroOutputCount = sum(positiveEmissionZeroOutputMask, 'all');
out.positiveEmissionZeroOutputEmission = sum(E(positiveEmissionZeroOutputMask), 'all');
end
