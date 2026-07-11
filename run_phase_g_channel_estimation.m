function result = run_phase_g_channel_estimation(opts)
%RUN_PHASE_G_CHANNEL_ESTIMATION Integer-DD pilot CE for AFWDM and MIMO-AFDM.
%
% The runner is independent of the existing Phase-E workflow. It reuses only
% the read-only scenario-preparation seam and the established channel helpers.

    scenario_results = cell(1, numel(opts.scenarios));
    for i_scenario = 1:numel(opts.scenarios)
        scenario = prepare_project_scenario(opts.scenarios{i_scenario});
        result_one = evaluate_scenario(scenario, opts);
        if isfield(opts, 'include_ber') && opts.include_ber
            result_one.ber = evaluate_scenario_ber(scenario, opts);
        end
        scenario_results{i_scenario} = result_one;
    end

    result = struct();
    result.created_at = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    result.options = opts;
    result.scenarios = [scenario_results{:}];

    if opts.save_results
        output_dir = fileparts(opts.output_file);
        if ~isempty(output_dir) && ~isfolder(output_dir)
            mkdir(output_dir);
        end
        save(opts.output_file, 'result', '-v7.3');
    end
end

function scenario = prepare_project_scenario(label)
    batch_mode = true; %#ok<NASGU>
    simulation_preset = 'standard_mimo_v5'; %#ok<NASGU>
    pas_model = label; %#ok<NASGU>
    do_multi_pas_compare = false; %#ok<NASGU>
    do_iso_oneshot_debug = false; %#ok<NASGU>
    do_diagnostic_checks = false; %#ok<NASGU>
    do_cap_p_sweep = false; %#ok<NASGU>
    prepare_scenario_only = true; %#ok<NASGU>
    channel_norm_mode = 'mrms'; %#ok<NASGU>

    if strcmpi(label, 'vmf')
        pas_config = '2cluster'; %#ok<NASGU>
        cv = 0.30;
        vmf_mean_theta_deg_override = [30, 10]; %#ok<NASGU>
        vmf_mean_phi_deg_override = [15, 180]; %#ok<NASGU>
        vmf_circular_var_override = cv * ones(1, 2); %#ok<NASGU>
    end

    if exist('Sigma2_p', 'var')
        clear Sigma2_p;
    end
    run('AFDM_AFWDM_Compare.m');
    runtime = scenario_runs{1}; %#ok<USENS>
    cfg_base = runtime.cfg;

    if exist('Sigma2_p', 'var') && ~isempty(Sigma2_p)
        sigma_taps = Sigma2_p;
    else
        sigma_taps = repmat( ...
            {runtime.Sigma2 / cfg_base.Lch}, 1, cfg_base.Lch);
    end
    cfg_base.Lch = numel(sigma_taps);

    scenario = struct();
    scenario.label = label;
    scenario.runtime = runtime;
    scenario.cfg = cfg_base;
    scenario.sigma_taps = sigma_taps;
end

