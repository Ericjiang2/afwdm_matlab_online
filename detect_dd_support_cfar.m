function detection = detect_dd_support_cfar(modal_observations, candidate_pairs, opts)
%DETECT_DD_SUPPORT_CFAR Joint-energy DD support detection over selected modes.

    n_candidates = numel(modal_observations);
    n_modal_coeff = numel(modal_observations{1});

    switch lower(opts.correction)
        case 'bonferroni'
            pfa_cell = opts.pfa_total / n_candidates;
        case 'sidak'
            pfa_cell = 1 - (1 - opts.pfa_total)^(1 / n_candidates);
        otherwise
            error('detect_dd_support_cfar:unknownCorrection', ...
                'Unknown family-wise correction "%s".', opts.correction);
    end

    threshold = gammaincinv(1 - pfa_cell, n_modal_coeff, 'lower');
    statistic = zeros(n_candidates, 1);
    for q = 1:n_candidates
        statistic(q) = opts.pilot_energy / opts.noise_variance * ...
            norm(modal_observations{q}, 'fro')^2;
    end
    active_mask = statistic > threshold;

    detection = struct();
    detection.statistic = statistic;
    detection.threshold = threshold;
    detection.pfa_cell = pfa_cell;
    detection.active_mask = active_mask;
    detection.support_pairs = candidate_pairs(active_mask, :);
end
