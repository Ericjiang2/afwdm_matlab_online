function cfg = make_iso_svd_snr20_tail_config()
%MAKE_ISO_SVD_SNR20_TAIL_CONFIG Frozen contract for the ISO SVD 20 dB diagnostic.

cfg = make_iso_perfect_snr15_tail_config('SVD_paper');
cfg.runner_version = 'iso-perfect-svd-snr20-tail-v1';
cfg.total_frames = 2250;
cfg.SNR_dB = 20;
cfg.slug = 'iso_svd_perfect_snr20_tail';
cfg.runner_file = 'run_online_iso_svd_perfect_snr20_tail.m';
cfg.active_file = '_ACTIVE_ISO_SVD_SNR20_TAIL_ID.txt';
cfg.summary_text_file = 'ISO_SVD_PERFECT_SNR20_TAIL_SUMMARY.txt';
cfg.target_point = sprintf('%s | %s | %s | %s | SNR=%g dB', ...
    cfg.scenario, cfg.scheme, cfg.strategy, cfg.csi_label, cfg.SNR_dB);
end
