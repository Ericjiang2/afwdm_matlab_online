function frame = simulate_imperfect_csi_gabp_frame( ...
    cfg, H_real, H_detector, qam_order, snr_db, opts)
%SIMULATE_IMPERFECT_CSI_GABP_FRAME One mismatched-CSI GaBP BER frame.
%
% H_real propagates the symbols; H_detector is the receiver-side channel
% estimate passed to GaBP. Optional pre-generated bits and unit noise let
% callers pair all schemes and CSI cases on identical Monte Carlo draws.

if nargin < 6 || isempty(opts)
    opts = struct();
end
opts = apply_defaults(opts, struct( ...
    'bits', [], ...
    'unit_noise', [], ...
    'detector_options', struct()));

validateattributes(qam_order, {'numeric'}, {'scalar', 'integer', '>', 1});
validateattributes(snr_db, {'numeric'}, {'scalar', 'real', 'finite'});
[H_real_eff, n_symbols] = effective_block_channel(cfg, H_real);
[H_detector_eff, detector_symbols] = effective_block_channel(cfg, H_detector);
if detector_symbols ~= n_symbols || ~isequal(size(H_real_eff), size(H_detector_eff))
    error('simulate_imperfect_csi_gabp_frame:dimensionMismatch', ...
        'Propagation and detector channels must have identical dimensions.');
end

n_bits = n_symbols * log2(qam_order);
if isempty(opts.bits)
    bits = logical(randi([0, 1], n_bits, 1));
else
    bits = logical(opts.bits(:));
    if numel(bits) ~= n_bits
        error('simulate_imperfect_csi_gabp_frame:bitCount', ...
            'Expected %d shared bits, got %d.', n_bits, numel(bits));
    end
end
symbols = qam_modulate(bits, qam_order);

n_observations = size(H_real_eff, 1);
if isempty(opts.unit_noise)
    unit_noise = (randn(n_observations, 1) + ...
        1j * randn(n_observations, 1)) / sqrt(2);
else
    unit_noise = opts.unit_noise(:);
    if numel(unit_noise) ~= n_observations
        error('simulate_imperfect_csi_gabp_frame:noiseCount', ...
            'Expected %d shared unit-noise samples, got %d.', ...
            n_observations, numel(unit_noise));
    end
end

noise_variance = 10^(-snr_db / 10);
signal = H_real_eff * symbols;
noise = sqrt(noise_variance) * unit_noise;
y = signal + noise;
[symbols_hat, detector_info] = detect_gmp( ...
    H_detector_eff, y, noise_variance, qam_order, opts.detector_options);
bits_hat = logical(qam_demodulate(symbols_hat, qam_order));
error_mask = bits ~= bits_hat(:);

frame = struct();
frame.bits = bits;
frame.error_mask = error_mask;
frame.error_count = sum(error_mask);
frame.bit_count = n_bits;
frame.detector = detector_info;
frame.signal_power = mean(abs(signal).^2);
frame.noise_power = mean(abs(noise).^2);
frame.aggregate_rx_snr_db = 10 * log10( ...
    max(frame.signal_power, realmin) / max(frame.noise_power, realmin));
frame.audit = struct( ...
    'propagation_channel', 'H_real', ...
    'detector_channel', 'H_detector', ...
    'shared_bits_supported', true, ...
    'shared_unit_noise_supported', true, ...
    'noise_variance', noise_variance);
end

function [H_eff, n_symbols] = effective_block_channel(cfg, H)
required = {'Nblk', 'Nstreams', 'ms', 'mr'};
for ii = 1:numel(required)
    if ~isfield(cfg, required{ii})
        error('simulate_imperfect_csi_gabp_frame:config', ...
            'Missing cfg.%s.', required{ii});
    end
end

N = cfg.Nblk;
Ns = min(cfg.Nstreams, min(cfg.ms, cfg.mr));
expected_size = [N * cfg.mr, N * cfg.ms];
if ~isequal(size(H), expected_size)
    error('simulate_imperfect_csi_gabp_frame:channelDimensions', ...
        'Expected H size %dx%d, got %dx%d.', ...
        expected_size(1), expected_size(2), size(H, 1), size(H, 2));
end

Fbb = [];
if isfield(cfg, 'Fbb_wdm')
    Fbb = cfg.Fbb_wdm;
end
if isempty(Fbb)
    Fbb = zeros(cfg.ms, Ns);
    Fbb(1:Ns, 1:Ns) = eye(Ns);
elseif ~isequal(size(Fbb), [cfg.ms, Ns])
    error('simulate_imperfect_csi_gabp_frame:FbbDimensions', ...
        'Fbb_wdm must be %dx%d.', cfg.ms, Ns);
end

Wbb = [];
if isfield(cfg, 'Wbb_wdm')
    Wbb = cfg.Wbb_wdm;
end
if isempty(Wbb)
    Wbb = eye(cfg.mr);
elseif size(Wbb, 1) ~= cfg.mr
    error('simulate_imperfect_csi_gabp_frame:WbbDimensions', ...
        'Wbb_wdm must have %d rows.', cfg.mr);
end

Ttx = kron(conj(Fbb), eye(N));
Trx = kron(Wbb.', eye(N));
H_eff = Trx * H * Ttx;
n_symbols = N * Ns;
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
