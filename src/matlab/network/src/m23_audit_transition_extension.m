function audit = m23_audit_transition_extension(inputs, governance, targetOrders, stress, growthConstraint, manifest, cfg)
% M23_AUDIT_TRANSITION_EXTENSION
% 独立审计低碳转型扩展结果，防止样本、矩阵、曲线和约束检查静默失败

failures = strings(0, 1);
proxyCheck = audit_proxy_local(inputs, governance, targetOrders, cfg);
[metricBounds, metricFailures] = audit_metrics_local(inputs, governance, stress, cfg);
[curveCheck, curveFailures] = audit_curves_local(stress, cfg);
[growthCheck, growthFailures] = audit_growth_local(growthConstraint, cfg);
failures = [failures; metricFailures; curveFailures; growthFailures]; %#ok<AGROW>
if any(proxyCheck.status ~= "PASS")
    failures = [failures; "proxy_or_sample_check_failed"]; %#ok<AGROW>
end

proxyPath = fullfile(cfg.outputDir, 'audit_transition_proxy_check.csv');
metricPath = fullfile(cfg.outputDir, 'audit_transition_metric_bounds.csv');
curvePath = fullfile(cfg.outputDir, 'audit_transition_curve_monotonicity.csv');
growthPath = fullfile(cfg.outputDir, 'audit_transition_growth_constraint.csv');
writetable(proxyCheck, proxyPath);
writetable(metricBounds, metricPath);
writetable(curveCheck, curvePath);
writetable(growthCheck, growthPath);

if isempty(failures)
    status = "PASS";
else
    status = "FAIL";
end

reportPath = fullfile(cfg.outputDir, 'transition_audit_report.md');
write_report_local(reportPath, status, failures, inputs, cfg);
update_manifest_status_local(manifest.path, status, cfg.outputDir);

audit = struct();
audit.status = status;
audit.failures = failures;
audit.reportPath = string(reportPath);
audit.proxyPath = string(proxyPath);
audit.metricPath = string(metricPath);
audit.curvePath = string(curvePath);
audit.growthPath = string(growthPath);
end

function proxyCheck = audit_proxy_local(inputs, governance, targetOrders, cfg)
rows = table();
for iYear = 1:numel(cfg.years)
    yearValue = cfg.years(iYear);
    fieldName = "y" + string(yearValue);
    cityCodes = double(inputs.yearData.(fieldName).cityTable.city_code);
    proxyCount = numel(intersect(cityCodes, double(cfg.excludedProxyCodes(:))));
    rows = [rows; one_proxy_row_local(yearValue, "input_city_table", numel(unique(cityCodes)), proxyCount, cfg)]; %#ok<AGROW>
    G = governance.byYear.(fieldName);
    rows = [rows; one_proxy_row_local(yearValue, "governance_metrics", numel(unique(double(G.city_code))), ...
        numel(intersect(double(G.city_code), double(cfg.excludedProxyCodes(:)))), cfg)]; %#ok<AGROW>
    O = targetOrders.table(targetOrders.table.year == yearValue, :);
    rows = [rows; one_proxy_row_local(yearValue, "target_orders", numel(unique(double(O.city_code))), ...
        numel(intersect(double(O.city_code), double(cfg.excludedProxyCodes(:)))), cfg)]; %#ok<AGROW>
end
proxyCheck = rows;
end

function row = one_proxy_row_local(yearValue, artifact, nCities, proxyCount, cfg)
row = table();
row.year = yearValue;
row.artifact = string(artifact);
row.unique_city_count = nCities;
row.proxy_code_count = proxyCount;
row.expected_city_count = double(cfg.expectedCities);
if nCities == cfg.expectedCities && proxyCount == 0
    row.status = "PASS";
else
    row.status = "FAIL";
end
end

