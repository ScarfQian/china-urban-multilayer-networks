function out = m16_write_paper_tables(runState, cfg)
% M16_WRITE_PAPER_TABLES
% Assemble publication-ready summary tables from the revised detailed
%   multilayer outputs without mutating any upstream results.

networkRows = table();
qapRows = table();
roleRows = table();
resilienceRows = table();
crossRows = table();

for i = 1:numel(runState.years)
    yearState = runState.years(i);
    yearNetwork = yearState.single.networkSummaryTable;
    yearNetwork.sample_mode = repmat(string(cfg.sampleMode), height(yearNetwork), 1);
    networkRows = append_table_local(networkRows, yearNetwork);

    qapFinal = yearState.qap.finalResultTable;
    qapDiag = yearState.qap.finalDiagnosticsTable(:, {'year','model','r2','adj_r2','n_permutations'});
    qapJoined = outerjoin(qapFinal, qapDiag, 'Keys', {'year','model','n_permutations'}, 'MergeKeys', true);
    qapRows = append_table_local(qapRows, qapJoined);

    roleSummary = summarize_roles_local(yearState.roles.roleTable, yearState.cross.multilayerNodeMetrics, cfg.sampleMode);
    roleRows = append_table_local(roleRows, roleSummary);

    resilienceSummary = summarize_resilience_local(yearState.resilience.aucSummaryTable, cfg.sampleMode);
    resilienceRows = append_table_local(resilienceRows, resilienceSummary);

    crossSummary = yearState.cross.similarityTable(ismember(yearState.cross.similarityTable.metric, [ ...
        "edge_weight_pearson","edge_weight_spearman","binary_overlap_raw", ...
        "weighted_overlap_layer_normalized","rank_overlap_spearman", ...
        "node_total_strength_rank_spearman","node_pagerank_rank_spearman"]), :);
    crossSummary.sample_mode = repmat(string(cfg.sampleMode), height(crossSummary), 1);
    crossRows = append_table_local(crossRows, crossSummary);
end

tableNetworkSummaryPath = fullfile(cfg.resultsDir, 'table_network_summary_paper.csv');
tableQapPath = fullfile(cfg.resultsDir, 'table_qap_results_paper.csv');
tableRolesPath = fullfile(cfg.resultsDir, 'table_multilayer_roles_paper.csv');
tableResiliencePath = fullfile(cfg.resultsDir, 'table_resilience_auc_paper.csv');
tableCrossLayerPath = fullfile(cfg.resultsDir, 'table_cross_layer_similarity_paper.csv');

writetable(networkRows, tableNetworkSummaryPath);
writetable(qapRows, tableQapPath);
writetable(roleRows, tableRolesPath);
writetable(resilienceRows, tableResiliencePath);
writetable(crossRows, tableCrossLayerPath);

out = struct();
out.tableNetworkSummaryPath = string(tableNetworkSummaryPath);
out.tableQapPath = string(tableQapPath);
out.tableRolesPath = string(tableRolesPath);
out.tableResiliencePath = string(tableResiliencePath);
out.tableCrossLayerPath = string(tableCrossLayerPath);
end

function out = summarize_roles_local(roleTable, multiNodeTable, sampleMode)
T = outerjoin(roleTable, multiNodeTable(:, {'city_code','participation_normalized','role_mismatch_index'}), ...
    'Keys', 'city_code', 'MergeKeys', true);
[G, yearValue, primaryRole] = findgroups(double(T.year), string(T.primary_role));
cityCount = splitapply(@numel, T.city_code, G);
meanParticipation = splitapply(@mean, double(T.participation_normalized), G);
meanMismatch = splitapply(@mean, double(T.role_mismatch_index), G);
shareMap = containers.Map('KeyType', 'double', 'ValueType', 'double');
uniqueYears = unique(double(T.year));
for i = 1:numel(uniqueYears)
    shareMap(uniqueYears(i)) = sum(double(T.year) == uniqueYears(i));
end
shareOfSample = zeros(size(cityCount));
for i = 1:numel(cityCount)
    shareOfSample(i) = cityCount(i) / max(shareMap(yearValue(i)), 1);
end
out = table(yearValue, primaryRole, cityCount, shareOfSample, meanParticipation, meanMismatch, ...
    repmat(string(sampleMode), numel(cityCount), 1), ...
    'VariableNames', {'year','primary_role','city_count','share_of_sample','mean_participation_normalized','mean_role_mismatch_index','sample_mode'});
end

function out = summarize_resilience_local(aucTable, sampleMode)
[G, yearValue, orderName, layerName, metricName] = findgroups(double(aucTable.year), string(aucTable.order_name), string(aucTable.layer), string(aucTable.metric));
aucMean = splitapply(@mean, double(aucTable.auc), G);
aucStd = splitapply(@std, double(aucTable.auc), G);
nRepeats = splitapply(@numel, double(aucTable.auc), G);
out = table(yearValue, orderName, layerName, metricName, aucMean, aucStd, nRepeats, repmat(string(sampleMode), numel(aucMean), 1), ...
    'VariableNames', {'year','order_name','layer','metric','auc_mean','auc_sd','n_repeats','sample_mode'});
end

function out = append_table_local(out, in)
if isempty(in) || height(in) == 0
    return;
end
if isempty(out)
    out = in;
else
    out = [out; in]; %#ok<AGROW>
end
end
