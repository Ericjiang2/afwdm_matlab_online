% run_online_iso_perfect_full_smoke_v4.m
% Timing smoke for ISO + perfect CSI + full-load Phase E BER.
%
% Purpose:
%   Measure how long one serial MATLAB Online frame costs before choosing a
%   larger adaptive frame budget for the high-SNR AFWDM-vs-SVD audit.
%
% Run in MATLAB Online:
%   run('run_online_iso_perfect_full_smoke_v4.m')

clear; clc;
online_runner = 'run_online_iso_perfect_full_smoke_v4.m';
if ~exist('online_run_id', 'var') || isempty(online_run_id)
    online_run_id = ['online_iso_full_smoke_' datestr(now, 'yyyymmdd_HHMMSS')];
end
setup_online_paths();
write_online_run_note(online_run_id, online_runner);

online_run_root = fullfile('results', 'online_runs', online_run_id);
if ~exist(online_run_root, 'dir'); mkdir(online_run_root); end
smoke_out_dir = fullfile(online_run_root, 'iso_perfect_full_timing_smoke');

fprintf('\n============================================================\n');
fprintf(' MATLAB Online ISO perfect/full timing smoke\n');
fprintf(' run_id: %s\n', online_run_id);
fprintf(' target: ISO, kappa=0, full, SNR=[5 10 15], one frame/SNR\n');
fprintf('============================================================\n');

phase_e_use_parfor = false;
pas_config        = '2cluster';
disable_prop_mask = true;
use_perpath_sigma = true;
adapt_power_floor = 0.10;
channel_norm_mode = 'mrms';
verify_diagnosis_only = false;

numFrames_default = 1;
SNR_list          = [5 10 15];
kappa_list        = 0;
strategies_sel    = {'full'};
solver_sel        = 'direct';
csi_error_mode    = 'snr_coupled';
out_dir_override  = smoke_out_dir;
pas_list          = {'isotropic'};
QAM_order         = 4;

tic;
run('run_phase_e_3scheme_csi_grid.m');
elapsed_sec = toc;

smoke_out_dir = out_dir_override;
qam_order_smoke = 4;
result_file = fullfile(smoke_out_dir, ...
    'E_isotropic_phase_e_v4_paper_SNR_3scheme_pas_isotropic_cv_1_00_d_eff_60_8x8.mat');
if ~exist(result_file, 'file')
    error('Smoke result file not found: %s', result_file);
end

S = load(result_file, 'results', 'cfg', 'switches');
ber = squeeze(S.results.BER(:, 1, :, 1));  % [scheme, SNR] for full/kappa=0
if isvector(ber); ber = reshape(ber, [], numel(SNR_list)); end
bits_per_point = S.cfg.Nblk * S.results.Ns_used(1) * log2(qam_order_smoke) * numFrames_default;
err_est = round(ber * bits_per_point);
sec_per_frame_snr = elapsed_sec / (numFrames_default * numel(SNR_list));

summary = struct();
summary.online_run_id = online_run_id;
summary.runner = online_runner;
summary.scope = 'ISO perfect CSI kappa=0 full-load timing smoke';
summary.SNR_list = SNR_list;
summary.numFrames_per_SNR = numFrames_default;
summary.bits_per_point = bits_per_point;
summary.elapsed_sec = elapsed_sec;
summary.sec_per_frame_snr = sec_per_frame_snr;
summary.schemes = S.results.schemes;
summary.BER = ber;
summary.err_est = err_est;
summary.result_file = result_file;

save(fullfile(smoke_out_dir, 'iso_perfect_full_timing_summary.mat'), 'summary');
write_timing_summary(fullfile(smoke_out_dir, 'TIMING_SUMMARY.txt'), summary);

fprintf('\nTiming smoke done.\n');
fprintf('  elapsed_sec        = %.3f\n', elapsed_sec);
fprintf('  sec_per_frame_snr  = %.3f\n', sec_per_frame_snr);
fprintf('  summary: %s\n', fullfile(smoke_out_dir, 'TIMING_SUMMARY.txt'));

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

function write_timing_summary(path, summary)
    fid = fopen(path, 'w');
    if fid < 0; error('Cannot write timing summary: %s', path); end
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, 'scope=%s\n', summary.scope);
    fprintf(fid, 'run_id=%s\n', summary.online_run_id);
    fprintf(fid, 'runner=%s\n', summary.runner);
    fprintf(fid, 'elapsed_sec=%.6f\n', summary.elapsed_sec);
    fprintf(fid, 'sec_per_frame_snr=%.6f\n', summary.sec_per_frame_snr);
    fprintf(fid, 'numFrames_per_SNR=%d\n', summary.numFrames_per_SNR);
    fprintf(fid, 'bits_per_point=%d\n', summary.bits_per_point);
    fprintf(fid, '\nSNR_dB');
    for i = 1:numel(summary.SNR_list); fprintf(fid, '\t%.0f', summary.SNR_list(i)); end
    fprintf(fid, '\n');
    for k = 1:numel(summary.schemes)
        name = char(summary.schemes{k});
        fprintf(fid, '%s_BER', name);
        for i = 1:numel(summary.SNR_list); fprintf(fid, '\t%.8g', summary.BER(k, i)); end
        fprintf(fid, '\n%s_err_est', name);
        for i = 1:numel(summary.SNR_list); fprintf(fid, '\t%d', summary.err_est(k, i)); end
        fprintf(fid, '\n');
    end
end