function [bounds, failures] = audit_metrics_local(inputs, governance, stress, cfg)
bounds = table();
failures = strings(0, 1);
for iYear = 1:numel(cfg.years)
    yearValue = cfg.years(iYear);
    fieldName = "y" + string(yearValue);
    Y = inputs.yearData.(fieldName);
    matrices = {Y.W_I, Y.W_E, Y.W_C};
    names = ["W_I", "W_E", "W_C"];
    for i = 1:numel(names)
        W = matrices{i};
        status = "PASS";
        if ~isequal(size(W), [cfg.expectedCities, cfg.expectedCities]) || any(W < -cfg.auditTolerance, 'all') || any(~isfinite(W), 'all')
            status = "FAIL";
            failures(end + 1, 1) = "matrix_check_failed_" + string(yearValue) + "_" + names(i); %#ok<AGROW>
        end
        bounds = [bounds; one_bound_row_local(yearValue, "matrix", names(i), min(W, [], 'all'), max(W, [], 'all'), status)]; %#ok<AGROW>
    end
    G = governance.byYear.(fieldName);
    shareNames = ["IC_share", "PC_share", "CB_share", "CI_share"];
    for i = 1:numel(shareNames)
        s = sum(double(G.(shareNames(i))));
        status = pass_fail_local(abs(s - 1) <= 1e-8 || s == 0);
        if status == "FAIL"
            failures(end + 1, 1) = "share_sum_failed_" + string(yearValue) + "_" + shareNames(i); %#ok<AGROW>
        end
        bounds = [bounds; one_bound_row_local(yearValue, "share_sum", shareNames(i), s, s, status)]; %#ok<AGROW>
    end
    zNames = ["IC_z", "PC_z", "CB_z", "CI_z", "ICE_z"];
    for i = 1:numel(zNames)
        z = double(G.(zNames(i)));
        status = pass_fail_local(all(isfinite(z)) && abs(mean(z)) <= 1e-8 && (std(z) == 0 || abs(std(z) - 1) <= 1e-8));
        if status == "FAIL"
            failures(end + 1, 1) = "zscore_failed_" + string(yearValue) + "_" + zNames(i); %#ok<AGROW>
        end
        bounds = [bounds; one_bound_row_local(yearValue, "zscore", zNames(i), mean(z), std(z), status)]; %#ok<AGROW>
    end
    C = stress.curvesByYear.(fieldName);
    rateOk = all(C.carbon_reduction >= -1e-10 & C.carbon_reduction <= 1 + 1e-10) && ...
        all(C.economic_retention >= -1e-10 & C.economic_retention <= 1 + 1e-10) && ...
        all(C.economic_loss >= -1e-10 & C.economic_loss <= 1 + 1e-10);
    status = pass_fail_local(rateOk && ~any(isinf(C.transition_efficiency)));
    if status == "FAIL"
        failures(end + 1, 1) = "curve_metric_bounds_failed_" + string(yearValue); %#ok<AGROW>
    end
    bounds = [bounds; one_bound_row_local(yearValue, "curve_rates", "transition_curves", ...
        min(C.carbon_reduction), max(C.economic_retention), status)]; %#ok<AGROW>
end
end

function row = one_bound_row_local(yearValue, checkType, metric, value1, value2, status)
row = table();
row.year = yearValue;
row.check_type = string(checkType);
row.metric = string(metric);
row.value_1 = double(value1);
row.value_2 = double(value2);
row.status = string(status);
end

function [curveCheck, failures] = audit_curves_local(stress, cfg)
curveCheck = table();
failures = strings(0, 1);
for iYear = 1:numel(cfg.years)
    yearValue = cfg.years(iYear);
    fieldName = "y" + string(yearValue);
    C = stress.curvesByYear.(fieldName);
    [G, keys] = findgroups(C(:, {'year','shock_type','strategy','repeat_id','tau','delta'}));
    for iGroup = 1:max(G)
        block = sortrows(C(G == iGroup, :), 'phi');
        key = keys(iGroup, :);
        phiZero = block(block.phi == 0, :);
        phiZeroOk = height(phiZero) == 1 && abs(phiZero.carbon_reduction) <= 1e-10 && ...
            abs(phiZero.economic_retention - 1) <= 1e-10 && abs(phiZero.economic_loss) <= 1e-10;
        isClean = string(key.shock_type) == "clean_decarbonization";
        if isClean
            monoOk = all(abs(block.economic_retention - 1) <= 1e-10) && all(abs(block.economic_loss) <= 1e-10) && all(isnan(block.transition_efficiency));
        else
            monoOk = all(diff(block.carbon_reduction) >= -1e-10) && ...
                all(diff(block.economic_retention) <= 1e-10) && ...
                all(diff(block.economic_loss) >= -1e-10);
        end
        boundsOk = all(block.carbon_reduction >= -1e-10 & block.carbon_reduction <= 1 + 1e-10) && ...
            all(block.economic_retention >= -1e-10 & block.economic_retention <= 1 + 1e-10) && ...
            all(block.economic_loss >= -1e-10 & block.economic_loss <= 1 + 1e-10);
        status = pass_fail_local(phiZeroOk && monoOk && boundsOk);
        if status == "FAIL"
            failures(end + 1, 1) = "curve_monotonicity_failed_" + string(yearValue) + "_" + string(key.shock_type) + "_" + string(key.strategy); %#ok<AGROW>
        end
        curveCheck = [curveCheck; curve_row_local(key, phiZeroOk, monoOk, boundsOk, status)]; %#ok<AGROW>
    end
