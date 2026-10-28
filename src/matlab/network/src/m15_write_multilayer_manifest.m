function out = m15_write_multilayer_manifest(runState, cfg)
% M15_WRITE_MULTILAYER_MANIFEST
% Record network inputs, parameters and result-file locations.

manifestPath = fullfile(cfg.resultsDir, 'multilayer_results_manifest.json');
summaryPath = fullfile(cfg.resultsDir, 'multilayer_pipeline_run_summary.md');

communityVariantUsed = collect_community_variant_used_local(runState.years);

manifest = struct();
manifest.generated_at = char(datetime('now', 'TimeZone', 'local', 'Format', 'yyyy-MM-dd HH:mm:ss Z'));
manifest.module = 'network';
manifest.output_surface = char(cfg.resultsDir);
manifest.frozen_inputs = struct( ...
    'city_mrio_2015_4', char(runState.inputs.paths.cityMrio2015Path), ...
    'city_mrio_2020_hybrid_4', char(runState.inputs.paths.cityMrio2020Path), ...
    'direct_emission_city4_2015', char(runState.inputs.paths.directEmission2015Path), ...
    'direct_emission_city4_2020', char(runState.inputs.paths.directEmission2020Path), ...
    'post_mgras_release_manifest', char(runState.inputs.paths.carbonManifestPath), ...
    'proxy_fallback_report', char(runState.inputs.paths.proxyFallbackPath), ...
    'investment_workbook', char(runState.inputs.paths.investmentWorkbookPath));
manifest.parameters = struct();
manifest.parameters.years = cfg.years;
manifest.parameters.sample_mode = char(string(cfg.sampleMode));
manifest.parameters.backbone_cumulative_share = cfg.backboneCumulativeShare;
manifest.parameters.qap_num_permutations = cfg.qapNumPermutations;
manifest.parameters.qap_final_permutations = cfg.qapNumPermutationsFinal;
manifest.parameters.random_attack_repeats = cfg.randomAttackRepeats;
manifest.parameters.transition_tau_values = cfg.transitionTauValues;
manifest.parameters.transition_phi_values = [min(cfg.transitionPhiValues), max(cfg.transitionPhiValues)];
manifest.parameters.transition_phi_step = cfg.transitionPhiValues(2) - cfg.transitionPhiValues(1);
manifest.parameters.transition_random_repeats = cfg.transitionRandomRepeats;
manifest.parameters.distance_floor_km = cfg.distanceFloorKm;
manifest.parameters.compute_betweenness = cfg.computeBetweenness;
manifest.parameters.compute_efficiency = cfg.computeEfficiency;
manifest.parameters.efficiency_retention_status = char(string(cfg.efficiencyRetentionStatus));
manifest.parameters.participation_normalized_used = true;
manifest.parameters.weighted_overlap_normalized_used = true;
manifest.parameters.community_variant_used = communityVariantUsed;
manifest.parameters.community_gamma_values = cfg.communityGammaValues;
manifest.output_summary_files = struct( ...
    'city_alignment_report', char(runState.alignment.cityReportPath), ...
    'sample_definition_report', char(runState.alignment.sampleDefinitionPath), ...
    'excluded_proxy_nodes', char(runState.alignment.excludedProxyNodesPath), ...
    'single_layer_network_summary', char(runState.summaryFiles.singleSummaryPath), ...
    'top_city_rankings_by_layer', char(runState.summaryFiles.topRankingsPath), ...
    'backbone_summary', char(runState.summaryFiles.backboneSummaryPath), ...
    'qap_model_diagnostics', char(runState.summaryFiles.qapDiagPath), ...
    'qap_model_diagnostics_final', char(runState.summaryFiles.qapDiagFinalPath), ...
    'community_summary', char(runState.summaryFiles.communitySummaryPath), ...
    'community_summary_by_variant', char(runState.summaryFiles.communitySummaryByVariantPath), ...
    'resilience_auc_summary', char(runState.summaryFiles.aucSummaryPath), ...
    'resilience_diagnostics', char(runState.summaryFiles.resilienceDiagnosticsPath), ...
    'attack_city_orders', char(runState.summaryFiles.attackOrdersPath), ...
    'transition_stress_auc_summary', char(runState.summaryFiles.transitionAucPath), ...
    'transition_target_city_orders', char(runState.summaryFiles.transitionTargetOrdersPath), ...
    'table_network_summary_paper', char(runState.paperTables.tableNetworkSummaryPath), ...
    'table_qap_results_paper', char(runState.paperTables.tableQapPath), ...
    'table_multilayer_roles_paper', char(runState.paperTables.tableRolesPath), ...
    'table_resilience_auc_paper', char(runState.paperTables.tableResiliencePath), ...
    'table_cross_layer_similarity_paper', char(runState.paperTables.tableCrossLayerPath));

