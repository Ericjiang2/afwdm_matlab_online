%% run_online_iso_afwdm_perfect_snr15_tail.m
% MATLAB Online resumable tail run for one BER point:
%   strict_isotropic, AFWDM, full strategy, perfect CSI, SNR=15 dB.
%
% Why this exists:
%   The delivery paperfig run observed 0 AFWDM errors over 768000 bits at
%   SNR=15 dB. The plot displayed 0.5/Nbits only as a log-scale marker.
%   This runner accumulates more bits for the same point, in chunks, so the
%   high-SNR tail can be reported by raw error counts instead of a marker.
%
% Default:
%   iso_afwdm_tail_total_frames = 1000;
%   iso_afwdm_tail_chunk_frames = 100;
%   iso_afwdm_tail_frame_start_offset = 100;  % continue after paperfig 100 frames
%
% Optional before running:
%   iso_afwdm_tail_total_frames = 1500;
%   iso_afwdm_tail_chunk_frames = 100;
%   run('delivery/atlas_v4_matlab/run_online_iso_afwdm_perfect_snr15_tail.m')

clearvars -except iso_afwdm_tail_total_frames iso_afwdm_tail_chunk_frames ...
    iso_afwdm_tail_frame_start_offset iso_afwdm_tail_run_id;
clc; close all;

this_dir = fileparts(mfilename('fullpath'));
addpath(this_dir);

cfg0 = make_delivery_config("paperfig_iso");
for ii = 1:numel(cfg0.path_dirs)
    if exist(cfg0.path_dirs{ii}, 'dir')
        addpath(cfg0.path_dirs{ii});
    end
end
if ~exist(cfg0.output_dir, 'dir')
    mkdir(cfg0.output_dir);
end

if ~exist('iso_afwdm_tail_total_frames', 'var') || isempty(iso_afwdm_tail_total_frames)
    iso_afwdm_tail_total_frames = 1000;
end
if ~exist('iso_afwdm_tail_chunk_frames', 'var') || isempty(iso_afwdm_tail_chunk_frames)
    iso_afwdm_tail_chunk_frames = 100;
end
if ~exist('iso_afwdm_tail_frame_start_offset', 'var') || isempty(iso_afwdm_tail_frame_start_offset)
    iso_afwdm_tail_frame_start_offset = 100;
end

if iso_afwdm_tail_total_frames <= 0 || iso_afwdm_tail_chunk_frames <= 0
    error('run_online_iso_afwdm_perfect_snr15_tail:badFrameCounts', ...
        'total_frames and chunk_frames must be positive.');
end

run_root_base = fullfile(cfg0.output_dir, 'online_runs');
ensure_dir(run_root_base);
active_file = fullfile(run_root_base, '_ACTIVE_ISO_AFWDM_SNR15_TAIL_ID.txt');
if exist('iso_afwdm_tail_run_id', 'var') && ~isempty(iso_afwdm_tail_run_id)
    run_id = char(iso_afwdm_tail_run_id);
elseif exist(active_file, 'file')
    fid = fopen(active_file, 'r');
    run_id = strtrim(fgetl(fid));
    fclose(fid);
else
    run_id = ['iso_afwdm_perfect_snr15_tail_' timestamp_for_id()];
    fid = fopen(active_file, 'w');
    fprintf(fid, '%s\n', run_id);
    fclose(fid);
end

run_root = fullfile(run_root_base, run_id);
chunk_root = fullfile(run_root, 'chunks');
checkpoint_dir = fullfile(run_root, 'checkpoints');
final_dir = fullfile(run_root, 'final');
ensure_dir(run_root);
ensure_dir(chunk_root);
ensure_dir(checkpoint_dir);
ensure_dir(final_dir);

write_run_info(run_root, run_id, iso_afwdm_tail_total_frames, ...
    iso_afwdm_tail_chunk_frames, iso_afwdm_tail_frame_start_offset);

n_chunks = ceil(iso_afwdm_tail_total_frames / iso_afwdm_tail_chunk_frames);

fprintf('\n============================================================\n');
fprintf(' ISO AFWDM perfect-CSI SNR=15 tail run\n');
fprintf(' run_id: %s\n', run_id);
fprintf(' total_frames=%d, chunk_frames=%d, frame_start_offset=%d\n', ...
    iso_afwdm_tail_total_frames, iso_afwdm_tail_chunk_frames, ...
    iso_afwdm_tail_frame_start_offset);
fprintf(' output: %s\n', run_root);
fprintf('============================================================\n');