function out = evaluate_scenario(scenario, opts)
    cfg = scenario.cfg;
    [schemes, d, candidate_pairs] = build_scheme_set(scenario, opts);

    method_names = {'full_grid_lmmse', 'threshold_ls', ...
        'threshold_lmmse', 'somp_ls', 'oracle_support_lmmse'};
    n_schemes = numel(schemes.names);
    n_methods = numel(method_names);
    n_pilot_snr = numel(opts.pilot_snr_db);
    nmse_modal = nan(n_schemes, n_methods, n_pilot_snr, opts.num_frames);
    ce_time_s = nan(size(nmse_modal));
    support_size = nan(n_schemes, n_methods, n_pilot_snr, opts.num_frames);
    support_precision = nan(size(support_size));
    support_recall = nan(size(support_size));
    support_exact = false(size(support_size));
    effective_support_size = nan(1, opts.num_frames);
    oracle_support_exact = false(n_schemes, opts.num_frames);

    for frm = 1:opts.num_frames
        [tau_vec, nu_vec, H_phys, seed_base] = ...
            generate_frame_realization(scenario, opts, frm);
        effective_support_size(frm) = size(unique( ...
            [tau_vec(:), nu_vec(:)], 'rows'), 1);

        for i_scheme = 1:n_schemes
            truth = build_modal_dd_truth( ...
                H_phys, tau_vec, nu_vec, schemes.Us{i_scheme}, ...
                schemes.Ur{i_scheme}, cfg, struct('build_block', false));
            truth_on_grid = modal_truth_on_grid(truth, candidate_pairs, d, d);
            oracle_mask = ismember(candidate_pairs, truth.support_pairs, 'rows');
            oracle_support_exact(i_scheme, frm) = ...
                isequal(sortrows(candidate_pairs(oracle_mask, :)), ...
                        sortrows(truth.support_pairs));

            for i_snr = 1:n_pilot_snr
                noise_variance = 10^(-opts.data_snr_db / 10);
                pilot_energy = noise_variance * ...
                    10^(opts.pilot_snr_db(i_snr) / 10);
                rng(seed_base * 100 + i_snr * 7919);
                data_symbols = random_qpsk(cfg.Nblk, d, d);
                training = simulate_embedded_pilot_training( ...
                    truth, candidate_pairs, cfg, ...
                    struct('pilot_bin', 0, 'pilot_energy', pilot_energy, ...
                           'include_data', true, ...
                           'data_symbols', data_symbols, ...
                           'noise_variance', noise_variance));

                estimates = cell(1, n_methods);
                tic_ce = tic;
                raw = estimate_modal_channel_ce( ...
                    training, candidate_pairs, cfg, ...
                    struct('method', 'full_grid_ls'));
                raw_time = toc(tic_ce);

                cached_opts = struct();
                cached_opts.raw_modal_observations = ...
                    raw.raw_modal_observations;
                spatial_variance = schemes.spatial_variance{i_scheme};

                tic_ce = tic;
                estimates{1} = estimate_modal_channel_ce( ...
                    training, candidate_pairs, cfg, ce_method_options( ...
                    'full_grid_lmmse', cached_opts, spatial_variance, opts));
                ce_time_s(i_scheme, 1, i_snr, frm) = raw_time + toc(tic_ce);

                tic_ce = tic;
                estimates{2} = estimate_modal_channel_ce( ...
                    training, candidate_pairs, cfg, ce_method_options( ...
                    'threshold_ls', cached_opts, spatial_variance, opts));
                ce_time_s(i_scheme, 2, i_snr, frm) = raw_time + toc(tic_ce);

                tic_ce = tic;
                estimates{3} = estimate_modal_channel_ce( ...
                    training, candidate_pairs, cfg, ce_method_options( ...
                    'threshold_lmmse', cached_opts, spatial_variance, opts));
                ce_time_s(i_scheme, 3, i_snr, frm) = raw_time + toc(tic_ce);

                tic_ce = tic;
                estimates{4} = estimate_modal_channel_somp( ...
                    training, candidate_pairs, cfg, somp_options(opts));
                ce_time_s(i_scheme, 4, i_snr, frm) = toc(tic_ce);

                tic_ce = tic;
                oracle_opts = ce_method_options( ...
                    'oracle_support_lmmse', cached_opts, spatial_variance, opts);
                oracle_opts.oracle_mask = oracle_mask;
                estimates{5} = estimate_modal_channel_ce( ...
                    training, candidate_pairs, cfg, oracle_opts);
                ce_time_s(i_scheme, 5, i_snr, frm) = raw_time + toc(tic_ce);

                for i_method = 1:n_methods
                    estimated_mask = estimates{i_method}.active_mask;
                    nmse_modal(i_scheme, i_method, i_snr, frm) = ...
                        modal_nmse(estimates{i_method}.modal_by_candidate, ...
                                   truth_on_grid);
                    support_size(i_scheme, i_method, i_snr, frm) = ...
                        nnz(estimated_mask);
                    true_positive = nnz(estimated_mask & oracle_mask);
                    support_precision(i_scheme, i_method, i_snr, frm) = ...
                        true_positive / max(nnz(estimated_mask), 1);
                    support_recall(i_scheme, i_method, i_snr, frm) = ...
                        true_positive / max(nnz(oracle_mask), 1);
                    support_exact(i_scheme, i_method, i_snr, frm) = ...
                        isequal(estimated_mask, oracle_mask);
                end
            end
        end
    end

    out = struct();
    out.label = scenario.label;
    out.scheme_names = schemes.names;
    out.method_names = method_names;
    out.candidate_pairs = candidate_pairs;
    out.pilot_snr_db = opts.pilot_snr_db;
    out.data_snr_db = opts.data_snr_db;
    out.selected_modes = d;
    out.nmse_modal = nmse_modal;
    out.ce_time_s = ce_time_s;
    out.support_size = support_size;
    out.support_precision = support_precision;
    out.support_recall = support_recall;
    out.support_exact = support_exact;
    out.retained_modal_coefficients = support_size * d^2;
    out.effective_support_size = effective_support_size;
    out.oracle_support_exact = oracle_support_exact;
