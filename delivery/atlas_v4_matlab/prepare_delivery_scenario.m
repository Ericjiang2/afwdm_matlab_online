function scenario = prepare_delivery_scenario(cfg_run, scenario_spec)
%PREPARE_DELIVERY_SCENARIO  Build PAS statistics and base cfg for delivery code.
%
% 这个文件替代旧探索脚本 AFDM_AFWDM_Compare.m 的 prepare_scenario_only
% wrapper 用法。这里只保留最新 atlas v4 需要的显式步骤:
%   1. 8x8 UPA + AFDM physical parameters
%   2. PAS -> Tx/Rx modal variances
%   3. Sigma2 = Pr * Ps^T
%   4. vMF per-path Sigma2_p, matching main.pdf Eq.(26)-(32)
%   5. Unit 2D-DFT bases Us_full/Ur_full
%
% main.pdf 对应:
%   - Eq.(1): 2D Fourier basis on the aperture
%   - Eq.(21)-(27): PAS / per-path statistical structure
%   - Eq.(31)-(32): per-path spatial channel scaling
%
% 最新 atlas v4 差异:
%   - 默认 disable_prop_mask=true, 即不再用 center-mask 截掉边缘 bin;
%     mode selection 由 select_modes_atlas_v4.m 使用 overlap/nomask 完成。

cfg = struct();

c0 = 3e8;
cfg.fc = cfg_run.fc;
cfg.lambda = c0 / cfg.fc;
cfg.v_max_kmh = cfg_run.v_max_kmh;
cfg.v_max = cfg.v_max_kmh / 3.6;
cfg.Deltaf = cfg_run.Deltaf;
cfg.Tsym = 1 / cfg.Deltaf;
cfg.Nblk = cfg_run.Nblk;
cfg.Ts = 1 / (cfg.Nblk * cfg.Deltaf);
cfg.nu_max = cfg.v_max / cfg.lambda;
cfg.kmax = ceil(cfg.nu_max / cfg.Deltaf);
cfg.tau_max = cfg_run.tau_max_us * 1e-6;
cfg.lmax = ceil(cfg.tau_max / cfg.Ts);
cfg.afdm_diversity_lhs = 2 * cfg.kmax * (cfg.lmax + 1) + cfg.lmax;
if cfg.afdm_diversity_lhs >= cfg.Nblk
    error('prepare_delivery_scenario:diversityCondition', ...
        'AFDM diversity condition violated: %d < %d is false.', ...
        cfg.afdm_diversity_lhs, cfg.Nblk);
end
cfg.c1 = (2 * cfg.kmax + 1) / (2 * cfg.Nblk);
cfg.c2 = 0.1 / cfg.Nblk;
cfg.Lch = 4;

cfg.Msx = cfg_run.array_shape(1);
cfg.Msy = cfg_run.array_shape(2);
cfg.Mrx = cfg_run.array_shape(1);
cfg.Mry = cfg_run.array_shape(2);
cfg.Ms = cfg.Msx * cfg.Msy;
cfg.Mr = cfg.Mrx * cfg.Mry;
cfg.dx = cfg_run.dx;
cfg.dy = cfg_run.dy;
cfg.Lsx = cfg.Msx * cfg.dx;
cfg.Lsy = cfg.Msy * cfg.dy;
cfg.Lrx = cfg.Mrx * cfg.dx;
cfg.Lry = cfg.Mry * cfg.dy;
cfg.sz = 0;
cfg.rz = 0;
cfg.pcg_max_iter = 150;
cfg.pcg_tol = 1e-7;
cfg.block_lmmse_solver = cfg_run.block_lmmse_solver;
cfg.disable_prop_mask = cfg_run.disable_prop_mask;
cfg.channel_norm_mode = cfg_run.channel_norm_mode;

cfg.Us_full = make_2d_dft(cfg.Msx, cfg.Msy);
cfg.Ur_full = make_2d_dft(cfg.Mrx, cfg.Mry);

cfg.pas_model = scenario_spec.pas_model;
cfg.pas_config = cfg_run.pas_config;
cfg.vmf_mean_theta_deg = cfg_run.vmf_mean_theta_deg;
cfg.vmf_mean_phi_deg = cfg_run.vmf_mean_phi_deg;
if strcmpi(cfg.pas_model, 'vmf')
    cfg.vmf_circular_var = scenario_spec.cv * ones(1, numel(cfg.vmf_mean_theta_deg));
else
    cfg.vmf_circular_var = [];
end

