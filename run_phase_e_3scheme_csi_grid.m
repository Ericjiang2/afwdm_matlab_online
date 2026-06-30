% run_phase_e_3scheme_csi_grid.m  —  Phase E: 三波形 BER 网格 (iso/aniso × perfect/imperfect CSI)
%
% 三波形 = AFWDM / DFT_precoded(1D-DFT 非DA) / SVD_paper
% 网格   = pas{iso, vmf-cv} × strategy{full N_s=ms, adaptive N_s=d_eff} × κ{0,0.1,1.0} × SNR
%
% cc-0531-05: 对齐 phase_d run_one_frame_ber 正确口径 (修 cc-0531-01..04 的 Wbb/Fbb 残留 bug):
%   每 scheme cfg 必须 ms=mr=Nstreams=N_s + 清空 Wbb/Fbb + block_lmmse_solver='direct'.
%   信道 perpath+tilt; precoder 用 sort_s 选 top-N_s (full=几何圆盘); 加 adaptive(d_eff).
%
% 8×8 / SNR 0:5:25 / κ=[0,0.1,1.0] / numFrames=50 / parpool 6w
%
% workspace override: pas_list / cv / SNR_list / numFrames_default / kappa_list / strategies_sel

clearvars -except SNR_list numFrames_default frame_start_offset kappa_list pas_list cv strategies_sel solver_sel csi_error_mode disable_prop_mask use_perpath_sigma pas_config out_dir_override adapt_power_floor channel_norm_mode verify_diagnosis_only online_run_id online_runner online_run_root phase_e_use_parfor; clc;
addpath('tools');
warning('off', 'svd_precoder_from_G:RankDeficient');

if ~exist('SNR_list','var');          SNR_list = 0:5:25; end
if ~exist('numFrames_default','var'); numFrames_default = 50; end
if ~exist('frame_start_offset','var')||isempty(frame_start_offset); frame_start_offset = 0; end
if ~exist('kappa_list','var');        kappa_list = [0, 0.1, 1.0]; end
if ~exist('strategies_sel','var');    strategies_sel = {'full'}; end
if ~exist('solver_sel','var');        solver_sel = 'direct'; end  % direct 实测更快且精确(91.7s vs pcg 115.4s)
if ~exist('csi_error_mode','var');    csi_error_mode = 'snr_coupled'; end  % 'snr_coupled'(默认,导频估计NMSE=κ/SNR) | 'fixed_var'(直接调每元素方差σ²_e)
if ~exist('use_perpath_sigma','var')||isempty(use_perpath_sigma); use_perpath_sigma = true; end
if ~exist('verify_diagnosis_only','var')||isempty(verify_diagnosis_only); verify_diagnosis_only = false; end
if ~exist('phase_e_use_parfor','var')||isempty(phase_e_use_parfor)
    phase_e_use_parfor = ~(exist('online_run_id','var') && ~isempty(online_run_id));
end

% ---- parpool (复用现有池, 不 delete 重建; 无池才创建) ----
parpool_workers = 0;
if ~phase_e_use_parfor
    fprintf('[parpool] disabled; running serial (MATLAB Online safe)\n');
else
    pool = gcp('nocreate');
    if ~isempty(pool)
        parpool_workers = pool.NumWorkers;
        fprintf('[parpool] 复用现有池 workers=%d\n', parpool_workers);
    else
        try
            p = parpool('Processes', 6); parpool_workers = p.NumWorkers;
            fprintf('[parpool] 新建 workers=%d\n', parpool_workers);
        catch
            try; p = parpool('Processes', 3); parpool_workers = p.NumWorkers;
                fprintf('[parpool] 新建 workers=%d (3w)\n', parpool_workers);
            catch; fprintf('[parpool] unavailable; running serial loop\n'); phase_e_use_parfor=false; end
        end
    end
    if phase_e_use_parfor
        pool = gcp('nocreate');
        if ~isempty(pool)
            try
                f = parfevalOnAll(@() warning('off', 'svd_precoder_from_G:RankDeficient'), 0);
                wait(f);
            catch ME
                fprintf('[parpool] RankDeficient warning worker silence skipped: %s\n', ME.message);
            end
        end
    end
