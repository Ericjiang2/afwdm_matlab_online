% run_delivery_online_resumable.m
% Resumable MATLAB Online runner for delivery paperfig tasks.
%
% Re-run this command after a browser/session interruption:
%   run('delivery/atlas_v4_matlab/run_delivery_online_resumable.m')
%
% BER and low-MIMO sweeps are checkpointed per SNR point. Per-SNR tasks save
% MAT files only; final multi-SNR figures are rebuilt from those MAT files under:
%   delivery/atlas_v4_matlab/outputs/online_runs/<run_id>/final/

clearvars -except delivery_online_profile delivery_online_screen; clc;

this_dir = fileparts(mfilename('fullpath'));
addpath(this_dir);

if ~exist('delivery_online_profile', 'var') || isempty(delivery_online_profile)
    delivery_online_profile = "paperfig";
end
profile = lower(string(delivery_online_profile));

if profile == "fullstream_waveform_screen"
    if ~exist('delivery_online_screen', 'var') || isempty(delivery_online_screen)
        error('run_delivery_online_resumable:missingScreenConfig', ...
            'The fullstream_waveform_screen profile requires delivery_online_screen.');
    end
    cfg0 = make_delivery_config("paperfig_low_mimo");
    cfg0 = merge_delivery_config(cfg0, struct( ...
        'output_dir', fullfile(this_dir, 'outputs', 'fullstream_waveform_screen'), ...
        'low_mimo', delivery_online_screen));
else
    cfg0 = make_delivery_config("paperfig");
end
if ~exist(cfg0.output_dir, 'dir')
    mkdir(cfg0.output_dir);
end
for ii = 1:numel(cfg0.path_dirs)
    if exist(cfg0.path_dirs{ii}, 'dir')
        addpath(cfg0.path_dirs{ii});
    end
end

run_id = get_or_create_delivery_run_id(cfg0.output_dir);
run_root = fullfile(cfg0.output_dir, 'online_runs', run_id);
checkpoint_dir = fullfile(run_root, 'checkpoints');
final_dir = fullfile(run_root, 'final');
ensure_dir(checkpoint_dir);
ensure_dir(final_dir);
write_delivery_run_info(run_root, run_id);

tasks = build_delivery_tasks(cfg0, run_root, final_dir, profile);

fprintf('\n============================================================\n');
fprintf(' Delivery online resumable runner\n');
fprintf(' run_id: %s\n', run_id);
fprintf(' root:   %s\n', run_root);
fprintf(' final:  %s\n', final_dir);
fprintf('============================================================\n');

for ii = 1:numel(tasks)
    task = tasks(ii);
    done_file = fullfile(checkpoint_dir, [task.id '.done']);

    if exist(done_file, 'file') && task_outputs_exist(task)
        fprintf('\n[%d/%d] SKIP %s (checkpoint exists)\n', ii, numel(tasks), task.id);
        continue;
    end
    if task_outputs_exist(task)
        write_task_done(done_file, task.id, 0, 'RECOVERED_FROM_OUTPUT');
        fprintf('\n[%d/%d] SKIP %s (output exists; checkpoint recovered)\n', ii, numel(tasks), task.id);
        continue;
    end

    fprintf('\n[%d/%d] START %s\n', ii, numel(tasks), task.id);
    append_task_status(run_root, task.id, 'START');
    t_task = tic;

    switch task.type
        case 'run'
            fprintf('  mode=%s\n', task.mode);
            if isfinite(task.snr_dB)
                fprintf('  SNR=%g dB\n', task.snr_dB);
            end
            run_delivery_mode(task.mode, this_dir, task.cfg_override);
        case 'combine_ber'
            combine_ber_tasks(task, tasks, final_dir, run_id);
        case 'combine_low_mimo'
            combine_low_mimo_tasks(task, tasks, final_dir, run_id);
        otherwise
            error('run_delivery_online_resumable:unknownTaskType', ...
                'Unknown task type "%s".', task.type);
    end

    if ~task_outputs_exist(task)
        error('run_delivery_online_resumable:missingOutput', ...
            'Task %s finished but expected output was not found.', task.id);
    end

    elapsed = toc(t_task);
    write_task_done(done_file, task.id, elapsed, 'DONE');
    append_task_status(run_root, task.id, 'DONE');
    fprintf('[%d/%d] DONE %s in %.1f s\n', ii, numel(tasks), task.id, elapsed);
end