switch lower(cfg.pas_model)
    case 'vmf'
        mean_theta_rad = cfg.vmf_mean_theta_deg / 180 * pi;
        mean_phi_rad = cfg.vmf_mean_phi_deg / 180 * pi;
        evalc('pas_channel = function_channelPAS(cfg.vmf_circular_var, mean_theta_rad, mean_phi_rad);');
        var_s_raw = function_channelVAR(cfg.Lsx, cfg.Lsy, pas_channel);
        var_r_raw = function_channelVAR(cfg.Lrx, cfg.Lry, pas_channel);
        Ps_shift_raw = var_s_raw.';
        Pr_shift_raw = var_r_raw.';

    case {'isotropic', 'isotropic_reference'}
        [var_s_raw, ~] = function_computeVar(cfg.Lsx, cfg.Lsy);
        [var_r_raw, ~] = function_computeVar(cfg.Lrx, cfg.Lry);
        Ps_shift_raw = var_s_raw.';
        Pr_shift_raw = var_r_raw.';

    otherwise
        error('prepare_delivery_scenario:unknownPAS', ...
            'Unknown PAS model "%s".', cfg.pas_model);
end

[idx_s_prop, n_prop_s] = select_center_modes_2d_overlap(cfg.Msx, cfg.Msy, 0, cfg.dx, cfg.dy);
[idx_r_prop, n_prop_r] = select_center_modes_2d_overlap(cfg.Mrx, cfg.Mry, 0, cfg.dx, cfg.dy);
cfg.idx_s_prop = idx_s_prop(:).';
cfg.idx_r_prop = idx_r_prop(:).';
cfg.ns_prop = n_prop_s;
cfg.nr_prop = n_prop_r;
cfg.ms = min(n_prop_s, n_prop_r);
cfg.mr = cfg.ms;
cfg.Nstreams = cfg.ms;

[KX_s, KY_s] = ndgrid((0:cfg.Msx-1) - floor(cfg.Msx/2), ...
                      (0:cfg.Msy-1) - floor(cfg.Msy/2));
[KX_r, KY_r] = ndgrid((0:cfg.Mrx-1) - floor(cfg.Mrx/2), ...
                      (0:cfg.Mry-1) - floor(cfg.Mry/2));
kappa2_s = (KX_s / cfg.Lsx).^2 + (KY_s / cfg.Lsy).^2;
kappa2_r = (KX_r / cfg.Lrx).^2 + (KY_r / cfg.Lry).^2;
prop_mask_s = kappa2_s <= 1.0;
prop_mask_r = kappa2_r <= 1.0;
if cfg.disable_prop_mask
    prop_mask_s(:) = true;
    prop_mask_r(:) = true;
end

Ps_shift = Ps_shift_raw .* prop_mask_s;
Pr_shift = Pr_shift_raw .* prop_mask_r;
Ps = ifftshift(Ps_shift);
Pr = ifftshift(Pr_shift);
Ps = Ps / sum(Ps(:));
Pr = Pr / sum(Pr(:));
Sigma2 = Pr(:) * (Ps(:).');
Sigma2 = Sigma2 / sum(Sigma2(:));

Ds = ones(cfg.Ms, 1);
Dr = ones(cfg.Mr, 1);

Sigma2_p = {};
use_perpath_sigma = strcmpi(cfg.pas_model, 'vmf') && scenario_spec.use_perpath_sigma;
if use_perpath_sigma
    evalc('Sigma2_p = build_perpath_sigma(cfg);');
    cfg.Lch = numel(Sigma2_p);
end

sigma_mass_sum = 0;
if use_perpath_sigma
    for ell = 1:numel(Sigma2_p)
        sigma_mass_sum = sigma_mass_sum + sum(Sigma2_p{ell}(:));
    end
else
    sigma_mass_sum = sum(Sigma2(:));
end
if abs(sigma_mass_sum - 1) > 1e-8
    error('prepare_delivery_scenario:sigmaMass', ...
        'Expected total Sigma mass 1, got %.16g.', sigma_mass_sum);
end

scenario = struct();
scenario.label = scenario_spec.label;
scenario.cfg = cfg;
scenario.Sigma2 = Sigma2;
scenario.Sigma2_p = Sigma2_p;
scenario.Dr = Dr;
scenario.Ds = Ds;
scenario.Ps = Ps;
scenario.Pr = Pr;
scenario.use_perpath_sigma = use_perpath_sigma;
scenario.sigma_mass_sum = sigma_mass_sum;
scenario.notes = struct( ...
    'mode_selector', cfg_run.mode_selector, ...
    'channel_scaling', 'paper Eq.(32): sqrt(Mr*Ms)*sqrt(Sigma2_p), no frame renormalization', ...
    'pas_reference', 'vMF cv=1.0 is used as isotropic-like in delivery defaults; strict isotropic reference is available but not default');

end
