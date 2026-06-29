% run_capacity_full_4scheme.m  -  cc-0602-05 (rev cc-0602-06)  (2026-06-02)
%
% 信道容量"跑全"脚本 — 给 Eric GUI 单次跑 (点 Run, 不 quit force)。
%
% 口径 (对齐参考论文 2512.08509v1 Eq.93 + Fig.7):
%   C = E[ Σ_i log₂(1 + (P_i/σ²)·ρ_i) ],  ρ_i = svd(H_blk)²
%   P_i: **water-filling only** (论文默认, 无 equal-power)
%   横轴 = 总发射功率 P [dBW]:  σ² 固定 = 1 (噪声钉死), Ptot = 10^(P_dBW/10) (扫功率)
%        Σ P_i = Ptot,  water-filling 分配
%   (注: 固定噪声扫发射功率 ≡ 论文 Fig.7; 与"固定功率扫SNR"数值同曲线, 仅 label 不同)
%
% 3 precoder (cc-0602-04: 满秩酉⊥容量; 截断 N_s<Ms 才看子空间对齐):
%   AFWDM   = WDM disk-top-N_s      [2D disk-aware]
%   SVD     = svd(G_paper) top-N_s  [信道最优]      <- 与 AFWDM 容量打平 (F-D.3.9)
%   1D-DFT  = geometry-blind prefix F_M(:,1:N_s)     <- 2D-disk 几何失配, 容量低
%
% 维度: 3 cv × 2 strat(full/adapt) × 3 scheme × nP × nFrm。parfor over frames。
% 容量 ⊥ 波形 (F-D.3.8) → 只在 AFWDM 波形(DAFT)下算, 不扫波形。

clearvars -except pas_config disable_prop_mask cap_out_tag cap_out_dir_override use_perpath_sigma P_dBW_list sigma2_fixed numFrames_per_pt cluster_var_list USE_PARFOR NUM_WORKERS channel_norm_mode strategies online_run_id online_runner online_run_root; clc; addpath('tools');

% 容量算 svd(H_blk)+注水, 不走 LMMSE → G_paper 掉秩对容量无害 (弱模态被注水丢弃)。
% 静音 SVD precoder 的 rank-deficient 预警 (那是给 BER/LMMSE 用的, 这里刷屏无意义)。
warning('off', 'svd_precoder_from_G:RankDeficient');

%% ==================== 可调参数 ====================
Msx_override = 8; Msy_override = 8;       % 8×8 (Eric 指定)
Mrx_override = 8; Mry_override = 8;
Lch_override     = 4;
if ~exist('P_dBW_list','var')||isempty(P_dBW_list); P_dBW_list = 0:5:30; end  % 横轴: 总发射功率 P [dBW]
if ~exist('sigma2_fixed','var')||isempty(sigma2_fixed); sigma2_fixed = 1; end % 噪声方差固定 (扫 P)
if ~exist('numFrames_per_pt','var')||isempty(numFrames_per_pt); numFrames_per_pt = 30; end
if ~exist('cluster_var_list','var')||isempty(cluster_var_list); cluster_var_list = [0.01, 0.30, 1.00]; end
if ~exist('USE_PARFOR','var')||isempty(USE_PARFOR); USE_PARFOR = true; end
if ~exist('NUM_WORKERS','var')||isempty(NUM_WORKERS); NUM_WORKERS = 6; end

%% ==================== AFDM_AFWDM_Compare setup ====================
batch_mode                    = true;
pas_model                     = 'vmf';
if ~exist('pas_config','var')||isempty(pas_config); pas_config='2cluster'; end  % paper 4 paths = P_r*P_s = 2x2
disable_prop_mask = true;   % paper Eq.22 arccos boundary, no center mask  % wrapper 可注入 '2cluster'
switch pas_config
    case '2cluster'   % 对齐 grid driver 2cluster 预设 (run_phase_e_3scheme_csi_grid.m:67)
        vmf_mean_theta_deg_override = [30, 10];
        vmf_mean_phi_deg_override   = [15, 180];
    otherwise         % 4cluster (老行为不变)
        vmf_mean_theta_deg_override = [20, 35, 55, 70];
        vmf_mean_phi_deg_override   = [-60, -15, 25, 70];
end
do_multi_pas_compare          = false;
do_iso_oneshot_debug          = false;
do_diagnostic_checks          = false;
verify_diagnosis_only         = true;
do_cap_p_sweep                = false;
QAM_order                     = 4;
if ~exist('channel_norm_mode','var')||isempty(channel_norm_mode); channel_norm_mode = 'paper_eq32'; end
if ~exist('use_perpath_sigma','var')||isempty(use_perpath_sigma); use_perpath_sigma = true; end

