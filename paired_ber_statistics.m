function stats = paired_ber_statistics(error_a, error_b, opts)
%PAIRED_BER_STATISTICS Paired BER ratio CI and exact McNemar significance.
%
% Rows are bits within a frame and columns are paired frames. The reported
% ratio is BER_B / BER_A, so values above one favor arm A (AFWDM in the
% time-diversity runner).

if nargin < 3 || isempty(opts)
    opts = struct();
end
opts = apply_defaults(opts, struct( ...
    'target_errors', 100, ...
    'bootstrap_samples', 2000, ...
    'bootstrap_seed', 20260715, ...
    'confidence', 0.95));
validateattributes(opts.target_errors, {'numeric'}, {'scalar', 'nonnegative'});
validateattributes(opts.bootstrap_samples, {'numeric'}, {'scalar', 'integer', 'positive'});
validateattributes(opts.bootstrap_seed, {'numeric'}, {'scalar', 'integer'});
validateattributes(opts.confidence, {'numeric'}, {'scalar', '>', 0, '<', 1});

if ~isequal(size(error_a), size(error_b)) || isempty(error_a)
    error('paired_ber_statistics:shape', ...
        'Paired error tables must be nonempty logical arrays with equal size.');
end

frame_errors_a = sum(error_a, 1);
frame_errors_b = sum(error_b, 1);
err_a = sum(frame_errors_a);
err_b = sum(frame_errors_b);
bit_count = numel(error_a);

stats = struct();
stats.ber_a = err_a / bit_count;
stats.ber_b = err_b / bit_count;
stats.ber_ratio_b_over_a = safe_ratio(err_b, err_a);
stats.error_count_a = err_a;
stats.error_count_b = err_b;
stats.bit_count = bit_count;
stats.frame_count = size(error_a, 2);
stats.discordant_a_only = sum(error_a(:) & ~error_b(:));
stats.discordant_b_only = sum(~error_a(:) & error_b(:));
stats.mcnemar_p = exact_mcnemar(stats.discordant_a_only, stats.discordant_b_only);
stats.noise_limited = min(err_a, err_b) < opts.target_errors;
stats.claim_eligible = ~stats.noise_limited;
stats.ber_ratio_ci = bootstrap_ratio_ci(frame_errors_a, frame_errors_b, opts);
end

function value = apply_defaults(value, defaults)
names = fieldnames(defaults);
for ii = 1:numel(names)
    name = names{ii};
    if ~isfield(value, name)
        value.(name) = defaults.(name);
    end
end
end

function ratio = safe_ratio(numerator, denominator)
if denominator == 0
    if numerator == 0
        ratio = NaN;
    else
        ratio = Inf;
    end
else
    ratio = numerator / denominator;
end
end

function ci = bootstrap_ratio_ci(errors_a, errors_b, opts)
previous_rng = rng;
cleanup = onCleanup(@() rng(previous_rng)); %#ok<NASGU>
rng(opts.bootstrap_seed, 'twister');

n_frames = numel(errors_a);
ratios = nan(opts.bootstrap_samples, 1);
for ii = 1:opts.bootstrap_samples
    index = randi(n_frames, 1, n_frames);
    ratios(ii) = safe_ratio(sum(errors_b(index)), sum(errors_a(index)));
end
ratios = sort(ratios(~isnan(ratios)));
if isempty(ratios)
    ci = [NaN, NaN];
    return;
end

alpha = (1 - opts.confidence) / 2;
lo = max(1, ceil(alpha * numel(ratios)));
hi = min(numel(ratios), ceil((1 - alpha) * numel(ratios)));
ci = [ratios(lo), ratios(hi)];
end

function p = exact_mcnemar(a_only, b_only)
n = a_only + b_only;
if n == 0
    p = 1;
    return;
end
k = min(a_only, b_only);
terms = zeros(k + 1, 1);
for jj = 0:k
    terms(jj + 1) = gammaln(n + 1) - gammaln(jj + 1) - ...
        gammaln(n - jj + 1) - n * log(2);
end
peak = max(terms);
lower_tail = exp(peak) * sum(exp(terms - peak));
p = min(1, 2 * lower_tail);
end