end

function H_phys = generate_physical_taps(scenario, seed_base)
    cfg = scenario.cfg;
    runtime = scenario.runtime;
    H_phys = cell(1, cfg.Lch);
    for ell = 1:cfg.Lch
        H_phys{ell} = beamspace_apd_channel_2d_perpath( ...
            cfg.Mr, cfg.Ms, scenario.sigma_taps{ell}, ...
            runtime.Dr, runtime.Ds, seed_base + ell, ...
            cfg.Ur_full, cfg.Us_full, ones(cfg.Ms, 1), ones(cfg.Mr, 1));
    end
    H_phys = normalize_channel_taps(H_phys, cfg.Mr * cfg.Ms);
end

function pairs = build_candidate_pairs(lmax, kmax)
    [delay_grid, doppler_grid] = ndgrid(0:lmax, -kmax:kmax);
    pairs = [delay_grid(:), doppler_grid(:)];
end

function values = modal_truth_on_grid(truth, candidate_pairs, d_r, d_s)
    values = cell(1, size(candidate_pairs, 1));
    for q = 1:numel(values)
        values{q} = zeros(d_r, d_s);
    end
    [present, location] = ismember(truth.support_pairs, candidate_pairs, 'rows');
    if ~all(present)
        error('run_phase_g_channel_estimation:trueSupportOutsideGrid', ...
            'A true DD support point is outside the configured candidate grid.');
    end
    for q = 1:numel(location)
        values{location(q)} = truth.modal_by_support{q};
    end
end

function value = modal_nmse(estimate, truth)
    numerator = 0;
    denominator = 0;
    for q = 1:numel(truth)
        numerator = numerator + norm(estimate{q} - truth{q}, 'fro')^2;
        denominator = denominator + norm(truth{q}, 'fro')^2;
    end
    value = numerator / max(denominator, eps);
end

function [schemes, d, candidate_pairs] = build_scheme_set(scenario, opts)
    cfg = scenario.cfg;
    runtime = scenario.runtime;
    d = min([cfg.ms, cfg.mr, opts.max_selected_modes]);
    candidate_pairs = build_candidate_pairs(cfg.lmax, cfg.kmax);

    schemes = struct();
    schemes.names = {'AFWDM', 'MIMO_AFDM'};
    schemes.Us = {cfg.Us(:, 1:d), runtime.Wt_sel(:, 1:d)};
    schemes.Ur = {cfg.Ur(:, 1:d), runtime.Wr_sel(:, 1:d)};

    aggregate_sigma = zeros(cfg.Mr, cfg.Ms);
    for ell = 1:numel(scenario.sigma_taps)
        aggregate_sigma = aggregate_sigma + scenario.sigma_taps{ell};
    end
    afwdm_variance = cfg.Mr * cfg.Ms / cfg.Lch * ...
        aggregate_sigma(runtime.idx_r(1:d), runtime.idx_s(1:d));
    mimo_afdm_variance = ones(d, d) / cfg.Lch;
    schemes.spatial_variance = {afwdm_variance, mimo_afdm_variance};
end

