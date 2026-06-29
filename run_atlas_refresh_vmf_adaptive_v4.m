% run_atlas_refresh_vmf_adaptive_v4.m
% One-click Win MATLAB runner for vMF adaptive BER ablation under paper v4.
%
% Scope:
%   - Runs vMF cv=0.10 and cv=0.30 adaptive BER only.
%   - Skips ISO.
%   - Skips ber3fv-* fixed_var seats.
%   - Does not run capacity.
%
% Paper-faithful v4 defaults:
%   - per-symbol SNR for BER, unit-average-power QAM.
%   - per-path Sigma2_p for vMF/NLoS, Eq.(32) sqrt(Mr*Ms) channel scaling.
%   - no frame-level channel renormalization.
%   - adaptive is an ablation: N_s=d_eff, metadata marks includes_adaptive_ablation.
%
% Run on Win GUI:
%   run('run_atlas_refresh_vmf_adaptive_v4.m')

clear; clc;
addpath('tools');

fprintf('\n============================================================\n');
fprintf(' Seat Atlas refresh: vMF adaptive v4 BER ablation\n');
fprintf(' Targets: vMF cv=0.10/cv=0.30 adaptive BER only\n');
fprintf(' Skipped: ISO, ber3fv-* fixed_var, capacity\n');
fprintf('============================================================\n');

ensure_parpool_local(6);

pas_config        = '2cluster';
disable_prop_mask = true;
use_perpath_sigma = true;
adapt_power_floor = 0.10;
channel_norm_mode = 'mrms';  % Eq.(32) paper scaling in current codebase corresponds to mrms normalization
verify_diagnosis_only = false;

numFrames_default = 35;
SNR_list          = -5:5:15;
kappa_list        = [0, 0.1, 1.0];
strategies_sel    = {'adaptive'};
solver_sel        = 'direct';
csi_error_mode    = 'snr_coupled';
out_dir_override  = fullfile('results', 'phase_e_v4_papersnr_perpath_nomask_adaptive');

fprintf('[BER adaptive] SNR_list = [%s] dB\n', num2str(SNR_list));
fprintf('[BER adaptive] out_dir = %s\n', out_dir_override);

fprintf('\n[BER 1/2] vMF cv=0.10 adaptive\n');
pas_list = {'vmf'};
cv = 0.10;
run('run_phase_e_3scheme_csi_grid.m');

fprintf('\n[BER 2/2] vMF cv=0.30 adaptive\n');
pas_list = {'vmf'};
cv = 0.30;
run('run_phase_e_3scheme_csi_grid.m');

fprintf('\n============================================================\n');
fprintf(' vMF adaptive v4 BER refresh done.\n');
fprintf(' BER output: results/phase_e_v4_papersnr_perpath_nomask_adaptive/\n');
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
