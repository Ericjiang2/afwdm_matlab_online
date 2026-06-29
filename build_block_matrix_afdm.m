function H = build_block_matrix_afdm(H_eff, tau_vec, nu_vec, cfg)
    % BUILD_BLOCK_MATRIX_AFDM  Construct the full AFDM block equivalent matrix.
    %
    % Using the Kronecker mixed-product property:
    %
    %   H_AFDM = (I_mr ⊗ A) [Σ_p H_eff_p ⊗ Θ_p] (I_ms ⊗ A^H)
    %          = Σ_p  H_eff_p ⊗ (A Θ_p A^H)
    %
    % where:
    %   H_eff_p     = mr × ms effective spatial channel for path p (SDM baseline)
    %   Θ_p         = N × N time-domain block matrix (delay + Doppler + CPP)
    %   A           = N × N DAFT matrix
    %   A Θ_p A^H   = N × N DAFT-domain path kernel
    %
    % Result: H is (mr*N × ms*N), maps vec(X) to vec(Y) in DAFT domain.
    %
    % Inputs:
    %   H_eff   - {1 × Lch} cell of (mr × ms) effective spatial matrices
    %   tau_vec - [1 × Lch] integer delays
    %   nu_vec  - [1 × Lch] integer Dopplers
    %   cfg     - struct with fields: Nblk, c1, c2
    %
    % Output:
    %   H       - (mr*N × ms*N) full block equivalent matrix

    N   = cfg.Nblk;
    ms  = size(H_eff{1}, 2);
    mr  = size(H_eff{1}, 1);
    Lch = numel(H_eff);

    % Build DAFT matrix once
    A = build_daft_matrix(cfg);

    H = zeros(mr*N, ms*N);

    for p = 1:Lch
        tau = round(real(tau_vec(p)));
        nu  = resolve_doppler(nu_vec(p), cfg);

        Theta_p = build_theta_p(tau, nu, N, cfg.c1);

        D_p = A * Theta_p * A';             % N × N  DAFT-domain path kernel
        H   = H + kron(H_eff{p}, D_p);      % (mr × ms) ⊗ (N × N)
    end
end