fprintf('\n============================================================\n');
fprintf(' Delivery online resumable tasks complete.\n');
fprintf(' Final outputs: %s\n', final_dir);
fprintf(' Checkpoints:   %s\n', checkpoint_dir);
fprintf('============================================================\n');

function tasks = build_delivery_tasks(cfg0, run_root, final_dir, profile)
tasks = empty_task();
tasks(:) = [];

iso_ids = {};
vmf_ids = {};
low_ids = {};

if profile == "fullstream_waveform_screen"
    low = cfg0.low_mimo;
    screen_N_s = resolve_screen_stream_count(low, cfg0);
    for snr = low.SNR_dB_list
        id = sprintf('fullstream_waveform_screen_snr_%s', snr_tag(snr));
        task_dir = fullfile(run_root, 'tasks', id);
        low_override = low;
        low_override.SNR_dB_list = snr;
        override = struct('output_dir', task_dir, 'low_mimo', low_override, 'skip_plots', true);
        tasks(end+1) = make_run_task(id, 'paperfig_low_mimo', snr, override, ...
            fullfile(task_dir, 'atlas_v4_delivery_paperfig_low_mimo_*.mat'), ...
            {}); %#ok<AGROW>
        low_ids{end+1} = id; %#ok<AGROW>
    end
    tasks(end+1) = make_combine_task('combine_fullstream_waveform_screen', 'combine_low_mimo', ...
        low_ids, fullfile(final_dir, 'atlas_v4_delivery_paperfig_low_mimo_resumable_*.mat'), ...
        {fullfile(final_dir, 'figures', sprintf('ber_low_mimo_%dx%d_ns%d_precoding.png', ...
            low.array_shape(1), low.array_shape(2), screen_N_s))}); %#ok<AGROW>
    return;
end

for snr = cfg0.SNR_dB_list
    id = sprintf('ber_strict_isotropic_snr_%s', snr_tag(snr));
    task_dir = fullfile(run_root, 'tasks', id);
    override = struct('SNR_dB_list', snr, 'output_dir', task_dir, 'skip_plots', true);
    tasks(end+1) = make_run_task(id, 'paperfig_iso', snr, override, ...
        fullfile(task_dir, 'atlas_v4_delivery_paperfig_iso_*.mat'), ...
        {}); %#ok<AGROW>
    iso_ids{end+1} = id; %#ok<AGROW>
end
tasks(end+1) = make_combine_task('combine_ber_strict_isotropic', 'combine_ber', ...
    iso_ids, fullfile(final_dir, 'atlas_v4_delivery_paperfig_iso_resumable_*.mat'), ...
    {fullfile(final_dir, 'figures', 'ber_strict_isotropic_perfect_vs_fixedvar.png')}); %#ok<AGROW>

for snr = cfg0.SNR_dB_list
    id = sprintf('ber_vmf_cv030_snr_%s', snr_tag(snr));
    task_dir = fullfile(run_root, 'tasks', id);
    override = struct('SNR_dB_list', snr, 'output_dir', task_dir, 'skip_plots', true);
    tasks(end+1) = make_run_task(id, 'paperfig_vmf', snr, override, ...
        fullfile(task_dir, 'atlas_v4_delivery_paperfig_vmf_*.mat'), ...
        {}); %#ok<AGROW>
    vmf_ids{end+1} = id; %#ok<AGROW>
end
tasks(end+1) = make_combine_task('combine_ber_vmf_cv030', 'combine_ber', ...
    vmf_ids, fullfile(final_dir, 'atlas_v4_delivery_paperfig_vmf_resumable_*.mat'), ...
    {fullfile(final_dir, 'figures', 'ber_vmf_cv030_perfect_vs_fixedvar.png')}); %#ok<AGROW>

tasks(end+1) = make_run_task('capacity_raw', 'paperfig_capacity', NaN, ...
    struct('output_dir', final_dir), ...
    fullfile(final_dir, 'atlas_v4_delivery_paperfig_capacity_*.mat'), ...
    {fullfile(final_dir, 'figures', 'capacity_raw_doubly_selective.png')}); %#ok<AGROW>

low = cfg0.low_mimo;
for snr = low.SNR_dB_list
    id = sprintf('low_mimo_precoding_snr_%s', snr_tag(snr));
    task_dir = fullfile(run_root, 'tasks', id);
    low_override = struct('SNR_dB_list', snr);
    override = struct('output_dir', task_dir, 'low_mimo', low_override, 'skip_plots', true);
    tasks(end+1) = make_run_task(id, 'paperfig_low_mimo', snr, override, ...
        fullfile(task_dir, 'atlas_v4_delivery_paperfig_low_mimo_*.mat'), ...
        {}); %#ok<AGROW>
    low_ids{end+1} = id; %#ok<AGROW>
