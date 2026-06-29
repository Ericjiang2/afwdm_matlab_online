% run_atlas_refresh_nonfixed_v4.m
% One-click Win MATLAB runner for Seat Atlas non-fixed-var paper v4 data.
%
% Scope:
%   - Resumes vMF cv=0.30 data for ber3-* seats (snr_coupled BER);
%     ISO and vMF cv=0.10 are assumed done.
%   - Refreshes data for cap-* seats (capacity sweep).
%   - Explicitly skips ber3fv-* fixed_var seats.
%   - Does not touch old D1/D2 diagnostic seats.
%
% Paper-faithful v4 defaults:
%   - per-symbol SNR for BER, unit-average-power QAM.
%   - per-path Sigma2_p for vMF/NLoS, Eq.(32) sqrt(Mr*Ms) channel scaling.
%   - no frame-level channel renormalization.
%   - full-load paper strategy only (ms streams).
%
% Run on Win GUI:
%   run('run_atlas_refresh_nonfixed_v4.m')

clear; clc;
addpath('tools');

fprintf('\n============================================================\n');
fprintf(' Seat Atlas refresh: non-fixed-var v4 paper data\n');
fprintf(' Targets: vMF cv=0.30 ber3-* + cap-* ; skipped: ISO/cv=0.10 BER and ber3fv-* fixed_var\n');
fprintf('============================================================\n');

ensure_parpool_local(6);

%% ===== Segment A: ber3-* BER, snr_coupled CSI error =====
fprintf('\n######## Segment A: ber3-* BER (snr_coupled, full-load) ########\n');

pas_config        = '2cluster';
disable_prop_mask = true;
use_perpath_sigma = true;
adapt_power_floor = 0.10;
channel_norm_mode = 'paper_eq32';

numFrames_default = 35;
SNR_list          = -5:5:15;
kappa_list        = [0, 0.1, 1.0];
strategies_sel    = {'full'};
solver_sel        = 'direct';
csi_error_mode    = 'snr_coupled';
out_dir_override  = fullfile('results', 'phase_e_v4_papersnr_perpath_nomask');

fprintf('[BER] SNR_list = [%s] dB\n', num2str(SNR_list));

fprintf('\n[BER 1/1] vMF cv=0.30 -> results/phase_e_v4_papersnr_perpath_nomask\n');
pas_list = {'vmf'};
cv = 0.30;
run('run_phase_e_3scheme_csi_grid.m');

%% ===== Segment C: cap-* capacity sweep =====
fprintf('\n######## Segment C: cap-* capacity (full-load, parfor) ########\n');

clear out_dir_override pas_list cv;
pas_config        = '2cluster';
disable_prop_mask = true;
use_perpath_sigma = true;
channel_norm_mode = 'paper_eq32';

cap_out_tag       = '_v4_paper';
cluster_var_list  = [0.01, 0.30, 1.00];
P_dBW_list        = 0:5:30;
sigma2_fixed      = 1;
numFrames_per_pt  = 30;
USE_PARFOR        = true;
NUM_WORKERS       = 6;
strategies        = {'full'};

run('run_capacity_full_3scheme.m');

fprintf('\n============================================================\n');
fprintf(' Atlas non-fixed-var v4 refresh done.\n');
fprintf(' BER output: results/phase_e_v4_papersnr_perpath_nomask/\n');
fprintf(' CAP output: results/phase_d3_capacity_3scheme_v4_paper/\n');
fprintf(' Next step after files sync back: update ber3-* and cap-* seat src_mat,\n');
fprintf(' then run atlas refresh/build. Fixed-var seats were intentionally skipped.\n');
fprintf('============================================================\n');

function ensure_parpool_local(num_workers)
    pool = gcp('nocreate');
    if ~isempty(pool) && pool.NumWorkers == num_workers
        fprintf('[parpool] reuse existing pool workers=%d\n', pool.NumWorkers);
        return;
    end
    if ~isempty(pool)
        fprintf('[parpool] recreate pool: old workers=%d, target=%d\n', ...
            pool.NumWorkers, num_workers);
        delete(pool);
    end
    try
        pool = parpool('Processes', num_workers);
    catch ME
        warning('Processes parpool failed (%s). Falling back to local profile.', ME.message);
        pool = parpool('local', num_workers);
    end
    fprintf('[parpool] ready workers=%d\n', pool.NumWorkers);
end
