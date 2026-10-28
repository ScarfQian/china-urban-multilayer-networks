function out = m18_compute_governance_mismatch_metrics(inputs, cfg)
% M18_COMPUTE_GOVERNANCE_MISMATCH_METRICS
% 计算资本控制、生产中心性、碳责任和投资碳暴露之间的治理错配

topAll = table();
out = struct();
out.byYear = struct();

for iYear = 1:numel(cfg.years)
    yearValue = cfg.years(iYear);
    fieldName = "y" + string(yearValue);
    Y = inputs.yearData.(fieldName);
    cityTable = Y.cityTable;
    roleTable = align_table_local(Y.roleTable, cityTable);

    investmentOut = sum(double(Y.W_I), 2);
    economicOut = sum(double(Y.W_E), 2);
    carbonOut = sum(double(Y.W_C), 2);
    carbonIn = sum(double(Y.W_C), 1)';

    IC = safe_share_local(investmentOut);
    PC = safe_share_local(economicOut);
    CB = safe_share_local(carbonOut);
    CI = safe_share_local(carbonIn);

    [IC_z, IC_sd_zero] = safe_zscore_local(IC);
    [PC_z, PC_sd_zero] = safe_zscore_local(PC);
    [CB_z, CB_sd_zero] = safe_zscore_local(CB);
    [CI_z, CI_sd_zero] = safe_zscore_local(CI);

    CRM = IC_z - CB_z;
    PCM = PC_z - CB_z;
    CBA = CI_z - CB_z;

    investmentRowSum = sum(double(Y.W_I), 2);
    rowNormalizedInvestment = zeros(size(Y.W_I));
    nz = investmentRowSum > 0;
    rowNormalizedInvestment(nz, :) = double(Y.W_I(nz, :)) ./ investmentRowSum(nz);
    ICE = rowNormalizedInvestment * CB;
    [ICE_z, ICE_sd_zero] = safe_zscore_local(ICE);
    LBG = ICE_z - CB_z;
    zeroInvestmentOutFlag = investmentRowSum <= 0;

    labels = governance_labels_local(CRM, PCM, CBA, ICE_z);

    T = table();
    T.year = repmat(yearValue, height(cityTable), 1);
    T.city_code = double(cityTable.city_code);
    T.city_name = string(cityTable.city_name);
    T.investment_out_strength = investmentOut;
    T.economic_out_strength = economicOut;
    T.carbon_out_strength = carbonOut;
    T.carbon_in_strength = carbonIn;
    T.IC_share = IC;
    T.PC_share = PC;
    T.CB_share = CB;
    T.CI_share = CI;
    T.IC_z = IC_z;
    T.PC_z = PC_z;
    T.CB_z = CB_z;
    T.CI_z = CI_z;
    T.CRM = CRM;
    T.PCM = PCM;
    T.CBA = CBA;
    T.ICE = ICE;
    T.ICE_z = ICE_z;
    T.LBG = LBG;
    T.zero_investment_out_flag = zeroInvestmentOutFlag;
    T.primary_role = string(roleTable.primary_role);
    T.relative_leaning_role = string(roleTable.relative_leaning_role);
    T.governance_mismatch_label = labels;
    T.IC_sd_zero_flag = repmat(IC_sd_zero, height(T), 1);
    T.PC_sd_zero_flag = repmat(PC_sd_zero, height(T), 1);
    T.CB_sd_zero_flag = repmat(CB_sd_zero, height(T), 1);
    T.CI_sd_zero_flag = repmat(CI_sd_zero, height(T), 1);
    T.ICE_sd_zero_flag = repmat(ICE_sd_zero, height(T), 1);

    outputPath = fullfile(cfg.outputDir, "governance_mismatch_metrics_" + string(yearValue) + ".csv");
    writetable(T, outputPath);
    out.byYear.(fieldName) = T;
    topAll = [topAll; top_table_local(T, yearValue)]; %#ok<AGROW>
end

topPath = fullfile(cfg.outputDir, 'table_top_governance_mismatch_cities.csv');
writetable(topAll, topPath);
out.topTable = topAll;
out.topTablePath = string(topPath);
end