end
tasks(end+1) = make_combine_task('combine_low_mimo_precoding', 'combine_low_mimo', ...
    low_ids, fullfile(final_dir, 'atlas_v4_delivery_paperfig_low_mimo_resumable_*.mat'), ...
    {fullfile(final_dir, 'figures', sprintf('ber_low_mimo_%dx%d_ns%d_precoding.png', ...
        low.array_shape(1), low.array_shape(2), low.N_s))}); %#ok<AGROW>
end

function task = empty_task()
task = struct( ...
    'id', '', ...
    'type', '', ...
    'mode', '', ...
    'snr_dB', NaN, ...
    'cfg_override', struct(), ...
    'mat_pattern', '', ...
    'png_files', {{}}, ...
    'source_ids', {{}});
end

function N_s = resolve_screen_stream_count(low, cfg0)
if ischar(low.N_s) || isstring(low.N_s)
    if ~strcmpi(string(low.N_s), "full")
        error('run_delivery_online_resumable:unknownScreenStreamRequest', ...
            'String screen N_s request must be "full", got "%s".', string(low.N_s));
    end
    [~, N_s] = select_center_modes_2d(low.array_shape(1), low.array_shape(2), ...
        0, cfg0.dx, cfg0.dy);
else
    N_s = low.N_s;
end
end

function task = make_run_task(id, mode, snr_dB, cfg_override, mat_pattern, png_files)
task = empty_task();
task.id = id;
task.type = 'run';
task.mode = mode;
task.snr_dB = snr_dB;
task.cfg_override = cfg_override;
task.mat_pattern = mat_pattern;
task.png_files = png_files;
end

function task = make_combine_task(id, type, source_ids, mat_pattern, png_files)
task = empty_task();
task.id = id;
task.type = type;
task.mat_pattern = mat_pattern;
task.png_files = png_files;
task.source_ids = source_ids;
end

function ok = task_outputs_exist(task)
hits = dir(task.mat_pattern);
ok = ~isempty(hits);
for ii = 1:numel(task.png_files)
    ok = ok && exist(task.png_files{ii}, 'file') == 2;
end
end

function run_delivery_mode(task_mode, this_dir, override)
mode = string(task_mode); %#ok<NASGU>
cfg_override = override; %#ok<NASGU>
run_capacity = []; %#ok<NASGU>
run(fullfile(this_dir, 'main_atlas_v4_delivery.m'));
end

function combine_ber_tasks(task, tasks, final_dir, run_id)
source_tasks = lookup_source_tasks(tasks, task.source_ids);
packs = load_task_packs(source_tasks);
[snrs, order] = sort([source_tasks.snr_dB]);

base = packs{order(1)};
results = base.results;
cfg_run = base.cfg_run;
metadata = base.metadata;

results.BER = cat_results_field(packs, order, 'BER', 3);
results.err_total = cat_results_field(packs, order, 'err_total', 3);
results.bit_total = cat_results_field(packs, order, 'bit_total', 3);
results.SNR_dB = snrs;

cfg_run.SNR_dB_list = snrs;
cfg_run.output_dir = final_dir;
metadata.generated_by = 'delivery/atlas_v4_matlab/run_delivery_online_resumable.m';
metadata.aggregate_from = 'per_snr_checkpoints';
metadata.online_run_id = run_id;
metadata.timestamp = timestamp_readable();

ensure_dir(final_dir);
out_mat = fullfile(final_dir, sprintf('atlas_v4_delivery_%s_resumable_%s.mat', ...
    cfg_run.mode, timestamp_for_file()));
save(out_mat, 'results', 'metadata', 'cfg_run', '-v7');
plot_delivery_results(results, cfg_run);
end

function combine_low_mimo_tasks(task, tasks, final_dir, run_id)
source_tasks = lookup_source_tasks(tasks, task.source_ids);
packs = load_task_packs(source_tasks);
[snrs, order] = sort([source_tasks.snr_dB]);

base = packs{order(1)};
results = base.results;
cfg_run = base.cfg_run;
metadata = base.metadata;

low = results.low_mimo;
low.BER = cat_low_field(packs, order, 'BER');
low.err_total = cat_low_field(packs, order, 'err_total');
low.bit_total = cat_low_field(packs, order, 'bit_total');
low.SNR_dB = snrs;

