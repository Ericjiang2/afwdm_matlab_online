%% run_online_iso_svd_perfect_snr15_tail.m
% MATLAB Online resumable supplement for strict-ISO SVD_paper at 15 dB.
% Default 750 frames = half of the 1500 completed AFWDM tail frames.
% frame_start_offset=100 reuses the same frame seeds as the first AFWDM half.

clearvars -except iso_svd_tail_total_frames iso_svd_tail_chunk_frames ...
    iso_svd_tail_frame_start_offset iso_svd_tail_run_id ...
    iso_svd_tail_output_root;
clc; close all;

this_dir = fileparts(mfilename('fullpath'));
addpath(this_dir);
cfg = make_iso_perfect_snr15_tail_config('SVD_paper');

if exist('iso_svd_tail_total_frames', 'var') && ~isempty(iso_svd_tail_total_frames)
    cfg.total_frames = iso_svd_tail_total_frames;
end
if exist('iso_svd_tail_chunk_frames', 'var') && ~isempty(iso_svd_tail_chunk_frames)
    cfg.chunk_frames = iso_svd_tail_chunk_frames;
end
if exist('iso_svd_tail_frame_start_offset', 'var') && ~isempty(iso_svd_tail_frame_start_offset)
    cfg.frame_start_offset = iso_svd_tail_frame_start_offset;
end
if exist('iso_svd_tail_run_id', 'var') && ~isempty(iso_svd_tail_run_id)
    cfg.run_id = char(iso_svd_tail_run_id);
end
if exist('iso_svd_tail_output_root', 'var') && ~isempty(iso_svd_tail_output_root)
    cfg.output_root = char(iso_svd_tail_output_root);
end

summary = run_iso_perfect_snr15_tail(cfg);
