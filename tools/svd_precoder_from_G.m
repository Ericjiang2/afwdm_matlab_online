function [W_s, W_r, sv] = svd_precoder_from_G(G, ms, mr)
% SVD_PRECODER_FROM_G  Per-frame SVD precoder/combiner for SVD-precoded MIMO.
%
% Implements paper Eq. 49-51 for SVD-precoded MIMO-AFDM/OFDM benchmark:
%   G = U * Sigma * V^H
%   W_s = V(:, 1:ms),  W_r = U(:, 1:mr)
%
% Input:
%   G   Mr × Ms spatial MIMO channel matrix (paper Eq. 31, sampled per frame)
%   ms  number of transmit streams (1 ≤ ms ≤ min(Mr,Ms))
%   mr  number of receive streams  (1 ≤ mr ≤ min(Mr,Ms))
%
% Output:
%   W_s  Ms × ms transmit precoder (semi-unitary, W_s' * W_s = I_ms)
%   W_r  Mr × mr receive  combiner (semi-unitary, W_r' * W_r = I_mr)
%   sv   singular values vector (length min(Mr,Ms)) — for diagnostics
%
% Numerical guard: warns if rank-effective < ms, which would make the
% LMMSE chain ill-conditioned downstream.

    [Mr, Ms] = size(G);
    k = min(Mr, Ms);
    assert(ms >= 1 && ms <= k, 'svd_precoder_from_G: ms=%d out of [1,%d].', ms, k);
    assert(mr >= 1 && mr <= k, 'svd_precoder_from_G: mr=%d out of [1,%d].', mr, k);

    [U, S, V] = svd(G, 'econ');
    sv = diag(S);

    W_s = V(:, 1:ms);
    W_r = U(:, 1:mr);

    % Numerical-stability guard: PSV ratio between ms-th and 1st singular value
    if sv(1) > 0 && sv(min(ms,length(sv))) / sv(1) < 1e-8
        warning('svd_precoder_from_G:RankDeficient', ...
            'sigma_%d/sigma_1 = %.2e (rank-effective < ms); LMMSE may be ill-conditioned.', ...
            ms, sv(min(ms,length(sv)))/sv(1));
    end
end