for iChunk = 1:n_chunks
    first_frame = (iChunk - 1) * iso_afwdm_tail_chunk_frames + 1;
    frames_this = min(iso_afwdm_tail_chunk_frames, ...
        iso_afwdm_tail_total_frames - first_frame + 1);
    frame_offset = iso_afwdm_tail_frame_start_offset + first_frame - 1;
    chunk_id = sprintf('chunk_%04d_frames_%06d_%06d', ...
        iChunk, frame_offset + 1, frame_offset + frames_this);
    chunk_dir = fullfile(chunk_root, chunk_id);
    done_file = fullfile(checkpoint_dir, [chunk_id '.done']);
    mat_pattern = fullfile(chunk_dir, 'atlas_v4_delivery_paperfig_iso_*.mat');

    if exist(done_file, 'file') && ~isempty(dir(mat_pattern))
        fprintf('[%d/%d] SKIP %s\n', iChunk, n_chunks, chunk_id);
        continue;
    end

    fprintf('\n[%d/%d] START %s\n', iChunk, n_chunks, chunk_id);
    append_status(run_root, chunk_id, 'START');
    ensure_dir(chunk_dir);
    t_chunk = tic;

    run_single_point_chunk(this_dir, chunk_dir, frames_this, frame_offset);

    hits = dir(mat_pattern);
    if isempty(hits)
        error('run_online_iso_afwdm_perfect_snr15_tail:missingChunkMat', ...
            'Chunk %s finished but no MAT was found.', chunk_id);
    end

    elapsed = toc(t_chunk);
    write_done(done_file, chunk_id, elapsed, frames_this, frame_offset);
    append_status(run_root, chunk_id, 'DONE');
    fprintf('[%d/%d] DONE %s in %.1f s\n', iChunk, n_chunks, chunk_id, elapsed);
end

summary = combine_tail_chunks(run_root, chunk_root, final_dir, run_id, ...
    iso_afwdm_tail_total_frames, iso_afwdm_tail_chunk_frames, ...
    iso_afwdm_tail_frame_start_offset);

fprintf('\n============================================================\n');
fprintf(' Tail summary: err=%d, bits=%d, BER=%.6g\n', ...
    summary.err_total, summary.bit_total, summary.BER);
if summary.err_total == 0
    fprintf(' Half-error marker: %.6g\n', summary.half_error_marker);
end
fprintf(' Final outputs: %s\n', final_dir);
fprintf('============================================================\n');

function run_single_point_chunk(this_dir, output_dir, frames_this, frame_offset)
mode = "paperfig_iso"; %#ok<NASGU>
cfg_override = make_single_point_override(output_dir, frames_this, frame_offset); %#ok<NASGU>
run_capacity = false; %#ok<NASGU>
run(fullfile(this_dir, 'main_atlas_v4_delivery.m'));
end

function cfg_override = make_single_point_override(output_dir, frames_this, frame_offset)
cfg_override = struct();
cfg_override.output_dir = output_dir;
cfg_override.skip_plots = true;
cfg_override.numFrames_BER = frames_this;
cfg_override.frame_start_offset = frame_offset;
cfg_override.SNR_dB_list = 15;
cfg_override.schemes = {'AFWDM'};
cfg_override.strategies = {'full'};
cfg_override.kappa_list = 0;
cfg_override.csi_error_mode = 'fixed_var';
cfg_override.csi_case_labels = {'perfect CSI'};
cfg_override.ber_scenarios = struct('label', 'strict_isotropic', ...
    'pas_model', 'isotropic', 'cv', 1.0, 'use_perpath_sigma', false);
end

function summary = combine_tail_chunks(run_root, chunk_root, final_dir, run_id, ...
    total_frames, chunk_frames, frame_start_offset)
chunk_mats = dir(fullfile(chunk_root, 'chunk_*', 'atlas_v4_delivery_paperfig_iso_*.mat'));
if isempty(chunk_mats)
    error('run_online_iso_afwdm_perfect_snr15_tail:noChunks', ...
        'No chunk MAT files found under %s.', chunk_root);
end

err_total = 0;
bit_total = 0;
chunk_records = struct('chunk_id', {}, 'mat_file', {}, 'err_total', {}, ...
    'bit_total', {}, 'BER', {}, 'numFrames_BER', {}, 'frame_start_offset', {});

for ii = 1:numel(chunk_mats)
    mat_file = fullfile(chunk_mats(ii).folder, chunk_mats(ii).name);
    pack = load(mat_file, 'results', 'cfg_run', 'metadata');
    e = pack.results.err_total(1, 1, 1, 1, 1);
    b = pack.results.bit_total(1, 1, 1, 1, 1);
    err_total = err_total + e;
    bit_total = bit_total + b;
    [~, chunk_id] = fileparts(chunk_mats(ii).folder);
    chunk_records(end+1) = struct( ... %#ok<AGROW>
        'chunk_id', chunk_id, ...
        'mat_file', mat_file, ...
        'err_total', e, ...
        'bit_total', b, ...
        'BER', e / max(b, 1), ...
        'numFrames_BER', pack.cfg_run.numFrames_BER, ...
        'frame_start_offset', pack.cfg_run.frame_start_offset);
