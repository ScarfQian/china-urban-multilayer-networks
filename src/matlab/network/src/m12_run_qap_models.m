function out = m12_run_qap_models(layerBundle, alignment, yearValue, cfg)
% M12_RUN_QAP_MODELS
% Estimate QAP-style matrix regressions for capital-production and
%   production-carbon coupling with both smoke-test and final permutation runs.

N = alignment.numCities;
mask = ~eye(N);
distanceMatrix = max(double(alignment.distanceMatrixKm), cfg.distanceFloorKm);
sameProvince = double(alignment.sameProvinceMatrix);
W_I = double(layerBundle.investment.W);
W_E = double(layerBundle.economic.W);
W_C = double(layerBundle.carbon.W);

modelSpecs = { ...
    struct('name', "Model1", 'yMatrix', log1p(W_E), 'predictors', {{log1p(W_I), log(distanceMatrix), sameProvince}}, ...
        'terms', ["Intercept","log1p_WI","log_distance","same_province"]), ...
    struct('name', "Model2", 'yMatrix', log1p(W_C), 'predictors', {{log1p(W_E), log1p(W_I), log(distanceMatrix), sameProvince}}, ...
        'terms', ["Intercept","log1p_WE","log1p_WI","log_distance","same_province"])};

smoke = run_qap_mode_local(modelSpecs, mask, N, yearValue, cfg.distanceFloorKm, cfg.randomSeed, cfg.qapNumPermutations, "smoke");
final = run_qap_mode_local(modelSpecs, mask, N, yearValue, cfg.distanceFloorKm, cfg.randomSeed + 1000, cfg.qapNumPermutationsFinal, "final");

smokeOutputCsv = fullfile(cfg.resultsDir, "qap_results_" + string(yearValue) + ".csv");
finalOutputCsv = fullfile(cfg.resultsDir, "qap_results_" + string(yearValue) + "_final.csv");
writetable(smoke.resultTable, smokeOutputCsv);
writetable(final.resultTable, finalOutputCsv);

out = struct();
out.year = yearValue;
out.smokeResultTable = smoke.resultTable;
out.smokeDiagnosticsTable = smoke.diagnosticsTable;
out.finalResultTable = final.resultTable;
out.finalDiagnosticsTable = final.diagnosticsTable;
out.outputCsv = string(smokeOutputCsv);
out.finalOutputCsv = string(finalOutputCsv);
end

function runOut = run_qap_mode_local(modelSpecs, mask, N, yearValue, distanceFloorKm, randomSeed, nPermutations, runLabel)
rng(randomSeed + yearValue);
resultRows = cell(0, 9);
diagRows = cell(0, 8);

for iModel = 1:numel(modelSpecs)
    spec = modelSpecs{iModel};
    y = spec.yMatrix(mask);
    xCell = spec.predictors;
    X = ones(numel(y), 1);
    for iX = 1:numel(xCell)
        X = [X, xCell{iX}(mask)]; %#ok<AGROW>
    end

    fit = ols_fit_local(y, X);
    betaPerm = zeros(nPermutations, numel(fit.beta));
    for iPerm = 1:nPermutations
        perm = randperm(N);
        yPermMatrix = spec.yMatrix(perm, perm);
        betaPerm(iPerm, :) = ols_fit_local(yPermMatrix(mask), X).beta';
    end
    pPerm = permutation_pvalue_local(betaPerm, fit.beta);

    for iTerm = 1:numel(spec.terms)
        resultRows(end + 1, :) = { ... %#ok<AGROW>
            yearValue, ...
            char(runLabel), ...
            char(spec.name), ...
            char(spec.terms(iTerm)), ...
            nPermutations, ...
            fit.beta(iTerm), ...
            fit.se(iTerm), ...
            fit.tStat(iTerm), ...
            pPerm(iTerm)};
    end

    diagRows(end + 1, :) = { ... %#ok<AGROW>
        yearValue, ...
        char(runLabel), ...
        char(spec.name), ...
        numel(y), ...
        nPermutations, ...
        fit.r2, ...
        fit.adjR2, ...
        distanceFloorKm};
end

runOut = struct();
runOut.resultTable = cell2table(resultRows, 'VariableNames', {'year','run_type','model','term','n_permutations','coefficient','std_error','t_stat','p_perm'});
runOut.diagnosticsTable = cell2table(diagRows, 'VariableNames', {'year','run_type','model','n_dyads','n_permutations','r2','adj_r2','distance_floor_km'});
end

function fit = ols_fit_local(y, X)
beta = X \ y;
resid = y - X * beta;
n = size(X, 1);
k = size(X, 2);
sigma2 = sum(resid .^ 2) / max(n - k, 1);
XtXInv = pinv(X' * X);
se = sqrt(max(diag(sigma2 * XtXInv), 0));
tStat = beta ./ max(se, eps);
sst = sum((y - mean(y)) .^ 2);
ssr = sum(resid .^ 2);
r2 = 1 - ssr / max(sst, eps);
adjR2 = 1 - (1 - r2) * (n - 1) / max(n - k, 1);

fit = struct();
fit.beta = beta;
fit.se = se;
fit.tStat = tStat;
fit.r2 = r2;
fit.adjR2 = adjR2;
end

function pVal = permutation_pvalue_local(betaPerm, betaHat)
pVal = zeros(1, numel(betaHat));
for i = 1:numel(betaHat)
    pVal(i) = (sum(abs(betaPerm(:, i)) >= abs(betaHat(i))) + 1) / (size(betaPerm, 1) + 1);
end
end