end

if exist('out_dir_override','var') && ~isempty(out_dir_override)
    out_dir = out_dir_override;  % 显式落点 (N_s 扫描防撞 production)
elseif strcmpi(csi_error_mode,'fixed_var')
    out_dir = fullfile('results', 'phase_e_fixedvar_v4_paper');
elseif exist('use_perpath_sigma','var') && use_perpath_sigma
    out_dir = fullfile('results', 'phase_e_v4_papersnr_perpath_nomask');  % paper SNR + Eq.(32) per-path
elseif exist('disable_prop_mask','var') && disable_prop_mask
    out_dir = fullfile('results', 'phase_e_v4_papersnr_nomask');  % anti-overwrite: 去mask独立目录, 不碰老 masked mat
else
    out_dir = fullfile('results', 'phase_e_3scheme_csi_grid');
end
if ~exist(out_dir, 'dir'); mkdir(out_dir); end

if ~exist('pas_list','var') || isempty(pas_list); pas_list = {'isotropic','vmf'}; end
nK = length(kappa_list); nSNR = length(SNR_list); nStrat = numel(strategies_sel);

for iPas = 1:numel(pas_list)
    this_pas = pas_list{iPas};
    batch_mode=true; pas_model=this_pas; do_multi_pas_compare=false;
    SNR_dB_list=SNR_list; numFrames=numFrames_default;
    do_iso_oneshot_debug=false; do_diagnostic_checks=false; do_cap_p_sweep=false;
    if strcmp(this_pas,'vmf')
        if ~exist('pas_config','var')||isempty(pas_config); pas_config='4cluster'; end
        if ~exist('cv','var')||isempty(cv); cv=1.0; end
        switch pas_config
            case '2cluster'
                vmf_mean_theta_deg_override=[30,10]; vmf_mean_phi_deg_override=[15,180];
                vmf_circular_var_override=cv*ones(1,2);
            otherwise   % 4cluster (默认, 老行为不变)
                vmf_mean_theta_deg_override=[20,35,55,70]; vmf_mean_phi_deg_override=[-60,-15,25,70];
                vmf_circular_var_override=cv*ones(1,4);
        end
    end

    if exist('Sigma2_p','var'); clear Sigma2_p; end
    prepare_scenario_only = true;
    run('AFDM_AFWDM_Compare.m');
    clear prepare_scenario_only;
    rt=scenario_runs{1}; cfg_base=rt.cfg; Sigma2=rt.Sigma2; Dr=rt.Dr; Ds=rt.Ds;
    ms=cfg_base.ms; mr=cfg_base.mr; Ms=cfg_base.Ms; Mr=cfg_base.Mr; Lch=cfg_base.Lch;
    Msx=cfg_base.Msx; Msy=cfg_base.Msy; Mrx=cfg_base.Mrx; Mry=cfg_base.Mry;
    % per-path tap 源: tap ell ← Σ_p (Lch=P); fallback 用 Sigma2/Lch 保持总方差质量=1
    if exist('Sigma2_p','var') && ~isempty(Sigma2_p)
        Lch = numel(Sigma2_p); Sig_taps = Sigma2_p;
        use_perpath_for_this_run = true;
    else
        Lch = max(Lch, 1);
        Sig_taps = repmat({Sigma2 / Lch}, 1, Lch);
        use_perpath_for_this_run = false;
    end
    cfg_base.Lch = Lch;
    sigma_mass_sum = 0;
    for ell = 1:Lch
        sigma_mass_sum = sigma_mass_sum + sum(Sig_taps{ell}(:));
    end
    sigma_mass_tol = 1e-8;
    if abs(sigma_mass_sum - 1) > sigma_mass_tol
        error('run_phase_e_3scheme_csi_grid:sigmaMassNotUnit', ...
            'Expected sum_ell sum(Sig_taps{ell}(:)) = 1 within %.1e, got %.16g.', ...
            sigma_mass_tol, sigma_mass_sum);
    end
    if ~exist('QAM_order','var')||isempty(QAM_order); QAM_order=4; end
    if ~exist('channel_norm_mode','var')||isempty(channel_norm_mode); channel_norm_mode='mrms'; end
    channel_norm_mode=lower(strtrim(channel_norm_mode));

    Us_full=cfg_base.Us_full; Ur_full=cfg_base.Ur_full;
    col_e_s=sum(Sigma2,1); col_e_r=sum(Sigma2,2).';
    % cc-0616-05: 切换 overlap 判据 (物理保真, 60模); 候选池=idx_prop, 池内按能量排
    [idx_s_prop,~]=select_center_modes_2d_overlap(Msx,Msy,0,cfg_base.dx,cfg_base.dy);
    [idx_r_prop,~]=select_center_modes_2d_overlap(Mrx,Mry,0,cfg_base.dx,cfg_base.dy);
    idx_s_prop=idx_s_prop(:).'; idx_r_prop=idx_r_prop(:).';
    [~,o_s]=sort(col_e_s(idx_s_prop),'descend'); sort_s=idx_s_prop(o_s);
    [~,o_r]=sort(col_e_r(idx_r_prop),'descend'); sort_r=idx_r_prop(o_r);
    % adapt 判据: 每模功率 ≥ floor·max (剔弱尾 deadweight 模; 旧 cumsum99.7% 对去mask太松留到N_s=55).
    if ~exist('adapt_power_floor','var')||isempty(adapt_power_floor); adapt_power_floor=0.10; end
    d_eff=min(nnz(col_e_s(idx_s_prop)>=adapt_power_floor*max(col_e_s)), ...
              nnz(col_e_r(idx_r_prop)>=adapt_power_floor*max(col_e_r)));
    cv_tag=1.0; if strcmp(this_pas,'vmf'); cv_tag=cv; end

    fprintf('\n========== Phase E pas=%s cv=%.2f | ms=%d d_eff=%d ==========\n', this_pas, cv_tag, ms, d_eff);

    schemes={'AFWDM','DFT_precoded','SVD_paper'};
    BER = nan(3, nStrat, nSNR, nK);   % [scheme, strategy, SNR, kappa]
    Ns_used = nan(1, nStrat);

    t_loops = tic;
    % cc-0616-05: overlap 判据, full 直接用 ms (overlap 池内全非零, 降门槛防误过滤边缘弱模)
    nnz_modes = min(nnz(col_e_s(idx_s_prop) > 1e-12*max(col_e_s)), nnz(col_e_r(idx_r_prop) > 1e-12*max(col_e_r)));
    for iStrat = 1:nStrat
        st = strategies_sel{iStrat};
        if isnumeric(st); N_s=st; st_tag=sprintf('Ns%d',st);
        elseif strcmp(st,'full'); N_s=ms; st_tag='full';  % overlap: ms=60 (ISO), 直接用不数 nnz
        else; N_s=d_eff; st_tag='adaptive'; end
        N_s = min(N_s, nnz_modes);   % 防选零功率模 (N_s>非零模数时 cap)
        Ns_used(iStrat)=N_s;
        Us_afwdm=Us_full(:,sort_s(1:N_s)); Ur_afwdm=Ur_full(:,sort_r(1:N_s));
        [W_s_dft,W_r_dft]=build_dft_precoder(Ms,Mr,N_s,N_s);
        fprintf('  -- strategy=%s N_s=%d (nnz_modes=%d) --\n', st_tag, N_s, nnz_modes);

        for iSNR = 1:nSNR
            SNR_dB = SNR_list(iSNR);
            err_per = zeros(numFrames_default, 3, nK);   % [frm, scheme, kappa]
            tot_per = zeros(numFrames_default, 3, nK);

            if phase_e_use_parfor
                parfor frm = 1:numFrames_default
                    [e_loc, t_loc] = run_one_frame_phase_e(frm, cfg_base, Lch, Sig_taps, Dr, Ds, ...
                        Mr, Ms, Ur_full, Us_full, kappa_list, SNR_dB, csi_error_mode, ...
                        Us_afwdm, Ur_afwdm, W_s_dft, W_r_dft, N_s, solver_sel, QAM_order, nK, frame_start_offset);
                    err_per(frm,:,:) = e_loc; tot_per(frm,:,:) = t_loc;
                end
            else
                for frm = 1:numFrames_default
                    [e_loc, t_loc] = run_one_frame_phase_e(frm, cfg_base, Lch, Sig_taps, Dr, Ds, ...
                        Mr, Ms, Ur_full, Us_full, kappa_list, SNR_dB, csi_error_mode, ...
                        Us_afwdm, Ur_afwdm, W_s_dft, W_r_dft, N_s, solver_sel, QAM_order, nK, frame_start_offset);
                    err_per(frm,:,:) = e_loc; tot_per(frm,:,:) = t_loc;
                end
            end

            err = squeeze(sum(err_per,1)); tot = squeeze(sum(tot_per,1));   % [3, nK]
            BER(:,iStrat,iSNR,:) = err ./ max(tot,1);
            fprintf('  [%s] SNR=%2d: ', st_tag, SNR_dB);
            for iK=1:nK
                fprintf('κ%.1f[A=%.2e D=%.2e S=%.2e] ', kappa_list(iK), BER(1,iStrat,iSNR,iK), BER(2,iStrat,iSNR,iK), BER(3,iStrat,iSNR,iK));
            end
            fprintf('\n');
        end
    end

    fprintf('  [time] 计算循环=%.1fs (排除 parpool+Compare 固定开销)\n', toc(t_loops));

    % ---- save per (pas,cv) ----
    results=struct();
    results.SNR_dB=SNR_list; results.kappa_list=kappa_list;
    results.schemes=schemes; results.strategies=strategies_sel;
    results.BER=BER;                       % [scheme, strategy, SNR, kappa]
    results.pas=this_pas; results.cv=cv_tag; results.d_eff=d_eff; results.Ns_used=Ns_used;
    results.frame_start_offset = frame_start_offset;
    if numel(strategies_sel) == 1 && ischar(strategies_sel{1}) && strcmp(strategies_sel{1}, 'full')
        stream_strategy = 'paper_full_load';
    else
        stream_strategy = 'includes_adaptive_ablation';
    end
    stream_load_save = Ns_used;
    if numel(stream_load_save) == 1
        stream_load_save = stream_load_save(1);
    end
    cfg_save = cfg_base;
    cfg_save.Ns_used = Ns_used;
    cfg_save.Nstreams = stream_load_save;
    if isscalar(stream_load_save)
        cfg_save.ms = stream_load_save;
        cfg_save.mr = stream_load_save;
    end
    switches=struct('pas_model',this_pas,'cv',cv_tag,'channel_norm_mode',channel_norm_mode, ...
        'Nstreams',stream_load_save,'numFrames',numFrames_default,'numFrames_block',numFrames_default, ...
        'parpool_workers',parpool_workers,'kappa_list',kappa_list,'SNR_list',SNR_list, ...
        'strategies',{strategies_sel},'solver',solver_sel,'csi_error_mode',csi_error_mode, ...
        'snr_definition','per_symbol_unit_qam','paper_channel_scaling','sqrt_MrMs_sigma_p_no_frame_norm', ...
        'sigma_mass_sum',sigma_mass_sum,'use_perpath_sigma',use_perpath_for_this_run, ...
        'stream_strategy',stream_strategy,'frame_start_offset',frame_start_offset);
    if exist('online_run_id','var') && ~isempty(online_run_id); switches.online_run_id=online_run_id; end
    if exist('online_runner','var') && ~isempty(online_runner); switches.online_runner=online_runner; end
    if strcmp(this_pas,'vmf'); combo_id=sprintf('E_vmf_cv%03d',round(cv_tag*100)); else; combo_id='E_isotropic'; end
    if strcmpi(csi_error_mode,'fixed_var'); combo_id=[combo_id '_fv']; end  % anti-overwrite 双保险
    label=sprintf('phase_e v4 paper-SNR 3scheme pas=%s cv=%.2f d_eff=%d 8x8', this_pas, cv_tag, d_eff);
    save_attack_result(combo_id, label, 'phase_e_v4', switches, cfg_save, results, out_dir);
