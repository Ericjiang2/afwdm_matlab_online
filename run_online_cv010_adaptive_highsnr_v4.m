% run_online_cv010_adaptive_highsnr_v4.m
% MATLAB Online high-SNR audit for vMF cv=0.10 adaptive perfect-CSI BER.
%
% Scope:
%   - vMF cv=0.10 only
%   - adaptive N_s=d_eff only
%   - perfect CSI only (kappa=0)
%   - high-SNR tail only: SNR=[10 15] dB
%   - 500 frames per SNR
%   - frame_start_offset=35 to avoid repeating the existing atlas 35 frames
%
% Outputs are isolated under:
%   results/online_runs/<online_run_id>/phase_e_v4_cv010_adaptive_perfect_highsnr_500f/

clear; clc;
online_runner = 'run_online_cv010_adaptive_highsnr_v4.m';
if ~exist('online_run_id', 'var') || isempty(online_run_id)
    online_run_id = ['online_cv010_adapt_hisnr_' datestr(now, 'yyyymmdd_HHMMSS')];
end
setup_online_paths();
write_online_run_note(online_run_id, online_runner);

online_run_root = fullfile('results', 'online_runs', online_run_id);
out_dir_override = fullfile(online_run_root, 'phase_e_v4_cv010_adaptive_perfect_highsnr_500f');
if ~exist(out_dir_override, 'dir'); mkdir(out_dir_override); end

fprintf('\n============================================================\n');
fprintf(' MATLAB Online cv=0.10 adaptive perfect high-SNR audit\n');
fprintf(' run_id: %s\n', online_run_id);
fprintf(' SNR_list=[10 15], frames=500, offset=35, kappa=0, strategy=adaptive\n');
fprintf('============================================================\n');

phase_e_use_parfor = false;
pas_config        = '2cluster';
disable_prop_mask = true;
use_perpath_sigma = true;
adapt_power_floor = 0.10;
channel_norm_mode = 'mrms';
verify_diagnosis_only = false;

numFrames_default = 500;
frame_start_offset = 35;
SNR_list          = [10 15];
kappa_list        = 0;
strategies_sel    = {'adaptive'};
solver_sel        = 'direct';
csi_error_mode    = 'snr_coupled';
pas_list          = {'vmf'};
cv = 0.10;

tic;
run('run_phase_e_3scheme_csi_grid.m');
elapsed_sec = toc;

result_file = fullfile(out_dir_override, ...
    'E_vmf_cv010_phase_e_v4_paper_SNR_3scheme_pas_vmf_cv_0_10_d_eff_23_8x8.mat');
if ~exist(result_file, 'file')
    error('High-SNR result file not found: %s', result_file);
end

S = load(result_file, 'results', 'cfg', 'switches');
summary_path = fullfile(out_dir_override, 'HIGH_SNR_500F_SUMMARY.txt');
write_summary(summary_path, S, elapsed_sec, result_file);

fprintf('\nHigh-SNR cv010 adaptive audit done.\n');
fprintf('  summary: %s\n', summary_path);
fprintf('  output:  %s\n', out_dir_override);

function setup_online_paths()
    root = fileparts(mfilename('fullpath'));
    cd(root);
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

function write_summary(path, S, elapsed_sec, result_file)
    fid = fopen(path, 'w');
    if fid < 0; error('Cannot write high-SNR summary: %s', path); end
    cleanup = onCleanup(@() fclose(fid));

    ber = S.results.BER;
    err = S.results.err_total;
    tot = S.results.tot_total;
    SNR = S.results.SNR_dB(:).';
    schemes = S.results.schemes;
    bits_per_point = squeeze(tot(1, 1, :, 1));

    fprintf(fid, 'scope=vMF cv=0.10 adaptive perfect CSI high-SNR audit\n');
    fprintf(fid, 'result_file=%s\n', result_file);
    fprintf(fid, 'elapsed_sec=%.3f\n', elapsed_sec);
    fprintf(fid, 'numFrames=%d\n', S.switches.numFrames);
    fprintf(fid, 'frame_start_offset=%d\n', S.results.frame_start_offset);
    fprintf(fid, 'N_s=%d\n\n', S.results.Ns_used(1));
    fprintf(fid, 'SNR_dB\tscheme\tBER\terr\ttot\tzero_error_95_upper\n');
    for iS = 1:numel(SNR)
        zero95 = 3 / bits_per_point(iS);
        for iW = 1:numel(schemes)
            fprintf(fid, '%.0f\t%s\t%.10g\t%d\t%d\t%.10g\n', ...
                SNR(iS), schemes{iW}, ber(iW,1,iS,1), err(iW,1,iS,1), tot(iW,1,iS,1), zero95);
        end
    end
end
