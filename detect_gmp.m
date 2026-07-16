function [x_hat, info] = detect_gmp(H, y, noise_variance, qam_order, opts)
%DETECT_GMP Damped Gaussian message passing with a finite-QAM prior.
%
% This is the rectangular MIMO-DD extension of the project's SISO BP-MP
% reference. It runs the same observation-to-variable and
% variable-to-observation equations on the supplied equivalent block channel
% H. AFWDM and OFWDM callers must pass the same opts; H is the only
% waveform-dependent detector input.

if nargin < 5 || isempty(opts)
    opts = struct();
end
opts = apply_defaults(opts, struct( ...
    'damping', 0.5, ...
    'max_iterations', 20, ...
    'tolerance', 1e-4, ...
    'edge_threshold_rel', 0, ...
    'regularization', 1e-10));

if opts.damping < 0.3 || opts.damping > 0.5
    error('detect_gmp:damping', 'Damping must be in the locked range [0.3, 0.5].');
end
validateattributes(opts.max_iterations, {'numeric'}, {'scalar', 'integer', '>=', 10, '<=', 60});
validateattributes(opts.tolerance, {'numeric'}, {'scalar', 'positive'});
validateattributes(opts.edge_threshold_rel, {'numeric'}, {'scalar', 'nonnegative', '<', 1});
validateattributes(opts.regularization, {'numeric'}, {'scalar', 'positive'});
validateattributes(noise_variance, {'numeric'}, {'scalar', 'positive', 'finite'});
if qam_order ~= 4
    error('detect_gmp:qamOrder', 'The time-diversity GaBP contract currently supports QPSK only.');
end
if size(H, 1) ~= numel(y)
    error('detect_gmp:dimensionMismatch', ...
        'H has %d rows but y has %d samples.', size(H, 1), numel(y));
end
if isempty(H) || any(~isfinite(H(:))) || any(~isfinite(y(:)))
    error('detect_gmp:invalidInput', 'H and y must be nonempty and finite.');
end

y = y(:);
[n_obs, n_var] = size(H);
constellation = qammod((0:qam_order-1).', qam_order, 'UnitAveragePower', true).';
prior_mean = mean(constellation);
prior_variance = mean(abs(constellation).^2) - abs(prior_mean)^2;

threshold = opts.edge_threshold_rel * max(abs(H(:)));
edge_mask = abs(H) > max(threshold, 0);
if ~any(edge_mask(:))
    error('detect_gmp:noEdges', 'No channel edges remain after thresholding.');
end
H_edge = H;
H_edge(~edge_mask) = 0;
abs_h2 = abs(H_edge).^2;

mu_v2o = prior_mean * ones(n_obs, n_var);
mu_v2o(~edge_mask) = 0;
var_v2o = prior_variance * double(edge_mask);
mu_o2v = zeros(n_obs, n_var);
var_o2v = inf(n_obs, n_var);
residual_history = nan(opts.max_iterations, 1);
variance_floor = max(0.1 * noise_variance, opts.regularization);
converged = false;

for iteration = 1:opts.max_iterations
    mu_old = mu_v2o;

    z_total = y - sum(H_edge .* mu_v2o, 2);
    variance_total = noise_variance + sum(abs_h2 .* var_v2o, 2);
    z_extrinsic = z_total + H_edge .* mu_v2o;
    variance_extrinsic = max(variance_total - abs_h2 .* var_v2o, variance_floor);
    mu_o2v(edge_mask) = z_extrinsic(edge_mask) ./ H_edge(edge_mask);
    var_o2v(edge_mask) = variance_extrinsic(edge_mask) ./ abs_h2(edge_mask);
    var_o2v(edge_mask) = max(var_o2v(edge_mask), opts.regularization);

    inverse_variance = zeros(n_obs, n_var);
    inverse_variance(edge_mask) = 1 ./ var_o2v(edge_mask);
    precision_total = sum(inverse_variance, 1);
    weighted_mean_total = sum(mu_o2v .* inverse_variance, 1);
    precision_extrinsic = max(precision_total - inverse_variance, opts.regularization);
    weighted_mean_extrinsic = weighted_mean_total - mu_o2v .* inverse_variance;
    variance_to_denoiser = 1 ./ precision_extrinsic;
    mean_to_denoiser = variance_to_denoiser .* weighted_mean_extrinsic;

    [mu_new, var_new] = qpsk_denoise(mean_to_denoiser, variance_to_denoiser, constellation);
    mu_v2o(edge_mask) = (1 - opts.damping) * mu_old(edge_mask) + ...
        opts.damping * mu_new(edge_mask);
    var_v2o(edge_mask) = max(var_new(edge_mask), opts.regularization);

    denominator = max(norm(mu_v2o(edge_mask)), opts.regularization);
    residual_history(iteration) = norm(mu_v2o(edge_mask) - mu_old(edge_mask)) / denominator;
    if residual_history(iteration) < opts.tolerance
        converged = true;
        break;
    end
end

inverse_variance = zeros(n_obs, n_var);
inverse_variance(edge_mask) = 1 ./ var_o2v(edge_mask);
precision_post = max(sum(inverse_variance, 1), opts.regularization);
mean_post = sum(mu_o2v .* inverse_variance, 1) ./ precision_post;
x_hat = hard_qpsk(mean_post, constellation).';

info = struct();
info.iterations = iteration;
info.converged = converged;
info.nonconverged = ~converged;
info.residual = residual_history(iteration);
info.residual_history = residual_history(1:iteration);
info.damping = opts.damping;
info.max_iterations = opts.max_iterations;
info.tolerance = opts.tolerance;
info.edge_threshold_rel = opts.edge_threshold_rel;
info.edge_count = nnz(edge_mask);
info.edge_density = info.edge_count / numel(H);
info.solver = 'damped_gaussian_mp_qpsk';
end

function [posterior_mean, posterior_variance] = qpsk_denoise(mean_in, variance_in, constellation)
max_log = -inf(size(mean_in));
for ii = 1:numel(constellation)
    log_weight = -abs(constellation(ii) - mean_in).^2 ./ variance_in;
    max_log = max(max_log, log_weight);
end

weight_sum = zeros(size(mean_in));
weighted_symbol = zeros(size(mean_in));
weighted_energy = zeros(size(mean_in));
for ii = 1:numel(constellation)
    weight = exp(-abs(constellation(ii) - mean_in).^2 ./ variance_in - max_log);
    weight_sum = weight_sum + weight;
    weighted_symbol = weighted_symbol + weight * constellation(ii);
    weighted_energy = weighted_energy + weight * abs(constellation(ii))^2;
end
weight_sum = max(weight_sum, realmin);
posterior_mean = weighted_symbol ./ weight_sum;
posterior_variance = weighted_energy ./ weight_sum - abs(posterior_mean).^2;
posterior_variance = max(real(posterior_variance), 1e-10);
end

function symbols = hard_qpsk(means, constellation)
distance = zeros(numel(constellation), numel(means));
for ii = 1:numel(constellation)
    distance(ii, :) = abs(means - constellation(ii)).^2;
end
[~, index] = min(distance, [], 1);
symbols = constellation(index);
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
