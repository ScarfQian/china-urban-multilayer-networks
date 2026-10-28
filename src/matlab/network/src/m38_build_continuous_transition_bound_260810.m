function continuousBound = m38_build_continuous_transition_bound_260810( ...
        inputs, binaryFrontier, cfg)
% M38_BUILD_CONTINUOUS_TRANSITION_BOUND_260810
% 构造生产流损失预算下的连续城市干预上界

parts = cell(numel(cfg.years), 1);
for yIdx = 1:numel(cfg.years)
    year = cfg.years(yIdx);
    key = sprintf('y%d', year);
    governance = inputs.governance.(key);
    e = governance.PC_share(:);
    c = governance.CB_share(:);
    rho = ratio_local(e, c, cfg);
    [~, order] = sortrows([-rho, governance.city_code], [1, 2]);

    rows = cell(numel(cfg.erGrid), 1);
    for etaIdx = 1:numel(cfg.erGrid)
        eta = cfg.erGrid(etaIdx);
        budget = 1 - eta;
        z = zeros(cfg.nCities, 1);

        % 中文说明: 零生产流且正碳流的城市不占预算，应完整纳入。
        freePositive = e <= cfg.feasibilityTolerance & ...
            c > cfg.objectiveTolerance;
        z(freePositive) = 1;
        remaining = budget;

        for idx = reshape(order, 1, [])
            if z(idx) > 0 || c(idx) <= cfg.objectiveTolerance || ...
                    e(idx) <= cfg.feasibilityTolerance
                continue;
            end
            if remaining <= cfg.feasibilityTolerance
                break;
            end
            fullCost = cfg.mainTau * e(idx);
            if fullCost <= remaining + cfg.feasibilityTolerance
                z(idx) = 1;
                remaining = max(0, remaining - fullCost);
            else
                z(idx) = max(0, min(1, remaining / fullCost));
                break;
            end
        end

        actualEL = cfg.mainTau * (e' * z);
        actualCR = cfg.mainTau * (c' * z);
        fractional = find(z > cfg.feasibilityTolerance & ...
            z < 1 - cfg.feasibilityTolerance);
        fullySelected = find(z >= 1 - cfg.feasibilityTolerance);
        if numel(fractional) > 1
            error('m38_continuous_bound:MultipleFractionalCities', ...
                '%d eta=%.3f has more than one fractional city.', year, eta);
        end
        if actualEL > budget + cfg.feasibilityTolerance
            error('m38_continuous_bound:BudgetViolation', ...
                '%d eta=%.3f exceeds the production-flow-loss budget.', year, eta);
        end

        binary = binaryFrontier(binaryFrontier.year == year & ...
            abs(binaryFrontier.eta - eta) <= cfg.objectiveTolerance, :);
        if height(binary) ~= 1
            error('m38_continuous_bound:BinaryFrontierJoin', ...
                'Expected one v1 binary frontier row for %d eta=%.3f.', year, eta);
        end
        gap = actualCR - binary.carbon_reduction;
        if abs(gap) <= cfg.objectiveTolerance + cfg.feasibilityTolerance
            gap = 0;
        end
        relativeGap = NaN;
        if actualCR > cfg.objectiveTolerance
            relativeGap = gap / actualCR;
        end

        fractionalCode = NaN;
        fractionalName = string(missing);
        fractionalShare = 0;
        if ~isempty(fractional)
            fractionalCode = governance.city_code(fractional);
            fractionalName = string(governance.city_name(fractional));
            fractionalShare = z(fractional);
        end

        row = table();
        row.year = year;
        row.eta = eta;
        row.economic_loss_budget = budget;
        row.continuous_carbon_reduction = actualCR;
        row.continuous_economic_loss = actualEL;
        row.continuous_economic_retention = 1 - actualEL;
        row.n_fully_selected = numel(fullySelected);
        row.n_fractional_cities = numel(fractional);
        row.fractional_city_code = fractionalCode;
        row.fractional_city_name = fractionalName;
        row.fractional_share = fractionalShare;
        row.binary_frontier_carbon_reduction = binary.carbon_reduction;
        row.binary_frontier_economic_loss = binary.economic_loss;
        row.binary_frontier_selected_cities = binary.n_selected_cities;
        row.absolute_integrality_gap = gap;
        row.relative_integrality_gap = relativeGap;
        row.bound_definition = "fractional_city_intervention_upper_bound";
        rows{etaIdx} = row;
    end
    parts{yIdx} = vertcat(rows{:});
end
continuousBound = vertcat(parts{:});
end

function rho = ratio_local(e, c, cfg)
% 中文说明: 明确处理零分母，避免技术效率排序依赖隐式 Inf 行为。
rho = zeros(size(e));
positiveEconomic = e > cfg.feasibilityTolerance;
rho(positiveEconomic) = c(positiveEconomic) ./ e(positiveEconomic);
rho(~positiveEconomic & c > cfg.objectiveTolerance) = Inf;
rho(~positiveEconomic & c <= cfg.objectiveTolerance) = 0;
end