yearOutputs = struct([]);
for i = 1:numel(runState.years)
    yearState = runState.years(i);
    item = struct();
    item.year = yearState.year;
    item.layer_validation = char(yearState.validation.outputCsv);
    item.single_layer_node_metrics = char(fullfile(cfg.resultsDir, "single_layer_node_metrics_" + string(yearState.year) + ".csv"));
    item.multilayer_node_metrics = char(fullfile(cfg.resultsDir, "multilayer_node_metrics_" + string(yearState.year) + ".csv"));
    item.cross_layer_similarity = char(fullfile(cfg.resultsDir, "cross_layer_similarity_" + string(yearState.year) + ".csv"));
    item.qap_results = char(yearState.qap.outputCsv);
    item.qap_results_final = char(yearState.qap.finalOutputCsv);
    item.role_classification = char(yearState.roles.outputCsv);
    item.community_labels = char(yearState.communities.communityLabelsPath);
    item.community_labels_by_variant = char(yearState.communities.communityByVariantPath);
    item.transition_stress_curves = char(yearState.transition.curvesPath);
    yearOutputs = append_struct_local(yearOutputs, item);
end
manifest.year_outputs = yearOutputs;
manifest.notes = { ...
    'Outputs are written to the configured model-results directory.', ...
    'Shihezi remains explicitly present under the documented missing_raw_zero_fill rule from CarbonMatching.', ...
    'Participation and weighted overlap use layer-normalized definitions.', ...
    'Transition stress test is a source-flow reduction experiment, not a node deletion attack.', ...
    'Efficiency retention is an auxiliary diagnostic.'};

fid = fopen(manifestPath, 'w');
payload = jsonencode(manifest, 'PrettyPrint', true);
fprintf(fid, '%s\n', payload);
fclose(fid);

fid = fopen(summaryPath, 'w');
fprintf(fid, '# Multilayer Pipeline Run Summary\n\n');
fprintf(fid, '## Frozen inputs\n');
fprintf(fid, '- city MRIO4 2015: `%s`\n', runState.inputs.paths.cityMrio2015Path);
fprintf(fid, '- city MRIO4 2020 hybrid: `%s`\n', runState.inputs.paths.cityMrio2020Path);
fprintf(fid, '- direct emission 2015: `%s`\n', runState.inputs.paths.directEmission2015Path);
fprintf(fid, '- direct emission 2020: `%s`\n', runState.inputs.paths.directEmission2020Path);
fprintf(fid, '- investment workbook: `%s`\n\n', runState.inputs.paths.investmentWorkbookPath);

fprintf(fid, '## Revised settings\n');
fprintf(fid, '- sample mode: `%s`\n', cfg.sampleMode);
fprintf(fid, '- backbone cumulative share: `%.2f`\n', cfg.backboneCumulativeShare);
fprintf(fid, '- QAP permutations (smoke / final): `%d / %d`\n', cfg.qapNumPermutations, cfg.qapNumPermutationsFinal);
fprintf(fid, '- transition stress tau values: `%s`\n', mat2str(cfg.transitionTauValues));
fprintf(fid, '- transition stress phi grid: `%.2f:%.2f:%.2f`\n', min(cfg.transitionPhiValues), cfg.transitionPhiValues(2) - cfg.transitionPhiValues(1), max(cfg.transitionPhiValues));
fprintf(fid, '- transition random repeats: `%d`\n', cfg.transitionRandomRepeats);
fprintf(fid, '- participation_normalized_used: `true`\n');
fprintf(fid, '- weighted_overlap_normalized_used: `true`\n');
fprintf(fid, '- efficiency_retention_status: `%s`\n\n', cfg.efficiencyRetentionStatus);

fprintf(fid, '## Key output surfaces\n');
fprintf(fid, '- city alignment report: `%s`\n', runState.alignment.cityReportPath);
fprintf(fid, '- sample definition report: `%s`\n', runState.alignment.sampleDefinitionPath);
fprintf(fid, '- QAP diagnostics final: `%s`\n', runState.summaryFiles.qapDiagFinalPath);
fprintf(fid, '- community summary by variant: `%s`\n', runState.summaryFiles.communitySummaryByVariantPath);
fprintf(fid, '- transition stress AUC summary: `%s`\n', runState.summaryFiles.transitionAucPath);
fprintf(fid, '- transition target city orders: `%s`\n', runState.summaryFiles.transitionTargetOrdersPath);
fprintf(fid, '- paper network table: `%s`\n', runState.paperTables.tableNetworkSummaryPath);
fprintf(fid, '- paper QAP table: `%s`\n', runState.paperTables.tableQapPath);
fprintf(fid, '- paper resilience table: `%s`\n\n', runState.paperTables.tableResiliencePath);

fprintf(fid, '## Notes\n');
fprintf(fid, '- Community labels are selected from a variant + gamma sweep and documented in community_summary_by_variant.csv.\n');
fprintf(fid, '- Transition stress test reduces outgoing production flows of targeted source cities and does not remove nodes.\n');
fprintf(fid, '- Efficiency retention is an auxiliary diagnostic.\n');
fclose(fid);

out = struct();
out.manifest = manifest;
out.manifestPath = string(manifestPath);
out.summaryPath = string(summaryPath);
end

function out = append_struct_local(out, item)
if isempty(out)
    out = item;
else
    out(end + 1) = item; %#ok<AGROW>
end
end

function value = collect_community_variant_used_local(yearStates)
tokens = strings(0, 1);
for i = 1:numel(yearStates)
    T = yearStates(i).communities.summaryTable;
    for j = 1:height(T)
        tokens(end + 1, 1) = string(T.year(j)) + ":" + string(T.layer(j)) + ":" + string(T.variant(j)) + ":gamma=" + string(T.gamma(j)); %#ok<AGROW>
    end
end
value = cellstr(tokens);
end
