% run_online_all_v4.m
% Resumable MATLAB Online master runner for the v4 workflow.
%
% Re-run the same command after a browser/network/session interruption:
%   run('run_online_all_v4.m')
%
% The script keeps a stable active run id in:
%   results/online_runs/_ACTIVE_RUN_ID.txt
%
% Each completed task writes:
%   results/online_runs/<run_id>/checkpoints/<task_id>.done

clear; clc;
online_runner = 'run_online_all_v4.m';
setup_online_paths();

online_run_id = get_or_create_online_run_id();
online_run_root = fullfile('results', 'online_runs', online_run_id);
checkpoint_dir = fullfile(online_run_root, 'checkpoints');
if ~exist(checkpoint_dir, 'dir'); mkdir(checkpoint_dir); end
write_online_run_note(online_run_id, online_runner);

fprintf('\n============================================================\n');
fprintf(' MATLAB Online resumable v4 master\n');
fprintf(' run_id: %s\n', online_run_id);
fprintf(' root:   %s\n', online_run_root);
fprintf('============================================================\n');

tasks = build_task_list(online_run_root);
for ii = 1:numel(tasks)
    task = tasks(ii);
    done_file = fullfile(checkpoint_dir, [task.id '.done']);
    if exist(done_file, 'file') && task_outputs_exist(task)
        fprintf('\n[%d/%d] SKIP %s (checkpoint exists)\n', ii, numel(tasks), task.id);
        continue;
    end

    fprintf('\n[%d/%d] START %s\n', ii, numel(tasks), task.id);
    fprintf('  %s\n', task.description);
    write_task_status(online_run_root, task.id, 'START');
    t_task = tic;

    switch task.kind
        case 'ber'
            run_ber_task(task, online_run_id, online_run_root, online_runner);
        case 'capacity'
            run_capacity_task(task, online_run_id, online_run_root, online_runner);
        otherwise
            error('Unknown task kind: %s', task.kind);
    end

    if ~task_outputs_exist(task)
        error('run_online_all_v4:missingOutput', ...
            'Task %s finished but expected output was not found.', task.id);
    end
    fid = fopen(done_file, 'w');
    fprintf(fid, 'task=%s\nstatus=DONE\nfinished_at=%s\nelapsed_sec=%.3f\n', ...
        task.id, datestr(now, 31), toc(t_task));
    fclose(fid);
    write_task_status(online_run_root, task.id, 'DONE');
    fprintf('[%d/%d] DONE %s in %.1f s\n', ii, numel(tasks), task.id, toc(t_task));
end

fprintf('\n============================================================\n');
fprintf(' All resumable v4 tasks are complete.\n');
fprintf(' Download this folder for local import:\n  %s\n', online_run_root);
fprintf('============================================================\n');

function tasks = build_task_list(run_root)
    ber_full_dir = fullfile(run_root, 'phase_e_v4_papersnr_perpath_nomask');
    ber_adapt_dir = fullfile(run_root, 'phase_e_v4_papersnr_perpath_nomask_adaptive');
    cap_dir = fullfile(run_root, 'phase_d3_capacity_3scheme_v4_paper');

    tasks = struct('id', {}, 'kind', {}, 'description', {}, 'out_dir', {}, ...
        'pas_list', {}, 'cv', {}, 'strategies_sel', {}, 'expected', {});

    tasks(end+1) = make_ber_task('ber_iso_full', ber_full_dir, ...
        'ISO full-load BER', {'isotropic'}, [], {'full'}, ...
        'E_isotropic_phase_e_v4_paper_SNR_3scheme_pas_isotropic_cv_1_00_d_eff_60_8x8.mat');
    tasks(end+1) = make_ber_task('ber_vmf010_full', ber_full_dir, ...
        'vMF cv=0.10 full-load BER', {'vmf'}, 0.10, {'full'}, ...
        'E_vmf_cv010_phase_e_v4_paper_SNR_3scheme_pas_vmf_cv_0_10_d_eff_23_8x8.mat');
    tasks(end+1) = make_ber_task('ber_vmf030_full', ber_full_dir, ...
        'vMF cv=0.30 full-load BER', {'vmf'}, 0.30, {'full'}, ...
        'E_vmf_cv030_phase_e_v4_paper_SNR_3scheme_pas_vmf_cv_0_30_d_eff_45_8x8.mat');
    tasks(end+1) = make_ber_task('ber_vmf010_adaptive', ber_adapt_dir, ...
        'vMF cv=0.10 adaptive BER ablation', {'vmf'}, 0.10, {'adaptive'}, ...
        'E_vmf_cv010_phase_e_v4_paper_SNR_3scheme_pas_vmf_cv_0_10_d_eff_23_8x8.mat');
    tasks(end+1) = make_ber_task('ber_vmf030_adaptive', ber_adapt_dir, ...
        'vMF cv=0.30 adaptive BER ablation', {'vmf'}, 0.30, {'adaptive'}, ...
        'E_vmf_cv030_phase_e_v4_paper_SNR_3scheme_pas_vmf_cv_0_30_d_eff_45_8x8.mat');

    task = struct();
    task.id = 'capacity_full';
    task.kind = 'capacity';
    task.description = 'vMF full-load capacity sweep';
    task.out_dir = cap_dir;
    task.pas_list = {};
    task.cv = [];
    task.strategies_sel = {'full'};
    task.expected = 'phase_d3_capacity_3scheme_v4_paper_*.mat';
    tasks(end+1) = task;
end

