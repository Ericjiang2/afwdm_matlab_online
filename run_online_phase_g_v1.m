% run_online_phase_g_v1.m
% MATLAB Online Phase-G production runner: channel-estimation NMSE (Stage B)
% and paired operator-PCG BER (Stage C) for AFWDM vs MIMO-AFDM.
%
% Resumable by design. Per-(task, scenario, chunk) checkpoints live under
%   results/online_runs/<online_run_id>/checkpoints/
% Re-running this script with the same online_run_id skips completed chunks
% and finally merges checkpoints into per-scenario combined MAT files.
%
% Optional overrides (set in the workspace before running):
%   online_run_id             = 'phase_g_v2';      % keep fixed to resume
%   phase_g_task              = 'all';             % 'nmse' | 'ber' | 'all'
%   phase_g_scenarios         = {'isotropic', 'vmf'};
%   phase_g_nmse_frames       = 200;
%   phase_g_ber_frames        = 50;
%   phase_g_chunk_frames      = 10;
%   phase_g_pilot_snr_list    = 0:5:40;            % NMSE pilot-SNR sweep
%   phase_g_ber_data_snr_list = 0:5:25;            % BER data-SNR sweep
%   phase_g_smoke             = true;              % 1-frame local smoke preset

clearvars -except online_run_id phase_g_task phase_g_scenarios ...
    phase_g_nmse_frames phase_g_ber_frames phase_g_chunk_frames ...
    phase_g_pilot_snr_list phase_g_ber_data_snr_list phase_g_smoke;
clc;

online_runner = 'run_online_phase_g_v1.m';
if ~exist('online_run_id', 'var') || isempty(online_run_id)
    % v2: v1 checkpoints predate the cc-0711-05 nomask fix and must not be
    % resumed; a fresh default id keeps a plain rerun from skipping chunks.
    online_run_id = 'phase_g_v2';
end
if ~exist('phase_g_task', 'var') || isempty(phase_g_task)
    phase_g_task = 'all';
end
if ~exist('phase_g_scenarios', 'var') || isempty(phase_g_scenarios)
    phase_g_scenarios = {'isotropic', 'vmf'};
end
if ~exist('phase_g_nmse_frames', 'var') || isempty(phase_g_nmse_frames)
    phase_g_nmse_frames = 200;
end
if ~exist('phase_g_ber_frames', 'var') || isempty(phase_g_ber_frames)
    phase_g_ber_frames = 50;
end
if ~exist('phase_g_chunk_frames', 'var') || isempty(phase_g_chunk_frames)
    phase_g_chunk_frames = 10;
end
if ~exist('phase_g_pilot_snr_list', 'var') || isempty(phase_g_pilot_snr_list)
    phase_g_pilot_snr_list = 0:5:40;
end
if ~exist('phase_g_ber_data_snr_list', 'var') || isempty(phase_g_ber_data_snr_list)
    phase_g_ber_data_snr_list = 0:5:25;
end
if ~exist('phase_g_smoke', 'var') || isempty(phase_g_smoke)
    phase_g_smoke = false;
end
if phase_g_smoke
    phase_g_scenarios = {'isotropic'};
    phase_g_nmse_frames = 1;
    phase_g_ber_frames = 1;
    phase_g_chunk_frames = 1;
    phase_g_pilot_snr_list = [20, 40];
    phase_g_ber_data_snr_list = [0, 25];
    online_run_id = [online_run_id, '_smoke'];
end

setup_online_paths();
online_run_root = fullfile('results', 'online_runs', online_run_id);
checkpoint_root = fullfile(online_run_root, 'checkpoints');
if ~exist(checkpoint_root, 'dir'); mkdir(checkpoint_root); end
write_online_run_note(online_run_id, online_runner);

fprintf('\n============================================================\n');
fprintf(' Phase-G online production run (NMSE + paired BER)\n');
fprintf(' run_id: %s | task: %s | smoke: %d\n', online_run_id, phase_g_task, phase_g_smoke);
fprintf(' scenarios: %s\n', strjoin(phase_g_scenarios, ', '));
fprintf(' nmse_frames=%d ber_frames=%d chunk=%d\n', ...
    phase_g_nmse_frames, phase_g_ber_frames, phase_g_chunk_frames);
fprintf('============================================================\n');

tasks = {};
if any(strcmpi(phase_g_task, {'nmse', 'all'})); tasks{end + 1} = 'nmse'; end
if any(strcmpi(phase_g_task, {'ber', 'all'})); tasks{end + 1} = 'ber'; end