function aligned = align_table_local(T, cityTable)
[found, idx] = ismember(double(cityTable.city_code), double(T.city_code));
if ~all(found)
    error('m18_compute_governance_mismatch_metrics:CityMissing', 'Role table misses %d cities.', sum(~found));
end
aligned = T(idx, :);
end

function share = safe_share_local(x)
x = double(x(:));
total = sum(x);
if total <= 0
    share = zeros(size(x));
else
    share = x ./ total;
end
end

function [z, sdZero] = safe_zscore_local(x)
x = double(x(:));
mu = mean(x, 'omitnan');
sigma = std(x, 0, 'omitnan');
sdZero = ~isfinite(sigma) || sigma <= 0;
if sdZero
    z = zeros(size(x));
else
    z = (x - mu) ./ sigma;
end
z(~isfinite(z)) = 0;
end

function labels = governance_labels_local(CRM, PCM, CBA, ICE_z)
n = numel(CRM);
labels = strings(n, 1);
crmTop = percentile_local(CRM, 90);
crmBottom = percentile_local(CRM, 10);
pcmTop = percentile_local(PCM, 90);
pcmBottom = percentile_local(PCM, 10);
cbaTop = percentile_local(CBA, 90);
cbaBottom = percentile_local(CBA, 10);
iceTop = percentile_local(ICE_z, 90);
for i = 1:n
    parts = strings(0, 1);
    if CRM(i) >= crmTop
        parts(end + 1, 1) = "capital_control_high_carbon_low"; %#ok<AGROW>
    end
    if CRM(i) <= crmBottom
        parts(end + 1, 1) = "carbon_burden_high_control_low"; %#ok<AGROW>
    end
    if PCM(i) >= pcmTop
        parts(end + 1, 1) = "production_high_carbon_low"; %#ok<AGROW>
    end
    if PCM(i) <= pcmBottom
        parts(end + 1, 1) = "carbon_high_production_low"; %#ok<AGROW>
    end
    if CBA(i) >= cbaTop
        parts(end + 1, 1) = "carbon_inflow_beneficiary"; %#ok<AGROW>
    end
    if CBA(i) <= cbaBottom
        parts(end + 1, 1) = "carbon_outflow_bearer"; %#ok<AGROW>
    end
    if ICE_z(i) >= iceTop
        parts(end + 1, 1) = "investment_exposure_high"; %#ok<AGROW>
    end
    if isempty(parts)
        labels(i) = "balanced_or_ordinary";
    else
        labels(i) = strjoin(parts, "|");
    end
end
end

function q = percentile_local(x, p)
x = sort(double(x(:)));
x = x(isfinite(x));
if isempty(x)
    q = NaN;
elseif numel(x) == 1
    q = x(1);
else
    pos = 1 + (numel(x) - 1) * p / 100;
    lo = floor(pos);
    hi = ceil(pos);
    if lo == hi
        q = x(lo);
    else
        q = x(lo) + (x(hi) - x(lo)) * (pos - lo);
    end
end
end

function topAll = top_table_local(T, yearValue)
indicators = ["CRM", "PCM", "CBA", "ICE", "LBG"];
topAll = table();
for i = 1:numel(indicators)
    name = indicators(i);
    values = double(T.(name));
    [~, idxTop] = sort(values, 'descend');
    [~, idxBottom] = sort(values, 'ascend');
    topAll = [topAll; one_side_local(T, values, idxTop(1:min(15, numel(idxTop))), yearValue, name + "_top")]; %#ok<AGROW>
    topAll = [topAll; one_side_local(T, values, idxBottom(1:min(15, numel(idxBottom))), yearValue, name + "_bottom")]; %#ok<AGROW>
end
end

function T2 = one_side_local(T, values, idx, yearValue, indicatorName)
n = numel(idx);
T2 = table();
T2.year = repmat(yearValue, n, 1);
T2.indicator = repmat(string(indicatorName), n, 1);
T2.rank = (1:n)';
T2.city_code = double(T.city_code(idx));
T2.city_name = string(T.city_name(idx));
T2.value = values(idx);
T2.primary_role = string(T.primary_role(idx));
T2.governance_mismatch_label = string(T.governance_mismatch_label(idx));
end
