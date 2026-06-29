% run_online_adaptive_v4.m
% MATLAB Online vMF adaptive v4 BER ablation runner.
%
% Outputs are isolated under:
%   results/online_runs/<online_run_id>/

clear; clc;
online_runner = 'run_online_adaptive_v4.m';
if ~exist('online_run_id', 'var') || isempty(online_run_id)
    online_run_id = ['online_adaptive_' datestr(now, 'yyyymmdd_HHMMSS')];
end
setup_online_paths();
write_online_run_note(online_run_id, online_runner);

online_run_root = fullfile('results', 'online_runs', online_run_id);
if ~exist(online_run_root, 'dir'); mkdir(online_run_root); end

fprintf('\n============================================================\n');
fprintf(' MATLAB Online adaptive v4 BER ablation\n');
fprintf(' run_id: %s\n', online_run_id);
fprintf(' Targets: vMF cv=0.10/cv=0.30 adaptive only\n');
fprintf('============================================================\n');

pas_config        = '2cluster';
disable_prop_mask = true;
use_perpath_sigma = true;
adapt_power_floor = 0.10;
channel_norm_mode = 'mrms';
verify_diagnosis_only = false;

numFrames_default = 35;
SNR_list          = -5:5:15;
kappa_list        = [0, 0.1, 1.0];
strategies_sel    = {'adaptive'};
solver_sel        = 'direct';
csi_error_mode    = 'snr_coupled';
out_dir_override  = fullfile(online_run_root, 'phase_e_v4_papersnr_perpath_nomask_adaptive');

fprintf('\n[BER 1/2] vMF cv=0.10 adaptive\n');
pas_list = {'vmf'};
cv = 0.10;
run('run_phase_e_3scheme_csi_grid.m');

fprintf('\n[BER 2/2] vMF cv=0.30 adaptive\n');
pas_list = {'vmf'};
cv = 0.30;
run('run_phase_e_3scheme_csi_grid.m');

fprintf('\nAdaptive v4 online run done. Download: %s\n', online_run_root);

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