%% ==================== parpool ====================
if USE_PARFOR
    if isempty(gcp('nocreate'))
        try
            parpool('local', NUM_WORKERS);
        catch ME
            warning('parpool 启动失败 (%s) → 退回串行', ME.message);
            USE_PARFOR = false;
        end
    end
    % 在所有 worker 上强制静音 (防 worker 缓存旧函数定义致告警漏网)
    if ~isempty(gcp('nocreate'))
        parfevalOnAll(@() warning('off', 'svd_precoder_from_G:RankDeficient'), 0);
    end
end

%% ==================== Storage ====================
nP = numel(P_dBW_list); nCV = numel(cluster_var_list);
schemes    = {'AFWDM', 'SVD', 'DFT1D_blind'};
if ~exist('strategies','var')||isempty(strategies); strategies = {'full'}; end
nW = numel(schemes); nS = numel(strategies);

Cap_wf = nan(nW, nS, nCV, nP, numFrames_per_pt);   % water-filling only
N_s_record = nan(nS, nCV);
sigma_mass_sum_record = nan(1, nCV);
use_perpath_sigma_record = false(1, nCV);

t_start = tic;
for iCV = 1:nCV
    cv = cluster_var_list(iCV);
    vmf_circular_var_override = cv * ones(1, numel(vmf_mean_theta_deg_override));
    fprintf('\n=== cluster_var = %.3f (%d/%d) ===\n', cv, iCV, nCV);
    SNR_dB_list = 15; numFrames = numFrames_per_pt;   % setup 占位, 容量自算 P sweep
    if exist('Sigma2_p','var'); clear Sigma2_p; end
    run('AFDM_AFWDM_Compare.m');

    rt = scenario_runs{1};
    cfg_base = rt.cfg;
    if exist('Sigma2_p','var') && ~isempty(Sigma2_p)
        Sig_p = Sigma2_p; cfg_base.Lch = numel(Sig_p);   % per-path P=P_r*P_s (paper Eq.26)
        use_perpath_for_this_run = true;
    else
        cfg_base.Lch = Lch_override;
        Sig_p = repmat({rt.Sigma2 / cfg_base.Lch}, 1, cfg_base.Lch);
        use_perpath_for_this_run = false;
    end
    sigma_mass_sum = 0;
    for ell = 1:cfg_base.Lch
        sigma_mass_sum = sigma_mass_sum + sum(Sig_p{ell}(:));
    end
    sigma_mass_tol = 1e-8;
    if abs(sigma_mass_sum - 1) > sigma_mass_tol
        error('run_capacity_full_3scheme:sigmaMassNotUnit', ...
            'Expected sum_ell sum(Sig_p{ell}(:)) = 1 within %.1e, got %.16g.', ...
            sigma_mass_tol, sigma_mass_sum);
    end
    sigma_mass_sum_record(iCV) = sigma_mass_sum;
    use_perpath_sigma_record(iCV) = use_perpath_for_this_run;
    Sigma2 = rt.Sigma2; Dr = rt.Dr; Ds = rt.Ds;
    Ms = cfg_base.Ms; Mr = cfg_base.Mr;
    Msx = cfg_base.Msx; Msy = cfg_base.Msy; Mrx = cfg_base.Mrx; Mry = cfg_base.Mry;
    Us_full = cfg_base.Us_full; Ur_full = cfg_base.Ur_full;

    col_e_s = sum(Sigma2, 1); col_e_r = sum(Sigma2, 2).';
    [~, sort_s] = sort(col_e_s, 'descend');
    [~, sort_r] = sort(col_e_r, 'descend');
    ns_prop = cfg_base.ms;
    c_s = cumsum(col_e_s(sort_s)) / sum(col_e_s);
    c_r = cumsum(col_e_r(sort_r)) / sum(col_e_r);
    d_eff = min(find(c_s >= 0.997, 1), find(c_r >= 0.997, 1));
    Ns_list = nan(1, nS);
    for jj = 1:nS
        st = strategies{jj};
        if isnumeric(st)
            Ns_list(jj) = st;
        elseif ischar(st) && strcmp(st, 'full')
            Ns_list(jj) = ns_prop;
        elseif ischar(st) && strcmp(st, 'adaptive')
            Ns_list(jj) = d_eff;
        else
            error('Unknown strategy.');
        end
    end
    N_s_record(:, iCV) = Ns_list(:);
    fprintf('  ns_prop=%d  d_eff=%d\n', ns_prop, d_eff);

    F_Ms = dftmtx(Ms)/sqrt(Ms); F_Mr = dftmtx(Mr)/sqrt(Mr);   % 1D-DFT 基 (frame 无关)

    for iStrat = 1:nS
        N_s = Ns_list(iStrat);
        st = strategies{iStrat};
        if isnumeric(st); st_tag = sprintf('Ns%d', st); else; st_tag = st; end
        fprintf('  strategy=%-8s N_s=%d\n', st_tag, N_s);

        Us_afwdm = Us_full(:, sort_s(1:N_s));  Ur_afwdm = Ur_full(:, sort_r(1:N_s));
        W_s_dft = F_Ms(:, 1:N_s);  W_r_dft = F_Mr(:, 1:N_s);

        cap_wf_frm = nan(numFrames_per_pt, nW, nP);
        if USE_PARFOR
            parfor frm = 1:numFrames_per_pt
                cap_wf_frm(frm, :, :) = run_one_frame_cap3(frm, iCV, iStrat, ...
                    P_dBW_list, sigma2_fixed, cfg_base, Sigma2, Sig_p, Dr, Ds, Mr, Ms, ...
                    Msx, Msy, Mrx, Mry, Us_full, Ur_full, Us_afwdm, Ur_afwdm, ...
                    W_s_dft, W_r_dft, N_s, channel_norm_mode, nW, nP); %#ok<PFBNS>
            end
        else
            for frm = 1:numFrames_per_pt
                cap_wf_frm(frm, :, :) = run_one_frame_cap3(frm, iCV, iStrat, ...
                    P_dBW_list, sigma2_fixed, cfg_base, Sigma2, Sig_p, Dr, Ds, Mr, Ms, ...
                    Msx, Msy, Mrx, Mry, Us_full, Ur_full, Us_afwdm, Ur_afwdm, ...
                    W_s_dft, W_r_dft, N_s, channel_norm_mode, nW, nP);
            end
        end

        for frm = 1:numFrames_per_pt
            for k = 1:nW
                for iP = 1:nP
                    Cap_wf(k, iStrat, iCV, iP, frm) = cap_wf_frm(frm, k, iP);
                end
            end
        end

        idx = find(P_dBW_list == 20, 1); if isempty(idx); idx = nP; end
        for k = 1:nW
            fprintf('    %-12s C@P=%ddBW = %8.2f bits/sym\n', schemes{k}, ...
                P_dBW_list(idx), mean(squeeze(Cap_wf(k,iStrat,iCV,idx,:)),'omitnan'));
        end
    end
