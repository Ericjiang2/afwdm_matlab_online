function H_phys_hat = inject_csi_error(H_phys, val, snr_lin, Mr, Ms, Lch, mode)
% INJECT_CSI_ERROR  Add channel estimation error per pilot-based estimation model.
%
% Two modes:
%   mode = 'snr_coupled' (default, legacy)
%     Standard MIMO CSI error model tied to working SNR:
%       H_hat = H_true + n_e,  n_e ~ CN(0, sigma^2_e * I)
%       sigma^2_e per element = val / (snr_lin * Lch)   (val = kappa pilot factor)
%     Under 'mrms' channel norm: sum_ell ||H_phys{ell}||^2_F = M_r*M_s
%     -> per-element sigma^2_H = 1/Lch, so relative MSE = val/snr_lin
%
%   mode = 'fixed_var' (cc-0518-04 NEW)
%     Decoupled from SNR -- directly set per-element error variance:
%       sigma^2_e per element = val   (val = absolute variance, e.g. 0.05, 0.1, 0.3)
%     Use when sweeping CSI quality independently of SNR (Eric 2026-05-18
%     "e 的方差你看着调, 0.05/0.1/0.几").
%
% Inputs:
%   H_phys   {1xLch} cell of M_r x M_s true physical channel taps
%   val      kappa (snr_coupled mode) or sigma^2_e per element (fixed_var mode);
%            val <= 0 returns perfect CSI shortcut in either mode
%   snr_lin  data SNR (linear); only used in snr_coupled mode
%   Mr, Ms, Lch  array dims
%   mode     'snr_coupled' (default) | 'fixed_var'
%
% Output:
%   H_phys_hat {1xLch} cell, each = H_phys{ell} + n_e per Eq above
%
% cc-0507-18 (snr_coupled), cc-0518-04 (fixed_var mode added)

    if nargin < 7 || isempty(mode); mode = 'snr_coupled'; end

    if val <= 0
        H_phys_hat = H_phys;   % perfect CSI shortcut
        return;
    end

    switch lower(mode)
        case 'snr_coupled'
            sigma_e2_per_elem = val / (snr_lin * Lch);
        case 'fixed_var'
            sigma_e2_per_elem = val;
        otherwise
            error('inject_csi_error: unknown mode "%s" (use snr_coupled | fixed_var).', mode);
    end

    sigma_e = sqrt(sigma_e2_per_elem / 2);

    H_phys_hat = cell(1, Lch);
    for ell = 1:Lch
        n_e = sigma_e * (randn(Mr, Ms) + 1j*randn(Mr, Ms));
        H_phys_hat{ell} = H_phys{ell} + n_e;
    end
end
