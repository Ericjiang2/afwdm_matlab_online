function summary = run_iso_perfect_snr15_tail(cfg)
%RUN_ISO_PERFECT_SNR15_TAIL Resumable single-scheme ISO 15 dB tail runner.

validate_config(cfg);

this_dir = fileparts(mfilename('fullpath'));
addpath(this_dir);
cfg0 = make_delivery_config("paperfig_iso");
for ii = 1:numel(cfg0.path_dirs)
    if exist(cfg0.path_dirs{ii}, 'dir')
        addpath(cfg0.path_dirs{ii});
    end
end

if isempty(cfg.output_root)
    run_root_base = fullfile(cfg0.output_dir, 'online_runs');
else
    run_root_base = cfg.output_root;
end
ensure_dir(run_root_base);

active_file = fullfile(run_root_base, cfg.active_file);
run_id = resolve_run_id(cfg.run_id, active_file, cfg.slug);
run_root = fullfile(run_root_base, run_id);
chunk_root = fullfile(run_root, 'chunks');
checkpoint_dir = fullfile(run_root, 'checkpoints');
final_dir = fullfile(run_root, 'final');
ensure_dir(run_root);
ensure_dir(chunk_root);
ensure_dir(checkpoint_dir);
ensure_dir(final_dir);

contract = build_contract(cfg, run_id);
validate_or_write_contract(run_root, contract);
write_run_info(run_root, cfg, run_id);

n_chunks = ceil(cfg.total_frames / cfg.chunk_frames);
fprintf('\n============================================================\n');
fprintf(' ISO %s perfect-CSI SNR=15 tail run\n', cfg.scheme);
fprintf(' run_id: %s\n', run_id);
fprintf(' total_frames=%d, chunk_frames=%d, frame_start_offset=%d\n', ...
    cfg.total_frames, cfg.chunk_frames, cfg.frame_start_offset);
fprintf(' output: %s\n', run_root);
fprintf('============================================================\n');

for iChunk = 1:n_chunks
    [chunk_id, frames_this, frame_offset] = chunk_spec(cfg, iChunk);
    chunk_dir = fullfile(chunk_root, chunk_id);
    done_file = fullfile(checkpoint_dir, [chunk_id '.done']);
    mat_pattern = fullfile(chunk_dir, 'atlas_v4_delivery_paperfig_iso_*.mat');
    hits = dir(mat_pattern);

    if ~isempty(hits)
        mat_file = newest_file(hits);
        verify_chunk_mat(mat_file, cfg, frames_this, frame_offset);
        if ~exist(done_file, 'file')
            write_done(done_file, chunk_id, 0, frames_this, frame_offset, 'RECOVERED');
            append_status(run_root, chunk_id, 'RECOVERED');
        end
        fprintf('[%d/%d] SKIP %s\n', iChunk, n_chunks, chunk_id);
        continue;
    end

    fprintf('\n[%d/%d] START %s\n', iChunk, n_chunks, chunk_id);
    append_status(run_root, chunk_id, 'START');
    ensure_dir(chunk_dir);
    t_chunk = tic;

    run_single_point_chunk(this_dir, chunk_dir, frames_this, frame_offset, cfg.scheme);

    hits = dir(mat_pattern);
    if isempty(hits)
        error('run_iso_perfect_snr15_tail:missingChunkMat', ...
            'Chunk %s finished but no MAT was found.', chunk_id);
    end
    mat_file = newest_file(hits);
    verify_chunk_mat(mat_file, cfg, frames_this, frame_offset);

    elapsed = toc(t_chunk);
    write_done(done_file, chunk_id, elapsed, frames_this, frame_offset, 'DONE');
    append_status(run_root, chunk_id, 'DONE');
    fprintf('[%d/%d] DONE %s in %.1f s\n', iChunk, n_chunks, chunk_id, elapsed);
end

summary = combine_tail_chunks(chunk_root, final_dir, run_id, cfg);
fprintf('\n============================================================\n');
fprintf(' Tail summary: err=%d, bits=%d, BER=%.6g\n', ...
    summary.err_total, summary.bit_total, summary.BER);
if summary.err_total == 0
    fprintf(' 95%% zero-error upper bound: %.6g\n', summary.zero_error_95_upper);
end
fprintf(' Final outputs: %s\n', final_dir);
fprintf('============================================================\n');
end

