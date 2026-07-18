%% run_online_iso_svd_perfect_snr20_tail.m
% MATLAB Online resumable diagnostic for strict-ISO SVD_paper at 20 dB.
% Default 2250 frames = 3x the completed 750-frame SNR=15 dB supplement.
% frame_start_offset=100 reuses its first 750 frame seeds across SNR.

clearvars -except iso_svd_snr20_tail_total_frames ...
    iso_svd_snr20_tail_chunk_frames ...
    iso_svd_snr20_tail_frame_start_offset ...
    iso_svd_snr20_tail_run_id iso_svd_snr20_tail_output_root;
clc; close all;

this_dir = fileparts(mfilename('fullpath'));
addpath(this_dir);
cfg = make_iso_svd_snr20_tail_config();

if exist('iso_svd_snr20_tail_total_frames', 'var') && ...
        ~isempty(iso_svd_snr20_tail_total_frames)
    cfg.total_frames = iso_svd_snr20_tail_total_frames;
end
if exist('iso_svd_snr20_tail_chunk_frames', 'var') && ...
        ~isempty(iso_svd_snr20_tail_chunk_frames)
    cfg.chunk_frames = iso_svd_snr20_tail_chunk_frames;
end
if exist('iso_svd_snr20_tail_frame_start_offset', 'var') && ...
        ~isempty(iso_svd_snr20_tail_frame_start_offset)
    cfg.frame_start_offset = iso_svd_snr20_tail_frame_start_offset;
end
if exist('iso_svd_snr20_tail_run_id', 'var') && ...
        ~isempty(iso_svd_snr20_tail_run_id)
    cfg.run_id = char(iso_svd_snr20_tail_run_id);
end
if exist('iso_svd_snr20_tail_output_root', 'var') && ...
        ~isempty(iso_svd_snr20_tail_output_root)
    cfg.output_root = char(iso_svd_snr20_tail_output_root);
end

summary = run_iso_perfect_snr15_tail(cfg);
