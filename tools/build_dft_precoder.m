function [W_s, W_r] = build_dft_precoder(M_s, M_r, m_s, m_r)
% BUILD_DFT_PRECODER  Channel-independent 1D-DFT precoder/combiner subset.
%
% Implements the supervisor's "DFT-precoded MIMO" baseline (2026-05-07
% 07:01 第七条 + Eric refinement): replace W_s, W_r in paper Eq. (51) with
% same-dimensional 1D-DFT submatrices.
%
% Unlike AFWDM's Phi_s (2D-IDFT subset = kron(F_My, F_Mx) with PAS
% truncation, geometry-aware) and SVD's W_s (V from G's SVD, channel-aware),
% the 1D-DFT here is **antenna-index-order DFT**: indexes the M_s antennas
% in linear order and applies 1×M_s DFT, *without* the planar (Mx, My)
% factorization. So this baseline is intentionally suboptimal on planar
% arrays (paper Eq. (1) shows AFWDM is 2D-IDFT, which collapses to 1D-DFT
% only when the array degenerates to a line; on a square array the two
% bases are maximally distinct).
%
% Input:
%   M_s, M_r   full Tx/Rx antenna count
%   m_s, m_r   precoder/combiner column counts (≤ M_s, M_r resp.)
%
% Output:
%   W_s        M_s × m_s, first m_s columns of M_s × M_s 1D-DFT (unitary normalized)
%   W_r        M_r × m_r, similarly
%
% Both W_s, W_r are semi-unitary: W_s' * W_s = I_{m_s}.

    assert(m_s >= 1 && m_s <= M_s, 'build_dft_precoder: m_s=%d out of [1,%d].', m_s, M_s);
    assert(m_r >= 1 && m_r <= M_r, 'build_dft_precoder: m_r=%d out of [1,%d].', m_r, M_r);

    F_s = dftmtx(M_s) / sqrt(M_s);    % M_s × M_s unitary 1D-DFT
    F_r = dftmtx(M_r) / sqrt(M_r);

    W_s = F_s(:, 1:m_s);
    W_r = F_r(:, 1:m_r);
end