function validate_config(cfg)
required = {'runner_version', 'scheme', 'total_frames', 'chunk_frames', ...
    'frame_start_offset', 'run_id', 'output_root', 'SNR_dB', 'scenario', ...
    'strategy', 'csi_label', 'slug', 'runner_file', 'active_file', ...
    'summary_text_file', 'target_point'};
for ii = 1:numel(required)
    if ~isfield(cfg, required{ii})
        error('run_iso_perfect_snr15_tail:config', ...
            'Missing configuration field: %s.', required{ii});
    end
end
if ~ismember(cfg.scheme, {'AFWDM', 'SVD_paper'})
    error('run_iso_perfect_snr15_tail:scheme', ...
        'Unsupported scheme "%s".', cfg.scheme);
end
validateattributes(cfg.total_frames, {'numeric'}, {'scalar', 'integer', 'positive'});
validateattributes(cfg.chunk_frames, {'numeric'}, {'scalar', 'integer', 'positive'});
validateattributes(cfg.frame_start_offset, {'numeric'}, {'scalar', 'integer', 'nonnegative'});
if cfg.SNR_dB ~= 15 || ~strcmp(cfg.scenario, 'strict_isotropic') || ...
        ~strcmp(cfg.strategy, 'full') || ~strcmp(cfg.csi_label, 'perfect CSI')
    error('run_iso_perfect_snr15_tail:target', ...
        'This runner is frozen to strict-isotropic/full/perfect-CSI/SNR=15 dB.');
end
end

function run_id = resolve_run_id(requested_id, active_file, slug)
if ~isempty(requested_id)
    run_id = char(requested_id);
elseif exist(active_file, 'file')
    fid = fopen(active_file, 'r');
    if fid < 0
        error('run_iso_perfect_snr15_tail:activeFile', ...
            'Cannot read active run file: %s.', active_file);
    end
    cleanup = onCleanup(@() fclose(fid));
    run_id = strtrim(fgetl(fid));
    if isempty(run_id)
        error('run_iso_perfect_snr15_tail:activeFile', ...
            'Active run file is empty: %s.', active_file);
    end
else
    run_id = [slug '_' timestamp_for_id()];
    fid = fopen(active_file, 'w');
    if fid < 0
        error('run_iso_perfect_snr15_tail:activeFile', ...
            'Cannot write active run file: %s.', active_file);
    end
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', run_id);
end
end

function contract = build_contract(cfg, run_id)
contract = struct();
contract.runner_version = cfg.runner_version;
contract.run_id = run_id;
contract.scheme = cfg.scheme;
contract.total_frames = cfg.total_frames;
contract.chunk_frames = cfg.chunk_frames;
contract.frame_start_offset = cfg.frame_start_offset;
contract.SNR_dB = cfg.SNR_dB;
contract.scenario = cfg.scenario;
contract.strategy = cfg.strategy;
contract.csi_label = cfg.csi_label;
end

function validate_or_write_contract(run_root, contract)
contract_file = fullfile(run_root, 'RUN_CONTRACT.mat');
if exist(contract_file, 'file')
    saved = load(contract_file, 'contract');
    if ~isfield(saved, 'contract') || ~isequaln(saved.contract, contract)
        error('run_iso_perfect_snr15_tail:manifestMismatch', ...
            ['RUN_CONTRACT.mat does not match the requested tail run. ', ...
             'Use a new run id instead of reusing these checkpoints.']);
    end
else
    legacy_mats = dir(fullfile(run_root, 'chunks', 'chunk_*', ...
        'atlas_v4_delivery_paperfig_iso_*.mat'));
    legacy_done = dir(fullfile(run_root, 'checkpoints', '*.done'));
    if exist(fullfile(run_root, 'RUN_INFO.txt'), 'file') || ...
            ~isempty(legacy_mats) || ~isempty(legacy_done)
        error('run_iso_perfect_snr15_tail:manifestMismatch', ...
            ['Existing tail artifacts predate RUN_CONTRACT.mat. ', ...
             'Use a new run id; legacy checkpoints cannot be adopted silently.']);
    end
    save(contract_file, 'contract', '-v7');
end
end

