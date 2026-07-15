function results = run_time_diversity_ber(cfg_run)
%RUN_TIME_DIVERSITY_BER Strictly paired AFWDM-vs-OFWDM MIMO-DD BER.
%
% The main pair fixes one channel-independent WDM spatial basis and changes
% only c1/c2. Integer and fractional Doppler use identical frame seeds.

td = cfg_run.time_diversity;
scenario = prepare_delivery_scenario(cfg_run, td.scenario);
cfg_base = scenario.cfg;
modes = select_modes_main_eq45_reference(cfg_base, scenario.Sigma2);
if modes.N_s ~= td.N_s
    error('run_time_diversity_ber:streamCount', ...
        'Expected strict 4x4 main.pdf mode count %d, got %d.', td.N_s, modes.N_s);
end

Us_wdm = cfg_base.Us_full(:, modes.sort_s(1:td.N_s));
Ur_wdm = cfg_base.Ur_full(:, modes.sort_r(1:td.N_s));

n_runs = numel(td.Lch_values) * numel(td.doppler_modes) * ...
    numel(td.spatial_pairs) * numel(td.detectors);
empty_run = struct('doppler_mode', '', 'detector', '', 'spatial_pair', 'wdm', ...
    'Lch', cfg_base.Lch, 'kmax', cfg_base.kmax, 'SNR_dB', td.SNR_dB_list, ...
    'points', [], 'waveform_audit', [], 'lch_audit', []);
runs = repmat(empty_run, 1, n_runs);
run_index = 0;

for iLch = 1:numel(td.Lch_values)
    [scenario_lch, lch_audit] = configure_time_diversity_lch(scenario, td.Lch_values(iLch));

    for iDoppler = 1:numel(td.doppler_modes)
        doppler_mode = td.doppler_modes{iDoppler};
        cfg_mode = scenario_lch.cfg;
        cfg_mode.use_fractional_doppler = strcmp(doppler_mode, 'fractional');
        for iSpatial = 1:numel(td.spatial_pairs)
            spatial_pair = td.spatial_pairs{iSpatial};

            for iDetector = 1:numel(td.detectors)
                detector = td.detectors{iDetector};
                run_index = run_index + 1;
                points = repmat(empty_point(), 1, numel(td.SNR_dB_list));
                waveform_audit = [];

                for iSNR = 1:numel(td.SNR_dB_list)
                    snr_db = td.SNR_dB_list(iSNR);
                    bits_per_frame = td.N_s * cfg_base.Nblk * log2(cfg_run.QAM_order);
                    error_afwdm = false(bits_per_frame, td.max_frames);
                    error_ofwdm = false(bits_per_frame, td.max_frames);
                    iterations = zeros(2, td.max_frames);
                    converged = false(2, td.max_frames);
                    final_residuals = nan(2, td.max_frames);
                    stop_reason = 'continue';

                    for frame = 1:td.max_frames
                        seed = td.seed_base + cfg_run.seed.frame_stride * frame;
                        [tau_vec, nu_vec] = generate_phys_dd_paths(cfg_mode, cfg_mode.Lch, seed);
                        H_phys = build_delivery_channel_taps(scenario_lch, seed);
                        [Us, Ur] = resolve_time_diversity_spatial_pair( ...
                            spatial_pair, cfg_mode, H_phys, Us_wdm, Ur_wdm, td.N_s);
                        [cfg_afwdm, cfg_ofwdm, waveform_audit] = ...
                            make_time_diversity_waveform_pair(cfg_mode, Us, Ur, td.N_s, cfg_run);
                        H_afwdm = build_block_matrix_afwdm(H_phys, tau_vec, nu_vec, cfg_afwdm);
                        H_ofwdm = build_block_matrix_afwdm(H_phys, tau_vec, nu_vec, cfg_ofwdm);

                        rng(td.bits_seed_offset + seed, 'twister');
                        shared_bits = randi([0, 1], bits_per_frame, 1);
                        shared_noise = (randn(size(H_afwdm, 1), 1) + ...
                            1j * randn(size(H_afwdm, 1), 1)) / sqrt(2);
                        pair_opts = struct( ...
                            'bits', shared_bits, ...
                            'unit_noise', shared_noise, ...
                            'detector', detector, ...
                            'detector_options', detector_options(td, detector));
                        pair = simulate_paired_waveform_frame(cfg_afwdm, H_afwdm, ...
                            cfg_ofwdm, H_ofwdm, cfg_run.QAM_order, snr_db, pair_opts);

                        error_afwdm(:, frame) = pair.error_a;
                        error_ofwdm(:, frame) = pair.error_b;
                        iterations(:, frame) = [pair.detector_a.iterations; pair.detector_b.iterations];
                        converged(:, frame) = [pair.detector_a.converged; pair.detector_b.converged];
                        final_residuals(:, frame) = [detector_final_residual(pair.detector_a); ...
                            detector_final_residual(pair.detector_b)];

                        [stop, stop_reason] = paired_stop_decision( ...
                            [sum(error_afwdm(:, 1:frame), 'all'), ...
                             sum(error_ofwdm(:, 1:frame), 'all')], frame, td);
                        if stop
                            break;
                        end
                    end

                    error_afwdm = error_afwdm(:, 1:frame);
                    error_ofwdm = error_ofwdm(:, 1:frame);
                    stats_opts = struct( ...
                        'target_errors', td.target_errors, ...
                        'bootstrap_samples', td.bootstrap_samples, ...
                        'bootstrap_seed', td.bootstrap_seed + 10000 * iLch + ...
                            1000 * iDoppler + 100 * iSpatial + 10 * iDetector + iSNR, ...
                        'confidence', 0.95);
                    stats = paired_ber_statistics(error_afwdm, error_ofwdm, stats_opts);
                    stats.stop_reason = stop_reason;
                    stats.average_iterations = mean(iterations(:, 1:frame), 2);
                    stats.nonconvergence_rate = mean(~converged(:, 1:frame), 2);
                    stats.final_residuals = final_residuals(:, 1:frame);
                    stats.average_final_residual = mean( ...
                        stats.final_residuals, 2, 'omitnan');
                    stats.error_table_afwdm = error_afwdm;
                    stats.error_table_ofwdm = error_ofwdm;
                    points(iSNR) = stats;
                end

                runs(run_index) = struct( ...
                    'doppler_mode', doppler_mode, ...
                    'detector', detector, ...
                    'spatial_pair', spatial_pair, ...
                    'Lch', cfg_mode.Lch, ...
                    'kmax', cfg_mode.kmax, ...
                    'SNR_dB', td.SNR_dB_list, ...
                    'points', points, ...
                    'waveform_audit', waveform_audit, ...
                    'lch_audit', lch_audit);
            end
        end
    end