end
end

function row = curve_row_local(key, phiZeroOk, monoOk, boundsOk, status)
row = key;
row.phi_zero_ok = phiZeroOk;
row.monotonicity_ok = monoOk;
row.bounds_ok = boundsOk;
row.status = string(status);
end

function [growthCheck, failures] = audit_growth_local(growthConstraint, cfg)
T = growthConstraint.table;
growthCheck = table();
failures = strings(0, 1);
for i = 1:height(T)
    statusOk = T.constraint_status(i) == "no_valid_curve" || ...
        (isfinite(T.economic_retention_at_selected_phi(i)) && T.economic_retention_at_selected_phi(i) >= T.eta(i) - 1e-10);
    phiOk = any(abs(T.selected_phi(i) - cfg.phiGrid(:)) <= 1e-12) || isnan(T.selected_phi(i));
    status = pass_fail_local(statusOk && phiOk);
    if status == "FAIL"
        failures(end + 1, 1) = "growth_constraint_failed_row_" + string(i); %#ok<AGROW>
    end
    row = T(i, {'year','shock_type','strategy','tau','delta','eta','selected_phi','economic_retention_at_selected_phi','constraint_status'});
    row.phi_grid_ok = phiOk;
    row.retention_constraint_ok = statusOk;
    row.status = string(status);
    growthCheck = [growthCheck; row]; %#ok<AGROW>
end

groups = unique(T(:, {'year','shock_type','strategy','tau','delta'}), 'rows');
for iGroup = 1:height(groups)
    hit = T.year == groups.year(iGroup) & T.shock_type == groups.shock_type(iGroup) & ...
        T.strategy == groups.strategy(iGroup) & T.tau == groups.tau(iGroup) & T.delta == groups.delta(iGroup);
    block = sortrows(T(hit, :), 'eta', 'descend');
        if height(block) >= 2 && any(diff(block.selected_phi) < -1e-12)
        failures(end + 1, 1) = "eta_monotonicity_failed_" + string(groups.year(iGroup)) + "_" + groups.strategy(iGroup); %#ok<AGROW>
    end
end
end

function status = pass_fail_local(conditionValue)
if conditionValue
    status = "PASS";
else
    status = "FAIL";
end
end

function write_report_local(pathValue, status, failures, inputs, cfg)
fid = fopen(pathValue, 'w');
if fid < 0
    error('m23_audit_transition_extension:WriteFailed', 'Cannot write %s.', pathValue);
end
cleanupObj = onCleanup(@() fclose(fid));
fprintf(fid, '# Transition extension audit report\n\n');
fprintf(fid, '- Run time: %s\n', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
fprintf(fid, '- Source revised results: `%s`\n', inputs.sourceResultsDir);
fprintf(fid, '- Output directory: `%s`\n', cfg.outputDir);
fprintf(fid, '- Expected sample: `%s`, n=%d\n\n', cfg.sampleMode, cfg.expectedCities);
if isempty(failures)
    fprintf(fid, 'No blocking audit failure was found.\n\n');
else
    fprintf(fid, 'Blocking audit failures:\n\n');
    for i = 1:numel(failures)
        fprintf(fid, '- %s\n', failures(i));
    end
    fprintf(fid, '\n');
end
fprintf(fid, 'Clean decarbonization records `transition_efficiency = NaN` by design because economic loss is zero and the efficiency ratio is not comparable.\n\n');
fprintf(fid, 'AUDIT_STATUS = %s\n', status);
delete(cleanupObj);
end

function update_manifest_status_local(manifestPath, status, outputDir)
data = jsondecode(fileread(manifestPath));
data.audit_status = char(status);
D = dir(outputDir);
D = D(~[D.isdir]);
data.files_created = cellstr(sort(string({D.name})'));
txt = jsonencode(data, 'PrettyPrint', true);
fid = fopen(manifestPath, 'w');
cleanupObj = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', txt);
delete(cleanupObj);
end
