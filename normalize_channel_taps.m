function Hcell = normalize_channel_taps(Hcell, target_power)
    % NORMALIZE_CHANNEL_TAPS  Scale all tap matrices jointly so that
    %   sum_{ell} ||Hcell{ell}||_F^2 = target_power.
    %
    % Inputs:
    %   Hcell        - 1 x Lch cell array of complex matrices
    %   target_power - desired total Frobenius-norm-squared across all taps
    %
    % Output:
    %   Hcell        - normalized cell array (same structure)

    L = numel(Hcell);
    tot = 0;
    for ell = 1:L
        tot = tot + norm(Hcell{ell}, 'fro')^2;
    end
    if tot > 0
        s = sqrt(target_power / tot);
        for ell = 1:L
            Hcell{ell} = s * Hcell{ell};
        end
    end
end