end
elapsed_sec = toc(t_start);

%% ==================== Save ====================
if ~exist('cap_out_tag','var')||isempty(cap_out_tag); cap_out_tag='_v4_paper'; end
out_subdir = ['phase_d3_capacity_3scheme' cap_out_tag];
if exist('cap_out_dir_override','var') && ~isempty(cap_out_dir_override)
    out_dir = cap_out_dir_override;
else
    out_dir = fullfile('results', out_subdir);
end
if ~exist(out_dir, 'dir'); mkdir(out_dir); end
ts = datestr(now, 'yyyymmdd_HHMMSS');
out_mat = fullfile(out_dir, sprintf('%s_%s.mat', out_subdir, ts));

results = struct();
results.Cap_wf = Cap_wf;
results.P_dBW_list = P_dBW_list; results.sigma2_fixed = sigma2_fixed;
results.cluster_var_list = cluster_var_list;
results.schemes = {schemes}; results.strategies = {strategies};
results.N_s_record = N_s_record; results.numFrames = numFrames_per_pt;
results.sigma_mass_sum = sigma_mass_sum_record;
results.use_perpath_sigma = use_perpath_sigma_record;

metadata = struct();
metadata.cc = 'cc-0623-01'; metadata.timestamp = ts;
metadata.array = sprintf('%dx%d', Msx, Msy);
metadata.Lch = cfg_base.Lch; metadata.Ms = Ms; metadata.Mr = Mr;
metadata.pas = ['vmf-' pas_config]; metadata.channel_norm_mode = channel_norm_mode;
metadata.power_axis = 'P_dBW (sigma2 fixed=1)';
metadata.snr_definition = 'capacity_power_sweep_fixed_noise';
metadata.paper_channel_scaling = 'sqrt_MrMs_sigma_p_no_frame_norm';
metadata.sigma_mass_sum = sigma_mass_sum_record;
metadata.use_perpath_sigma = use_perpath_sigma_record;
if exist('online_run_id','var') && ~isempty(online_run_id); metadata.online_run_id = online_run_id; end
if exist('online_runner','var') && ~isempty(online_runner); metadata.online_runner = online_runner; end
if numel(strategies) == 1 && ischar(strategies{1}) && strcmp(strategies{1}, 'full')
    metadata.stream_strategy = 'paper_full_load';
else
    metadata.stream_strategy = 'includes_adaptive_ablation';
