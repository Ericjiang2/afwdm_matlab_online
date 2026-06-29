% function [err_bits, tot_bits] = simulate_afwdm_snr_block(cfg, H_blk_afwdm, QAM_order, SNR_dB)
%     % SIMULATE_AFWDM_SNR_BLOCK  AFWDM BER simulation using direct block matrix model.
%     %
%     % This is the strict end-to-end model:
%     %   y = H_blk_afwdm * x + w
%     % where H_blk_afwdm is the full AFWDM equivalent matrix built from
%     %   H = (Phi_r^T ⊗ A) * (sum_p G_p ⊗ Theta_p) * (conj(Phi_s) ⊗ A^H)
%     %
%     % Detection uses LMMSE solved by PCG on normal equations:
%     %   (H^H H + alpha I) x_hat = H^H y,   alpha = N0.
%     %
%     % Inputs:
%     %   cfg         - config struct (fields: Nblk, ms, pcg_tol, pcg_max_iter)
%     %   H_blk_afwdm - full block matrix, size (mr*Nblk) x (ms*Nblk)
%     %   QAM_order   - modulation order (e.g., 4 for QPSK)
%     %   SNR_dB      - SNR in dB
%     %
%     % Outputs:
%     %   err_bits    - number of bit errors
%     %   tot_bits    - total number of transmitted bits
% 
%     Nblk = cfg.Nblk;
%     ms   = cfg.ms;
% 
%     bits = randi([0 1], Nblk * ms * log2(QAM_order), 1);
%     symbols = qam_modulate(bits, QAM_order);
%     X = reshape(symbols, [Nblk, ms]);
% 
%     x_vec = X(:);
% 
%     snrLin = 10^(SNR_dB / 10);
%     N0     = 1 / snrLin;
% 
%     % Forward model: y = Hx + w
%     y_clean = H_blk_afwdm * x_vec;
%     w = sqrt(N0/2) * (randn(size(y_clean)) + 1j*randn(size(y_clean)));
%     y = y_clean + w;
% 
%     % LMMSE via PCG (without explicitly forming H^H H)
%     alpha = N0;
%     Atb = H_blk_afwdm' * y;
%     Afun = @(z) (H_blk_afwdm' * (H_blk_afwdm * z) + alpha * z);
% 
%     x0 = zeros(size(x_vec));
%     [x_est, ~] = pcg(Afun, Atb, cfg.pcg_tol, cfg.pcg_max_iter, [], [], x0);
% 
%     bits_est = qam_demodulate(x_est, QAM_order);
% 
%     err_bits = sum(bits ~= bits_est);
%     tot_bits = length(bits);
% end
function [err_bits, tot_bits] = simulate_afwdm_snr_block(cfg, H_blk_afwdm, QAM_order, SNR_dB)
    % SIMULATE_AFWDM_SNR_BLOCK  AFWDM BER simulation using direct block matrix model.
    %
    % This is the strict end-to-end model:
    %   y = H_blk_afwdm * x + w
    % where H_blk_afwdm is the full AFWDM equivalent matrix built from
    %   H = (Phi_r^T ⊗ A) * (sum_p G_p ⊗ Theta_p) * (conj(Phi_s) ⊗ A^H)
    %
    % Detection uses LMMSE solved by PCG on normal equations:
    %   (H^H H + alpha I) x_hat = H^H y,   alpha = N0.
    %
    % Inputs:
    %   cfg         - config struct (fields: Nblk, ms, pcg_tol, pcg_max_iter)
    %   H_blk_afwdm - full block matrix, size (mr*Nblk) x (ms*Nblk)
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

    % Per-symbol SNR: each active AF-wavenumber grid carries unit-average QAM.
    s_vec = S(:);

    snrLin = 10^(SNR_dB / 10);
    N0     = 1 / snrLin;

    % Effective block channel with BB mapping/combining:
    %   y_s = (Wbb^T ⊗ I) * H_blk * (conj(Fbb) ⊗ I) * s
    Ttx = kron(conj(cfg.Fbb_wdm), eye(Nblk));
    assert(size(cfg.Wbb_wdm,1) == mr, 'Wbb_wdm row size must be mr.');
    Trx = kron(cfg.Wbb_wdm.', eye(Nblk));
    H_eff_blk = Trx * H_blk_afwdm * Ttx;

    % Forward model: y = H_eff_blk * s + w
    y_clean = H_eff_blk * s_vec;
    w = sqrt(N0/2) * (randn(size(y_clean)) + 1j*randn(size(y_clean)));
    y = y_clean + w;

    % LMMSE solve. For the small block systems used in this project, a
    % direct solve is more reliable than PCG in the high-SNR regime, where
    % the normal equations can become ill-conditioned and mimic an error floor.
    alpha = N0;
    Atb = H_eff_blk' * y;
    n_unknown = size(H_eff_blk, 2);
    solver = 'direct';
    if isfield(cfg, 'block_lmmse_solver') && ~isempty(cfg.block_lmmse_solver)
        solver = lower(string(cfg.block_lmmse_solver));
    % elseif n_unknown > 512
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
                warning('simulate_afwdm_snr_block:pcgNotConverged', ...
                    'PCG did not fully converge (flag=%d) at SNR=%.1f dB.', flag, SNR_dB);
            end
        otherwise
            error('Unknown cfg.block_lmmse_solver: %s', char(solver));
    end

    bits_est = qam_demodulate(x_est, QAM_order);

    err_bits = sum(bits ~= bits_est);
    tot_bits = length(bits);
end