for i_task = 1:numel(tasks)
    task = tasks{i_task};
    if strcmp(task, 'nmse')
        total_frames = phase_g_nmse_frames;
    else
        total_frames = phase_g_ber_frames;
    end
    n_chunks = ceil(total_frames / phase_g_chunk_frames);

    for i_scenario = 1:numel(phase_g_scenarios)
        scenario = phase_g_scenarios{i_scenario};
        fprintf('\n[%s | %s] %d frames in %d chunks\n', ...
            upper(task), scenario, total_frames, n_chunks);

        chunk_files = cell(1, n_chunks);
        for k = 1:n_chunks
            chunk_start = (k - 1) * phase_g_chunk_frames + 1;
            chunk_frames = min(phase_g_chunk_frames, total_frames - chunk_start + 1);
            chunk_files{k} = fullfile(checkpoint_root, sprintf( ...
                'phase_g_%s_%s_chunk%03dof%03d.mat', task, scenario, k, n_chunks));
            if exist(chunk_files{k}, 'file')
                fprintf('  chunk %d/%d already done, skip.\n', k, n_chunks);
                continue;
            end

            opts = struct();
            opts.scenarios = {scenario};
            opts.num_frames = chunk_frames;
            opts.data_snr_db = 15;
            opts.pfa_total = 1e-3;
            opts.save_results = false;
            opts.max_selected_modes = Inf;
            opts.seed_offset = 1000 * (chunk_start - 1);
            if strcmp(task, 'nmse')
                opts.pilot_snr_db = phase_g_pilot_snr_list;
                opts.include_ber = false;
            else
                opts.pilot_snr_db = 20;
                opts.include_ber = true;
                opts.ber_data_snr_db = phase_g_ber_data_snr_list;
                opts.ber_linked_pilot_offset_db = 10;
                opts.ber_fixed_pilot_snr_db = 25;
                opts.ber_solver = 'pcg';
                opts.ber_pcg_tol = 1e-6;
                opts.ber_pcg_max_iter = 5000;
            end

            t_chunk = tic;
            chunk_result = run_phase_g_channel_estimation(opts);
            chunk_meta = struct( ...
                'task', task, 'scenario', scenario, ...
                'chunk_index', k, 'n_chunks', n_chunks, ...
                'frame_start', chunk_start, ...
                'frame_count', chunk_frames, ...
                'seed_offset', opts.seed_offset, ...
                'elapsed_s', toc(t_chunk), ...
                'finished_at', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), ...
                'runner', online_runner, ...
                'git_commit', read_commit_marker());
            save(chunk_files{k}, 'chunk_result', 'chunk_meta', '-v7.3');
            fprintf('  chunk %d/%d done in %.1fs -> %s\n', ...
                k, n_chunks, chunk_meta.elapsed_s, chunk_files{k});
        end

        combined = combine_phase_g_chunks(chunk_files, task);
        combined.run_id = online_run_id;
        combined.task = task;
        combined.scenario_label = scenario;
        combined.total_frames = total_frames;
        combined_file = fullfile(online_run_root, sprintf( ...
            'phase_g_%s_%s_combined.mat', task, scenario));
        save(combined_file, 'combined', '-v7.3');
        fprintf('  combined -> %s\n', combined_file);
        print_phase_g_summary(combined, task);
    end
end

if phase_g_smoke
    fprintf('\nPHASE_G_ONLINE_SMOKE_OK run_id=%s\n', online_run_id);
end
fprintf('\nPhase-G online run done. Download folder: %s\n', online_run_root);

function setup_online_paths()
    root = fileparts(mfilename('fullpath'));
    addpath(root);
    if exist(fullfile(root, 'tools'), 'dir'); addpath(fullfile(root, 'tools')); end
    if exist(fullfile(root, 'variance'), 'dir')
        addpath(genpath(fullfile(root, 'variance')));
    end
    if exist(fullfile(root, 'variance_aniso'), 'dir')
        addpath(genpath(fullfile(root, 'variance_aniso')));
    end
    if exist(fullfile(root, '方差计算'), 'dir')
        addpath(genpath(fullfile(root, '方差计算')));
    end
end

function write_online_run_note(run_id, runner)
    run_root = fullfile('results', 'online_runs', run_id);
    if ~exist(run_root, 'dir'); mkdir(run_root); end
    fid = fopen(fullfile(run_root, 'RUN_INFO.txt'), 'a');
    fprintf(fid, 'run_id=%s\nrunner=%s\nstarted_at=%s\ngit_commit=%s\n---\n', ...
        run_id, runner, char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), ...
        read_commit_marker());
    fclose(fid);
end

function commit = read_commit_marker()
    commit = 'unknown';
    marker = fullfile(fileparts(mfilename('fullpath')), '.provenance_commit');
    if exist(marker, 'file')
        fid = fopen(marker, 'r');
        if fid > 0
            line = strtrim(fgetl(fid));
            fclose(fid);
            if ischar(line) && ~isempty(line); commit = line; end
        end
    end