function ber = evaluate_scenario_ber(scenario, opts)
%EVALUATE_SCENARIO_BER Stage-C paired BER over operator-based PCG detection.
%
% All CSI branches share the same channel realization, data bits, and data
% noise. Detectors are matrix-free modal block operators, so no branch ever
% materializes the N*d_r x N*d_s dense matrix.

    cfg = scenario.cfg;
    [schemes, d, candidate_pairs] = build_scheme_set(scenario, opts);

    data_snr_db = get_option(opts, 'ber_data_snr_db', 0:5:25);
    linked_offset_db = get_option(opts, 'ber_linked_pilot_offset_db', 10);
    fixed_pilot_snr_db = get_option(opts, 'ber_fixed_pilot_snr_db', 25);
    pcg_tol = get_option(opts, 'ber_pcg_tol', 1e-8);
    pcg_max_iter = get_option(opts, 'ber_pcg_max_iter', 400);
    ber_solver = get_option(opts, 'ber_solver', 'pcg');
    use_operator = strcmpi(ber_solver, 'pcg');

    pilot_modes = {'linked'};
    if ~isempty(fixed_pilot_snr_db)
        pilot_modes{end + 1} = 'fixed_pilot';
    end

    detector_names = {'perfect_csi', 'full_grid_lmmse', ...
        'threshold_lmmse', 'somp_ls'};
    n_schemes = numel(schemes.names);
    n_detectors = numel(detector_names);
    n_modes = numel(pilot_modes);
    n_snr = numel(data_snr_db);
    bits_per_frame = 2 * cfg.Nblk * d;

    error_bits = nan(n_schemes, n_detectors, n_modes, n_snr, opts.num_frames);
    solver_flag = nan(size(error_bits));
    solver_iter = nan(size(error_bits));
    detect_time_s = nan(size(error_bits));
    pilot_snr_used_db = nan(n_modes, n_snr);

    for frm = 1:opts.num_frames
        [tau_vec, nu_vec, H_phys, seed_base] = ...
            generate_frame_realization(scenario, opts, frm);

        for i_scheme = 1:n_schemes
            truth = build_modal_dd_truth( ...
                H_phys, tau_vec, nu_vec, schemes.Us{i_scheme}, ...
                schemes.Ur{i_scheme}, cfg, struct('build_block', false));
            truth_on_grid = modal_truth_on_grid(truth, candidate_pairs, d, d);
            H_true = detector_channel( ...
                truth_on_grid, candidate_pairs, cfg, use_operator);

            for i_mode = 1:n_modes
                for i_snr = 1:n_snr
                    data_snr = data_snr_db(i_snr);
                    noise_variance = 10^(-data_snr / 10);
                    if strcmp(pilot_modes{i_mode}, 'linked')
                        pilot_snr = data_snr + linked_offset_db;
                    else
                        pilot_snr = fixed_pilot_snr_db;
                    end
                    pilot_snr_used_db(i_mode, i_snr) = pilot_snr;
                    pilot_energy = noise_variance * 10^(pilot_snr / 10);

                    rng(seed_base * 100 + i_snr * 7919 + ...
                        500000 * i_mode + 97 * i_scheme);
                    training = simulate_embedded_pilot_training( ...
                        truth, candidate_pairs, cfg, ...
                        struct('pilot_bin', 0, ...
                               'pilot_energy', pilot_energy, ...
                               'include_data', true, ...
                               'data_symbols', random_qpsk(cfg.Nblk, d, d), ...
                               'noise_variance', noise_variance));

                    raw = estimate_modal_channel_ce( ...
                        training, candidate_pairs, cfg, ...
                        struct('method', 'full_grid_ls'));
                    cached_opts = struct();
                    cached_opts.raw_modal_observations = ...
                        raw.raw_modal_observations;
                    spatial_variance = schemes.spatial_variance{i_scheme};

                    est_full = estimate_modal_channel_ce( ...
                        training, candidate_pairs, cfg, ce_method_options( ...
                        'full_grid_lmmse', cached_opts, spatial_variance, opts));
                    est_threshold = estimate_modal_channel_ce( ...
                        training, candidate_pairs, cfg, ce_method_options( ...
                        'threshold_lmmse', cached_opts, spatial_variance, opts));
                    est_somp = estimate_modal_channel_somp( ...
                        training, candidate_pairs, cfg, somp_options(opts));

                    detectors = struct();
                    detectors.names = detector_names;
                    detectors.H = {H_true, ...
                        detector_channel(est_full.modal_by_candidate, ...
                            candidate_pairs, cfg, use_operator), ...
                        detector_channel(est_threshold.modal_by_candidate, ...
                            candidate_pairs, cfg, use_operator), ...
                        detector_channel(est_somp.modal_by_candidate, ...
                            candidate_pairs, cfg, use_operator)};

                    bits = randi([0, 1], bits_per_frame, 1);
                    noise = sqrt(noise_variance / 2) * ...
                        (randn(cfg.Nblk * d, 1) + ...
                         1i * randn(cfg.Nblk * d, 1));
                    paired = simulate_paired_csi_ber( ...
                        H_true, detectors, 4, data_snr, ...
                        struct('bits', bits, 'noise', noise, ...
                               'solver', ber_solver, 'pcg_tol', pcg_tol, ...
                               'pcg_max_iter', pcg_max_iter));

                    error_bits(i_scheme, :, i_mode, i_snr, frm) = ...
                        paired.error_bits;
                    solver_flag(i_scheme, :, i_mode, i_snr, frm) = ...
                        paired.solver_flag;
                    solver_iter(i_scheme, :, i_mode, i_snr, frm) = ...
                        paired.solver_iter;
                    detect_time_s(i_scheme, :, i_mode, i_snr, frm) = ...
                        paired.solve_time_s;
                end
            end
        end
    end

    ber = struct();
    ber.detector_names = detector_names;
    ber.pilot_modes = pilot_modes;
    ber.data_snr_db = data_snr_db;
    ber.linked_pilot_offset_db = linked_offset_db;
    ber.fixed_pilot_snr_db = fixed_pilot_snr_db;
    ber.pilot_snr_used_db = pilot_snr_used_db;
    ber.bits_per_frame = bits_per_frame;
    ber.solver = ber_solver;
    ber.error_bits = error_bits;
    ber.solver_flag = solver_flag;
    ber.solver_iter = solver_iter;
    ber.detect_time_s = detect_time_s;
    ber.ber = sum(error_bits, 5) / (bits_per_frame * opts.num_frames);
