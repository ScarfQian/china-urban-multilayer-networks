function metrics = m04_compute_block_share_metrics(predVec, truthVec, varargin)
% M04_COMPUTE_BLOCK_SHARE_METRICS
% Compute stable distribution-distance metrics for one block share vector.

p = inputParser;
p.addRequired('predVec', @(x) isnumeric(x) && isvector(x));
p.addRequired('truthVec', @(x) isnumeric(x) && isvector(x));
p.addParameter('Epsilon', 1e-12, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.parse(predVec, truthVec, varargin{:});
opt = p.Results;

pred = double(predVec(:));
truth = double(truthVec(:));
if numel(pred) ~= numel(truth)
    error('m04_compute_block_share_metrics:LengthMismatch', ...
        'predVec and truthVec must have the same length.');
end

predShare = normalize_share(pred, opt.Epsilon);
truthShare = normalize_share(truth, opt.Epsilon);
meanShare = 0.5 * (predShare + truthShare);

metrics = struct();
metrics.l1_share_distance = sum(abs(predShare - truthShare));
metrics.js_divergence = 0.5 * kl_divergence(predShare, meanShare) + 0.5 * kl_divergence(truthShare, meanShare);
metrics.hellinger_distance = sqrt(0.5 * sum((sqrt(predShare) - sqrt(truthShare)).^2));

[~, predOrder] = sort(predShare, 'descend');
[~, truthOrder] = sort(truthShare, 'descend');
metrics.top1_hit = double(predOrder(1) == truthOrder(1));
metrics.top1_overlap = metrics.top1_hit;
metrics.top3_overlap = numel(intersect(predOrder(1:min(3,end)), truthOrder(1:min(3,end)))) / min(3, numel(predOrder));
metrics.pred_top_index = predOrder(1);
metrics.truth_top_index = truthOrder(1);
end

function share = normalize_share(vec, epsilon)
vec = max(double(vec(:)), 0);
vec = vec + epsilon;
share = vec ./ sum(vec);
end

function value = kl_divergence(P, Q)
mask = P > 0 & Q > 0;
value = sum(P(mask) .* log(P(mask) ./ Q(mask)));
end