end

fprintf('\n========== Phase E done ==========\n  out_dir: %s\n', out_dir);

% ---- local fns ----
function tilt=build_tilt_vec(Mx,My,dx,dy,kx,ky)
    M=Mx*My; n=(0:M-1).'; ux=mod(n,Mx); uy=floor(n/Mx);
    tilt=exp(1j*2*pi*(dx*kx*ux+dy*ky*uy));
end

function [e_loc, t_loc] = run_one_frame_phase_e(frm, cfg_base, Lch, Sig_taps, Dr, Ds, ...
        Mr, Ms, Ur_full, Us_full, kappa_list, SNR_dB, csi_error_mode, ...
        Us_afwdm, Ur_afwdm, W_s_dft, W_r_dft, N_s, solver_sel, QAM_order, nK, frame_start_offset)
    seed_base = 1000 * (frame_start_offset + frm);
    [tau_vec, nu_vec, ~, ~, theta_s, phi_s, theta_r, phi_r] = ...
        generate_phys_dd_paths(cfg_base, Lch, seed_base);
    H_phys = cell(1, Lch);
    for ell = 1:Lch
        % paper Eq.31 phase Gamma global (unitary) -> drop per-path tilt; direction in Sigma_p
        H_phys{ell}=beamspace_apd_channel_2d_perpath(Mr,Ms,Sig_taps{ell},Dr,Ds, ...
        seed_base+ell, Ur_full, Us_full, ones(Ms,1), ones(Mr,1));
    end
    e_loc=zeros(3,nK); t_loc=zeros(3,nK);
    for iK = 1:nK
        rng(seed_base*100 + iK*7919);
        H_hat = inject_csi_error(H_phys, kappa_list(iK), 10^(SNR_dB/10), Mr, Ms, Lch, csi_error_mode);
        % per-frame SVD precoder (channel-aware, on H_hat)
        G_hat = build_G_paper_eq31(H_hat, 'sum_taps');
        [W_s_svd, W_r_svd, ~] = svd_precoder_from_G(G_hat, N_s, N_s);
        Us_set = {Us_afwdm, W_s_dft, W_s_svd};
        Ur_set = {Ur_afwdm, W_r_dft, W_r_svd};
        for k = 1:3
            cfg_k = cfg_base;
            cfg_k.Us=Us_set{k}; cfg_k.Ur=Ur_set{k};
            cfg_k.ms=N_s; cfg_k.mr=N_s; cfg_k.Nstreams=N_s;
            cfg_k.Wbb_wdm=[]; cfg_k.Wbb_sdm=[]; cfg_k.Fbb_wdm=[]; cfg_k.Fbb_sdm=[];
            cfg_k.block_lmmse_solver=solver_sel;
            Hr = build_block_matrix_afwdm(H_phys, tau_vec, nu_vec, cfg_k);
            Hd = build_block_matrix_afwdm(H_hat,  tau_vec, nu_vec, cfg_k);
            [e,b] = simulate_imperfect_csi_block(cfg_k, Hr, Hd, QAM_order, SNR_dB);
            e_loc(k,iK)=e; t_loc(k,iK)=b;
        end
    end
end