function [chunk_id, frames_this, frame_offset] = chunk_spec(cfg, iChunk)
first_frame = (iChunk - 1) * cfg.chunk_frames + 1;
frames_this = min(cfg.chunk_frames, cfg.total_frames - first_frame + 1);
frame_offset = cfg.frame_start_offset + first_frame - 1;
chunk_id = sprintf('chunk_%04d_frames_%06d_%06d', ...
    iChunk, frame_offset + 1, frame_offset + frames_this);
end

function run_single_point_chunk(this_dir, output_dir, frames_this, frame_offset, scheme)
mode = "paperfig_iso"; %#ok<NASGU>
cfg_override = make_single_point_override(output_dir, frames_this, frame_offset, scheme); %#ok<NASGU>
run_capacity = false; %#ok<NASGU>
run(fullfile(this_dir, 'main_atlas_v4_delivery.m'));
end

function cfg_override = make_single_point_override(output_dir, frames_this, frame_offset, scheme)
cfg_override = struct();
cfg_override.output_dir = output_dir;
cfg_override.skip_plots = true;
cfg_override.numFrames_BER = frames_this;
cfg_override.frame_start_offset = frame_offset;
cfg_override.SNR_dB_list = 15;
cfg_override.schemes = {scheme};
cfg_override.strategies = {'full'};
cfg_override.kappa_list = 0;
cfg_override.csi_error_mode = 'fixed_var';
cfg_override.csi_case_labels = {'perfect CSI'};
cfg_override.ber_scenarios = struct('label', 'strict_isotropic', ...
    'pas_model', 'isotropic', 'cv', 1.0, 'use_perpath_sigma', false);
end

function verify_chunk_mat(mat_file, cfg, frames_this, frame_offset)
pack = load(mat_file, 'results', 'cfg_run');
if ~isfield(pack, 'results') || ~isfield(pack, 'cfg_run')
    error('run_iso_perfect_snr15_tail:chunkContract', ...
        'Chunk MAT lacks results or cfg_run: %s.', mat_file);
end
if ~isequal(pack.results.schemes, {cfg.scheme}) || ...
        ~isequal(pack.results.SNR_dB, cfg.SNR_dB) || ...
        ~isequal(pack.results.strategies, {cfg.strategy}) || ...
        pack.cfg_run.numFrames_BER ~= frames_this || ...
        pack.cfg_run.frame_start_offset ~= frame_offset
    error('run_iso_perfect_snr15_tail:chunkContract', ...
        'Chunk MAT does not match the requested scheme/frame contract: %s.', mat_file);
end
end

function summary = combine_tail_chunks(chunk_root, final_dir, run_id, cfg)
n_chunks = ceil(cfg.total_frames / cfg.chunk_frames);
err_total = 0;
bit_total = 0;
chunk_records = repmat(struct('chunk_id', '', 'mat_file', '', 'err_total', 0, ...
    'bit_total', 0, 'BER', NaN, 'numFrames_BER', 0, 'frame_start_offset', 0), ...
    1, n_chunks);

for iChunk = 1:n_chunks
    [chunk_id, frames_this, frame_offset] = chunk_spec(cfg, iChunk);
    hits = dir(fullfile(chunk_root, chunk_id, 'atlas_v4_delivery_paperfig_iso_*.mat'));
    if isempty(hits)
        error('run_iso_perfect_snr15_tail:noChunks', ...
            'Missing completed chunk MAT for %s.', chunk_id);
    end
    mat_file = newest_file(hits);
    verify_chunk_mat(mat_file, cfg, frames_this, frame_offset);
    pack = load(mat_file, 'results', 'cfg_run');
    e = pack.results.err_total(1, 1, 1, 1, 1);
    b = pack.results.bit_total(1, 1, 1, 1, 1);
    err_total = err_total + e;
    bit_total = bit_total + b;
    chunk_records(iChunk) = struct( ...
        'chunk_id', chunk_id, 'mat_file', mat_file, ...
        'err_total', e, 'bit_total', b, 'BER', e / max(b, 1), ...
        'numFrames_BER', pack.cfg_run.numFrames_BER, ...
        'frame_start_offset', pack.cfg_run.frame_start_offset);
end

