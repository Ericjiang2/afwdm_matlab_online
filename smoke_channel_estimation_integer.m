function report = smoke_channel_estimation_integer()
%SMOKE_CHANNEL_ESTIMATION_INTEGER Run the deterministic end-to-end CE gates.

    cfg = struct('Nblk', 8, 'c1', 1/16, 'c2', 0);
    candidate_pairs = [0, 0; 1, 0; 2, 0];
    S_00 = [1+1i, 0.2; -0.1i, 0.9];
    S_20 = [0.3, 0.1i; 0.2, -0.4i];
    truth = build_modal_dd_truth( ...
        {S_00, S_20}, [0, 2], [0, 0], eye(2), eye(2), cfg);

    pilot_opts = struct( ...
        'pilot_bin', 0, ...
        'pilot_energy', 1, ...
        'include_data', false, ...
        'noise_variance', 0);
    pilot_only = simulate_embedded_pilot_training( ...
        truth, candidate_pairs, cfg, pilot_opts);
    full_grid = estimate_modal_channel_ce( ...
        pilot_only, candidate_pairs, cfg, struct('method', 'full_grid_ls'));
    full_grid_block = build_block_matrix_modal( ...
        full_grid.modal_by_candidate, candidate_pairs, cfg);

    block_error = norm(full_grid_block - truth.H_blk, 'fro')^2;
    block_power = max(norm(truth.H_blk, 'fro')^2, eps);
    noiseless_block_nmse = block_error / block_power;

    embedded_opts = pilot_opts;
    embedded_opts.include_data = true;
    embedded_opts.data_symbols = repmat( ...
        ((1+1i) / sqrt(2)) * ones(cfg.Nblk, 2), 1, 1, 2);
    embedded = simulate_embedded_pilot_training( ...
        truth, candidate_pairs, cfg, embedded_opts);
    rows = pilot_only.observation_rows;
    observation_error = norm( ...
        embedded.Y(rows, :, :) - pilot_only.Y(rows, :, :), 'fro')^2;
    observation_power = max(norm(pilot_only.Y(rows, :, :), 'fro')^2, eps);
    embedded_observation_gap = observation_error / observation_power;

    somp = estimate_modal_channel_somp( ...
        pilot_only, candidate_pairs, cfg, ...
        struct('pfa_total', 1e-3, 'correction', 'bonferroni', ...
               'residual_tolerance', 1e-12));
    true_mask = ismember(candidate_pairs, truth.support_pairs, 'rows');
    somp_exact_support = isequal(somp.active_mask, true_mask);

    bits = repmat([0; 0; 1; 1], 8, 1);
    detectors = struct( ...
        'names', {{'perfect', 'full_grid_ls'}}, ...
        'H', {{truth.H_blk, full_grid_block}});
    ber_result = simulate_paired_csi_ber( ...
        truth.H_blk, detectors, 4, 30, ...
        struct('bits', bits, 'noise', zeros(size(truth.H_blk, 1), 1), ...
               'solver', 'direct'));
    paired_ber_equal = isequal(ber_result.bits_est{1}, ber_result.bits_est{2});
    [cfar_calibrated, cfar_empirical, cfar_expected] = ...
        run_noise_only_cfar_smoke();

    report = struct();
    report.noiseless_block_nmse = noiseless_block_nmse;
    report.embedded_observation_gap = embedded_observation_gap;
    report.somp_exact_support = somp_exact_support;
    report.paired_ber_equal = paired_ber_equal;
    report.cfar_calibrated = cfar_calibrated;
    report.cfar_empirical = cfar_empirical;
    report.cfar_expected = cfar_expected;
    report.ber = ber_result.ber;
    report.all_passed = noiseless_block_nmse < 1e-20 && ...
        embedded_observation_gap < 1e-20 && somp_exact_support && ...
        paired_ber_equal && cfar_calibrated;
end

function [calibrated, empirical, expected] = run_noise_only_cfar_smoke()
    rng(20260711);
    n_trials = 2000;
    n_candidates = 3;
    d_r = 2;
    d_s = 2;
    pfa_total = 0.1;
    false_alarm_trials = 0;
    candidate_pairs = [(0:n_candidates-1).', zeros(n_candidates, 1)];

    for trial = 1:n_trials
        observations = cell(1, n_candidates);
        for q = 1:n_candidates
            observations{q} = (randn(d_r, d_s) + ...
                1i * randn(d_r, d_s)) / sqrt(2);
        end
        detection = detect_dd_support_cfar( ...
            observations, candidate_pairs, ...
            struct('noise_variance', 1, 'pilot_energy', 1, ...
                   'pfa_total', pfa_total, 'correction', 'bonferroni'));
        false_alarm_trials = false_alarm_trials + any(detection.active_mask);
    end

    empirical = false_alarm_trials / n_trials;
    expected = 1 - (1 - pfa_total / n_candidates)^n_candidates;
    standard_error = sqrt(expected * (1 - expected) / n_trials);
    calibrated = abs(empirical - expected) <= 4 * standard_error;
end
