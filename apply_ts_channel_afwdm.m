function Ybar = apply_ts_channel_afwdm(Xbar, G_eff, tau_vec, nu_vec, cfg)
    % APPLY_TS_CHANNEL_AFWDM  Apply the delay-Doppler channel in time-sample
    % domain for AFWDM (full physical aperture, with CPP correction).
    %
    % For each path ell:
    %   1. Circular delay shift Xbar by tau_ell
    %   2. Doppler modulation: exp(+j2pi*nu_ell*n/N)
    %   3. CPP phase correction on samples n = 0..tau_ell-1
    %   4. Spatial mixing: Ybar += X_corrected * G_eff{ell}.'
    %
    % Per-path vec relation:
    %   vec(Ybar_ell) = (G_eff{ell} \otimes Theta_ell) vec(Xbar)
    % where Theta_ell is the time-domain delay/Doppler/CPP operator.
    %
    % Inputs:
    %   Xbar    - (N x Ms) time-domain signal at full Tx aperture
    %   G_eff   - {1 x Lch} cell of (Mr x Ms) physical channel matrices
    %   tau_vec - [1 x Lch] integer delays
    %   nu_vec  - [1 x Lch] integer Dopplers
    %   cfg     - struct with fields: Nblk, c1
    %
    % Output:
    %   Ybar    - (N x Mr) received time-domain signal at full Rx aperture

    [N, Ms] = size(Xbar);
    Mr  = size(G_eff{1}, 1);
    Lch = length(G_eff);

    Ybar = zeros(N, Mr);
    n = (0:N-1).';

    for ell = 1:Lch
        tau = round(real(tau_vec(ell)));
        nu  = resolve_doppler(nu_vec(ell), cfg);

        % 1. Circular delay shift
        Xshift = circshift(Xbar, tau, 1);

        % 2. Doppler modulation
        dopp = exp(+1j * 2*pi * nu * n / N);
        X_dopp = Xshift .* (dopp * ones(1, Ms));

        % 3. CPP phase correction
        if tau > 0
            phi = compute_cpp_phase(tau, N, cfg.c1);
            X_dopp(1:tau, :) = X_dopp(1:tau, :) .* (phi(1:tau) * ones(1, Ms));
        end

        % 4. Spatial mixing
        Ybar = Ybar + X_dopp * (G_eff{ell}.');
    end
end
