function [err_bits, tot_bits] = simulate_afdm_snr_block(cfg, H_blk_afdm, QAM_order, SNR_dB)
    % SIMULATE_AFDM_SNR_BLOCK  AFDM/OFDM BER simulation using direct block matrix model.
    %
    % Mirrors simulate_afwdm_snr_block but for the SDM (point-sampling) front-end.
    % Used for both OFDM (cfg.c1=cfg.c2=0) and AFDM (cfg.c1>0) by switching the
    % chirp parameters in the cfg used to build H_blk_afdm.
    %
    % End-to-end model:
    %   y = (Wbb_sdm.' kron I_Nblk) * H_blk_afdm * (conj(Fbb_sdm) kron I_Nblk) * s + w
    %
    % Detection: LMMSE via PCG on normal equations
    %   (H_eff^H H_eff + alpha I) x_hat = H_eff^H y,   alpha = N0.
    %
    % Inputs:
    %   cfg         - config (Nblk, ms, mr, Nstreams, pcg_*; optional Fbb_sdm/Wbb_sdm)
    %   H_blk_afdm  - (mr*Nblk) x (ms*Nblk) full AFDM/OFDM block matrix
    %                 (built by build_block_matrix_afdm with appropriate cfg.c1/c2)
    %   QAM_order   - modulation order (e.g., 4 for QPSK)
    %   SNR_dB      - SNR in dB
    %
    % Outputs:
    %   err_bits    - number of bit errors
    %   tot_bits    - total number of transmitted bits

    Nblk = cfg.Nblk;
    ms   = cfg.ms;
    mr   = cfg.mr;
    Ns   = min(cfg.Nstreams, min(ms, mr));
    cfg.Nstreams = Ns;

    % Default Fbb/Wbb: identity-style stream-to-front-end mapping; Wbb keeps all mr observations
    % (主代码 reset_stream_mapping M:2104-2110 实际上已经设了 cfg.Fbb_sdm; 这里只是 fallback)
    if ~isfield(cfg, 'Fbb_sdm') || isempty(cfg.Fbb_sdm) || any(size(cfg.Fbb_sdm) ~= [ms, Ns])
        cfg.Fbb_sdm = zeros(ms, Ns);
        cfg.Fbb_sdm(1:Ns, 1:Ns) = eye(Ns);
    end
    if ~isfield(cfg, 'Wbb_sdm') || isempty(cfg.Wbb_sdm)
        cfg.Wbb_sdm = eye(mr);
    end

    bits = randi([0 1], Nblk * Ns * log2(QAM_order), 1);
    symbols = qam_modulate(bits, QAM_order);
    S = reshape(symbols, [Nblk, Ns]);

    % Per-symbol SNR: each active grid carries unit-average QAM.
    s_vec = S(:);

    snrLin = 10^(SNR_dB / 10);
    N0     = 1 / snrLin;

    % Effective block channel with BB mapping/combining (symmetric to AFWDM):
    Ttx = kron(conj(cfg.Fbb_sdm), eye(Nblk));
    assert(size(cfg.Wbb_sdm, 1) == mr, 'Wbb_sdm row size must be mr.');
    Trx = kron(cfg.Wbb_sdm.', eye(Nblk));
    H_eff_blk = Trx * H_blk_afdm * Ttx;

    % Forward model
    y_clean = H_eff_blk * s_vec;
    w = sqrt(N0/2) * (randn(size(y_clean)) + 1j*randn(size(y_clean)));
    y = y_clean + w;

    % LMMSE solve. Keep AFDM/OFDM and AFWDM on the same numerical footing:
    % use a direct solve for small systems and PCG only when dimensions grow.
    alpha = N0;
    Atb   = H_eff_blk' * y;
    n_unknown = size(H_eff_blk, 2);
    solver = 'direct';
    if isfield(cfg, 'block_lmmse_solver') && ~isempty(cfg.block_lmmse_solver)
        solver = lower(string(cfg.block_lmmse_solver));
    elseif n_unknown > 1100
        solver = 'pcg';
    end

    switch char(solver)
        case 'direct'
            Gram = H_eff_blk' * H_eff_blk + alpha * eye(n_unknown);
            x_est = Gram \ Atb;
        case 'pcg'
            Afun = @(z) (H_eff_blk' * (H_eff_blk * z) + alpha * z);
            x0 = zeros(size(s_vec));
            [x_est, flag] = pcg(Afun, Atb, cfg.pcg_tol, cfg.pcg_max_iter, [], [], x0);
            if flag ~= 0
                warning('simulate_afdm_snr_block:pcgNotConverged', ...
                    'PCG did not fully converge (flag=%d) at SNR=%.1f dB.', flag, SNR_dB);
            end
        otherwise
            error('Unknown cfg.block_lmmse_solver: %s', char(solver));
    end

    bits_est = qam_demodulate(x_est, QAM_order);

    err_bits = sum(bits ~= bits_est);
    tot_bits = length(bits);
end
