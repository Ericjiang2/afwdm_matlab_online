%% run_online_iso_afwdm_perfect_snr15_tail.m
% Backward-compatible AFWDM wrapper for the shared resumable ISO tail runner.

clearvars -except iso_afwdm_tail_total_frames iso_afwdm_tail_chunk_frames ...
    iso_afwdm_tail_frame_start_offset iso_afwdm_tail_run_id ...
    iso_afwdm_tail_output_root;
clc; close all;

this_dir = fileparts(mfilename('fullpath'));
addpath(this_dir);
cfg = make_iso_perfect_snr15_tail_config('AFWDM');

if exist('iso_afwdm_tail_total_frames', 'var') && ~isempty(iso_afwdm_tail_total_frames)
    cfg.total_frames = iso_afwdm_tail_total_frames;
end
if exist('iso_afwdm_tail_chunk_frames', 'var') && ~isempty(iso_afwdm_tail_chunk_frames)
    cfg.chunk_frames = iso_afwdm_tail_chunk_frames;
end
if exist('iso_afwdm_tail_frame_start_offset', 'var') && ~isempty(iso_afwdm_tail_frame_start_offset)
    cfg.frame_start_offset = iso_afwdm_tail_frame_start_offset;
end
if exist('iso_afwdm_tail_run_id', 'var') && ~isempty(iso_afwdm_tail_run_id)
    cfg.run_id = char(iso_afwdm_tail_run_id);
end
if exist('iso_afwdm_tail_output_root', 'var') && ~isempty(iso_afwdm_tail_output_root)
    cfg.output_root = char(iso_afwdm_tail_output_root);
end

summary = run_iso_perfect_snr15_tail(cfg);
