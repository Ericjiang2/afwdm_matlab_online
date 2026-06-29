function C_avg = wideband_capacity_block(H_taps, tau_vec, nu_vec, cfg, snrLin, modulation_type)
    % WIDEBAND_CAPACITY_BLOCK  Ergodic capacity via full block matrix construction
    % with DFT/DAFT modulation included.
    %
    % This function constructs the complete equivalent block matrix that includes
    % both the channel effect AND the modulation transform (DFT for OFDM, DAFT for AFDM).
    % Then it computes capacity via water-filling on the eigenvalues of this full matrix.
    %
    % This is the physically correct way to compute capacity because:
    %   - OFDM uses DFT modulation (c1=c2=0)
    %   - AFDM uses DAFT modulation (c1>0)
    % The modulation affects the equivalent channel matrix and thus the capacity.
    %
    % Inputs:
    %   H_taps          - {1 × Lch} cell of (Nr × Nt) spatial channel matrices
    %   tau_vec         - [1 × Lch] integer delays
    %   nu_vec          - [1 × Lch] integer Dopplers
    %   cfg             - struct with fields: Nblk, c1, c2, etc.
    %   snrLin          - linear SNR (P_total / sigma^2)
    %   modulation_type - 'ofdm' or 'afdm' (determines whether to use DFT or DAFT)
    %
    % Output:
    %   C_avg           - average ergodic spectral efficiency per resource unit (bit/s/Hz)
    %
    % Algorithm:
    %   1. Build modulation matrix A (DFT for OFDM, DAFT for AFDM)
    %   2. Build full block matrix: H = sum_p (H_p ⊗ (A * Theta_p * A^H))
    %   3. Compute SVD eigenvalues: lambda_i = sv_i(H)^2
    %   4. Water-filling: allocate power across eigenvalues
    %   5. Compute capacity: C = (1/Nblk) * sum log2(1 + p_i * lambda_i / sigma^2)

    N   = cfg.Nblk;
    Lch = numel(H_taps);
    Nr  = size(H_taps{1}, 1);
    Nt  = size(H_taps{1}, 2);

    % Noise variance and total power
    sigma2 = 1 / snrLin;
    Ptot   = N;  % total transmit power (normalized)

    % Build modulation matrix based on type
    modulation_type = lower(strtrim(modulation_type));
    if strcmp(modulation_type, 'ofdm')
        % OFDM: use DFT (c1=c2=0)
        cfg_mod = cfg;
        cfg_mod.c1 = 0;
        cfg_mod.c2 = 0;
        A = build_daft_matrix(cfg_mod);  % with c1=c2=0, this becomes DFT
    elseif strcmp(modulation_type, 'afdm')
        % AFDM: use DAFT with configured c1
        A = build_daft_matrix(cfg);
    else
        error('Invalid modulation_type: %s. Use ''ofdm'' or ''afdm''.', modulation_type);
    end

    % Build full block matrix
    H = zeros(Nr*N, Nt*N);

    for p = 1:Lch
        tau = round(real(tau_vec(p)));
        nu  = resolve_doppler(nu_vec(p), cfg);

        % Time-domain block matrix for path p
        if strcmp(modulation_type, 'ofdm')
            Theta_p = build_theta_p(tau, nu, N, 0);  % c1=0 for OFDM
        else
            Theta_p = build_theta_p(tau, nu, N, cfg.c1);  % c1>0 for AFDM
        end

        % Transform to modulation domain: D_p = A * Theta_p * A^H
        D_p = A * Theta_p * A';

        % Kronecker product: (spatial) ⊗ (modulation-domain kernel)
        H = H + kron(H_taps{p}, D_p);
    end

    % Compute singular values and eigenvalues
    s = svd(H);
    lambda = s.^2;
    lambda = lambda(lambda > 1e-14);  % discard numerical zeros

    if isempty(lambda)
        C_avg = 0;
        return;
    end

    % Sort eigenvalues descending
    lambda_sorted  = sort(lambda, 'descend');
    inv_snr_lambda = sigma2 ./ lambda_sorted;

    % Water-filling: find global water level mu
    cumsum_inv = cumsum(inv_snr_lambda);
    r = length(lambda_sorted);

    mu = 0;
    k_active = 0;
    for k = r:-1:1
        mu_try = (Ptot + cumsum_inv(k)) / k;
        if mu_try > inv_snr_lambda(k)
            mu = mu_try;
            k_active = k;
            break;
        end
    end

    if k_active == 0
        C_avg = 0;
        return;
    end

    % Compute capacity
    p_active   = mu - inv_snr_lambda(1:k_active);
    snr_active = p_active .* lambda_sorted(1:k_active) / sigma2;
    C_total    = sum(log2(1 + snr_active));

    C_avg = max(C_total, 0) / N;
end
