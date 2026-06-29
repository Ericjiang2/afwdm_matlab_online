function G = build_G_paper_eq31(H_phys, mode)
% BUILD_G_PAPER_EQ31  Build paper Eq. (31) physical spatial channel G for SVD baseline.
%
% Paper Eq. (31):
%   G = sum_p Phi_r^* * exp(j*Gamma_r) * H_{a,p} * exp(-j*Gamma_s) * Phi_s^T
% Each H_phys{ell} from beamspace_apd_channel_2d.m is already this form
% (one realization summed over EM paths internally via random Hw weighted
% by Sigma2 + z-phase Dr/Ds + Fourier basis Ur_plain/Us_plain).
%
% Input:
%   H_phys  {1×Lch} cell of M_r × M_s physical channel taps (full size
%           BEFORE antenna selection — distinct from H_eff_ber)
%   mode    'sum_taps' (default) — sum across delay taps for spatial coherence
%           'first_tap' — narrowband / LoS-dominant approximation
%
% Output:
%   G       M_r × M_s paper-faithful single spatial channel for SVD design.
%
% Note: this REPLACES the buggy `H_agg_sdm = sum H_eff_ber{ell}` path
% (lines 1039-1043 of AFDM_AFWDM_Compare.m) which sums in the SDM-selected
% subspace (47×47), not the full physical domain (64×64). Operating in the
% full domain is required for V(:,1:m_s) to be a true projection (M_s × m_s
% with m_s < M_s); else V is unitary square and SVD precoding is a no-op
% under LMMSE detection.

    if nargin < 2 || isempty(mode); mode = 'sum_taps'; end

    Lch = length(H_phys);
    assert(Lch >= 1, 'build_G_paper_eq31: empty H_phys cell.');

    switch lower(mode)
        case 'sum_taps'
            G = zeros(size(H_phys{1}));
            for ell = 1:Lch
                G = G + H_phys{ell};
            end
        case 'first_tap'
            G = H_phys{1};
        otherwise
            error('build_G_paper_eq31: unknown mode "%s" (use sum_taps | first_tap).', mode);
    end
end