end

summary = struct();
summary.run_id = run_id;
summary.source_environment = 'MATLAB Online';
summary.generated_by = 'delivery/atlas_v4_matlab/run_online_iso_afwdm_perfect_snr15_tail.m';
summary.target_point = 'strict_isotropic | AFWDM | full | perfect CSI | SNR=15 dB';
summary.total_frames_requested = total_frames;
summary.chunk_frames = chunk_frames;
summary.frame_start_offset = frame_start_offset;
summary.err_total = err_total;
summary.bit_total = bit_total;
summary.BER = err_total / max(bit_total, 1);
summary.half_error_marker = 0.5 / max(bit_total, 1);
summary.chunk_records = chunk_records;
summary.notes = ['If err_total is zero, BER is an observation of zero errors; ', ...
    'half_error_marker is only for log-scale plotting, not a measured BER.'];

metadata = struct();
metadata.mode = 'iso_afwdm_perfect_snr15_tail';
metadata.timestamp = timestamp_readable();
metadata.online_run_id = run_id;
metadata.aggregate_from = 'chunked_single_point_tail_run';
metadata.generated_by = summary.generated_by;

out_mat = fullfile(final_dir, sprintf('iso_afwdm_perfect_snr15_tail_summary_%s.mat', ...
    timestamp_for_file()));
save(out_mat, 'summary', 'metadata', '-v7');

out_txt = fullfile(final_dir, 'ISO_AFWDM_PERFECT_SNR15_TAIL_SUMMARY.txt');
fid = fopen(out_txt, 'w');
fprintf(fid, 'run_id=%s\n', run_id);
fprintf(fid, 'target=strict_isotropic | AFWDM | full | perfect CSI | SNR=15 dB\n');
fprintf(fid, 'total_frames_requested=%d\n', total_frames);
fprintf(fid, 'chunk_frames=%d\n', chunk_frames);
fprintf(fid, 'frame_start_offset=%d\n', frame_start_offset);
fprintf(fid, 'chunks_found=%d\n', numel(chunk_records));
fprintf(fid, 'err_total=%d\n', err_total);
fprintf(fid, 'bit_total=%d\n', bit_total);
fprintf(fid, 'BER=%.16g\n', summary.BER);
fprintf(fid, 'half_error_marker=%.16g\n', summary.half_error_marker);
fprintf(fid, 'summary_mat=%s\n', out_mat);
fclose(fid);
end

function write_run_info(run_root, run_id, total_frames, chunk_frames, frame_start_offset)
fid = fopen(fullfile(run_root, 'RUN_INFO.txt'), 'w');
fprintf(fid, 'run_id=%s\n', run_id);
fprintf(fid, 'runner=run_online_iso_afwdm_perfect_snr15_tail.m\n');
fprintf(fid, 'source_environment=MATLAB Online\n');
fprintf(fid, 'target=strict_isotropic | AFWDM | full | perfect CSI | SNR=15 dB\n');
fprintf(fid, 'total_frames=%d\nchunk_frames=%d\nframe_start_offset=%d\n', ...
    total_frames, chunk_frames, frame_start_offset);
fprintf(fid, 'started_or_resumed_at=%s\n', timestamp_iso());
fclose(fid);
end

function append_status(run_root, task_id, status)
status_file = fullfile(run_root, 'TASK_STATUS.tsv');
need_header = exist(status_file, 'file') ~= 2;
fid = fopen(status_file, 'a');
if need_header
    fprintf(fid, 'timestamp\ttask_id\tstatus\n');
end
fprintf(fid, '%s\t%s\t%s\n', timestamp_iso(), task_id, status);
fclose(fid);
end

function write_done(done_file, task_id, elapsed_sec, frames_this, frame_offset)
fid = fopen(done_file, 'w');
fprintf(fid, 'task=%s\nstatus=DONE\nfinished_at=%s\nelapsed_sec=%.3f\nframes=%d\nframe_start_offset=%d\n', ...
    task_id, timestamp_iso(), elapsed_sec, frames_this, frame_offset);
fclose(fid);
end

function ensure_dir(path_name)
if ~exist(path_name, 'dir')
    mkdir(path_name);
end
end

function s = timestamp_for_id()
s = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
end

function s = timestamp_for_file()
s = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
end

function s = timestamp_iso()
s = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss'));
end

function s = timestamp_readable()
s = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
end