end
metadata.elapsed_sec = elapsed_sec; metadata.matlab_version = version;
% Provenance commit (cc-0602-02): 优先读 Mac 权威 .provenance_commit marker
% (Win .git 是 Syncthing stale 残留, git rev-parse 会返回幻影 hash 如 5056b7b)。
% marker -> git -> unknown。
metadata.git_commit = 'unknown';
pc_file = fullfile(pwd, '.provenance_commit');
if exist(pc_file, 'file')
    fid = fopen(pc_file, 'r');
    if fid > 0
        c = strtrim(fgetl(fid)); fclose(fid);
        if ischar(c) && ~isempty(c); metadata.git_commit = c; end
    end
end
if strcmp(metadata.git_commit, 'unknown')
    [gs, gc] = system('git rev-parse HEAD 2>nul');
    if gs == 0; metadata.git_commit = strtrim(gc); end
end

save(out_mat, 'results', 'metadata', '-v7');
fprintf('\n========== 容量跑全 done in %.1f min ==========\n', elapsed_sec/60);
fprintf('  mat: %s\n  git: %s\n', out_mat, metadata.git_commit);
% GUI 跑: 不 quit force, Cap_wf 留 workspace 可直接画 (横轴 P_dBW_list)

%% ==================== helpers ====================
function c_wf = run_one_frame_cap3(frm, iCV, iStrat, P_dBW_list, sigma2, ...
        cfg_base, Sigma2, Sig_p, Dr, Ds, Mr, Ms, Msx, Msy, Mrx, Mry, ...
        Us_full, Ur_full, Us_afwdm, Ur_afwdm, W_s_dft, W_r_dft, N_s, ...
        channel_norm_mode, nW, nP)
    warning('off', 'svd_precoder_from_G:RankDeficient');   % parfor worker 各自静音
    seed_base = 1000*frm + 99991*iCV + 13*iStrat;

    [tau_vec, nu_vec, ~, ~, theta_s, phi_s, theta_r, phi_r] = ...
        generate_phys_dd_paths(cfg_base, cfg_base.Lch, seed_base);
    H_phys = cell(1, cfg_base.Lch);
    for ell = 1:cfg_base.Lch
        % paper Eq.31 global phase (unitary) -> drop tilt; direction in Sig_p (Eq.26-27)
        H_phys{ell} = beamspace_apd_channel_2d_perpath(Mr, Ms, Sig_p{ell}, Dr, Ds, ...
        seed_base + ell, Ur_full, Us_full, ones(Ms,1), ones(Mr,1));
    end
    G_paper = build_G_paper_eq31(H_phys, 'sum_taps');
    [W_s_svd, W_r_svd, ~] = svd_precoder_from_G(G_paper, N_s, N_s);

    Us_list = {Us_afwdm, W_s_svd, W_s_dft};
    Ur_list = {Ur_afwdm, W_r_svd, W_r_dft};

    c_wf = nan(1, nW, nP);
    for k = 1:nW
        cfg_k = cfg_base;
        cfg_k.Us = Us_list{k}; cfg_k.Ur = Ur_list{k};
        cfg_k.ms = N_s; cfg_k.mr = N_s; cfg_k.Nstreams = N_s;
        cfg_k.Wbb_wdm=[]; cfg_k.Wbb_sdm=[]; cfg_k.Fbb_wdm=[]; cfg_k.Fbb_sdm=[];
        H_blk = build_block_matrix_afwdm(H_phys, tau_vec, nu_vec, cfg_k);
        rho = svd(H_blk).^2; rho_pos = rho(rho > 1e-12);
        for iP = 1:nP
            Ptot = 10^(P_dBW_list(iP)/10);            % 总发射功率 (扫这个, σ² 固定)
            P_wf = water_filling(rho_pos, sigma2, Ptot);
            c_wf(1, k, iP) = sum(log2(1 + (P_wf .* rho_pos) / sigma2));
        end
    end
end

function tilt = build_tilt_vec(Mx, My, dx, dy, kx, ky)
    M = Mx * My; n_idx = (0:M-1).'; ux = mod(n_idx, Mx); uy = floor(n_idx / Mx);
    tilt = exp(1j * 2*pi * (dx*kx*ux + dy*ky*uy));
end

function P = water_filling(rho, sigma2, Ptot)
    rho = rho(:); r = numel(rho); rho_safe = max(rho, 1e-20); idx = 1:r; P = zeros(r, 1);
    while ~isempty(idx)
        mu = (Ptot + sum(sigma2 ./ rho_safe(idx))) / numel(idx);
        P_try = mu - sigma2 ./ rho_safe(idx);
        if all(P_try >= 0); P(idx) = P_try; break; end
        keep = P_try > 0; if ~any(keep); break; end; idx = idx(keep);
    end
end
