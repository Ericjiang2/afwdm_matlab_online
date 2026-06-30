% run_online_iso_perfect_full_audit_v4.m
% ISO + perfect CSI + full-load high-SNR BER audit.
%
% First-round plan from timing smoke:
%   SNR  5 dB:  20 frames
%   SNR 10 dB: 150 frames
%   SNR 15 dB: 350 frames
%
% Each SNR is saved in a separate directory to avoid overwriting .mat files.
% Optional future continuation: edit the third column of audit_plan to set a
% nonzero frame_start_offset, so new batches do not repeat frame seeds.

clear; clc;
online_runner = 'run_online_iso_perfect_full_audit_v4.m';
if ~exist('online_run_id', 'var') || isempty(online_run_id)
    online_run_id = ['online_iso_full_audit_' datestr(now, 'yyyymmdd_HHMMSS')];
end
setup_online_paths();
write_online_run_note(online_run_id, online_runner);

online_run_root = fullfile('results', 'online_runs', online_run_id);
audit_root = fullfile(online_run_root, 'iso_perfect_full_highsnr_audit');
if ~exist(audit_root, 'dir'); mkdir(audit_root); end

% Columns: [SNR_dB, numFrames, frame_start_offset]
audit_plan = [
     5,  20, 0;
    10, 150, 0;
    15, 350, 0
];

fprintf('\n============================================================\n');
fprintf(' MATLAB Online ISO perfect/full high-SNR audit\n');
fprintf(' run_id: %s\n', online_run_id);
fprintf(' plan: [SNR_dB, frames, frame_start_offset]\n');
disp(audit_plan);
fprintf('============================================================\n');

records_cell = cell(1, size(audit_plan, 1));
for ii = 1:size(audit_plan, 1)
    records_cell{ii} = run_one_snr_audit(online_run_id, online_run_root, online_runner, ...
        audit_root, audit_plan(ii, 1), audit_plan(ii, 2), audit_plan(ii, 3));
end
records = [records_cell{:}];

summary_path = fullfile(audit_root, 'AUDIT_PLAN_SUMMARY.txt');
write_audit_summary(summary_path, records);
save(fullfile(audit_root, 'audit_plan_summary.mat'), 'records', 'audit_plan');

fprintf('\nAudit plan done.\n');
fprintf('  summary: %s\n', summary_path);
fprintf('  output:  %s\n', audit_root);

function rec = run_one_snr_audit(run_id, run_root, runner, audit_root, snr_db, n_frames, frame_offset)
    online_run_id = run_id; %#ok<NASGU>
    online_run_root = run_root; %#ok<NASGU>
    online_runner = runner; %#ok<NASGU>
    phase_e_use_parfor = false; %#ok<NASGU>

    snr_tag = sprintf('snr%02d_frames%04d_offset%06d', snr_db, n_frames, frame_offset);
    out_dir_override = fullfile(audit_root, snr_tag); %#ok<NASGU>

    pas_config        = '2cluster'; %#ok<NASGU>
    disable_prop_mask = true; %#ok<NASGU>
    use_perpath_sigma = true; %#ok<NASGU>
    adapt_power_floor = 0.10; %#ok<NASGU>
    channel_norm_mode = 'mrms'; %#ok<NASGU>
    verify_diagnosis_only = false; %#ok<NASGU>

    numFrames_default = n_frames; %#ok<NASGU>
    frame_start_offset = frame_offset; %#ok<NASGU>
    SNR_list          = snr_db; %#ok<NASGU>
    kappa_list        = 0; %#ok<NASGU>
    strategies_sel    = {'full'}; %#ok<NASGU>
    solver_sel        = 'direct'; %#ok<NASGU>
    csi_error_mode    = 'snr_coupled'; %#ok<NASGU>
    pas_list          = {'isotropic'}; %#ok<NASGU>

    fprintf('\n[AUDIT] SNR=%g dB, frames=%d, frame_start_offset=%d\n', ...
        snr_db, n_frames, frame_offset);
    tic;
    run('run_phase_e_3scheme_csi_grid.m');
    elapsed_sec = toc;

    result_file = fullfile(out_dir_override, ...
        'E_isotropic_phase_e_v4_paper_SNR_3scheme_pas_isotropic_cv_1_00_d_eff_60_8x8.mat');
    if ~exist(result_file, 'file')
        error('Audit result file not found: %s', result_file);
    end

    S = load(result_file, 'results', 'cfg', 'switches');
    ber = squeeze(S.results.BER(:, 1, 1, 1));
    bits_per_point = S.cfg.Nblk * S.results.Ns_used(1) * log2(4) * numFrames_default;
    err_est = round(ber(:) * bits_per_point);
    zero95 = 3 / bits_per_point;

    rec = struct();
    rec.SNR_dB = SNR_list(1);
    rec.numFrames = numFrames_default;
    rec.frame_start_offset = frame_start_offset;
    rec.bits_per_point = bits_per_point;
    rec.elapsed_sec = elapsed_sec;
    rec.sec_per_frame = elapsed_sec / numFrames_default;
    rec.schemes = S.results.schemes;
    rec.BER = ber(:).';
    rec.err_est = err_est(:).';
    rec.zero_error_95_upper = zero95;
    rec.result_file = result_file;
    rec.out_dir = out_dir_override;
end

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

function write_audit_summary(path, records)
    fid = fopen(path, 'w');
    if fid < 0; error('Cannot write audit summary: %s', path); end
    cleanup = onCleanup(@() fclose(fid));

    fprintf(fid, 'scope=ISO perfect CSI kappa=0 full-load high-SNR audit\n');
    fprintf(fid, 'columns=SNR_dB,frames,offset,bits,elapsed_sec,AFWDM_BER,AFWDM_err,DFT_BER,DFT_err,SVD_BER,SVD_err,zero_error_95_upper\n\n');
    fprintf(fid, 'SNR_dB\tframes\toffset\tbits\telapsed_sec\tAFWDM_BER\tAFWDM_err\tDFT_BER\tDFT_err\tSVD_BER\tSVD_err\tzero_error_95_upper\n');
    for i = 1:numel(records)
        r = records(i);
        fprintf(fid, '%.0f\t%d\t%d\t%d\t%.3f\t%.8g\t%d\t%.8g\t%d\t%.8g\t%d\t%.8g\n', ...
            r.SNR_dB, r.numFrames, r.frame_start_offset, r.bits_per_point, r.elapsed_sec, ...
            r.BER(1), r.err_est(1), r.BER(2), r.err_est(2), r.BER(3), r.err_est(3), ...
            r.zero_error_95_upper);
    end
end
