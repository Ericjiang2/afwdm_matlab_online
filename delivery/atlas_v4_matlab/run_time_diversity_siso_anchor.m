function anchor = run_time_diversity_siso_anchor(cfg_run)
%RUN_TIME_DIVERSITY_SISO_ANCHOR Internal SISO mechanism diagnostic (no figure).

td = cfg_run.time_diversity;
cfg = physical_siso_cfg(cfg_run);
cfg.Lch = 6;
runs = repmat(struct('doppler_mode', '', 'SNR_dB', td.siso_SNR_dB_list, ...
    'points', []), 1, numel(td.doppler_modes));

for iDoppler = 1:numel(td.doppler_modes)
    cfg_mode = cfg;
    cfg_mode.use_fractional_doppler = strcmp(td.doppler_modes{iDoppler}, 'fractional');
    cfg_afdm = cfg_mode;
    cfg_ofdm = cfg_mode;
    cfg_ofdm.c1 = 0;
    cfg_ofdm.c2 = 0;
    points = repmat(struct('ber_a', NaN, 'ber_b', NaN, ...
        'ber_ratio_b_over_a', NaN, 'noise_limited', true), ...
        1, numel(td.siso_SNR_dB_list));

    for iSNR = 1:numel(td.siso_SNR_dB_list)
        error_a = false(cfg.Nblk * 2, td.siso_frames);
        error_b = false(cfg.Nblk * 2, td.siso_frames);
        for frame = 1:td.siso_frames
            seed = td.seed_base + cfg_run.seed.frame_stride * frame;
            rng(seed, 'twister');
            H_phys = cell(1, cfg.Lch);
            for ell = 1:cfg.Lch
                H_phys{ell} = (randn + 1j * randn) / sqrt(2 * cfg.Lch);
            end
            [tau_vec, nu_vec] = generate_phys_dd_paths(cfg_mode, cfg.Lch, seed);
            H_afdm = build_block_matrix_afwdm(H_phys, tau_vec, nu_vec, cfg_afdm);
            H_ofdm = build_block_matrix_afwdm(H_phys, tau_vec, nu_vec, cfg_ofdm);
            rng(td.bits_seed_offset + seed, 'twister');
            opts = struct( ...
                'bits', randi([0, 1], cfg.Nblk * 2, 1), ...
                'unit_noise', (randn(cfg.Nblk, 1) + 1j * randn(cfg.Nblk, 1)) / sqrt(2), ...
                'detector', 'block_lmmse');
            pair = simulate_paired_waveform_frame(cfg_afdm, H_afdm, cfg_ofdm, ...
                H_ofdm, 4, td.siso_SNR_dB_list(iSNR), opts);
            error_a(:, frame) = pair.error_a;
            error_b(:, frame) = pair.error_b;
        end
        stats = paired_ber_statistics(error_a, error_b, struct( ...
            'target_errors', td.target_errors, ...
            'bootstrap_samples', td.bootstrap_samples, ...
            'bootstrap_seed', td.bootstrap_seed + 100 * iDoppler + iSNR));
        points(iSNR) = struct( ...
            'ber_a', stats.ber_a, ...
            'ber_b', stats.ber_b, ...
            'ber_ratio_b_over_a', stats.ber_ratio_b_over_a, ...
            'noise_limited', stats.noise_limited);
    end
    runs(iDoppler).doppler_mode = td.doppler_modes{iDoppler};
    runs(iDoppler).points = points;
end

anchor = struct();
anchor.runs = runs;
anchor.N_s = 1;
anchor.Nblk = cfg.Nblk;
anchor.Lch = cfg.Lch;
anchor.kmax = cfg.kmax;
anchor.lmax = cfg.lmax;
anchor.internal_diagnostic_only = true;
anchor.figure_included = false;
end

function cfg = physical_siso_cfg(cfg_run)
cfg = struct();
cfg.fc = cfg_run.fc;
cfg.lambda = 3e8 / cfg.fc;
cfg.v_max_kmh = cfg_run.v_max_kmh;
cfg.v_max = cfg.v_max_kmh / 3.6;
cfg.Deltaf = cfg_run.Deltaf;
cfg.Nblk = cfg_run.Nblk;
cfg.Ts = 1 / (cfg.Nblk * cfg.Deltaf);
cfg.nu_max = cfg.v_max / cfg.lambda;
cfg.kmax = ceil(cfg.nu_max / cfg.Deltaf);
cfg.tau_max = cfg_run.tau_max_us * 1e-6;
cfg.lmax = ceil(cfg.tau_max / cfg.Ts);
cfg.afdm_diversity_lhs = 2 * cfg.kmax * (cfg.lmax + 1) + cfg.lmax;
cfg.c1 = (2 * cfg.kmax + 1) / (2 * cfg.Nblk);
cfg.c2 = 0.1 / cfg.Nblk;
cfg.Ms = 1; cfg.Mr = 1; cfg.ms = 1; cfg.mr = 1; cfg.Nstreams = 1;
cfg.Us = 1; cfg.Ur = 1; cfg.Fbb_wdm = []; cfg.Wbb_wdm = [];
cfg.block_lmmse_solver = 'direct'; cfg.pcg_tol = 1e-8; cfg.pcg_max_iter = 50;
end
