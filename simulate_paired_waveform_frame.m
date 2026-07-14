function pair = simulate_paired_waveform_frame(cfg_a, H_a, cfg_b, H_b, qam_order, snr_db, opts)
%SIMULATE_PAIRED_WAVEFORM_FRAME Evaluate two waveform arms on identical data/noise.
%
% H_a and H_b are the two equivalent MIMO-DD block channels. The caller
% supplies one bit vector and one unit-variance complex noise vector so the
% only arm-specific inputs are the temporal basis already represented by H.

if nargin < 7 || isempty(opts)
    opts = struct();
end
opts = apply_defaults(opts, struct( ...
    'bits', [], ...
    'unit_noise', [], ...
    'detector', 'block_lmmse', ...
    'detector_options', struct()));
validateattributes(qam_order, {'numeric'}, {'scalar', 'integer', '>', 1});
validateattributes(snr_db, {'numeric'}, {'scalar', 'real'});

[H_eff_a, n_symbols_a] = effective_block_channel(cfg_a, H_a);
[H_eff_b, n_symbols_b] = effective_block_channel(cfg_b, H_b);
if n_symbols_a ~= n_symbols_b || size(H_eff_a, 1) ~= size(H_eff_b, 1)
    error('simulate_paired_waveform_frame:dimensionMismatch', ...
        'Paired arms must have identical input and output dimensions.');
end

n_bits = n_symbols_a * log2(qam_order);
if isempty(opts.bits)
    bits = randi([0, 1], n_bits, 1);
else
    bits = logical(opts.bits(:));
    if numel(bits) ~= n_bits
        error('simulate_paired_waveform_frame:bitCount', ...
            'Expected %d shared bits, got %d.', n_bits, numel(bits));
    end
end
symbols = qam_modulate(bits, qam_order);

if isempty(opts.unit_noise)
    unit_noise = (randn(size(H_eff_a, 1), 1) + ...
        1j * randn(size(H_eff_a, 1), 1)) / sqrt(2);
else
    unit_noise = opts.unit_noise(:);
    if numel(unit_noise) ~= size(H_eff_a, 1)
        error('simulate_paired_waveform_frame:noiseCount', ...
            'Expected %d shared unit-noise samples, got %d.', ...
            size(H_eff_a, 1), numel(unit_noise));
    end
end

noise_variance = 10^(-snr_db / 10);
noise = sqrt(noise_variance) * unit_noise;
y_a = H_eff_a * symbols + noise;
y_b = H_eff_b * symbols + noise;

[x_a, detector_a] = run_detector(opts.detector, H_eff_a, y_a, ...
    noise_variance, cfg_a, qam_order, opts.detector_options);
[x_b, detector_b] = run_detector(opts.detector, H_eff_b, y_b, ...
    noise_variance, cfg_b, qam_order, opts.detector_options);

bits_a = qam_demodulate(x_a, qam_order);
bits_b = qam_demodulate(x_b, qam_order);

pair = struct();
pair.bits = bits;
pair.error_a = logical(bits ~= bits_a(:));
pair.error_b = logical(bits ~= bits_b(:));
pair.err_a = sum(pair.error_a);
pair.err_b = sum(pair.error_b);
pair.bit_count = n_bits;
pair.detector_a = detector_a;
pair.detector_b = detector_b;
pair.audit = struct( ...
    'shared_bits', true, ...
    'shared_unit_noise', true, ...
    'detector', opts.detector, ...
    'noise_variance', noise_variance);
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

function [H_eff, n_symbols] = effective_block_channel(cfg, H)
N = cfg.Nblk;
Ns = min(cfg.Nstreams, min(cfg.ms, cfg.mr));

Fbb = [];
if isfield(cfg, 'Fbb_wdm')
    Fbb = cfg.Fbb_wdm;
end
if isempty(Fbb) || any(size(Fbb) ~= [cfg.ms, Ns])
    Fbb = zeros(cfg.ms, Ns);
    Fbb(1:Ns, 1:Ns) = eye(Ns);
end

Wbb = [];
if isfield(cfg, 'Wbb_wdm')
    Wbb = cfg.Wbb_wdm;
end
if isempty(Wbb)
    Wbb = eye(cfg.mr);
end

Ttx = kron(conj(Fbb), eye(N));
Trx = kron(Wbb.', eye(N));
H_eff = Trx * H * Ttx;
n_symbols = N * Ns;
end

function [x_hat, info] = run_detector(name, H, y, noise_variance, cfg, qam_order, detector_options)
switch lower(name)
    case 'block_lmmse'
        rhs = H' * y;
        n = size(H, 2);
        solver = 'direct';
        if isfield(cfg, 'block_lmmse_solver') && ~isempty(cfg.block_lmmse_solver)
            solver = lower(char(cfg.block_lmmse_solver));
        end
        switch solver
            case 'direct'
                x_hat = (H' * H + noise_variance * eye(n)) \ rhs;
                info = struct('iterations', 1, 'converged', true, 'solver', solver);
            case 'pcg'
                Afun = @(z) H' * (H * z) + noise_variance * z;
                [x_hat, flag, ~, iterations] = pcg(Afun, rhs, ...
                    cfg.pcg_tol, cfg.pcg_max_iter, [], [], zeros(n, 1));
                info = struct('iterations', iterations, 'converged', flag == 0, 'solver', solver);
            otherwise
                error('simulate_paired_waveform_frame:detectorSolver', ...
                    'Unknown block LMMSE solver "%s".', solver);
        end
    case 'gabp'
        [x_hat, info] = detect_gmp(H, y, noise_variance, qam_order, detector_options);
    case 'per_stream_lmmse'
        [x_hat, info] = detect_per_stream_lmmse(H, y, noise_variance, cfg);
    otherwise
        error('simulate_paired_waveform_frame:detector', ...
            'Unknown detector "%s".', name);
end
end

function [x_hat, info] = detect_per_stream_lmmse(H, y, noise_variance, cfg)
N = cfg.Nblk;
Ns = min(cfg.Nstreams, min(cfg.ms, cfg.mr));
if size(H, 1) ~= N * Ns || size(H, 2) ~= N * Ns
    error('simulate_paired_waveform_frame:perStreamDimensions', ...
        'Per-stream LMMSE requires a square Nblk*Nstreams block channel.');
end

x_hat = zeros(N * Ns, 1);
for stream = 1:Ns
    index = (stream - 1) * N + (1:N);
    H_stream = H(index, index);
    x_hat(index) = (H_stream' * H_stream + noise_variance * eye(N)) \ ...
        (H_stream' * y(index));
end
info = struct('iterations', 1, 'converged', true, ...
    'solver', 'per_stream_lmmse', 'stream_count', Ns);
end
