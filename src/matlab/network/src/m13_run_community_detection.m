function out = m13_run_community_detection(backbones, alignment, yearValue, cfg)
% M13_RUN_COMMUNITY_DETECTION
% Detect communities across multiple backbone variants and a resolution
%   sweep, then select one publication-ready variant per layer-year.

layerNames = ["investment","economic","carbon"];
variantSpecs = { ...
    struct('name', "cumulative_flow_share", 'field', "cumulativeFlowShare", 'priority', 1), ...
    struct('name', "density_matched", 'field', "densityMatched", 'priority', 2)};

labelRowsByVariant = cell(0, 9);
summaryRowsByVariant = cell(0, 9);
selectedLabelRows = cell(0, 7);
selectedSummaryRows = cell(0, 8);

for iLayer = 1:numel(layerNames)
    layerName = layerNames(iLayer);
    candidates = struct([]);
    for iVariant = 1:numel(variantSpecs)
        spec = variantSpecs{iVariant};
        W = double(backbones.(layerName).(spec.field));
        A = (W + W') / 2;
        for iGamma = 1:numel(cfg.communityGammaValues)
            gamma = double(cfg.communityGammaValues(iGamma));
            Awork = resolution_adjusted_adjacency_local(A, gamma);
            labels = weighted_label_propagation_local(Awork, cfg.maxCommunityIter);
            [communityIds, ~, normalizedLabel] = unique(labels);
            counts = accumarray(normalizedLabel, 1);
            largestSize = max(counts);
            largestShare = largestSize / alignment.numCities;
            modularity = weighted_modularity_local(A, normalizedLabel, gamma);

            candidate = struct( ...
                'layer', layerName, ...
                'variant', spec.name, ...
                'variantPriority', spec.priority, ...
                'gamma', gamma, ...
                'labels', normalizedLabel, ...
                'numCommunities', numel(communityIds), ...
                'largestCommunitySize', largestSize, ...
                'largestCommunityShare', largestShare, ...
                'modularity', modularity);
            candidates = append_candidate_local(candidates, candidate);

            for iCity = 1:alignment.numCities
                labelRowsByVariant(end + 1, :) = { ... %#ok<AGROW>
                    yearValue, ...
                    char(layerName), ...
                    char(spec.name), ...
                    gamma, ...
                    alignment.cityTable.city_code(iCity), ...
                    char(alignment.cityTable.city_cn(iCity)), ...
                    normalizedLabel(iCity), ...
                    modularity, ...
                    0};
            end
            summaryRowsByVariant(end + 1, :) = { ... %#ok<AGROW>
                yearValue, ...
                char(layerName), ...
                char(spec.name), ...
                gamma, ...
                numel(communityIds), ...
                largestSize, ...
                largestShare, ...
                modularity, ...
                0};
        end
    end

    bestCandidate = select_best_candidate_local(candidates, cfg, alignment.numCities);
    selectedSummaryRows(end + 1, :) = { ... %#ok<AGROW>
        yearValue, ...
        char(layerName), ...
        char(bestCandidate.variant), ...
        bestCandidate.gamma, ...
        bestCandidate.numCommunities, ...
        bestCandidate.largestCommunitySize, ...
        bestCandidate.largestCommunityShare, ...
        bestCandidate.modularity};

    matchMask = strcmp(cellfun(@(x) x, labelRowsByVariant(:, 2), 'UniformOutput', false), char(layerName)) & ...
        strcmp(cellfun(@(x) x, labelRowsByVariant(:, 3), 'UniformOutput', false), char(bestCandidate.variant)) & ...
        cellfun(@(x) abs(double(x) - bestCandidate.gamma) <= eps(10), labelRowsByVariant(:, 4));
    for iRow = find(matchMask(:))'
        labelRowsByVariant{iRow, 9} = 1;
    end
    summaryMatchMask = strcmp(cellfun(@(x) x, summaryRowsByVariant(:, 2), 'UniformOutput', false), char(layerName)) & ...
        strcmp(cellfun(@(x) x, summaryRowsByVariant(:, 3), 'UniformOutput', false), char(bestCandidate.variant)) & ...
        cellfun(@(x) abs(double(x) - bestCandidate.gamma) <= eps(10), summaryRowsByVariant(:, 4));
    for iRow = find(summaryMatchMask(:))'
        summaryRowsByVariant{iRow, 9} = 1;
    end

    for iCity = 1:alignment.numCities
        selectedLabelRows(end + 1, :) = { ... %#ok<AGROW>
            yearValue, ...
            char(layerName), ...
            char(bestCandidate.variant), ...
            bestCandidate.gamma, ...
            alignment.cityTable.city_code(iCity), ...
            char(alignment.cityTable.city_cn(iCity)), ...
            bestCandidate.labels(iCity)};
    end
end

communityTableByVariant = cell2table(labelRowsByVariant, 'VariableNames', {'year','layer','variant','gamma','city_code','city_name','community_id','modularity','selected_for_paper'});
summaryByVariantTable = cell2table(summaryRowsByVariant, 'VariableNames', {'year','layer','variant','gamma','num_communities','largest_community_size','largest_community_share','modularity','selected_for_paper'});
communityTable = cell2table(selectedLabelRows, 'VariableNames', {'year','layer','variant','gamma','city_code','city_name','community_id'});
summaryTable = cell2table(selectedSummaryRows, 'VariableNames', {'year','layer','variant','gamma','num_communities','largest_community_size','largest_community_share','modularity'});

communityByVariantPath = fullfile(cfg.resultsDir, "community_labels_by_variant_" + string(yearValue) + ".csv");
communityLabelsPath = fullfile(cfg.resultsDir, "community_labels_" + string(yearValue) + ".csv");
writetable(communityTableByVariant, communityByVariantPath);
writetable(communityTable, communityLabelsPath);

out = struct();
out.year = yearValue;
out.communityTable = communityTable;
out.communityTableByVariant = communityTableByVariant;
out.summaryTable = summaryTable;
out.summaryByVariantTable = summaryByVariantTable;
out.communityLabelsPath = string(communityLabelsPath);
out.communityByVariantPath = string(communityByVariantPath);
end

function candidates = append_candidate_local(candidates, candidate)
if isempty(candidates)
    candidates = candidate;
else
    candidates(end + 1) = candidate; %#ok<AGROW>
end
end

function best = select_best_candidate_local(candidates, cfg, numCities)
numCommunities = [candidates.numCommunities]';
largestShare = [candidates.largestCommunityShare]';
modularity = [candidates.modularity]';
variantPriority = [candidates.variantPriority]';
gamma = [candidates.gamma]';

nonTrivial = numCommunities > 1 & numCommunities < numCities;
nonCollapsed = largestShare < cfg.communityCollapseThreshold;

if any(nonTrivial & nonCollapsed)
    keep = nonTrivial & nonCollapsed;
elseif any(nonTrivial)
    keep = nonTrivial;
else
    keep = true(size(numCommunities));
end

candidateIdx = find(keep);
scoreTable = [ ...
    -modularity(candidateIdx), ...
    largestShare(candidateIdx), ...
    abs(gamma(candidateIdx) - 1), ...
    variantPriority(candidateIdx), ...
    -numCommunities(candidateIdx)];
[~, order] = sortrows(scoreTable, [1, 2, 3, 4, 5]);
best = candidates(candidateIdx(order(1)));
end

function Awork = resolution_adjusted_adjacency_local(A, gamma)
strength = sum(A, 2);
twoM = sum(strength);
if twoM <= 0
    Awork = zeros(size(A));
    return;
end
expected = (strength * strength') / twoM;
Awork = max(A - gamma * expected, 0);
Awork(1:size(Awork, 1)+1:end) = 0;
end

function labels = weighted_label_propagation_local(A, maxIter)
N = size(A, 1);
labels = (1:N)';
degree = sum(A, 2);
[~, updateOrder] = sort(degree, 'descend');

for iter = 1:maxIter
    changed = false;
    for i = 1:N
        node = updateOrder(i);
        nbr = find(A(node, :) > 0);
        if isempty(nbr)
            continue;
        end
        nbrLabels = labels(nbr);
        nbrWeights = A(node, nbr)';
        uLabels = unique(nbrLabels);
        score = zeros(numel(uLabels), 1);
        for j = 1:numel(uLabels)
            score(j) = sum(nbrWeights(nbrLabels == uLabels(j)));
        end
        maxScore = max(score);
        bestLabels = uLabels(score == maxScore);
        newLabel = min(bestLabels);
        if labels(node) ~= newLabel
            labels(node) = newLabel;
            changed = true;
        end
    end
    if ~changed
        break;
    end
end
end

function Q = weighted_modularity_local(A, labels, gamma)
strength = sum(A, 2);
twoM = sum(strength);
if twoM <= 0
    Q = 0;
    return;
end
Qsum = 0;
for i = 1:numel(labels)
    sameCommunity = labels == labels(i);
    expected = (gamma * strength(i) * strength(sameCommunity) / twoM)';
    Qsum = Qsum + sum(A(i, sameCommunity) - expected);
end
Q = Qsum / twoM;
end
