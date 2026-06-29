function [err_bits, tot_bits] = simulate_imperfect_csi_block(cfg, H_blk_real, H_blk_detector, QAM_order, SNR_dB)
% SIMULATE_IMPERFECT_CSI_BLOCK  AFWDM/SVD BER under imperfect CSI.
%
% Twin to simulate_afwdm_snr_block.m but takes TWO block matrices to
% separate (a) signal propagation through the TRUE channel from (b) the
% LMMSE detector's view of the channel (built from the channel ESTIMATE
% H_hat).
%
% Setup:
%   y      = H_blk_real     * s + w        (signal goes through TRUE channel)
%   x_est  = LMMSE_detector(y, H_blk_detector)   (detector uses ESTIMATE)
%
% For Phase C the two blocks are constructed as follows:
%   AFWDM (cfg.Us = AFWDM, channel-INDEPENDENT):
%     H_blk_real     = build_block_matrix_afwdm(H_phys_TRUE, ..., cfg)
%     H_blk_detector = build_block_matrix_afwdm(H_phys_HAT,  ..., cfg)
%     → only 1× CSI error source: detector channel mismatch
%   SVD-paper (cfg.Us = V(:,1:m_s) of G_HAT, channel-DEPENDENT):
%     cfg_p.Us = SVD(G_HAT) ;  cfg_p.Ur = U(G_HAT)    (precoder/combiner from HAT)
%     H_blk_real     = build_block_matrix_afwdm(H_phys_TRUE, ..., cfg_p)
%     H_blk_detector = build_block_matrix_afwdm(H_phys_HAT,  ..., cfg_p)
%     → 3× CSI error sources: precoder W_s_hat, channel mismatch, combiner W_r_hat
%
% Inputs:
%   cfg          config struct (Nblk, ms, mr, Nstreams, ...)
%   H_blk_real     (mr*Nblk × ms*Nblk) signal-propagation block matrix (uses H_TRUE)
%   H_blk_detector (mr*Nblk × ms*Nblk) detector's estimate block matrix (uses H_HAT)
%   QAM_order, SNR_dB
%
% Outputs: err_bits, tot_bits
%
% Mirrors simulate_afwdm_snr_block.m line-by-line except for the LMMSE step.
% cc-0507-19

    Nblk = cfg.Nblk;
    ms   = cfg.ms;
    mr   = cfg.mr;
    Ns   = min(cfg.Nstreams, min(ms, mr));
    cfg.Nstreams = Ns;

    if ~isfield(cfg, 'Fbb_wdm') || isempty(cfg.Fbb_wdm) || any(size(cfg.Fbb_wdm) ~= [ms, Ns])
        cfg.Fbb_wdm = zeros(ms, Ns);
        cfg.Fbb_wdm(1:Ns, 1:Ns) = eye(Ns);
    end
    if ~isfield(cfg, 'Wbb_wdm') || isempty(cfg.Wbb_wdm)
        cfg.Wbb_wdm = eye(mr);
    end

    bits = randi([0 1], Nblk * Ns * log2(QAM_order), 1);
    symbols = qam_modulate(bits, QAM_order);
    S = reshape(symbols, [Nblk, Ns]);
    % Per-symbol SNR: each active grid carries unit-average QAM.
    s_vec = S(:);

    snrLin = 10^(SNR_dB / 10);
    N0     = 1 / snrLin;

    % Apply BB mapping/combining to BOTH block matrices (Tx/Rx know what they applied)
    Ttx = kron(conj(cfg.Fbb_wdm), eye(Nblk));
    assert(size(cfg.Wbb_wdm,1) == mr, 'Wbb_wdm row size must be mr.');
    Trx = kron(cfg.Wbb_wdm.', eye(Nblk));
    H_eff_real     = Trx * H_blk_real     * Ttx;
    H_eff_detector = Trx * H_blk_detector * Ttx;

    % Signal propagation through TRUE channel
    y_clean = H_eff_real * s_vec;
    w = sqrt(N0/2) * (randn(size(y_clean)) + 1j*randn(size(y_clean)));
    y = y_clean + w;

    % LMMSE detector uses ESTIMATE channel (H_eff_detector)
    alpha = N0;
    Atb = H_eff_detector' * y;
    n_unknown = size(H_eff_detector, 2);
    solver = 'direct';
    if isfield(cfg, 'block_lmmse_solver') && ~isempty(cfg.block_lmmse_solver)
        solver = lower(string(cfg.block_lmmse_solver));
    elseif n_unknown > 1100
        solver = 'pcg';
    end

    switch char(solver)
        case 'direct'
            Gram = H_eff_detector' * H_eff_detector + alpha * eye(n_unknown);
            x_est = Gram \ Atb;
        case 'pcg'
            Afun = @(z) (H_eff_detector' * (H_eff_detector * z) + alpha * z);
            x0 = zeros(size(s_vec));
            [x_est, flag] = pcg(Afun, Atb, cfg.pcg_tol, cfg.pcg_max_iter, [], [], x0);
            if flag ~= 0
                warning('simulate_imperfect_csi_block:pcgNotConverged', ...
                    'PCG did not fully converge (flag=%d) at SNR=%.1f dB.', flag, SNR_dB);
            end
        otherwise
            error('Unknown cfg.block_lmmse_solver: %s', char(solver));
    end

    bits_est = qam_demodulate(x_est, QAM_order);
    err_bits = sum(bits ~= bits_est);
    tot_bits = length(bits);
end
