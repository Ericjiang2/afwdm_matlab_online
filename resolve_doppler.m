function nu = resolve_doppler(nu_val, cfg)
%RESOLVE_DOPPLER  Convert raw Doppler value(s) to integer or fractional per cfg switch.
%
%   When cfg.use_fractional_doppler is true, returns fractional Doppler
%   (paper main.pdf eq 33: αp + kᵥ, kᵥ ∈ [0, βmax]).
%   Otherwise rounds to nearest integer (legacy behavior, same as kᵥ=0 case).
%
%   Centralizing this conversion in one helper prevents the int-vs-frac
%   coverage gap from causing hard-to-debug mismatches.
%
%   Inputs:
%     nu_val - scalar or array Doppler value(s); may be complex (real part used)
%     cfg    - config struct with optional field use_fractional_doppler (default false)
%   Output:
%     nu     - resolved Doppler (same shape as nu_val)

    if isfield(cfg,'use_fractional_doppler') && cfg.use_fractional_doppler
        nu = real(nu_val);
    else
        nu = round(real(nu_val));
    end
end
