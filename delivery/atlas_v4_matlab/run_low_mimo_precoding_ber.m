function low = run_low_mimo_precoding_ber(cfg_run)
%RUN_LOW_MIMO_PRECODING_BER  5x5/Ns=1 waveform and precoder BER comparison.
%
% This is kept separate from main_atlas_v4_delivery so Fig.4-specific
% parameters and six-scheme bookkeeping do not thicken the main BER flow.

cfg_low = cfg_run;
cfg_low.array_shape = cfg_run.low_mimo.array_shape;
cfg_low.v_max_kmh = cfg_run.low_mimo.v_max_kmh;
cfg_low.tau_max_us = cfg_run.low_mimo.tau_max_us;
cfg_low.quick_stream_cap = [];

scenario = prepare_delivery_scenario(cfg_low, cfg_run.low_mimo.scenario);
cfg_base = scenario.cfg;
cfg_base.use_fractional_doppler = cfg_run.low_mimo.use_fractional_doppler;

modes = select_modes_atlas_v4(cfg_base, scenario.Sigma2, cfg_run.adapt_power_floor);
N_s = cfg_run.low_mimo.N_s;

schemes = {'AFWDM', 'AFDM_DFT_precoded', 'AFDM_SVD_precoded', ...
    'OFWDM', 'OFDM_DFT_precoded', 'OFDM_SVD_precoded'};
nScheme = numel(schemes);
nSNR = numel(cfg_run.low_mimo.SNR_dB_list);

BER = nan(nScheme, nSNR);
err_total = zeros(nScheme, nSNR);
bit_total = zeros(nScheme, nSNR);

Us_wdm = cfg_base.Us_full(:, modes.sort_s(1:N_s));
Ur_wdm = cfg_base.Ur_full(:, modes.sort_r(1:N_s));
[W_s_dft, W_r_dft] = build_dft_precoder(cfg_base.Ms, cfg_base.Mr, N_s, N_s);

for iSNR = 1:nSNR
    SNR_dB = cfg_run.low_mimo.SNR_dB_list(iSNR);
    fprintf('  low-mimo SNR=%g dB: ', SNR_dB);

    err_acc = zeros(nScheme, 1);
    bit_acc = zeros(nScheme, 1);

    for frm = 1:cfg_run.low_mimo.numFrames
        seed_base = cfg_run.seed.low_mimo_base + cfg_run.seed.frame_stride * frm;
        [tau_vec, nu_vec] = generate_phys_dd_paths(cfg_base, cfg_base.Lch, seed_base);
        H_phys = build_delivery_channel_taps(scenario, seed_base);

        G_hat = build_G_paper_eq31(H_phys, 'sum_taps');
        [W_s_svd, W_r_svd] = svd_precoder_from_G(G_hat, N_s, N_s);

        Us_list = {Us_wdm, W_s_dft, W_s_svd, Us_wdm, W_s_dft, W_s_svd};
        Ur_list = {Ur_wdm, W_r_dft, W_r_svd, Ur_wdm, W_r_dft, W_r_svd};
        is_ofdm = [false, false, false, true, true, true];

        for k = 1:nScheme
            cfg_k = make_delivery_scheme_cfg(cfg_base, Us_list{k}, Ur_list{k}, N_s, cfg_run);
            if is_ofdm(k)
                cfg_k.c1 = 0;
                cfg_k.c2 = 0;
            end

            H_blk = build_block_matrix_afwdm(H_phys, tau_vec, nu_vec, cfg_k);
            [e, b] = simulate_imperfect_csi_block(cfg_k, H_blk, H_blk, ...
                cfg_run.QAM_order, SNR_dB);
            err_acc(k) = err_acc(k) + e;
            bit_acc(k) = bit_acc(k) + b;
        end
    end

    err_total(:, iSNR) = err_acc;
    bit_total(:, iSNR) = bit_acc;
    BER(:, iSNR) = err_acc ./ max(bit_acc, 1);

    for k = 1:nScheme
        fprintf('%s %.2e ', schemes{k}, BER(k, iSNR));
    end
    fprintf('\n');
end

low = struct();
low.BER = BER;
low.err_total = err_total;
low.bit_total = bit_total;
low.SNR_dB = cfg_run.low_mimo.SNR_dB_list;
low.schemes = schemes;
low.N_s = N_s;
low.array_shape = cfg_run.low_mimo.array_shape;
low.v_max_kmh = cfg_run.low_mimo.v_max_kmh;
low.tau_max_us = cfg_run.low_mimo.tau_max_us;
low.use_fractional_doppler = cfg_run.low_mimo.use_fractional_doppler;
low.mode_summary = modes;
end
