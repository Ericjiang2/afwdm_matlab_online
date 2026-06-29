% run_online_smoke_v4.m
% MATLAB Online smoke test for the v4 paper-SNR / per-path / nomask chain.
%
% Run in MATLAB Online after clone/pull or after uploading the bundle:
%   run('run_online_smoke_v4.m')

clear; clc;
online_runner = 'run_online_smoke_v4.m';
if ~exist('online_run_id', 'var') || isempty(online_run_id)
    online_run_id = ['online_smoke_' datestr(now, 'yyyymmdd_HHMMSS')];
end
setup_online_paths();
write_online_run_note(online_run_id, online_runner);

online_run_root = fullfile('results', 'online_runs', online_run_id);
if ~exist(online_run_root, 'dir'); mkdir(online_run_root); end

fprintf('\n============================================================\n');
fprintf(' MATLAB Online smoke v4\n');
fprintf(' run_id: %s\n', online_run_id);
fprintf('============================================================\n');

%% BER smoke: ISO, one frame, one SNR/kappa point.
pas_config        = '2cluster';
disable_prop_mask = true;
use_perpath_sigma = true;
adapt_power_floor = 0.10;
channel_norm_mode = 'mrms';

numFrames_default = 1;
SNR_list          = 0;
kappa_list        = 0;
strategies_sel    = {'full'};
solver_sel        = 'direct';
csi_error_mode    = 'snr_coupled';
out_dir_override  = fullfile(online_run_root, 'phase_e_v4_papersnr_perpath_nomask');
pas_list          = {'isotropic'};

run('run_phase_e_3scheme_csi_grid.m');

%% Capacity smoke: one cv, one power point, serial.
clear out_dir_override pas_list cv;
online_runner     = 'run_online_smoke_v4.m';
pas_config        = '2cluster';
disable_prop_mask = true;
use_perpath_sigma = true;
channel_norm_mode = 'mrms';
cap_out_tag       = '_v4_paper';
cap_out_dir_override = fullfile(online_run_root, 'phase_d3_capacity_3scheme_v4_paper');
cluster_var_list  = 0.30;
P_dBW_list        = 0;
sigma2_fixed      = 1;
numFrames_per_pt  = 1;
USE_PARFOR        = false;
NUM_WORKERS       = 1;
strategies        = {'full'};

run('run_capacity_full_3scheme.m');

fprintf('\nSmoke done. Download or inspect: %s\n', online_run_root);

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
