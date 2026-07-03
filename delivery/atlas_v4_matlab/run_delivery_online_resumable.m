% run_delivery_online_resumable.m
% Resumable MATLAB Online runner for delivery paperfig tasks.
%
% Re-run this command after a browser/session interruption:
%   run('delivery/atlas_v4_matlab/run_delivery_online_resumable.m')
%
% Completed tasks write checkpoints under:
%   delivery/atlas_v4_matlab/outputs/online_runs/<run_id>/checkpoints/

clear; clc;

this_dir = fileparts(mfilename('fullpath'));
addpath(this_dir);

cfg0 = make_delivery_config("paperfig");
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
if ~exist(checkpoint_dir, 'dir')
    mkdir(checkpoint_dir);
end
write_delivery_run_info(run_root, run_id);

tasks = build_delivery_tasks(cfg0);

fprintf('\n============================================================\n');
fprintf(' Delivery online resumable runner\n');
fprintf(' run_id: %s\n', run_id);
fprintf(' root:   %s\n', run_root);
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
    fprintf('  mode=%s\n', task.mode);
    append_task_status(run_root, task.id, 'START');
    t_task = tic;

    run_delivery_mode(task.mode, this_dir);

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
fprintf(' Outputs: %s\n', cfg0.output_dir);
fprintf(' Checkpoints: %s\n', checkpoint_dir);
fprintf('============================================================\n');

function tasks = build_delivery_tasks(cfg0)
output_dir = cfg0.output_dir;
low = cfg0.low_mimo;
tasks = struct('id', {}, 'mode', {}, 'mat_pattern', {}, 'png_files', {});
tasks(end+1) = make_task('ber_strict_isotropic', 'paperfig_iso', ...
    fullfile(output_dir, 'atlas_v4_delivery_paperfig_iso_*.mat'), ...
    {fullfile(output_dir, 'figures', 'ber_strict_isotropic_perfect_vs_fixedvar.png')});
tasks(end+1) = make_task('ber_vmf_cv030', 'paperfig_vmf', ...
    fullfile(output_dir, 'atlas_v4_delivery_paperfig_vmf_*.mat'), ...
    {fullfile(output_dir, 'figures', 'ber_vmf_cv030_perfect_vs_fixedvar.png')});
tasks(end+1) = make_task('capacity_raw', 'paperfig_capacity', ...
    fullfile(output_dir, 'atlas_v4_delivery_paperfig_capacity_*.mat'), ...
    {fullfile(output_dir, 'figures', 'capacity_raw_doubly_selective.png')});
tasks(end+1) = make_task('low_mimo_precoding', 'paperfig_low_mimo', ...
    fullfile(output_dir, 'atlas_v4_delivery_paperfig_low_mimo_*.mat'), ...
    {fullfile(output_dir, 'figures', sprintf('ber_low_mimo_%dx%d_ns%d_precoding.png', ...
        low.array_shape(1), low.array_shape(2), low.N_s))});
end

function task = make_task(id, mode, mat_pattern, png_files)
task = struct('id', id, 'mode', mode, 'mat_pattern', mat_pattern, 'png_files', {png_files});
end

function ok = task_outputs_exist(task)
hits = dir(task.mat_pattern);
ok = ~isempty(hits);
for ii = 1:numel(task.png_files)
    ok = ok && exist(task.png_files{ii}, 'file') == 2;
end
end

function run_delivery_mode(task_mode, this_dir)
mode = string(task_mode); %#ok<NASGU>
run_capacity = []; %#ok<NASGU>
run(fullfile(this_dir, 'main_atlas_v4_delivery.m'));
end

function run_id = get_or_create_delivery_run_id(output_dir)
run_root = fullfile(output_dir, 'online_runs');
if ~exist(run_root, 'dir')
    mkdir(run_root);
end
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
if ~exist(run_root, 'dir')
    mkdir(run_root);
end
fid = fopen(fullfile(run_root, 'RUN_INFO.txt'), 'w');
fprintf(fid, 'run_id=%s\nrunner=run_delivery_online_resumable.m\nstarted_or_resumed_at=%s\n', ...
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

function s = timestamp_for_id()
s = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
end

function s = timestamp_iso()
s = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss'));
end
