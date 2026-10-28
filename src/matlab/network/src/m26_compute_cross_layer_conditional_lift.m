function out = m26_compute_cross_layer_conditional_lift(inputs, cfg)
% M26_COMPUTE_CROSS_LAYER_CONDITIONAL_LIFT
% 计算跨层高权重边条件概率和 lift

out = struct();
for iYear = 1:numel(cfg.years)
    yearValue = cfg.years(iYear);
    fieldName = "y" + string(yearValue);
    Y = inputs.yearData.(fieldName);
    W = {double(Y.W_I), double(Y.W_E), double(Y.W_C)};
    mask = ~eye(size(W{1}, 1));
    highSets = cell(numel(W), numel(cfg.highWeightQuantiles));
    thresholds = zeros(numel(W), numel(cfg.highWeightQuantiles));
    for iLayer = 1:numel(W)
        weights = W{iLayer}(mask);
        positiveWeights = weights(weights > 0);
        for iQ = 1:numel(cfg.highWeightQuantiles)
            q = cfg.highWeightQuantiles(iQ);
            if isempty(positiveWeights)
                threshold = Inf;
            else
                threshold = quantile_manual_local(positiveWeights, q);
            end
            thresholds(iLayer, iQ) = threshold;
            highSets{iLayer, iQ} = mask & W{iLayer} >= threshold & W{iLayer} > 0;
        end
    end

    rows = table();
    for iQ = 1:numel(cfg.highWeightQuantiles)
        q = cfg.highWeightQuantiles(iQ);
        for fromLayer = 1:3
            for toLayer = 1:3
                if fromLayer == toLayer
                    continue;
                end
                Hfrom = highSets{fromLayer, iQ};
                Hto = highSets{toLayer, iQ};
                nFrom = nnz(Hfrom);
                nTo = nnz(Hto);
                nBoth = nnz(Hfrom & Hto);
                pTo = nTo / nnz(mask);
                pToGivenFrom = nBoth / max(nFrom, 1);
                lift = pToGivenFrom / max(pTo, eps);
                rows = [rows; table(yearValue, q, cfg.layerCodes(fromLayer), cfg.layerCodes(toLayer), ...
                    cfg.layerNames(fromLayer), cfg.layerNames(toLayer), thresholds(fromLayer, iQ), thresholds(toLayer, iQ), ...
                    nFrom, nTo, nBoth, pTo, pToGivenFrom, lift, ...
                    'VariableNames', {'year','quantile','from_layer_code','to_layer_code','from_layer','to_layer', ...
                    'from_threshold','to_threshold','n_high_from','n_high_to','n_overlap','p_high_to','p_high_to_given_from','lift'})]; %#ok<AGROW>
            end
        end
    end
    pathValue = fullfile(cfg.outputDir, "cross_layer_edge_conditional_lift_" + string(yearValue) + ".csv");
    writetable(rows, pathValue);
    out.byYear.(fieldName) = rows;
end
end

function qv = quantile_manual_local(x, q)
x = sort(double(x(:)));
if isempty(x)
    qv = NaN;
elseif numel(x) == 1
    qv = x(1);
else
    pos = 1 + (numel(x) - 1) * q;
    lo = floor(pos);
    hi = ceil(pos);
    if lo == hi
        qv = x(lo);
    else
        qv = x(lo) + (x(hi) - x(lo)) * (pos - lo);
    end
end
end