end

function combined = combine_phase_g_chunks(chunk_files, task)
    chunks = cell(1, numel(chunk_files));
    for k = 1:numel(chunk_files)
        loaded = load(chunk_files{k}, 'chunk_result', 'chunk_meta');
        chunks{k} = loaded;
    end

    first = chunks{1}.chunk_result.scenarios(1);
    combined = struct();
    combined.label = first.label;
    combined.scheme_names = first.scheme_names;
    combined.chunk_meta = cellfun(@(c) c.chunk_meta, chunks);

    if strcmp(task, 'nmse')
        combined.method_names = first.method_names;
        combined.pilot_snr_db = first.pilot_snr_db;
        combined.data_snr_db = first.data_snr_db;
        combined.selected_modes = first.selected_modes;
        combined.candidate_pairs = first.candidate_pairs;
        combined.nmse_modal = cat_scenario_field(chunks, 'nmse_modal', 4);
        combined.ce_time_s = cat_scenario_field(chunks, 'ce_time_s', 4);
        combined.support_size = cat_scenario_field(chunks, 'support_size', 4);
        combined.support_precision = cat_scenario_field(chunks, 'support_precision', 4);
        combined.support_recall = cat_scenario_field(chunks, 'support_recall', 4);
        combined.support_exact = cat_scenario_field(chunks, 'support_exact', 4);
        combined.effective_support_size = cat_scenario_field(chunks, 'effective_support_size', 2);
        combined.oracle_support_exact = cat_scenario_field(chunks, 'oracle_support_exact', 2);
        combined.nmse_mean = mean(combined.nmse_modal, 4);
    else
        first_ber = first.ber;
        combined.detector_names = first_ber.detector_names;
        combined.pilot_modes = first_ber.pilot_modes;
        combined.data_snr_db = first_ber.data_snr_db;
        combined.linked_pilot_offset_db = first_ber.linked_pilot_offset_db;
        combined.fixed_pilot_snr_db = first_ber.fixed_pilot_snr_db;
        combined.pilot_snr_used_db = first_ber.pilot_snr_used_db;
        combined.bits_per_frame = first_ber.bits_per_frame;
        combined.solver = first_ber.solver;
        combined.error_bits = cat_ber_field(chunks, 'error_bits');
        combined.solver_flag = cat_ber_field(chunks, 'solver_flag');
        combined.solver_iter = cat_ber_field(chunks, 'solver_iter');
        combined.detect_time_s = cat_ber_field(chunks, 'detect_time_s');
        n_frames_total = size(combined.error_bits, 5);
        combined.ber = sum(combined.error_bits, 5) / ...
            (combined.bits_per_frame * n_frames_total);
    end
end

function value = cat_scenario_field(chunks, field_name, dim)
    parts = cellfun(@(c) c.chunk_result.scenarios(1).(field_name), ...
        chunks, 'UniformOutput', false);
    value = cat(dim, parts{:});
end

function value = cat_ber_field(chunks, field_name)
    parts = cellfun(@(c) c.chunk_result.scenarios(1).ber.(field_name), ...
        chunks, 'UniformOutput', false);
    value = cat(5, parts{:});
end

function print_phase_g_summary(combined, task)
    if strcmp(task, 'nmse')
        i_last = numel(combined.pilot_snr_db);
        fprintf('  NMSE @ pilot %g dB (mean over %d frames):\n', ...
            combined.pilot_snr_db(i_last), size(combined.nmse_modal, 4));
        for i_scheme = 1:numel(combined.scheme_names)
            for i_method = 1:numel(combined.method_names)
                fprintf('    %-10s %-20s %.3e\n', ...
                    combined.scheme_names{i_scheme}, ...
                    combined.method_names{i_method}, ...
                    combined.nmse_mean(i_scheme, i_method, i_last, 1));
            end
        end
    else
        i_last = numel(combined.data_snr_db);
        fprintf('  paired BER @ data %g dB (%d frames, %d bits/frame):\n', ...
            combined.data_snr_db(i_last), size(combined.error_bits, 5), ...
            combined.bits_per_frame);
        for i_mode = 1:numel(combined.pilot_modes)
            for i_scheme = 1:numel(combined.scheme_names)
                for i_det = 1:numel(combined.detector_names)
                    fprintf('    %-11s %-10s %-16s %.3e\n', ...
                        combined.pilot_modes{i_mode}, ...
                        combined.scheme_names{i_scheme}, ...
                        combined.detector_names{i_det}, ...
                        combined.ber(i_scheme, i_det, i_mode, i_last));
                end
            end
        end
        max_flag = max(combined.solver_flag(:));
        fprintf('  PCG convergence: max flag = %g (0 means all converged)\n', max_flag);
    end
end
