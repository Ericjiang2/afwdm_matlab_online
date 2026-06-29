% function H = build_block_matrix_afwdm(G_eff, tau_vec, nu_vec, cfg)
%     % BUILD_BLOCK_MATRIX_AFWDM  Construct the full AFWDM block equivalent matrix.
%     %
%     % Using the Kronecker mixed-product property (main.pdf Eq.(48)):
%     %
%     %   H_AFWDM = (Φ_r^T ⊗ A) [Σ_p G_p ⊗ Θ_p] (conj(Φ_s) ⊗ A^H)
%     %           = Σ_p  (Φ_r^T G_p conj(Φ_s)) ⊗ (A Θ_p A^H)
%     %
%     % where:
%     %   G_p           = Mr × Ms full-aperture physical channel for path p
%     %   Θ_p           = N × N time-domain block matrix (delay + Doppler + CPP)
%     %   A             = N × N DAFT matrix
%     %   Φ_s           = Ms × ms  Tx wavenumber selection (cfg.PhiS)
%     %   Φ_r           = Mr × mr  Rx wavenumber selection (cfg.PhiR)
%     %   Φ_r^T         = mr × Mr  (non-conjugate transpose)
%     %   conj(Φ_s)     = Ms × ms  (elementwise conjugate)
%     %
%     % Derivation from the operator chain:
%     %   Tx:  Xbar = A^H X Φ_s^H    →  vec = (conj(Φ_s) ⊗ A^H) vec(X)
%     %   Ch:  Ybar = Σ_p Θ_p Xbar G_p^T  →  vec = Σ_p (G_p ⊗ Θ_p) vec(Xbar)
%     %   Rx:  Y    = A Ybar Φ_r           →  vec = (Φ_r^T ⊗ A) vec(Ybar)
%     %
%     % Result: H is (mr*N × ms*N), maps vec(X) to vec(Y) in AFW domain.
%     %
%     % Inputs:
%     %   G_eff   - {1 × Lch} cell of (Mr × Ms) full-aperture channel matrices
%     %   tau_vec - [1 × Lch] integer delays
%     %   nu_vec  - [1 × Lch] integer Dopplers
%     %   cfg     - struct with fields: Nblk, c1, c2, ms, mr, PhiS, PhiR
%     %
%     % Output:
%     %   H       - (mr*N × ms*N) full block equivalent matrix
% 
%     N   = cfg.Nblk;
%     ms  = cfg.ms;
%     mr  = cfg.mr;
%     Lch = numel(G_eff);
% 
%     % Build DAFT matrix once
%     A = build_daft_matrix(cfg);
% 
%     % Spatial projection matrices (precompute once)
%     PhiR_T    = cfg.PhiR.';        % mr × Mr  (non-conjugate transpose)
%     PhiS_conj = conj(cfg.PhiS);    % Ms × ms  (elementwise conjugate)
% 
%     H = zeros(mr*N, ms*N);
% 
%     for p = 1:Lch
%         tau = round(real(tau_vec(p)));
%         nu  = round(real(nu_vec(p)));
% 
%         Theta_p = build_theta_p(tau, nu, N, cfg.c1);
% 
%         S_p = PhiR_T * G_eff{p} * PhiS_conj;   % (mr×Mr)(Mr×Ms)(Ms×ms) = mr × ms
%         D_p = A * Theta_p * A';                  % N × N  DAFT-domain path kernel
% 
%         H = H + kron(S_p, D_p);                  % (mr × ms) ⊗ (N × N)
%     end
% end
% function H = build_block_matrix_afwdm(G_eff, tau_vec, nu_vec, cfg)
%     % BUILD_BLOCK_MATRIX_AFWDM  Construct the full AFWDM block equivalent matrix.
%     %
%     % Using the Kronecker mixed-product property (main.pdf Eq.(48)):
%     %
%     %   H_AFWDM = (Φ_r^T ⊗ A) [Σ_p G_p ⊗ Θ_p] (conj(Φ_s) ⊗ A^H)
%     %           = Σ_p  (Φ_r^T G_p conj(Φ_s)) ⊗ (A Θ_p A^H)
%     %
%     % where:
%     %   G_p           = Mr × Ms full-aperture physical channel for path p
%     %   Θ_p           = N × N time-domain block matrix (delay + Doppler + CPP)
%     %   A             = N × N DAFT matrix
%     %   Φ_s           = Ms × ms  Tx wavenumber selection (cfg.PhiS)
%     %   Φ_r           = Mr × mr  Rx wavenumber selection (cfg.PhiR)
%     %   Φ_r^T         = mr × Mr  (non-conjugate transpose)
%     %   conj(Φ_s)     = Ms × ms  (elementwise conjugate)
%     %
%     % Derivation from the operator chain:
%     %   Tx:  Xbar = A^H X Φ_s^T    →  vec = (Φ_s ⊗ A^H) vec(X)
%     %   Ch:  Ybar = Σ_p Θ_p Xbar G_p^T  →  vec = Σ_p (G_p ⊗ Θ_p) vec(Xbar)
%     %   Rx:  Y    = A Ybar conj(Φ_r)     →  vec = (Φ_r^H ⊗ A) vec(Ybar)
%     %
%     % Result: H is (mr*N × ms*N), maps vec(X) to vec(Y) in AFW domain.
%     %
%     % Inputs:
%     %   G_eff   - {1 × Lch} cell of (Mr × Ms) full-aperture channel matrices
%     %   tau_vec - [1 × Lch] integer delays
%     %   nu_vec  - [1 × Lch] integer Dopplers
%     %   cfg     - struct with fields: Nblk, c1, c2, ms, mr, PhiS, PhiR
%     %
%     % Output:
%     %   H       - (mr*N × ms*N) full block equivalent matrix
% 
%     N   = cfg.Nblk;
%     ms  = cfg.ms;
%     mr  = cfg.mr;
%     Lch = numel(G_eff);
% 
%     % Build DAFT matrix once
%     A = build_daft_matrix(cfg);
% 
%     % Spatial projection matrices (precompute once)
%     PhiR_H    = cfg.PhiR';          % mr × Mr  (conjugate transpose = Hermitian)
%     PhiS_plain = cfg.PhiS;           % Ms × ms  (no conjugate)
% 
%     H = zeros(mr*N, ms*N);
% 
%     for p = 1:Lch
%         tau = round(real(tau_vec(p)));
%         nu  = round(real(nu_vec(p)));
% 
%         Theta_p = build_theta_p(tau, nu, N, cfg.c1);
% 
%         S_p = PhiR_H * G_eff{p} * PhiS_plain;   % (mr×Mr)(Mr×Ms)(Ms×ms) = mr × ms  [beamspace]
%         D_p = A * Theta_p * A';                  % N × N  DAFT-domain path kernel
% 
%         H = H + kron(S_p, D_p);                  % (mr × ms) ⊗ (N × N)
%     end
% end
function H = build_block_matrix_afwdm(G_eff, tau_vec, nu_vec, cfg)
    % BUILD_BLOCK_MATRIX_AFWDM  AFDM-time × spatial-precoded block channel matrix.
    %
    % Despite the "afwdm" name (origin: paper Eq.(48) AFWDM derivation), this
    % function builds a GENERIC "AFDM-time DAFT × arbitrary spatial precoder
    % cfg.Us / cfg.Ur" block matrix. The same builder is shared by AFWDM,
    % SVD-precoded MIMO-AFDM (paper Eq.49-51), and DFT-precoded MIMO-AFDM
    % baselines — only cfg.Us / cfg.Ur differ across schemes. See cc-0518-01
    % for the legality argument.
    %
    % Plain-basis form (this code's convention, see docs/Code_Analysis.md §13):
    %
    %   H = Σ_p (U_r^H G_p U_s) ⊗ (A Θ_p A^H)
    %
    % Paper-alias form (paper §IV symbols, equivalent under cc-0323-01 双层命名):
    %
    %   H = Σ_p (Φ_r^* G_p Φ_s^T) ⊗ (A Θ_p A^H)
    %   where  Φ_r^* = conj(cfg.Ur),  Φ_s^T = cfg.Us.' = cfg.Phi_s_T_paper
    %
    % Note: paper symbol Φ_s^H ↔ cfg.Us.' (PURE transpose), NOT MATLAB Hermitian.
    % See archived Code_Analysis_v0.1.md §11 for the 2026-03-22 audit that
    % fixed BER floor 0.3 → 1e-4 via this convention correction.
    %
    % where:
    %   G_p   = Mr × Ms full-aperture physical channel for path p
    %   Θ_p   = N × N delay+Doppler+CPP matrix (DAFT domain)
    %   A     = N × N AFDM DAFT matrix (Lambda_c2 · F · Lambda_c1)
    %   U_s   = cfg.Us, Ms × ms plain-basis Tx precoder columns
    %   U_r   = cfg.Ur, Mr × mr plain-basis Rx combiner columns
    %
    % Operator chain (plain-basis, matches simulate_afwdm_snr line 90-96):
    %   Tx:  Xbar = A^H X U_s^T            → vec = (U_s ⊗ A^H) vec(X)
    %   Ch:  Ybar = Σ_p Θ_p Xbar G_p^T     → vec = Σ_p (G_p ⊗ Θ_p) vec(Xbar)
    %   Rx:  Y    = A Ybar conj(U_r)       → vec = (U_r^H ⊗ A) vec(Ybar)
    %   → combined: H = Σ_p (U_r^H G_p U_s) ⊗ (A Θ_p A^H)
    %
    % Paper cross-reference (main.pdf §IV):
    %   - paper Eq.(56) for SVD-MIMO baseline:
    %       H_MIMO = (W_r^H ⊗ A) H̄ (W_s ⊗ A^H)
    %       → identifies DIRECTLY with code S_p = U_r^H G_p U_s under
    %         W_r ↔ cfg.Ur, W_s ↔ cfg.Us (no conjugation gymnastics).
    %   - paper Eq.(48) for AFWDM:
    %       H = (Φ_r ⊗ A) H̄ (Φ_s^H ⊗ A^H)
    %       → equivalent after row/col-stacking reconciliation per §13 双层命名:
    %         Φ_r ↔ conj(cfg.Ur), Φ_s^H ↔ cfg.Us.' (pure transpose, see §11 audit).
    %   - paper Eq.(31) for per-path channel:
    %       G_p = Φ_r^* H_{a,p} Φ_s^T
    %       semi-unitarity Φ_r^H Φ_r = I_{m_r}, Φ_s^H Φ_s = I_{m_s} (page 1)
    %       reduces Eq.(48) inner kernel to S_p = H_{a,p} in beamspace,
    %       equivalent to code U_r^H G_p U_s when cfg.Us holds the disk basis.
    %
    % Inputs:
    %   G_eff   - {1 × Lch} cell of (Mr × Ms) full-aperture channel matrices
    %   tau_vec - [1 × Lch] integer delays
    %   nu_vec  - [1 × Lch] integer Dopplers
    %   cfg     - struct with fields: Nblk, c1, c2, ms, mr, Us, Ur
    %
    % Output:
    %   H       - (mr*N × ms*N) full block equivalent matrix

    N   = cfg.Nblk;
    ms  = cfg.ms;
    mr  = cfg.mr;
    Lch = numel(G_eff);

    % Build DAFT matrix once
    A = build_daft_matrix(cfg);

    % Spatial projection matrices (precompute once)
    % PhiR_H    = cfg.PhiR';          % mr × Mr  (conjugate transpose = Hermitian)
    % PhiS_plain = cfg.PhiS;           % Ms × ms  (no conjugate)
    UrH = cfg.Ur';    % mr x Mr
    Us  = cfg.Us;     % Ms x ms

    H = zeros(mr*N, ms*N);

    for p = 1:Lch
        tau = round(real(tau_vec(p)));
        nu  = resolve_doppler(nu_vec(p), cfg);

        Theta_p = build_theta_p(tau, nu, N, cfg.c1);

        % S_p = PhiR_H * G_eff{p} * PhiS_plain;   % (mr×Mr)(Mr×Ms)(Ms×ms) = mr × ms  [beamspace]
        S_p = UrH * G_eff{p} * Us;      
        D_p = A * Theta_p * A';                  % N × N  DAFT-domain path kernel

        H = H + kron(S_p, D_p);                  % (mr × ms) ⊗ (N × N)
    end
end