end

results = struct();
results.runs = runs;
results.N_s = td.N_s;
results.Nblk = cfg_base.Nblk;
results.array_shape = cfg_run.array_shape;
results.fc = cfg_base.fc;
results.Deltaf = cfg_base.Deltaf;
results.c1_formula = '(2*kmax+1)/(2*Nblk)';
results.c2_formula = '0.1/Nblk';
results.same_frame_seeds_across_doppler = true;
results.production_profile = strcmp(cfg_run.mode, 'time_diversity_online');
results.summary_table = build_time_diversity_summary( ...
    runs, max(td.Lch_values), td.summary_target_ber);
if all(ismember([4, 6], td.Lch_values))
    results.lch_comparison = compare_time_diversity_lch(runs, 4, 6);
else
    results.lch_comparison = [];
end
end

function point = empty_point()
point = struct( ...
    'ber_a', NaN, 'ber_b', NaN, 'ber_ratio_b_over_a', NaN, ...
    'error_count_a', 0, 'error_count_b', 0, 'bit_count', 0, ...
    'frame_count', 0, 'discordant_a_only', 0, 'discordant_b_only', 0, ...
    'mcnemar_p', NaN, 'noise_limited', true, 'claim_eligible', false, ...
    'ber_ratio_ci', [NaN, NaN], 'stop_reason', '', ...
    'average_iterations', [NaN; NaN], 'nonconvergence_rate', [NaN; NaN], ...
    'final_residuals', nan(2, 0), 'average_final_residual', [NaN; NaN], ...
    'error_table_afwdm', false(0, 0), 'error_table_ofwdm', false(0, 0));
end

function residual = detector_final_residual(info)
residual = NaN;
if isfield(info, 'residual') && isscalar(info.residual) && ...
        isfinite(info.residual)
    residual = info.residual;
end
end

function opts = detector_options(td, detector)
opts = struct();
if strcmp(detector, 'gabp') && isfield(td, 'gabp')
    opts = td.gabp;
end
end