summary = struct();
summary.run_id = run_id;
summary.source_environment = 'MATLAB Online';
summary.generated_by = ['delivery/atlas_v4_matlab/' cfg.runner_file];
summary.target_point = cfg.target_point;
summary.scheme = cfg.scheme;
summary.total_frames_requested = cfg.total_frames;
summary.chunk_frames = cfg.chunk_frames;
summary.frame_start_offset = cfg.frame_start_offset;
summary.err_total = err_total;
summary.bit_total = bit_total;
summary.BER = err_total / max(bit_total, 1);
summary.half_error_marker = 0.5 / max(bit_total, 1);
summary.zero_error_95_upper = 3 / max(bit_total, 1);
summary.chunk_records = chunk_records;
summary.notes = ['A zero error count is an observation, not BER=0. ', ...
    'half_error_marker is display-only; zero_error_95_upper is the rule-of-three bound.'];

metadata = struct();
metadata.mode = cfg.slug;
metadata.timestamp = timestamp_readable();
metadata.online_run_id = run_id;
metadata.runner_version = cfg.runner_version;
metadata.aggregate_from = 'chunked_single_point_tail_run';
metadata.generated_by = summary.generated_by;

out_mat = fullfile(final_dir, sprintf('%s_summary_%s.mat', ...
    cfg.slug, timestamp_for_file()));
save(out_mat, 'summary', 'metadata', '-v7');

out_txt = fullfile(final_dir, cfg.summary_text_file);
fid = fopen(out_txt, 'w');
if fid < 0
    error('run_iso_perfect_snr15_tail:summaryFile', ...
        'Cannot write summary file: %s.', out_txt);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'run_id=%s\n', run_id);
fprintf(fid, 'target=%s\n', cfg.target_point);
fprintf(fid, 'total_frames_requested=%d\n', cfg.total_frames);
fprintf(fid, 'chunk_frames=%d\n', cfg.chunk_frames);
fprintf(fid, 'frame_start_offset=%d\n', cfg.frame_start_offset);
fprintf(fid, 'chunks_found=%d\n', numel(chunk_records));
fprintf(fid, 'err_total=%d\n', err_total);
fprintf(fid, 'bit_total=%d\n', bit_total);
fprintf(fid, 'BER=%.16g\n', summary.BER);
fprintf(fid, 'half_error_marker=%.16g\n', summary.half_error_marker);
fprintf(fid, 'zero_error_95_upper=%.16g\n', summary.zero_error_95_upper);
fprintf(fid, 'summary_mat=%s\n', out_mat);
end

function write_run_info(run_root, cfg, run_id)
fid = fopen(fullfile(run_root, 'RUN_INFO.txt'), 'w');
if fid < 0
    error('run_iso_perfect_snr15_tail:runInfo', 'Cannot write RUN_INFO.txt.');
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'run_id=%s\n', run_id);
fprintf(fid, 'runner=%s\n', cfg.runner_file);
fprintf(fid, 'runner_version=%s\n', cfg.runner_version);
fprintf(fid, 'source_environment=MATLAB Online\n');
fprintf(fid, 'target=%s\n', cfg.target_point);
fprintf(fid, 'total_frames=%d\nchunk_frames=%d\nframe_start_offset=%d\n', ...
    cfg.total_frames, cfg.chunk_frames, cfg.frame_start_offset);
fprintf(fid, 'started_or_resumed_at=%s\n', timestamp_iso());
end

function append_status(run_root, task_id, status)
status_file = fullfile(run_root, 'TASK_STATUS.tsv');
need_header = exist(status_file, 'file') ~= 2;
fid = fopen(status_file, 'a');
if fid < 0
    error('run_iso_perfect_snr15_tail:statusFile', ...
        'Cannot append status file: %s.', status_file);
end
cleanup = onCleanup(@() fclose(fid));
if need_header
    fprintf(fid, 'timestamp\ttask_id\tstatus\n');
end
fprintf(fid, '%s\t%s\t%s\n', timestamp_iso(), task_id, status);
end

function write_done(done_file, task_id, elapsed_sec, frames_this, frame_offset, status)
fid = fopen(done_file, 'w');
if fid < 0
    error('run_iso_perfect_snr15_tail:doneFile', ...
        'Cannot write checkpoint: %s.', done_file);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'task=%s\nstatus=%s\nfinished_at=%s\nelapsed_sec=%.3f\nframes=%d\nframe_start_offset=%d\n', ...
    task_id, status, timestamp_iso(), elapsed_sec, frames_this, frame_offset);
end

function mat_file = newest_file(hits)
[~, idx] = max([hits.datenum]);
mat_file = fullfile(hits(idx).folder, hits(idx).name);
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
