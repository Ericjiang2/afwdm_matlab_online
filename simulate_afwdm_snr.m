function [err_bits, tot_bits] = simulate_afwdm_snr(cfg, G_eff, tau_vec, nu_vec, QAM_order, SNR_dB)
    % SIMULATE_AFWDM_SNR  Simulate one AFWDM frame and return bit errors.
    %
    % Uses the full physical channel G_eff (Mr x Ms per tap) with wavenumber-
    % domain (WDM) projection matrices PhiS / PhiR stored in cfg.
    %
    % Tx chain:  symbols -> IDAFT -> * PhiS^T -> (physical channel) -> DAFT -> * conj(PhiR) -> Rx
    %
    % Inputs:
    %   cfg       - config struct (Nblk, c1, c2, ms, mr, PhiS, PhiS_H, PhiR, PhiR_H, pcg_*)
    %   G_eff     - {1 x Lch} cell of (Mr x Ms) full-aperture channel matrices
    %   tau_vec   - [1 x Lch] integer delays
    %   nu_vec    - [1 x Lch] integer Dopplers
    %   QAM_order - modulation order
    %   SNR_dB    - signal-to-noise ratio in dB
    %
    % Outputs:
    %   err_bits  - number of bit errors in this frame
    %   tot_bits  - total number of bits transmitted

    Nblk = cfg.Nblk;
    % ms   = size(cfg.PhiS, 2);
    % mr   = size(cfg.PhiR, 2);
    ms   = size(cfg.Us, 2);
    mr   = size(cfg.Ur, 2);
    Ns   = min(cfg.Nstreams, min(ms, mr));

    cfg.Nstreams = Ns;

    num_bits = Nblk * Ns * log2(QAM_order);
    bits = randi([0 1], num_bits, 1);
    symbols = qam_modulate(bits, QAM_order);
    S = reshape(symbols, [Nblk, Ns]);

    % Keep total Tx power = 1 across spatial modes
    S = S / sqrt(Ns);

    % Digital stream-to-mode mapping (Ns -> ms)
    if ~isfield(cfg, 'Fbb_wdm') || isempty(cfg.Fbb_wdm) || any(size(cfg.Fbb_wdm) ~= [ms, Ns])
        cfg.Fbb_wdm = zeros(ms, Ns);
        cfg.Fbb_wdm(1:Ns, 1:Ns) = eye(Ns);
    end
    if ~isfield(cfg, 'Wbb_wdm') || isempty(cfg.Wbb_wdm)
        cfg.Wbb_wdm = eye(mr);
    end
    X = S * cfg.Fbb_wdm';
    assert(all(size(X) == [Nblk, ms]), 'AFWDM Tx map size mismatch: X must be Nblk x ms.');

    snrLin = 10^(SNR_dB / 10);
    N0     = 1 / snrLin;

    % AFWDM Tx:  Xbar = IDAFT(X) * PhiS^T  (map to full aperture, transpose not Hermitian)
    % Xbar = afdm_idaft(X, cfg) * cfg.PhiS.';
    % AFWDM Tx:  Xbar = IDAFT(X) * Phi_s^H (paper alias)
    Xbar = afdm_idaft(X, cfg) * cfg.Phi_s_H_paper;
    assert(size(Xbar,2) == size(G_eff{1},2), 'AFWDM Tx aperture size mismatch with G_eff.');

    % Physical-domain channel over full aperture
    Ybar = apply_ts_channel_afwdm(Xbar, G_eff, tau_vec, nu_vec, cfg);

    % AWGN
    Wbar = sqrt(N0/2) * (randn(size(Ybar)) + 1j*randn(size(Ybar)));
    Ybar_noisy = Ybar + Wbar;

    % AFWDM Rx:  Y = DAFT(Ybar) * conj(PhiR)  (matched-filter beamspace projection)
    % Y_mode = afdm_daft(Ybar_noisy, cfg) * conj(cfg.PhiR);
    % AFWDM Rx:  Y = DAFT(Ybar) * Phi_r (paper alias)
    Y_mode = afdm_daft(Ybar_noisy, cfg) * cfg.Phi_r_paper;
    assert(all(size(Y_mode) == [Nblk, mr]), 'AFWDM Rx mode size mismatch: Y_mode must be Nblk x mr.');
    if size(cfg.Wbb_wdm, 1) == mr
        Y = Y_mode * cfg.Wbb_wdm;
    else
        Y = Y_mode;
    end
    assert(size(Y,1) == Nblk, 'AFWDM BB combiner row size mismatch.');

    % LMMSE via PCG
    alpha = N0 * Ns;
    X_est = lmmse_detect_afwdm(Y, G_eff, tau_vec, nu_vec, cfg, alpha);

    assert(all(size(X_est) == [Nblk, Ns]), 'AFWDM detector output size mismatch: X_est must be Nblk x Ns.');
    bits_est = qam_demodulate(X_est(:), QAM_order);
    assert(numel(bits_est) == num_bits, 'AFWDM demapper bits length mismatch.');

    err_bits = sum(bits ~= bits_est);
    tot_bits = length(bits);
end
