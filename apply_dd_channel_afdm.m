function R = apply_dd_channel_afdm(C, H_eff, tau_vec, nu_vec, cfg)
    % APPLY_DD_CHANNEL_AFDM  Apply the delay-Doppler channel in time-sample
    % domain for AFDM (with CPP correction on the first tau samples).
    %
    % For each path ell:
    %   1. Circular delay shift by tau_ell
    %   2. Doppler modulation: exp(+j2pi*nu_ell*n/N)
    %   3. CPP phase correction on samples n = 0..tau_ell-1
    %   4. Spatial mixing: R += C_corrected * H_eff{ell}.'
    %
    % Inputs:
    %   C       - (N x Ptx) time-domain Tx signal
    %   H_eff   - {1 x Lch} cell of (Prx x Ptx) spatial matrices
    %   tau_vec - [1 x Lch] integer delays
    %   nu_vec  - [1 x Lch] integer Dopplers
    %   cfg     - struct with fields: Nblk, c1
    %
    % Output:
    %   R       - (N x Prx) received time-domain signal

    [N, Ptx] = size(C);
    Prx = size(H_eff{1}, 1);
    Lch = length(H_eff);

    R = zeros(N, Prx);
    n = (0:N-1).';

    for ell = 1:Lch
        tau = round(real(tau_vec(ell)));
        nu  = resolve_doppler(nu_vec(ell), cfg);

        % 1. Circular delay shift
        C_shift = circshift(C, tau, 1);

        % 2. Doppler modulation
        dopp = exp(+1j * 2*pi * nu * n / N);
        C_dopp = C_shift .* dopp;

        % 3. CPP phase correction (Eq.(40): applies to n < tau)
        if tau > 0
            phi = compute_cpp_phase(tau, N, cfg.c1);
            C_dopp(1:tau, :) = C_dopp(1:tau, :) .* phi(1:tau);
        end

        % 4. Spatial mixing
        R = R + C_dopp * (H_eff{ell}.');
    end
end