function task = make_ber_task(id, out_dir, description, pas_list, cv, strategies_sel, expected)
    task = struct();
    task.id = id;
    task.kind = 'ber';
    task.description = description;
    task.out_dir = out_dir;
    task.pas_list = pas_list;
    task.cv = cv;
    task.strategies_sel = strategies_sel;
    task.expected = expected;
end

function ok = task_outputs_exist(task)
    if ~isempty(strfind(task.expected, '*')) %#ok<STREMP>
        hits = dir(fullfile(task.out_dir, task.expected));
        ok = ~isempty(hits);
    else
        ok = exist(fullfile(task.out_dir, task.expected), 'file') == 2;
    end
end

function run_ber_task(task, run_id, run_root, runner)
    online_run_id = run_id; %#ok<NASGU>
    online_run_root = run_root; %#ok<NASGU>
    online_runner = runner; %#ok<NASGU>
    phase_e_use_parfor = false; %#ok<NASGU>
    pas_config        = '2cluster'; %#ok<NASGU>
    disable_prop_mask = true; %#ok<NASGU>
    use_perpath_sigma = true; %#ok<NASGU>
    adapt_power_floor = 0.10; %#ok<NASGU>
    channel_norm_mode = 'mrms'; %#ok<NASGU>
    verify_diagnosis_only = false; %#ok<NASGU>

    numFrames_default = 35; %#ok<NASGU>
    SNR_list          = -5:5:15; %#ok<NASGU>
    kappa_list        = [0, 0.1, 1.0]; %#ok<NASGU>
    strategies_sel    = task.strategies_sel; %#ok<NASGU>
    solver_sel        = 'direct'; %#ok<NASGU>
    csi_error_mode    = 'snr_coupled'; %#ok<NASGU>
    out_dir_override  = task.out_dir; %#ok<NASGU>
    pas_list          = task.pas_list; %#ok<NASGU>
    if ~isempty(task.cv); cv = task.cv; end %#ok<NASGU>
    run('run_phase_e_3scheme_csi_grid.m');
end

function run_capacity_task(task, run_id, run_root, runner)
    online_run_id = run_id; %#ok<NASGU>
    online_run_root = run_root; %#ok<NASGU>
    online_runner = runner; %#ok<NASGU>
    pas_config        = '2cluster'; %#ok<NASGU>
    disable_prop_mask = true; %#ok<NASGU>
    use_perpath_sigma = true; %#ok<NASGU>
    channel_norm_mode = 'mrms'; %#ok<NASGU>
    cap_out_tag       = '_v4_paper'; %#ok<NASGU>
    cap_out_dir_override = task.out_dir; %#ok<NASGU>
    cluster_var_list  = [0.01, 0.30, 1.00]; %#ok<NASGU>
    P_dBW_list        = 0:5:30; %#ok<NASGU>
    sigma2_fixed      = 1; %#ok<NASGU>
    numFrames_per_pt  = 30; %#ok<NASGU>
    USE_PARFOR        = false; %#ok<NASGU>
    NUM_WORKERS       = 1; %#ok<NASGU>
    strategies        = {'full'}; %#ok<NASGU>
    run('run_capacity_full_3scheme.m');
end

function run_id = get_or_create_online_run_id()
    root = fullfile('results', 'online_runs');
    if ~exist(root, 'dir'); mkdir(root); end
    active_file = fullfile(root, '_ACTIVE_RUN_ID.txt');
    if exist('online_run_id', 'var') && ~isempty(online_run_id)
        run_id = online_run_id;
    elseif exist(active_file, 'file')
        fid = fopen(active_file, 'r');
        run_id = strtrim(fgetl(fid));
        fclose(fid);
    else
        run_id = ['online_all_' datestr(now, 'yyyymmdd_HHMMSS')];
    end
    fid = fopen(active_file, 'w');
    fprintf(fid, '%s\n', run_id);
    fclose(fid);
end

function write_task_status(run_root, task_id, status)
    f = fullfile(run_root, 'TASK_STATUS.tsv');
    need_header = exist(f, 'file') ~= 2;
    fid = fopen(f, 'a');
    if need_header
        fprintf(fid, 'timestamp\ttask_id\tstatus\n');
    end
    fprintf(fid, '%s\t%s\t%s\n', datestr(now, 31), task_id, status);
    fclose(fid);
end

function setup_online_paths()
    root = fileparts(mfilename('fullpath'));
    addpath(root);
    addpath(fullfile(root, 'tools'));
    addpath(genpath(fullfile(root, 'variance')));
    addpath(genpath(fullfile(root, 'variance_aniso')));
    if exist(fullfile(root, '方差计算'), 'dir'); addpath(genpath(fullfile(root, '方差计算'))); end
end

function write_online_run_note(run_id, runner)
    run_root = fullfile('results', 'online_runs', run_id);
    if ~exist(run_root, 'dir'); mkdir(run_root); end
    commit = read_commit_marker();
    fid = fopen(fullfile(run_root, 'RUN_INFO.txt'), 'w');
    fprintf(fid, 'run_id=%s\nrunner=%s\nstarted_at=%s\ngit_commit=%s\n', ...
        run_id, runner, datestr(now, 31), commit);
    fclose(fid);
end

function commit = read_commit_marker()
    commit = 'unknown';
    pc = fullfile(pwd, '.provenance_commit');
    if exist(pc, 'file')
        fid = fopen(pc, 'r');
        if fid > 0
            line = strtrim(fgetl(fid)); fclose(fid);
            if ischar(line) && ~isempty(line); commit = line; return; end
        end
    end
    [s, out] = system('git rev-parse HEAD 2>nul');
    if s == 0; commit = strtrim(out); end
end