results.low_mimo = low;
cfg_run.low_mimo.SNR_dB_list = snrs;
cfg_run.output_dir = final_dir;
metadata.generated_by = 'delivery/atlas_v4_matlab/run_delivery_online_resumable.m';
metadata.aggregate_from = 'per_snr_checkpoints';
metadata.online_run_id = run_id;
metadata.timestamp = timestamp_readable();

ensure_dir(final_dir);
out_mat = fullfile(final_dir, sprintf('atlas_v4_delivery_%s_resumable_%s.mat', ...
    cfg_run.mode, timestamp_for_file()));
save(out_mat, 'results', 'metadata', 'cfg_run', '-v7');
plot_delivery_results(results, cfg_run);
end

function out = cat_results_field(packs, order, field_name, dim)
parts = cell(1, numel(order));
for ii = 1:numel(order)
    parts{ii} = packs{order(ii)}.results.(field_name);
end
out = cat(dim, parts{:});
end

function out = cat_low_field(packs, order, field_name)
parts = cell(1, numel(order));
for ii = 1:numel(order)
    parts{ii} = packs{order(ii)}.results.low_mimo.(field_name);
end
out = cat(2, parts{:});
end

function source_tasks = lookup_source_tasks(tasks, source_ids)
source_tasks = empty_task();
source_tasks(:) = [];
for ii = 1:numel(source_ids)
    hit = find(strcmp({tasks.id}, source_ids{ii}), 1);
    if isempty(hit)
        error('run_delivery_online_resumable:missingSourceTask', ...
            'Could not find source task "%s".', source_ids{ii});
    end
    if ~task_outputs_exist(tasks(hit))
        error('run_delivery_online_resumable:missingSourceOutput', ...
            'Source task "%s" is not complete.', source_ids{ii});
    end
    source_tasks(end+1) = tasks(hit); %#ok<AGROW>
end
end

function packs = load_task_packs(source_tasks)
packs = cell(1, numel(source_tasks));
for ii = 1:numel(source_tasks)
    mat_file = latest_mat_file(source_tasks(ii).mat_pattern);
    packs{ii} = load(mat_file, 'results', 'metadata', 'cfg_run');
end
end

function mat_file = latest_mat_file(pattern)
hits = dir(pattern);
if isempty(hits)
    error('run_delivery_online_resumable:noMatFile', ...
        'No MAT file matches pattern "%s".', pattern);
end
[~, idx] = max([hits.datenum]);
mat_file = fullfile(hits(idx).folder, hits(idx).name);
end

function run_id = get_or_create_delivery_run_id(output_dir)
run_root = fullfile(output_dir, 'online_runs');
ensure_dir(run_root);
active_file = fullfile(run_root, '_ACTIVE_RUN_ID.txt');
if exist(active_file, 'file')
    fid = fopen(active_file, 'r');
    run_id = strtrim(fgetl(fid));
    fclose(fid);
else
    run_id = ['delivery_' timestamp_for_id()];
    fid = fopen(active_file, 'w');
    fprintf(fid, '%s\n', run_id);
    fclose(fid);
end
end

function write_delivery_run_info(run_root, run_id)
ensure_dir(run_root);
fid = fopen(fullfile(run_root, 'RUN_INFO.txt'), 'w');
fprintf(fid, 'run_id=%s\nrunner=run_delivery_online_resumable.m\ncheckpoint_grain=per_snr\nstarted_or_resumed_at=%s\n', ...
    run_id, timestamp_iso());
fclose(fid);
end

function append_task_status(run_root, task_id, status)
status_file = fullfile(run_root, 'TASK_STATUS.tsv');
need_header = exist(status_file, 'file') ~= 2;
fid = fopen(status_file, 'a');
if need_header
    fprintf(fid, 'timestamp\ttask_id\tstatus\n');
end
fprintf(fid, '%s\t%s\t%s\n', timestamp_iso(), task_id, status);
fclose(fid);
end

function write_task_done(done_file, task_id, elapsed_sec, status)
fid = fopen(done_file, 'w');
fprintf(fid, 'task=%s\nstatus=%s\nfinished_at=%s\nelapsed_sec=%.3f\n', ...
    task_id, status, timestamp_iso(), elapsed_sec);
fclose(fid);
end

function ensure_dir(path_name)
if ~exist(path_name, 'dir')
    mkdir(path_name);
end
end

function tag = snr_tag(snr)
if snr < 0
    prefix = 'm';
else
    prefix = 'p';
end
tag = sprintf('%s%g', prefix, abs(snr));
tag = strrep(tag, '.', 'p');
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
