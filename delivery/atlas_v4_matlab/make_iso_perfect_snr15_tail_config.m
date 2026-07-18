function cfg = make_iso_perfect_snr15_tail_config(scheme)
%MAKE_ISO_PERFECT_SNR15_TAIL_CONFIG Frozen contract for the ISO 15 dB tail.

scheme = char(string(scheme));

cfg = struct();
cfg.runner_version = 'iso-perfect-snr15-tail-v2';
cfg.chunk_frames = 100;
cfg.frame_start_offset = 100;
cfg.run_id = '';
cfg.output_root = '';
cfg.SNR_dB = 15;
cfg.scenario = 'strict_isotropic';
cfg.strategy = 'full';
cfg.csi_label = 'perfect CSI';

switch scheme
    case 'AFWDM'
        cfg.scheme = 'AFWDM';
        cfg.total_frames = 1000;
        cfg.slug = 'iso_afwdm_perfect_snr15_tail';
        cfg.runner_file = 'run_online_iso_afwdm_perfect_snr15_tail.m';
        cfg.active_file = '_ACTIVE_ISO_AFWDM_SNR15_TAIL_ID.txt';
        cfg.summary_text_file = 'ISO_AFWDM_PERFECT_SNR15_TAIL_SUMMARY.txt';
    case 'SVD_paper'
        cfg.scheme = 'SVD_paper';
        cfg.total_frames = 750;
        cfg.slug = 'iso_svd_perfect_snr15_tail';
        cfg.runner_file = 'run_online_iso_svd_perfect_snr15_tail.m';
        cfg.active_file = '_ACTIVE_ISO_SVD_SNR15_TAIL_ID.txt';
        cfg.summary_text_file = 'ISO_SVD_PERFECT_SNR15_TAIL_SUMMARY.txt';
    otherwise
        error('make_iso_perfect_snr15_tail_config:scheme', ...
            'Unsupported scheme "%s". Use AFWDM or SVD_paper.', scheme);
end

cfg.target_point = sprintf('%s | %s | %s | %s | SNR=%g dB', ...
    cfg.scenario, cfg.scheme, cfg.strategy, cfg.csi_label, cfg.SNR_dB);
end