end

function H = detector_channel(modal_by_candidate, candidate_pairs, cfg, use_operator)
    if use_operator
        H = build_modal_block_operator( ...
            modal_by_candidate, candidate_pairs, cfg);
    else
        H = build_block_matrix_modal( ...
            modal_by_candidate, candidate_pairs, cfg);
    end
end

function value = get_option(opts, name, default)
    if isfield(opts, name)
        value = opts.(name);
    else
        value = default;
    end
end

function [tau_vec, nu_vec, H_phys, seed_base] = ...
        generate_frame_realization(scenario, opts, frm)
% Single source of the per-frame channel realization so the NMSE and BER
% tasks are guaranteed to see identical channels for the same frame index.
    seed_base = opts.seed_offset + 1000 * frm;
    [tau_vec, nu_vec] = generate_phys_dd_paths( ...
        scenario.cfg, scenario.cfg.Lch, seed_base);
    H_phys = generate_physical_taps(scenario, seed_base);
end

function method_opts = ce_method_options(method, cached_opts, spatial_variance, opts)
% Single source of each estimator's information boundary, shared by the NMSE
% and BER loops. Practical estimators receive only the aggregate PAS variance
% and CFAR settings; the oracle mask is added separately by the caller.
    method_opts = cached_opts;
    method_opts.method = method;
    switch method
        case 'full_grid_lmmse'
            method_opts.spatial_variance = spatial_variance;
        case 'threshold_ls'
            method_opts.pfa_total = opts.pfa_total;
            method_opts.correction = 'bonferroni';
        case 'threshold_lmmse'
            method_opts.spatial_variance = spatial_variance;
            method_opts.pfa_total = opts.pfa_total;
            method_opts.correction = 'bonferroni';
        case 'oracle_support_lmmse'
            method_opts.spatial_variance = spatial_variance;
        otherwise
            error('run_phase_g_channel_estimation:unknownCeMethod', ...
                'No option template for CE method "%s".', method);
    end
end

function somp_opts = somp_options(opts)
    somp_opts = struct('pfa_total', opts.pfa_total, ...
        'correction', 'bonferroni', 'residual_tolerance', 1e-10);
end

function symbols = random_qpsk(N, d_s, T)
    symbols = ((2 * randi([0, 1], N, d_s, T) - 1) + ...
        1i * (2 * randi([0, 1], N, d_s, T) - 1)) / sqrt(2);
end
