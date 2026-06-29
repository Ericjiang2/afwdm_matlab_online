function H = beamspace_apd_channel_2d_perpath(Mr, Ms, Sigma2, Dr, Ds, seed, ...
                                                Ur_plain, Us_plain, ...
                                                tilt_s, tilt_r)
%BEAMSPACE_APD_CHANNEL_2D_PERPATH  Per-path angle variant (paper Eq. (26)).
%
%   Twin of beamspace_apd_channel_2d.m but accepts per-path angular
%   modulation vectors (tilt_s, tilt_r) applied in beamspace BEFORE the
%   plain-Fourier basis transforms Ur_plain, Us_plain. The modulation
%   shifts the apparent angular center of the Fourier-random field
%   realization on a per-path basis, satisfying paper Eq. (26) where each
%   of the P channel paths has its own dominant direction
%   (theta_s_p, phi_s_p, theta_r_p, phi_r_p).
%
%   Caller builds tilt_s (Ms x 1) and tilt_r (Mr x 1) from per-path angles
%   sampled in generate_phys_dd_paths.m (cc-0518-03). Default behaviour
%   (tilt_s = ones(Ms,1), tilt_r = ones(Mr,1)) reproduces the original
%   beamspace_apd_channel_2d output bit-for-bit.
%
%   Inputs:
%       Mr, Ms        scalar array sizes
%       Sigma2        Mr x Ms per-path PAS variance mass sigma_p^2
%       Dr, Ds        Mr x 1, Ms x 1 z-phase vectors (paper Eq. (31))
%       seed          path-specific RNG seed
%       Ur_plain      Mr x Mr plain Fourier basis (Rx)
%       Us_plain      Ms x Ms plain Fourier basis (Tx)
%       tilt_s        Ms x 1 per-path Tx beamspace modulation
%       tilt_r        Mr x 1 per-path Rx beamspace modulation
%
%   Output:
%       H             Mr x Ms physical channel realization for this path
%
%   cc-0518-02
%   See also: beamspace_apd_channel_2d, generate_phys_dd_paths

    rng(seed);

    % 1. small-scale white noise (Eq. (21))
    Hw = (randn(Mr, Ms) + 1j*randn(Mr, Ms)) / sqrt(2);

    % 2. apply paper Eq. (32): Sigma_p collects sqrt(Ms*Mr)*sigma_p.
    Hw_weighted = sqrt(Mr * Ms) * (Hw .* sqrt(Sigma2));

    % 3. apply z-phase (paper Eq. (31): Gamma_r, Gamma_s)
    Hw_weighted = (Dr .* Hw_weighted) .* (Ds.');

    % 4. per-path angular modulation in beamspace (NEW, paper Eq. (26))
    %    tilt_r (Mr x 1) and tilt_s (Ms x 1) shift the apparent angular
    %    center per path while preserving the Fourier-random structure.
    Hw_weighted = (tilt_r .* Hw_weighted) .* (tilt_s.');

    % 5. back to spatial domain
    H = Ur_plain * Hw_weighted * Us_plain';
end
