% Batch-mode guard: when run from a wrapper that pre-populates base workspace
% (e.g., tools/run_attack_M2to5_sweep.m), set `batch_mode=true` to skip clear/clc
% so injected switches survive. Default behavior unchanged when run standalone.
if ~exist('batch_mode','var') || ~batch_mode
    clear; clear functions; rehash; close all; clc;
end
rng(1);
this_dir = fileparts(mfilename('fullpath'));
if exist(fullfile(this_dir, 'variance'), 'dir')
    addpath(fullfile(this_dir, 'variance'));
else
    addpath(fullfile(this_dir, '方差计算'));
end
if exist(fullfile(this_dir, 'variance_aniso'), 'dir')
    addpath(fullfile(this_dir, 'variance_aniso'));
else
    addpath(fullfile(this_dir, '方差计算', '各向异性'));
end
clear this_dir;
fprintf('Using function files:\n');
fprintf('  simulate_afwdm_snr:     %s\n', which('simulate_afwdm_snr'));
fprintf('  lmmse_detect_afwdm:     %s\n', which('lmmse_detect_afwdm'));
fprintf('  simulate_afdm_snr:      %s\n', which('simulate_afdm_snr'));
fprintf('  lmmse_detect_afdm:      %s\n\n', which('lmmse_detect_afdm'));

%% ---------------- Simulation Parameters ----------------
% High-level simulation preset:
%   'standard_mimo' - textbook fully-digital MIMO reference:
%                     all Tx/Rx dimensions are kept in digital baseband.
%                     Best for看 AFWDM/AFDM 的“算法本征性能”。
%   'paper_hybrid'  - RF-limited / paper-style hybrid receiver:
%                     only Ns baseband outputs are kept after analog combining.
if ~exist('simulation_preset','var') || isempty(simulation_preset)
    simulation_preset = 'standard_mimo_v5';   % 'standard_mimo' | 'paper_hybrid'
end

% Preset-driven defaults (only set if not already injected by batch wrapper)
switch lower(strtrim(simulation_preset))
    case 'standard_mimo'
        if ~exist('SNR_dB_list','var');                      SNR_dB_list = -5:5:10;                            end
        if ~exist('wbb_mode','var');                         wbb_mode = 'fully_digital';                       end
        if ~exist('experiment_profile_default','var');       experiment_profile_default = 'supported_dof_baseline'; end
        if ~exist('aniso_s_afwdm_adaptive_SNR_list_default','var'); aniso_s_afwdm_adaptive_SNR_list_default = -15:5:10; end
    case 'paper_hybrid'
        if ~exist('SNR_dB_list','var');                      SNR_dB_list = 0:5:20;                              end
        if ~exist('wbb_mode','var');                         wbb_mode = 'hybrid';                                end
        if ~exist('experiment_profile_default','var');       experiment_profile_default = 'rf_limited_baseline'; end
        if ~exist('aniso_s_afwdm_adaptive_SNR_list_default','var'); aniso_s_afwdm_adaptive_SNR_list_default = 5:5:25; end
    case 'standard_mimo_v5'
        % V5 = 试 "PAS 排序 + Ns 限到 ns_eff" 修复 (第二回答方案)
        if ~exist('SNR_dB_list','var');                      SNR_dB_list = 5:5:30;                              end
        if ~exist('wbb_mode','var');                         wbb_mode = 'fully_digital';                         end
        if ~exist('experiment_profile_default','var');       experiment_profile_default = 'supported_dof_baseline_v5'; end
        if ~exist('aniso_s_afwdm_adaptive_SNR_list_default','var'); aniso_s_afwdm_adaptive_SNR_list_default = -10:5:20; end
    otherwise
        error('Unknown simulation_preset: %s', simulation_preset);
end

fprintf('\n=== Simulation Preset ===\n');
fprintf('  preset             = %s\n', simulation_preset);
fprintf('  BER SNR sweep (dB) = [%s]\n', num2str(SNR_dB_list));
fprintf('  wbb_mode           = %s\n', wbb_mode);
fprintf('  profile            = %s\n', experiment_profile_default);

if ~exist('numFrames','var');       numFrames = 400;       end       % Monte-Carlo frames per SNR
if ~exist('numFrames_block','var'); numFrames_block = 400; end       % Frames for strict block-capacity (SVD per frame; keep low)

% AFWDM BER simulation mode switch: 'operator' | 'block' | 'both'
if ~exist('afwdm_ber_mode','var'); afwdm_ber_mode = 'block'; end

% Capacity simulation mode switch: 'bin' | 'block' | 'both'
if ~exist('afwdm_cap_mode','var'); afwdm_cap_mode = 'block'; end
cfg.block_lmmse_solver = 'direct';
% BER control experiment switch (false=original ch energy; true=per-frame eq-energy norm)
if ~exist('do_equal_energy_norm','var'); do_equal_energy_norm = false; end
do_equal_energy_norm_log = true;   % print first-tap normalization info per frame
eqnorm_log_every = 100;             % print every N frames when eqnorm log is enabled1
% NOTE: full_digital_baseline 下 SDM/WDM tap 能量恒等 (酉变换保范数)，此开关无效，仅 rf_limited_baseline 有意义

% 补充 BER 图: false=主图 (identity); true=补充图 (基于信道聚合 SVD 的 strongest-subspace 预编码)
if ~exist('use_tx_svd_precoding_for_ber','var'); use_tx_svd_precoding_for_ber = false; end

% Rx 接收架构开关 (控制 reset_stream_mapping 里 Wbb_sdm / Wbb_wdm 的形式)
%   'hybrid'         - Wbb = [I_Ns; 0_{mr-Ns, Ns}] (mr×Ns 截断)
%                      物理对应: Ns 条 RF 链路 + 模拟移相器网络压缩 mr→Ns，LMMSE 观测数 = Ns·Nblk
%                      AFWDM paper 默认架构
%   'fully_digital'  - Wbb = eye(mr) (mr×mr 全保留)
%                      物理对应: 每根天线一条独立 RF 链路，LMMSE 观测数 = mr·Nblk (超定)
%                      对 AFDM 和 AFWDM 同等作用，公平对比不变，只是性能上限更高
% 由 simulation_preset 自动设置；如需手动覆盖，可直接改上面的 preset。

% Power-sweep capacity reproduction (paper-style): C_H vs P(dBW)
if ~exist('do_cap_p_sweep','var'); do_cap_p_sweep = false; end
if ~exist('P_dBW_list','var');     P_dBW_list = 0:5:20;     end
if ~exist('chi2_dBW','var');       chi2_dBW = 0;             end       % chi^2(dBW) -> chi^2_lin
chi2_lin = 10^(chi2_dBW/10);
if ~exist('cap_p_display_unit','var'); cap_p_display_unit = 'bit'; end

% 多 PAS 场景联合仿真: true=同仿 iso+aniso(small)+aniso(large) / false=单 PAS (cfg.pas_model)
% Default false (cc-0507-15c, 2026-05-07): 各向同性已成主线 narrative;
% 跑 ANISO 显式置 true 即可。Phase A/A.b/B/B.b wrapper 已显式 false 不受影响。
if ~exist('do_multi_pas_compare','var'); do_multi_pas_compare = false; end

% 诊断 / 单样本验证开关
if ~exist('do_diagnostic_checks','var');     do_diagnostic_checks = false;     end
if ~exist('do_operator_verification','var'); do_operator_verification = false; end
if ~exist('do_iso_oneshot_debug','var');     do_iso_oneshot_debug = true;      end

% V1-V4 诊断停车: true=跑完 PAS scenario_runs 即 return；false=正常进 BER/capacity 主循环
if ~exist('verify_diagnosis_only','var'); verify_diagnosis_only = false; end
% Library mode for wrappers: prepare scenario_runs/Sigma2_p and return
% before this legacy script's own OFDM/AFDM/AFWDM-blk BER loop.
if ~exist('prepare_scenario_only','var'); prepare_scenario_only = false; end

mode_val = lower(strtrim(afwdm_ber_mode));
if ~ismember(mode_val, {'operator','block','both'})
    error('Invalid afwdm_ber_mode: %s. Use operator/block/both.', afwdm_ber_mode);
end
do_ber_op  = strcmp(mode_val, 'operator') || strcmp(mode_val, 'both');
do_ber_blk = strcmp(mode_val, 'block')    || strcmp(mode_val, 'both');

cap_mode_val = lower(strtrim(afwdm_cap_mode));
if ~ismember(cap_mode_val, {'bin','block','both'})
    error('Invalid afwdm_cap_mode: %s. Use bin/block/both.', afwdm_cap_mode);
end
do_cap_bin = strcmp(cap_mode_val, 'bin')   || strcmp(cap_mode_val, 'both');
do_cap_blk = strcmp(cap_mode_val, 'block') || strcmp(cap_mode_val, 'both');
if do_multi_pas_compare
    % 多 PAS 总图默认只看 strict block total 容量，避免一张图里混两种口径。
    do_cap_bin = false;
    do_cap_blk = true;
end

cap_p_unit_val = lower(strtrim(cap_p_display_unit));
if ~ismember(cap_p_unit_val, {'bit','kbit'})
    error('Invalid cap_p_display_unit: %s. Use bit/kbit.', cap_p_display_unit);
end

% DD grid dimensions (used by wideband_capacity for bin-decoupled capacity)
% NOTE: These M,N are NOT the AFDM block length!
% The actual AFDM/OFDM block length is cfg.Nblk (defined in physical params).
% M = 16;  % delay bins (for capacity computation)
% N = 16;  % Doppler bins (for capacity computation)
% Nblk_dd = M*N;  % DD grid size (not used by AFDM modulation)

QAM_order = 4;   % QPSK

%% ---------------- System Configuration ----------------
cfg = struct();
cfg.wbb_mode = wbb_mode;   % 传递 Rx 架构开关给 reset_stream_mapping
if exist('use_fractional_doppler','var')
    cfg.use_fractional_doppler = use_fractional_doppler;
else
    cfg.use_fractional_doppler = false;   % default: legacy integer Doppler (paper eq 33 with kᵥ=0)
end

%% ==================== Physical Scenario Parameters ====================
% All delay/Doppler indices are derived from physical quantities.
% This ensures the simulation has physical meaning.

c0 = 3e8;  % speed of light [m/s]

% ---- Carrier and wavelength ----
cfg.fc = 4e9;                 % carrier frequency [Hz]
cfg.lambda = c0 / cfg.fc;     % wavelength [m]

% ---- Mobility ----
if exist('v_max_kmh','var')
    cfg.v_max_kmh = v_max_kmh;       % override from base workspace (e.g. M3.b)
else
    cfg.v_max_kmh = 540;             % default: high-speed rail scenario
end
cfg.v_max = cfg.v_max_kmh / 3.6;   % [m/s]

% ---- Waveform parameters ----
cfg.Deltaf = 2e3;             % subcarrier spacing [Hz]
cfg.Tsym   = 1 / cfg.Deltaf;  % symbol duration [s]

% ---- Block length (AFDM/OFDM subcarriers) ----
cfg.Nblk = 64;                % 64 for debug, 256 for main results

% ---- Sampling period (delay resolution) ----
cfg.Ts = 1 / (cfg.Nblk * cfg.Deltaf);   % = 1/B

% ---- Physical max Doppler -> discrete kmax ----
% ν_max = v_max / λ,  kmax = ceil(ν_max / Δf)
cfg.nu_max = cfg.v_max / cfg.lambda;    % [Hz]
cfg.kmax = ceil(cfg.nu_max / cfg.Deltaf);

% ---- Physical max delay -> discrete lmax ----
% τ_max: scenario-dependent, lmax = ceil(τ_max / Δτ)
if exist('tau_max_us','var')
    cfg.tau_max = tau_max_us * 1e-6;     % override from base workspace [s]
else
    cfg.tau_max = 16e-6;                  % default 16 μs (典型城市多径时延扩展)
end
cfg.lmax = ceil(cfg.tau_max / cfg.Ts);

% ---- AFDM full-diversity condition check ----
% Condition: 2*kmax*(lmax+1) + lmax < Nblk
cfg.afdm_diversity_lhs = 2*cfg.kmax*(cfg.lmax+1) + cfg.lmax;
if cfg.afdm_diversity_lhs >= cfg.Nblk
    error(['AFDM full-diversity condition violated!\n' ...
           '  Condition: 2*kmax*(lmax+1) + lmax < Nblk\n' ...
           '  Current: %d < %d ? NO\n' ...
           '  Solution: increase Nblk or reduce tau_max/v_max'], ...
           cfg.afdm_diversity_lhs, cfg.Nblk);
end

% ---- Chirp parameters (AFDM) ----
cfg.c1 = (2*cfg.kmax + 1) / (2*cfg.Nblk);
cfg.c2 = 0.1 / cfg.Nblk;

% ---- Multipath ----
cfg.Lch = 4;  % number of taps (paths)

% ---- Consistency check output ----
fprintf('\n=== Physical Parameter Summary ===\n');
fprintf('  fc = %.3f GHz, λ = %.4f m\n', cfg.fc/1e9, cfg.lambda);
fprintf('  v_max = %.1f km/h, ν_max = %.1f Hz, kmax = %d\n', ...
    cfg.v_max_kmh, cfg.nu_max, cfg.kmax);
fprintf('  Δf = %.1f kHz, Nblk = %d, Ts = %.3e s\n', ...
    cfg.Deltaf/1e3, cfg.Nblk, cfg.Ts);
fprintf('  τ_max = %.3e s, lmax = %d\n', cfg.tau_max, cfg.lmax);
fprintf('  AFDM diversity: %d < %d ? YES\n', cfg.afdm_diversity_lhs, cfg.Nblk);
fprintf('  Chirp params: c1 = %.6f, c2 = %.6f\n', cfg.c1, cfg.c2);

%% ==================== Three-Waveform Comparison ====================
% Simultaneously compare: OFDM, AFDM, AFWDM
%
% | Waveform | Time-Freq Modulation | Spatial Processing |
% |----------|---------------------|-------------------|
% | OFDM     | DFT (c1=c2=0)       | SDM (antenna sel) |
% | AFDM     | DAFT (c1>0)         | SDM (antenna sel) |
% | AFWDM    | DAFT (c1>0)         | WDM (mode sel)    |
%
fprintf('\n[INFO] Three-waveform comparison: OFDM + AFDM + AFWDM\n');
fprintf('  OFDM:  c1=0, c2=0 (DFT)\n');
fprintf('  AFDM:  c1=%.6f, c2=%.6f (DAFT + SDM)\n', cfg.c1, cfg.c2);
fprintf('  AFWDM: c1=%.6f, c2=%.6f (DAFT + WDM)\n', cfg.c1, cfg.c2);

%% ==================== Array Configuration ====================

% (A) 2D planar sampling points on the aperture
% Choose factors such that Ms = Msx*Msy and Mr = Mrx*Mry
% Override hook (cc-0507-15): workspace vars Msx_override / Msy_override
% (and Mrx/Mry) let wrappers pick non-square arrays for line-array reverse
% test (Phase B.b) without editing this script. Default 8×8 unchanged.
if exist('Msx_override','var'); cfg.Msx = Msx_override; else; cfg.Msx = 8; end
if exist('Msy_override','var'); cfg.Msy = Msy_override; else; cfg.Msy = 8; end
cfg.Ms = cfg.Msx*cfg.Msy;
if exist('Mrx_override','var'); cfg.Mrx = Mrx_override; else; cfg.Mrx = 8; end
if exist('Mry_override','var'); cfg.Mry = Mry_override; else; cfg.Mry = 8; end
cfg.Mr = cfg.Mrx*cfg.Mry;

% (C) Physical array parameters
% Element spacing normalized by wavelength: d/lambda (0.5 = half-wavelength)
% Override hook (cc-0507-15b): allow workspace dx_override / dy_override
% so wrappers can switch to dy=1.0 for strict 1×N line array (where
% Msy=1, dy=0.5 violates Lsy integer assertion in function_computeVar).
if exist('dx_override','var'); cfg.dx = dx_override; else; cfg.dx = 0.5; end
if exist('dy_override','var'); cfg.dy = dy_override; else; cfg.dy = 0.5; end
% Aperture sizes (in wavelengths): L = M * d
cfg.Lsx = cfg.Msx * cfg.dx;   % Tx aperture x
cfg.Lsy = cfg.Msy * cfg.dy;   % Tx aperture y
cfg.Lrx = cfg.Mrx * cfg.dx;   % Rx aperture x
cfg.Lry = cfg.Mry * cfg.dy;   % Rx aperture y
assert(abs(cfg.Lsx - round(cfg.Lsx)) < 1e-12, 'Lsx must be integer (in lambda) to use function_computeVar.');
assert(abs(cfg.Lsy - round(cfg.Lsy)) < 1e-12, 'Lsy must be integer (in lambda) to use function_computeVar.');

% (D) z-direction geometry (paper Eq.(31): Gamma_s, Gamma_r)
cfg.sz = 0;    % Tx array z-position (in lambda). 0 = no z-phase.
cfg.rz = 0;    % Rx array z-position (in lambda). 0 = no z-phase.

% (B) Experiment Profile Selection
%
% PROFILE:
%   'supported_dof_baseline' — propagation-disk DoF 全加载
%       WDM: propagation-disk plain 2D DFT basis (Us=Ut2(:, idx_s_prop), Ur=Ur2(:, idx_r_prop))
%       SDM: 17 根选点天线 / 稀疏采样阵列
%       Streams: Ns = min(ns_prop, nr_prop), Fbb = I, Wbb = I
%       No extra Tx compensation: compare under the same symbol-energy budget
%
%   'full_digital_baseline' — 规范 A / 全加载 + 无 precoding
%       SDM: Ms-antenna full-digital (Wt_sel=I, Wr_sel=I)
%       WDM: Ms-mode plain 2D DFT basis (Us=Ut2, Ur=Ur2, 不按 PAS 排序)
%       Streams: Ns = min(ms, mr), Fbb = I, Wbb = I
%
%   'rf_limited_baseline' — 遗留/附录用的共同 RF 预算比较
%       SDM: rf_budget 个均匀选点天线
%       WDM: rf_budget 个最强 WDM 模式 (候选→显著→预算内)
if ~exist('experiment_profile','var') || isempty(experiment_profile)
    experiment_profile = experiment_profile_default;
end
if ~exist('rf_budget','var'); rf_budget = 17; end          % 仅 rf_limited_baseline / 附录路径使用
% cfg.* fields: pull from base if injected by batch wrapper, else default
if exist('stream_loading_mode','var');  cfg.stream_loading_mode = stream_loading_mode;
else;                                   cfg.stream_loading_mode = 'full_load';  end       % 'full_load' | 'fixed'
if exist('requested_Nstreams','var');   cfg.requested_Nstreams = requested_Nstreams;
else;                                   cfg.requested_Nstreams = 7;             end       % 仅 stream_loading_mode='fixed' 时使用
cfg.Nstreams = cfg.requested_Nstreams;   % 将在 profile 逻辑里覆盖为最终值

% Placeholder — will be set by profile logic after PAS computation
cfg.ms_rf = cfg.Ms;
cfg.mr_rf = cfg.Mr;
cfg.ms = cfg.Ms;
cfg.mr = cfg.Mr;

% PCG settings (for AFDM/AFWDM LMMSE detector)
cfg.pcg_max_iter = 150;
cfg.pcg_tol      = 1e-7;

%% ---------------- 2D Wavenumber (DFT) Mode Matrices ----------------
% Full unitary 2D DFT matrices on the Tx/Rx apertures
Ut2 = make_2d_dft(cfg.Msx, cfg.Msy);    % Ms x Ms
Ur2 = make_2d_dft(cfg.Mrx, cfg.Mry);    % Mr x Mr

% Full plain Fourier basis columns (bottom-layer convention)
cfg.Us_full = Ut2;
cfg.Ur_full = Ur2;

%% ==================== PAS Configuration ====================
% Power Angular Spectrum model selection
%   'isotropic' - Uniform PAS (all directions equally likely)
%   'vmf'       - von Mises-Fisher mixture (clustered scattering)
%
% 当 do_multi_pas_compare=true 时：
%   1) Isotropic
%   2) 当前 cfg.pas_config 对应的 anisotropic (small variance)
%   3) 当前 cfg.pas_config 对应的 anisotropic (large variance)
%      - 若 cfg.pas_config='2cluster'，则自动生成 2-cluster small/large
%      - 若 cfg.pas_config='4cluster'，则自动生成 4-cluster small/large
%
% 当 do_multi_pas_compare=false 时：
%   使用下面 cfg.pas_model / cfg.pas_config 指定的单场景。

if exist('pas_model','var');  cfg.pas_model = pas_model;   else; cfg.pas_model = 'vmf';        end   % 单场景模式下使用
if exist('pas_config','var'); cfg.pas_config = pas_config; else; cfg.pas_config = '4cluster';  end   % '2cluster' | '4cluster' | 'custom'

switch cfg.pas_config
    case '2cluster'
        cfg.vmf_circular_var    = [0.05, 0.03];
        cfg.vmf_mean_theta_deg  = [30, 10];
        cfg.vmf_mean_phi_deg    = [15, 180];

    case '4cluster'
        cfg.vmf_circular_var    = [0.02, 0.03, 0.05, 0.07];
        cfg.vmf_mean_theta_deg  = [20, 35, 55, 70];
        cfg.vmf_mean_phi_deg    = [-60, -15, 25, 70];

    case 'custom'
        cfg.vmf_circular_var    = [0.01, 0.005];
        cfg.vmf_mean_theta_deg  = [30, 10];
        cfg.vmf_mean_phi_deg    = [15, 180];

    otherwise
        error('Unknown cfg.pas_config: %s', cfg.pas_config);
end

% Optional base-workspace overrides for PAS cluster parameters (M3 后新增模式)
%   - vmf_circular_var_override: K×1 集中度向量（必须 ∈ (0,1]）
%   - vmf_mean_theta_deg_override / vmf_mean_phi_deg_override: K×1 簇方向
% 用法: assignin('base','vmf_circular_var_override',[0.05 0.05 0.05 0.05])
% 长度必须与 cfg.pas_config 选定的簇数一致（2cluster→2，4cluster→4）
if exist('vmf_circular_var_override','var') && ~isempty(vmf_circular_var_override)
    assert(numel(vmf_circular_var_override) == numel(cfg.vmf_circular_var), ...
        'vmf_circular_var_override 长度 %d 与 pas_config=%s 簇数 %d 不一致', ...
        numel(vmf_circular_var_override), cfg.pas_config, numel(cfg.vmf_circular_var));
    cfg.vmf_circular_var = vmf_circular_var_override(:).';
end
if exist('vmf_mean_theta_deg_override','var') && ~isempty(vmf_mean_theta_deg_override)
    cfg.vmf_mean_theta_deg = vmf_mean_theta_deg_override(:).';
end
if exist('vmf_mean_phi_deg_override','var') && ~isempty(vmf_mean_phi_deg_override)
    cfg.vmf_mean_phi_deg = vmf_mean_phi_deg_override(:).';
end

cfg.eff_energy_capture = 0.99;
if ~exist('channel_norm_mode','var') || isempty(channel_norm_mode)
    channel_norm_mode = 'mrms';   % 'none' | 'unit' | 'mrms' | 'post_sdm'
end

fprintf('\n=== PAS Comparison Configuration ===\n');
fprintf('  do_multi_pas_compare = %d\n', do_multi_pas_compare);
fprintf('  channel_norm_mode    = %s\n', channel_norm_mode);
fprintf('  stream_loading_mode  = %s\n', cfg.stream_loading_mode);
fprintf('  diagnostics enabled  = %d\n', do_diagnostic_checks);
fprintf('  operator verify      = %d\n', do_operator_verification);

% ---- 第一步：获取传播圆盘内的所有候选模式 ----
% cc-0616-05: 切换 overlap 判据 (物理保真, 60 模 for 8×8 ISO)
[idx_s_prop, n_prop_s] = select_center_modes_2d_overlap(cfg.Msx, cfg.Msy, 0, cfg.dx, cfg.dy);
[idx_r_prop, n_prop_r] = select_center_modes_2d_overlap(cfg.Mrx, cfg.Mry, 0, cfg.dx, cfg.dy);
cfg.idx_s_prop = idx_s_prop;
cfg.idx_r_prop = idx_r_prop;
cfg.ns_prop = n_prop_s;
cfg.nr_prop = n_prop_r;
fprintf('Propagation disk (overlap criterion): Tx %d modes, Rx %d modes (out of %d, %d total)\n', ...
    n_prop_s, n_prop_r, cfg.Ms, cfg.Mr);

Ur_plain_full = cfg.Ur_full;
Us_plain_full = cfg.Us_full;

pas_scenarios = build_pas_scenarios(do_multi_pas_compare, cfg);
num_pas_scenarios = numel(pas_scenarios);
scenario_runs = cell(1, num_pas_scenarios);
scenario_labels = cell(1, num_pas_scenarios);
scenario_short_labels = cell(1, num_pas_scenarios);

fprintf('\n预计算每个 PAS 场景的方差、模式选择和前端配置...\n');
for iScenario = 1:num_pas_scenarios
    pas_case = pas_scenarios(iScenario);
    scenario_labels{iScenario} = pas_case.label;
    scenario_short_labels{iScenario} = pas_case.short_label;

    fprintf('\n--------------------------------------------------------------------\n');
    fprintf('Scenario %d/%d: %s\n', iScenario, num_pas_scenarios, pas_case.label);
    fprintf('--------------------------------------------------------------------\n');

    cfg.disable_prop_mask = exist('disable_prop_mask','var') && disable_prop_mask;  % 传入函数(函数scope看不见base workspace flag)
    scenario_runs{iScenario} = prepare_pas_runtime(cfg, pas_case, experiment_profile, rf_budget, Ut2, Ur2);
end

% 保留第一个 PAS 场景的变量名，供可选诊断 / 验证段复用
cfg = scenario_runs{1}.cfg;
Sigma2 = scenario_runs{1}.Sigma2;
Dr = scenario_runs{1}.Dr;
Ds = scenario_runs{1}.Ds;
Wt_sel = scenario_runs{1}.Wt_sel;
Wr_sel = scenario_runs{1}.Wr_sel;
idx_s = scenario_runs{1}.idx_s;
idx_r = scenario_runs{1}.idx_r;

% per-path Σ_p (paper Eq.26-32). Clear stale workspace values first because
% batch wrappers run this script repeatedly without clearing the base scope.
if exist('Sigma2_p','var'); clear Sigma2_p; end
cfg.use_perpath_sigma = false;
cfg.sigma_mass_sum = NaN;
scenario_runs{1}.cfg.use_perpath_sigma = false;
scenario_runs{1}.cfg.sigma_mass_sum = NaN;
use_perpath_sigma_local = false;
is_vmf_pas = strcmpi(cfg.pas_model, 'vmf');
if is_vmf_pas
    if exist('use_perpath_sigma','var') && ~isempty(use_perpath_sigma)
        use_perpath_sigma_local = logical(use_perpath_sigma);
    else
        use_perpath_sigma_local = true;  % paper-faithful default for vMF/NLoS
    end
end
if use_perpath_sigma_local
    Sigma2_p = build_perpath_sigma(cfg);
    sigma_mass_sum = 0;
    for pp = 1:numel(Sigma2_p)
        sigma_mass_sum = sigma_mass_sum + sum(Sigma2_p{pp}(:));
    end
    cfg.Lch = numel(Sigma2_p);
    cfg.use_perpath_sigma = true;
    cfg.sigma_mass_sum = sigma_mass_sum;
    scenario_runs{1}.cfg.Lch = cfg.Lch;   % 让 wrapper cfg_base.Lch=P
    scenario_runs{1}.cfg.use_perpath_sigma = true;
    scenario_runs{1}.cfg.sigma_mass_sum = sigma_mass_sum;
    fprintf('[per-path] use_perpath_sigma=ON: P=%d paths, mass=%.12f\n', numel(Sigma2_p), sigma_mass_sum);
elseif is_vmf_pas
    scenario_runs{1}.cfg.use_perpath_sigma = false;
    scenario_runs{1}.cfg.sigma_mass_sum = NaN;
    fprintf('[per-path] use_perpath_sigma=OFF: using aggregate Sigma2 simplification.\n');
else
    fprintf('[per-path] PAS=%s: per-path Sigma disabled; wrapper will use aggregate Sigma2/Lch taps.\n', cfg.pas_model);
end

fprintf('\n预计算完成！准备进入仿真...\n\n');

if verify_diagnosis_only
    fprintf('\n');
    fprintf('============================================================\n');
    fprintf('  >>> VERIFY-ONLY 模式: scenario_runs 已就绪, 主循环跳过 <<<\n');
    fprintf('  下一步在 MATLAB 命令行里跑:\n');
    fprintf('      run tools/verify_ber_diagnosis.m\n');
    fprintf('  看每节 [CONCLUSION] 行决定 V1-V4 谁对.\n');
    fprintf('  跑完后改 verify_diagnosis_only=false 即可恢复主流程.\n');
    fprintf('============================================================\n');
    return;
end

if prepare_scenario_only
    fprintf('[prepare_scenario_only] scenario_runs ready; skip legacy BER/capacity main loop.\n');
    return;
end

%% ---------------- BER & Capacity Containers ----------------
% 维度: [PAS scenario, sweep point]
ber_ofdm = nan(num_pas_scenarios, length(SNR_dB_list));
ber_afdm = nan(num_pas_scenarios, length(SNR_dB_list));
ber_afwdm = nan(num_pas_scenarios, length(SNR_dB_list));
ber_afwdm_blk = nan(num_pas_scenarios, length(SNR_dB_list));

capP_blk_ofdm = nan(num_pas_scenarios, length(P_dBW_list));
capP_blk_sdm  = nan(num_pas_scenarios, length(P_dBW_list));
capP_blk_wdm  = nan(num_pas_scenarios, length(P_dBW_list));
snrLin_from_P = nan(1, length(P_dBW_list));

%% ========================================================================
%  DIAGNOSTIC CHECK 1 & 2: Verify wavenumber index alignment and energy capture
%  ========================================================================
if do_diagnostic_checks
fprintf('\n');
fprintf('========================================================================\n');
fprintf('  DIAGNOSTIC CHECKS: Wavenumber Index Alignment & Energy Capture\n');
fprintf('========================================================================\n\n');

num_test_channels = 50;
H_b_power_accum = zeros(cfg.Mr, cfg.Ms);

fprintf('Generating %d test channel realizations...\n', num_test_channels);

for test_idx = 1:num_test_channels
    H_phys_test = beamspace_apd_channel_2d(cfg.Mr, cfg.Ms, Sigma2, Dr, Ds, test_idx*12345, Ur_plain_full, Us_plain_full);
    H_b_test = Ur2' * H_phys_test * Ut2;
    H_b_power_accum = H_b_power_accum + abs(H_b_test).^2;
end

H_b_power_avg = H_b_power_accum / num_test_channels;

% ---- CHECK 1: Where is the APD peak in the beamspace? ----
fprintf('\n--- CHECK 1: APD Peak Location in Beamspace ---\n');

[max_power, max_lin_idx] = max(H_b_power_avg(:));
[max_row, max_col] = ind2sub([cfg.Mr, cfg.Ms], max_lin_idx);

max_ux = mod(max_col-1, cfg.Msx) + 1;
max_uy = floor((max_col-1) / cfg.Msx) + 1;
max_vx = mod(max_row-1, cfg.Mrx) + 1;
max_vy = floor((max_row-1) / cfg.Mrx) + 1;

fprintf('  Max beamspace power location:\n');
fprintf('    Tx: linear idx = %d, (ux, uy) = (%d, %d)\n', max_col, max_ux, max_uy);
fprintf('    Rx: linear idx = %d, (vx, vy) = (%d, %d)\n', max_row, max_vx, max_vy);
fprintf('  DC power = %.4e, Max power = %.4e\n', H_b_power_avg(1,1), max_power);
if strcmpi(cfg.pas_model, 'isotropic')
    fprintf('  Isotropic check: expected DC-dominant behavior.\n');
    if isequal([max_row, max_col], [1, 1])
        fprintf('  DC is at max? YES\n');
    else
        fprintf('  DC is at max? NO (possible discretization / finite-sample effect)\n');
    end
else
    fprintf('  Anisotropic check: peak off-DC is expected, not an index mismatch.\n');
end

is_peak_in_selected_s = ismember(max_col, idx_s);
is_peak_in_selected_r = ismember(max_row, idx_r);
if is_peak_in_selected_s
    fprintf('  Is Tx peak (col=%d) in selected modes idx_s? YES\n', max_col);
else
    fprintf('  Is Tx peak (col=%d) in selected modes idx_s? NO  <-- PROBLEM!\n', max_col);
end
if is_peak_in_selected_r
    fprintf('  Is Rx peak (row=%d) in selected modes idx_r? YES\n', max_row);
else
    fprintf('  Is Rx peak (row=%d) in selected modes idx_r? NO  <-- PROBLEM!\n', max_row);
end

fprintf('\n  Selected Tx mode indices (idx_s): ');
fprintf('%d ', idx_s); fprintf('\n');
fprintf('  Selected Rx mode indices (idx_r): ');
fprintf('%d ', idx_r); fprintf('\n');

% ---- CHECK 2: Compute eta_WDM vs eta_SDM ----
fprintf('\n--- CHECK 2: Energy Capture Ratios ---\n');

total_power = sum(H_b_power_avg(:));

power_in_selected = sum(sum(H_b_power_avg(idx_r, idx_s)));
eta_WDM_beam = power_in_selected / total_power;
fprintf('  eta_WDM(beamspace mask) = %.4f\n', eta_WDM_beam);

% 更严格、同口径的真实投影能量捕获率（WDM/SDM都按 Frobenius 比值计算）
eta_wdm_acc = 0;
eta_sdm_acc = 0;
for test_idx = 1:num_test_channels
    H_phys_test = beamspace_apd_channel_2d(cfg.Mr, cfg.Ms, Sigma2, Dr, Ds, test_idx*12345, Ur_plain_full, Us_plain_full);
    denom = max(norm(H_phys_test, 'fro')^2, 1e-15);
    eta_wdm_acc = eta_wdm_acc + norm(cfg.Ur' * H_phys_test * cfg.Us, 'fro')^2 / denom;
    eta_sdm_acc = eta_sdm_acc + norm(Wr_sel' * H_phys_test * Wt_sel, 'fro')^2 / denom;
end
eta_WDM = eta_wdm_acc / num_test_channels;
eta_SDM = eta_sdm_acc / num_test_channels;

fprintf('  eta_WDM(real proj) = %.4f\n', eta_WDM);
fprintf('  eta_SDM(real proj) = %.4f\n', eta_SDM);

fprintf('\n  COMPARISON:\n');
fprintf('    eta_WDM = %.4f\n', eta_WDM);
fprintf('    eta_SDM = %.4f\n', eta_SDM);
if eta_WDM > eta_SDM
    fprintf('    eta_WDM > eta_SDM: AFWDM should capture MORE energy than SDM baseline.\n');
else
    fprintf('    eta_WDM <= eta_SDM: WARNING! AFWDM may capture LESS energy than SDM!\n');
    fprintf('    This could explain why AFWDM performs worse.\n');
end

% ---- Visualize the beamspace power distribution ----
fprintf('\n--- Generating diagnostic plots... ---\n');

figure('Position', [100, 100, 1400, 500], 'Name', 'Diagnostic: Beamspace Power Distribution');

subplot(1,3,1);
Tx_power = sum(H_b_power_avg, 1);
Tx_power_2D = reshape(Tx_power, [cfg.Msx, cfg.Msy]);
imagesc(Tx_power_2D.');
colorbar;
hold on;
for i = 1:length(idx_s)
    ux = mod(idx_s(i)-1, cfg.Msx) + 1;
    uy = floor((idx_s(i)-1) / cfg.Msx) + 1;
    plot(ux, uy, 'ro', 'MarkerSize', 10, 'LineWidth', 2);
end
plot(1, 1, 'g+', 'MarkerSize', 15, 'LineWidth', 3);
title(sprintf('Tx Marginal Power (sum over Rx)\nRed circles: selected modes, Green +: DC'));
xlabel('u_x (1..Msx)');
ylabel('u_y (1..Msy)');
axis equal tight;

subplot(1,3,2);
Rx_power = sum(H_b_power_avg, 2);
Rx_power_2D = reshape(Rx_power, [cfg.Mrx, cfg.Mry]);
imagesc(Rx_power_2D.');
colorbar;
hold on;
for i = 1:length(idx_r)
    vx = mod(idx_r(i)-1, cfg.Mrx) + 1;
    vy = floor((idx_r(i)-1) / cfg.Mrx) + 1;
    plot(vx, vy, 'ro', 'MarkerSize', 10, 'LineWidth', 2);
end
plot(1, 1, 'g+', 'MarkerSize', 15, 'LineWidth', 3);
title(sprintf('Rx Marginal Power (sum over Tx)\nRed circles: selected modes, Green +: DC'));
xlabel('v_x (1..Mrx)');
ylabel('v_y (1..Mry)');
axis equal tight;

subplot(1,3,3);
bar_data = [eta_WDM, 1-eta_WDM, eta_SDM];
bar(bar_data);
set(gca, 'XTickLabel', {'η_{WDM}', '1-η_{WDM}', 'η_{SDM}'});
ylabel('Fraction of Total Power');
title('Energy Capture Comparison');
grid on;
text(1, bar_data(1)+0.02, sprintf('%.3f', bar_data(1)), 'HorizontalAlignment', 'center');
text(2, bar_data(2)+0.02, sprintf('%.3f', bar_data(2)), 'HorizontalAlignment', 'center');
text(3, bar_data(3)+0.02, sprintf('%.3f', bar_data(3)), 'HorizontalAlignment', 'center');

sgtitle(sprintf('Diagnostic:  Ms=%d, ms=%d, Mr=%d, mr=%d', ...
    cfg.Ms, cfg.ms, cfg.Mr, cfg.mr));

fprintf('\n  Diagnostic figure generated.\n');
fprintf('  Please inspect the plots and the printed values above.\n');
fprintf('  Press any key to continue with the main simulation...\n\n');
pause;

fprintf('========================================================================\n');
fprintf('  END OF DIAGNOSTIC CHECKS - Starting Main Simulation\n');
fprintf('========================================================================\n\n');
end

%% ========================================================================
%  VERIFICATION: Block matrix (Kronecker) vs Operator chain (single sample)
%  Confirms that  H_block * vec(X) == vec(Y_operator)  up to machine eps.
%  ========================================================================
if do_operator_verification
fprintf('\n');
fprintf('========================================================================\n');
fprintf('  VERIFICATION: Block Matrix vs Operator Chain\n');
fprintf('========================================================================\n\n');

rng_state_backup = rng;   % save RNG state so main loop is unaffected
rng(9999);

% Generate one test channel
H_phys_v = cell(1, cfg.Lch);
for ell = 1:cfg.Lch
    H_phys_v{ell} = beamspace_apd_channel_2d(cfg.Mr, cfg.Ms, Sigma2, Dr, Ds, 5000+ell, Ur_plain_full, Us_plain_full);
end
% H_phys_v = normalize_channel_taps(H_phys_v, cfg.Mr*cfg.Ms);
H_phys_v = normalize_channel_taps(H_phys_v, 1);
[tau_v, nu_v, ~, ~] = generate_phys_dd_paths(cfg, cfg.Lch, 9999);

% ---- Check 1: whether CPP degenerates to CP under current parameters ----
fprintf('--- CPP Degeneracy Check (CPP -> CP) ---\n');
fprintf('  2*N*c1 = %.12f\n', 2*cfg.Nblk*cfg.c1);
for p = 1:numel(tau_v)
    phi_v = compute_cpp_phase(tau_v(p), cfg.Nblk, cfg.c1);
    fprintf('  path %d: max|phi-1| = %.3e\n', p, max(abs(phi_v - 1)));
end
fprintf('\n');

% SDM effective channel
H_eff_v = cell(1, cfg.Lch);
for ell = 1:cfg.Lch
    H_eff_v{ell} = Wr_sel' * H_phys_v{ell} * Wt_sel;
end

% Random test input (complex Gaussian, not power-normalized — just for checking linearity)
X_test = (randn(cfg.Nblk, cfg.ms) + 1j*randn(cfg.Nblk, cfg.ms)) / sqrt(2);

% ---- AFDM verification ----
fprintf('--- AFDM ---\n');
%  Operator chain: X -> IDAFT -> channel -> DAFT -> Y
C_v = afdm_idaft(X_test, cfg);
R_v = apply_dd_channel_afdm(C_v, H_eff_v, tau_v, nu_v, cfg);
Y_op_afdm = afdm_daft(R_v, cfg);
y_op_afdm = Y_op_afdm(:);

%  Block matrix: y = H * x
H_blk_afdm_v = build_block_matrix_afdm(H_eff_v, tau_v, nu_v, cfg);
y_blk_afdm = H_blk_afdm_v * X_test(:);

err_afdm_v = max(abs(y_op_afdm - y_blk_afdm));
ref_afdm_v = max(abs(y_op_afdm));
rel_afdm_v = err_afdm_v / ref_afdm_v;
fprintf('  Max |y_operator - y_block|     = %.2e\n', err_afdm_v);
fprintf('  Relative error                 = %.2e\n', rel_afdm_v);
if rel_afdm_v < 1e-10
    fprintf('  MATCH: YES (relative error < 1e-10)\n');
else
    fprintf('  MATCH: NO  <-- CHECK FORMULAS\n');
end

% ---- OFDM vs AFDM singular-value consistency check ----
fprintf('\n--- OFDM vs AFDM Singular-Value Check (same channel realization) ---\n');
cfg_ofdm_sv = cfg;
cfg_ofdm_sv.c1 = 0;
cfg_ofdm_sv.c2 = 0;

H_ofdm_v = build_block_matrix_afdm(H_eff_v, tau_v, nu_v, cfg_ofdm_sv);
H_afdm_v = H_blk_afdm_v;

s_ofdm = sort(svd(H_ofdm_v), 'descend');
s_afdm = sort(svd(H_afdm_v), 'descend');
rel_sv_diff = norm(s_ofdm - s_afdm) / max(norm(s_ofdm), 1e-15);

fprintf('  relative sv diff               = %.3e\n', rel_sv_diff);
if rel_sv_diff < 1e-10
    fprintf('  Spectrum match: YES (near machine precision)\n');
else
    fprintf('  Spectrum match: NO (OFDM and AFDM spectra differ)\n');
end

% ---- AFWDM verification ----
fprintf('\n--- AFWDM ---\n');
%  Operator chain: X -> IDAFT -> *Phi_s^H(paper) -> channel -> DAFT -> *Phi_r(paper) -> Y
Xbar_v = afdm_idaft(X_test, cfg) * cfg.Phi_s_H_paper;
Ybar_v = apply_ts_channel_afwdm(Xbar_v, H_phys_v, tau_v, nu_v, cfg);
Y_op_afwdm = afdm_daft(Ybar_v, cfg) * cfg.Phi_r_paper;
y_op_afwdm = Y_op_afwdm(:);

%  Block matrix: y = H * x
H_blk_afwdm_v = build_block_matrix_afwdm(H_phys_v, tau_v, nu_v, cfg);
y_blk_afwdm = H_blk_afwdm_v * X_test(:);

err_afwdm_v = max(abs(y_op_afwdm - y_blk_afwdm));
ref_afwdm_v = max(abs(y_op_afwdm));
den_afwdm_v = max([ref_afwdm_v, max(abs(y_blk_afwdm)), 1e-14]);
rel_afwdm_v = err_afwdm_v / den_afwdm_v;
fprintf('  Max |y_operator - y_block|     = %.2e\n', err_afwdm_v);
fprintf('  Relative error                 = %.2e\n', rel_afwdm_v);
if (err_afwdm_v < 1e-12) || (rel_afwdm_v < 1e-10)
    fprintf('  MATCH: YES (relative error < 1e-10)\n');
else
    fprintf('  MATCH: NO  <-- CHECK FORMULAS\n');
end

fprintf('\n  Block matrix dims:  AFDM = %d x %d,  AFWDM = %d x %d\n', ...
    size(H_blk_afdm_v,1), size(H_blk_afdm_v,2), ...
    size(H_blk_afwdm_v,1), size(H_blk_afwdm_v,2));
fprintf('  Memory per matrix: ~%.0f MB (complex double)\n', ...
    numel(H_blk_afwdm_v) * 16 / 1e6);

rng(rng_state_backup);   % restore RNG state
fprintf('\n========================================================================\n\n');
end

%% ===================== ANISO-S Statistical Verification (additive) =====================
% 单线自适应 BER 测试模式：
%   do_aniso_s_afwdm_adaptive = true -> 只跑 ANISO-S × AFWDM-blk × SNR=0:5:20
%                                      每个 SNR 点累计到 target_err_bits 后自动停止
%                                      同时设置 min/max frames 防止过早停止或无限运行
do_aniso_s_afwdm_adaptive              = false;
aniso_s_afwdm_adaptive_SNR_list        = aniso_s_afwdm_adaptive_SNR_list_default;
% 高 SNR 点需要更多错误比特才能让 BER 曲线更平滑。
% 这里允许按 SNR 单独设置停止门限；若传标量则自动广播到所有 SNR 点。
aniso_s_afwdm_adaptive_target_err_bits = 100;
aniso_s_afwdm_adaptive_min_frames      = 200;
aniso_s_afwdm_adaptive_max_frames      = 200000;
aniso_s_afwdm_adaptive_save_mat        = fullfile('results', 'aniso_s_afwdm_adaptive.mat');
aniso_s_afwdm_adaptive_save_csv        = fullfile('results', 'aniso_s_afwdm_adaptive.csv');
do_aniso_s_afwdm_tail_diagnostics      = true;
aniso_s_rank_diag_num_channels         = 24;
aniso_s_tail_fit_num_points            = 3;

% 开关说明：
%   do_aniso_s_verify = false  -> 跳过验证，主函数 Multi-PAS 主循环照常跑
%   do_aniso_s_verify = true   -> 只跑 ANISO-S × SNR=[15,20] × 5000 帧验证，跑完 return
%                                  (主函数后续 BER 主循环 / capacity / 绘图全部不跑)
do_aniso_s_verify        = false;
aniso_s_verify_numFrames = 25000;
aniso_s_verify_SNR_list  = [15, 20];

% BER self-check (paper notation):
%   this code path uses integer Doppler only, so set alpha_max = 0 and
%   map k_nu -> cfg.kmax. LP is tracked here purely as a feasibility
%   diagnostic for the CP/CPP-style guard-length requirement.
if ~isfield(cfg, 'LP') || isempty(cfg.LP)
    cfg.LP = cfg.lmax;
end
N = cfg.Nblk;
alpha_max = 0;
k_nu = cfg.kmax;
l_max = cfg.lmax;
fprintf('\n================ BER Pre-Check ================\n');
fprintf('c1 check: c1=%.6f, required=(2*(%d+%d)+1)/(2*%d)=%.6f\n', ...
    cfg.c1, alpha_max, k_nu, N, (2*(alpha_max+k_nu)+1)/(2*N));
fprintf('diversity: 2*(%d+%d)*(%d+1)+%d=%d < N=%d ? %d\n', ...
    alpha_max, k_nu, l_max, l_max, ...
    2*(alpha_max+k_nu)*(l_max+1)+l_max, N, ...
    2*(alpha_max+k_nu)*(l_max+1)+l_max < N);
fprintf('CPP: L_P=%d >= l_max=%d ? %d\n', cfg.LP, l_max, cfg.LP >= l_max);

if do_aniso_s_afwdm_adaptive && do_aniso_s_verify
    error('do_aniso_s_afwdm_adaptive and do_aniso_s_verify cannot both be true.');
end

if do_aniso_s_afwdm_adaptive
    nS_low = numel(aniso_s_afwdm_adaptive_SNR_list);
    target_err_bits_low = expand_per_snr_param(aniso_s_afwdm_adaptive_target_err_bits, nS_low, ...
        'aniso_s_afwdm_adaptive_target_err_bits');
    min_frames_low_cfg = expand_per_snr_param(aniso_s_afwdm_adaptive_min_frames, nS_low, ...
        'aniso_s_afwdm_adaptive_min_frames');
    max_frames_low_cfg = expand_per_snr_param(aniso_s_afwdm_adaptive_max_frames, nS_low, ...
        'aniso_s_afwdm_adaptive_max_frames');

    fprintf('\n================ ANISO-S AFWDM Adaptive BER Run ================\n');
    fprintf('SNR = [%s] dB (ANISO-S, AFWDM-blk only)\n', ...
        num2str(aniso_s_afwdm_adaptive_SNR_list));
    fprintf('Per-SNR stopping rules:\n');
    for iSNR_low = 1:nS_low
        fprintf('  SNR=%2d dB -> target_err_bits=%d, min_frames=%d, max_frames=%d\n', ...
            aniso_s_afwdm_adaptive_SNR_list(iSNR_low), ...
            target_err_bits_low(iSNR_low), ...
            min_frames_low_cfg(iSNR_low), ...
            max_frames_low_cfg(iSNR_low));
    end
    fprintf('\n');

    aniso_s_idx = find(strcmpi(scenario_short_labels, 'ANISO-S'), 1);
    if isempty(aniso_s_idx)
        error('ANISO-S scenario not found in scenario_short_labels.');
    end

    rt_low     = scenario_runs{aniso_s_idx};
    cfg_sc_low = rt_low.cfg;
    err_low    = zeros(1, nS_low);
    tot_low    = zeros(1, nS_low);
    frames_low = zeros(1, nS_low);
    reached_target_low = false(1, nS_low);
    stop_reason_low = strings(1, nS_low);

    for iSNR_low = 1:nS_low
        SNR_dB_low = aniso_s_afwdm_adaptive_SNR_list(iSNR_low);
        target_err_i = target_err_bits_low(iSNR_low);
        min_frames_i = min_frames_low_cfg(iSNR_low);
        max_frames_i = max_frames_low_cfg(iSNR_low);
        for frm_low = 1:max_frames_i
            H_phys_low = generate_channel_taps(cfg_sc_low, rt_low.Sigma2, rt_low.Dr, rt_low.Ds, ...
                                               300000 + 1000*frm_low, channel_norm_mode, ...
                                               rt_low.Wr_sel, rt_low.Wt_sel);
            [tau_vec_low, nu_vec_low, ~, ~] = generate_phys_dd_paths(cfg_sc_low, cfg_sc_low.Lch, ...
                                                                      300000 + 1000*frm_low);
            [~, G_eff_low, ~] = build_effective_channels(H_phys_low, cfg_sc_low, ...
                                                         rt_low.Wr_sel, rt_low.Wt_sel);

            H_blk_afwdm_low = build_block_matrix_afwdm(G_eff_low, tau_vec_low, nu_vec_low, cfg_sc_low);
            [ew_low, bw_low] = simulate_afwdm_snr_block(cfg_sc_low, H_blk_afwdm_low, QAM_order, SNR_dB_low);

            err_low(iSNR_low) = err_low(iSNR_low) + ew_low;
            tot_low(iSNR_low) = tot_low(iSNR_low) + bw_low;
            frames_low(iSNR_low) = frm_low;

            if mod(frm_low, 100) == 0 || frm_low == max_frames_i
                fprintf('  SNR=%2d dB frm=%6d/%d: AFWDM=%.3e  err=%d\n', ...
                    SNR_dB_low, frm_low, max_frames_i, ...
                    err_low(iSNR_low) / max(tot_low(iSNR_low), 1), ...
                    err_low(iSNR_low));
            end

            if frm_low >= min_frames_i && err_low(iSNR_low) >= target_err_i
                reached_target_low(iSNR_low) = true;
                stop_reason_low(iSNR_low) = "target_err_bits";
                fprintf('  SNR=%2d dB stop at frm=%5d: target_err_bits reached (%d errors).\n', ...
                    SNR_dB_low, frm_low, err_low(iSNR_low));
                break;
            end
        end

        if strlength(stop_reason_low(iSNR_low)) == 0
            stop_reason_low(iSNR_low) = "max_frames";
            fprintf('  SNR=%2d dB stop at frm=%5d: max_frames reached (%d errors).\n', ...
                SNR_dB_low, frames_low(iSNR_low), err_low(iSNR_low));
        end
    end

    ber_low = err_low ./ max(tot_low, 1);
    results_aniso_s_afwdm_adaptive = struct();
    results_aniso_s_afwdm_adaptive.scenario_label = scenario_labels{aniso_s_idx};
    results_aniso_s_afwdm_adaptive.scenario_short_label = scenario_short_labels{aniso_s_idx};
    results_aniso_s_afwdm_adaptive.waveform = 'AFWDM-blk';
    results_aniso_s_afwdm_adaptive.snr_db = aniso_s_afwdm_adaptive_SNR_list(:);
    results_aniso_s_afwdm_adaptive.ber = ber_low(:);
    results_aniso_s_afwdm_adaptive.err_bits = err_low(:);
    results_aniso_s_afwdm_adaptive.tot_bits = tot_low(:);
    results_aniso_s_afwdm_adaptive.frames_used = frames_low(:);
    results_aniso_s_afwdm_adaptive.reached_target = reached_target_low(:);
    results_aniso_s_afwdm_adaptive.stop_reason = stop_reason_low(:);
    results_aniso_s_afwdm_adaptive.target_err_bits = target_err_bits_low(:);
    results_aniso_s_afwdm_adaptive.min_frames = min_frames_low_cfg(:);
    results_aniso_s_afwdm_adaptive.max_frames = max_frames_low_cfg(:);
    results_aniso_s_afwdm_adaptive.Nblk = cfg_sc_low.Nblk;
    results_aniso_s_afwdm_adaptive.Nstreams = cfg_sc_low.Nstreams;
    results_aniso_s_afwdm_adaptive.QAM_order = QAM_order;
    results_aniso_s_afwdm_adaptive.channel_norm_mode = channel_norm_mode;
    results_aniso_s_afwdm_adaptive.wbb_mode = cfg_sc_low.wbb_mode;
    results_aniso_s_afwdm_adaptive.timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    if do_aniso_s_afwdm_tail_diagnostics
        results_aniso_s_afwdm_adaptive.diagnostics = run_aniso_s_afwdm_diagnostics( ...
            results_aniso_s_afwdm_adaptive, rt_low, channel_norm_mode, ...
            aniso_s_rank_diag_num_channels, aniso_s_tail_fit_num_points);
    end

    out_dir = fileparts(aniso_s_afwdm_adaptive_save_mat);
    if ~isempty(out_dir) && ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end
    save(aniso_s_afwdm_adaptive_save_mat, 'results_aniso_s_afwdm_adaptive');

    fid_low = fopen(aniso_s_afwdm_adaptive_save_csv, 'w');
    if fid_low < 0
        error('Failed to open %s for writing.', aniso_s_afwdm_adaptive_save_csv);
    end
    fprintf(fid_low, 'scenario,waveform,SNR_dB,BER,err_bits,tot_bits,frames_used,reached_target,stop_reason,target_err_bits,min_frames,max_frames,Nblk,Nstreams,QAM_order,channel_norm_mode,wbb_mode\n');
    for iSNR_low = 1:nS_low
        fprintf(fid_low, '%s,%s,%g,%.16e,%d,%d,%d,%d,%s,%d,%d,%d,%d,%d,%d,%s,%s\n', ...
            results_aniso_s_afwdm_adaptive.scenario_short_label, ...
            results_aniso_s_afwdm_adaptive.waveform, ...
            aniso_s_afwdm_adaptive_SNR_list(iSNR_low), ...
            ber_low(iSNR_low), ...
            err_low(iSNR_low), ...
            tot_low(iSNR_low), ...
            frames_low(iSNR_low), ...
            reached_target_low(iSNR_low), ...
            char(stop_reason_low(iSNR_low)), ...
            target_err_bits_low(iSNR_low), ...
            min_frames_low_cfg(iSNR_low), ...
            max_frames_low_cfg(iSNR_low), ...
            cfg_sc_low.Nblk, ...
            cfg_sc_low.Nstreams, ...
            QAM_order, ...
            channel_norm_mode, ...
            cfg_sc_low.wbb_mode);
    end
    fclose(fid_low);

    fprintf('\n=== Saved ANISO-S AFWDM adaptive BER ===\n');
    for iSNR_low = 1:nS_low
        fprintf('SNR=%2d dB | AFWDM=%.3e (%d/%d) | frames=%d | stop=%s\n', ...
            aniso_s_afwdm_adaptive_SNR_list(iSNR_low), ...
            ber_low(iSNR_low), err_low(iSNR_low), tot_low(iSNR_low), ...
            frames_low(iSNR_low), char(stop_reason_low(iSNR_low)));
    end
    fprintf('Saved MAT: %s\n', aniso_s_afwdm_adaptive_save_mat);
    fprintf('Saved CSV: %s\n', aniso_s_afwdm_adaptive_save_csv);
    return;
end

if do_aniso_s_verify
    fprintf('\n================ ANISO-S Statistical Verification ================\n');
    fprintf('numFrames = %d, SNR = [%s] dB (only ANISO-S scenario)\n\n', ...
        aniso_s_verify_numFrames, num2str(aniso_s_verify_SNR_list));

    aniso_s_idx = find(strcmpi(scenario_short_labels, 'ANISO-S'), 1);
    if isempty(aniso_s_idx)
        error('ANISO-S scenario not found in scenario_short_labels.');
    end
    rt_v     = scenario_runs{aniso_s_idx};
    cfg_sc_v = rt_v.cfg;
    cfg_ofdm_v = cfg_sc_v;
    cfg_ofdm_v.c1 = 0;
    cfg_ofdm_v.c2 = 0;

    nS_v  = numel(aniso_s_verify_SNR_list);
    err_v = zeros(3, nS_v);    % rows: OFDM / AFDM / AFWDM
    tot_v = zeros(3, nS_v);

    for iSNR_v = 1:nS_v
        SNR_dB_v = aniso_s_verify_SNR_list(iSNR_v);
        for frm_v = 1:aniso_s_verify_numFrames
            H_phys_v = generate_channel_taps(cfg_sc_v, rt_v.Sigma2, rt_v.Dr, rt_v.Ds, ...
                                             1000*frm_v, channel_norm_mode, ...
                                             rt_v.Wr_sel, rt_v.Wt_sel);
            [tau_vec_v, nu_vec_v, ~, ~] = generate_phys_dd_paths(cfg_sc_v, cfg_sc_v.Lch, 1000*frm_v);
            [H_eff_v, G_eff_v, ~] = build_effective_channels(H_phys_v, cfg_sc_v, ...
                                                              rt_v.Wr_sel, rt_v.Wt_sel);

            H_blk_ofdm_v  = build_block_matrix_afdm (H_eff_v, tau_vec_v, nu_vec_v, cfg_ofdm_v);
            H_blk_afdm_v  = build_block_matrix_afdm (H_eff_v, tau_vec_v, nu_vec_v, cfg_sc_v);
            H_blk_afwdm_v = build_block_matrix_afwdm(G_eff_v, tau_vec_v, nu_vec_v, cfg_sc_v);

            [eo_v, bo_v] = simulate_afdm_snr_block (cfg_ofdm_v, H_blk_ofdm_v,  QAM_order, SNR_dB_v);
            [ea_v, ba_v] = simulate_afdm_snr_block (cfg_sc_v,   H_blk_afdm_v,  QAM_order, SNR_dB_v);
            [ew_v, bw_v] = simulate_afwdm_snr_block(cfg_sc_v,   H_blk_afwdm_v, QAM_order, SNR_dB_v);

            err_v(:, iSNR_v) = err_v(:, iSNR_v) + [eo_v; ea_v; ew_v];
            tot_v(:, iSNR_v) = tot_v(:, iSNR_v) + [bo_v; ba_v; bw_v];

            if mod(frm_v, 200) == 0 || frm_v == aniso_s_verify_numFrames
                fprintf('  SNR=%2d dB frm=%4d/%d: OFDM=%.3e AFDM=%.3e AFWDM=%.3e\n', ...
                    SNR_dB_v, frm_v, aniso_s_verify_numFrames, ...
                    err_v(1,iSNR_v)/max(tot_v(1,iSNR_v),1), ...
                    err_v(2,iSNR_v)/max(tot_v(2,iSNR_v),1), ...
                    err_v(3,iSNR_v)/max(tot_v(3,iSNR_v),1));
            end
        end
    end

    fprintf('\n=== Final BER (ANISO-S, %d frames/SNR) ===\n', aniso_s_verify_numFrames);
    for iSNR_v = 1:nS_v
        fprintf('SNR=%2d dB | OFDM=%.3e (%d/%d) | AFDM=%.3e (%d/%d) | AFWDM=%.3e (%d/%d)\n', ...
            aniso_s_verify_SNR_list(iSNR_v), ...
            err_v(1,iSNR_v)/tot_v(1,iSNR_v), err_v(1,iSNR_v), tot_v(1,iSNR_v), ...
            err_v(2,iSNR_v)/tot_v(2,iSNR_v), err_v(2,iSNR_v), tot_v(2,iSNR_v), ...
            err_v(3,iSNR_v)/tot_v(3,iSNR_v), err_v(3,iSNR_v), tot_v(3,iSNR_v));
    end
    return;
end

%% ===================== Multi-PAS Main Simulation =====================
fprintf('\n================ BER Sweep over PAS Scenarios ================\n');
iso_oneshot_debug_printed = false;
for iScenario = 1:num_pas_scenarios
    rt = scenario_runs{iScenario};
    cfg_sc = rt.cfg;
    Ns_sc = cfg_sc.Nstreams;

    fprintf('\n--- BER Scenario %d/%d: %s ---\n', ...
        iScenario, num_pas_scenarios, scenario_labels{iScenario});

    for iSNR = 1:length(SNR_dB_list)
        SNR_dB = SNR_dB_list(iSNR);
        err_ofdm = 0;  tot_ofdm = 0;
        err_afdm = 0;  tot_afdm = 0;
        err_afwdm = 0; tot_afwdm = 0;
        err_afwdm_blk_sc = 0;  tot_afwdm_blk_sc = 0;

        for frm = 1:numFrames
            H_phys = generate_channel_taps(cfg_sc, rt.Sigma2, rt.Dr, rt.Ds, 1000*frm, channel_norm_mode, rt.Wr_sel, rt.Wt_sel);
            [tau_vec, nu_vec, ~, ~] = generate_phys_dd_paths(cfg_sc, cfg_sc.Lch, 1000*frm);
            [H_eff, G_eff, G_wdm] = build_effective_channels(H_phys, cfg_sc, rt.Wr_sel, rt.Wt_sel);

            H_eff_ber = H_eff;
            G_eff_ber = G_eff;
            if do_equal_energy_norm
                tap1_sdm_pre = 0;
                tap1_wdm_pre = 0;
                tap1_sdm_post = 0;
                tap1_wdm_post = 0;
                for ell = 1:cfg_sc.Lch
                    n_sdm = norm(H_eff{ell}, 'fro');
                    n_wdm = norm(G_wdm{ell}, 'fro');
                    target = sqrt(0.5 * (n_sdm^2 + n_wdm^2));

                    if ell == 1
                        tap1_sdm_pre = n_sdm;
                        tap1_wdm_pre = n_wdm;
                    end

                    if n_sdm > 0
                        H_eff_ber{ell} = (target / n_sdm) * H_eff{ell};
                    end
                    if n_wdm > 0
                        G_eff_ber{ell} = (target / n_wdm) * G_eff{ell};
                    end

                    if ell == 1
                        tap1_sdm_post = norm(H_eff_ber{ell}, 'fro');
                        tap1_wdm_post = norm((cfg_sc.Ur' * G_eff_ber{ell} * cfg_sc.Us), 'fro');
                    end
                end

                if do_equal_energy_norm_log && (mod(frm, eqnorm_log_every) == 0 || frm == numFrames)
                    r_sdm = tap1_sdm_post / max(tap1_sdm_pre, 1e-15);
                    r_wdm = tap1_wdm_post / max(tap1_wdm_pre, 1e-15);
                    fprintf(['[EqNorm][%s] SNR=%2d dB frm=%3d tap1 | ' ...
                             'SDM %.3e->%.3e (x%.3f), WDM %.3e->%.3e (x%.3f)\n'], ...
                            scenario_short_labels{iScenario}, SNR_dB, frm, ...
                            tap1_sdm_pre, tap1_sdm_post, r_sdm, ...
                            tap1_wdm_pre, tap1_wdm_post, r_wdm);
                end
            end

            if use_tx_svd_precoding_for_ber
                H_agg_sdm = zeros(cfg_sc.mr, cfg_sc.ms);
                for ell = 1:cfg_sc.Lch
                    H_agg_sdm = H_agg_sdm + H_eff_ber{ell};
                end
                [U_sdm, ~, V_sdm] = svd(H_agg_sdm, 'econ');
                cfg_sc.Fbb_sdm = V_sdm(:, 1:Ns_sc);
                cfg_sc.Wbb_sdm = U_sdm(:, 1:Ns_sc);

                G_agg_wdm = zeros(cfg_sc.mr, cfg_sc.ms);
                for ell = 1:cfg_sc.Lch
                    G_agg_wdm = G_agg_wdm + cfg_sc.Ur' * G_eff_ber{ell} * cfg_sc.Us;
                end
                [U_wdm, ~, V_wdm] = svd(G_agg_wdm, 'econ');
                cfg_sc.Fbb_wdm = V_wdm(:, 1:Ns_sc);
                cfg_sc.Wbb_wdm = U_wdm(:, 1:Ns_sc);
            end

            cfg_ofdm = cfg_sc;
            cfg_ofdm.c1 = 0;
            cfg_ofdm.c2 = 0;

            % Build block matrices once per frame; OFDM/AFDM share build_block_matrix_afdm
            % (DAFT degenerates to DFT when c1=c2=0).
            H_blk_ofdm_sc  = build_block_matrix_afdm(H_eff_ber,  tau_vec, nu_vec, cfg_ofdm);
            H_blk_afdm_sc  = build_block_matrix_afdm(H_eff_ber,  tau_vec, nu_vec, cfg_sc);
            H_blk_afwdm_sc = build_block_matrix_afwdm(G_eff_ber, tau_vec, nu_vec, cfg_sc);

            if do_iso_oneshot_debug && ~iso_oneshot_debug_printed && ...
                    strcmpi(scenario_short_labels{iScenario}, 'ISO') && iSNR == 1 && frm == 1
                E_phys = 0;
                E_sdm = 0;
                E_g_eff = 0;
                E_g_wdm = 0;
                for ell = 1:cfg_sc.Lch
                    E_phys = E_phys + norm(H_phys{ell}, 'fro')^2;
                    E_sdm = E_sdm + norm(H_eff{ell}, 'fro')^2;
                    E_g_eff = E_g_eff + norm(G_eff{ell}, 'fro')^2;
                    E_g_wdm = E_g_wdm + norm(G_wdm{ell}, 'fro')^2;
                end

                snrLin_dbg = 10^(SNR_dB / 10);
                N0_dbg = 1 / snrLin_dbg;
                alpha_dbg = N0_dbg * cfg_sc.Nstreams;

                fprintf('\n================ ISO One-Shot Debug ================\n');
                fprintf('scenario=%s, SNR=%g dB, frame=%d\n', ...
                    scenario_short_labels{iScenario}, SNR_dB, frm);
                fprintf('dims: Ms=%d Mr=%d | ms=%d mr=%d | Ns=%d\n', ...
                    cfg_sc.Ms, cfg_sc.Mr, cfg_sc.ms, cfg_sc.mr, cfg_sc.Nstreams);
                fprintf('mode sets: ns_prop=%d nr_prop=%d | ns_eff=%d nr_eff=%d\n', ...
                    cfg_sc.ns_prop, cfg_sc.nr_prop, cfg_sc.ns_eff, cfg_sc.nr_eff);
                fprintf('wbb_mode=%s, stream_loading_mode=%s\n', ...
                    cfg_sc.wbb_mode, cfg_sc.stream_loading_mode);
                fprintf('energy: H_phys=%.6e H_eff=%.6e G_eff=%.6e G_wdm=%.6e\n', ...
                    E_phys, E_sdm, E_g_eff, E_g_wdm);
                fprintf('front-end: ||Wt_sel||_F^2=%.6f ||Wr_sel||_F^2=%.6f\n', ...
                    norm(rt.Wt_sel, 'fro')^2, norm(rt.Wr_sel, 'fro')^2);
                fprintf('maps: Fbb_wdm=%dx%d Fbb_sdm=%dx%d\n', ...
                    size(cfg_sc.Fbb_wdm, 1), size(cfg_sc.Fbb_wdm, 2), ...
                    size(cfg_sc.Fbb_sdm, 1), size(cfg_sc.Fbb_sdm, 2));
                fprintf('maps: Wbb_wdm=%dx%d Wbb_sdm=%dx%d\n', ...
                    size(cfg_sc.Wbb_wdm, 1), size(cfg_sc.Wbb_wdm, 2), ...
                    size(cfg_sc.Wbb_sdm, 1), size(cfg_sc.Wbb_sdm, 2));
                fprintf('alpha: N0=%.6e, Ns=%d => alpha=%.6e\n', ...
                    N0_dbg, cfg_sc.Nstreams, alpha_dbg);
                fprintf('block dims: OFDM=%dx%d AFDM=%dx%d AFWDM=%dx%d\n', ...
                    size(H_blk_ofdm_sc, 1), size(H_blk_ofdm_sc, 2), ...
                    size(H_blk_afdm_sc, 1), size(H_blk_afdm_sc, 2), ...
                    size(H_blk_afwdm_sc, 1), size(H_blk_afwdm_sc, 2));
                fprintf('====================================================\n\n');
                iso_oneshot_debug_printed = true;
            end

            % OFDM+SDM via symmetric block-matrix LMMSE (full mr Rx observations)
            [e_ofdm, b_ofdm] = simulate_afdm_snr_block(cfg_ofdm, H_blk_ofdm_sc, QAM_order, SNR_dB);
            err_ofdm = err_ofdm + e_ofdm;
            tot_ofdm = tot_ofdm + b_ofdm;

            % AFDM+SDM via symmetric block-matrix LMMSE
            [e_afdm, b_afdm] = simulate_afdm_snr_block(cfg_sc, H_blk_afdm_sc, QAM_order, SNR_dB);
            err_afdm = err_afdm + e_afdm;
            tot_afdm = tot_afdm + b_afdm;

            if do_ber_op
                [e_afwdm, b_afwdm] = simulate_afwdm_snr(cfg_sc, G_eff_ber, tau_vec, nu_vec, QAM_order, SNR_dB);
                err_afwdm = err_afwdm + e_afwdm;
                tot_afwdm = tot_afwdm + b_afwdm;
            end

            if do_ber_blk && frm <= numFrames_block
                [e_blk, b_blk] = simulate_afwdm_snr_block(cfg_sc, H_blk_afwdm_sc, QAM_order, SNR_dB);
                err_afwdm_blk_sc = err_afwdm_blk_sc + e_blk;
                tot_afwdm_blk_sc = tot_afwdm_blk_sc + b_blk;
            end

            % Energy capture diagnostic every 50 frames (per scenario / SNR)
            if mod(frm, 50) == 0
                E_phys = 0; E_sdm = 0; E_wdm = 0;
                for ell = 1:cfg_sc.Lch
                    E_phys = E_phys + norm(H_phys{ell},   'fro')^2;
                    E_sdm  = E_sdm  + norm(H_eff_ber{ell},'fro')^2;
                    E_wdm  = E_wdm  + norm(G_wdm{ell},    'fro')^2;
                end
                ratio_dB = 10*log10(max(E_wdm,1e-30)/max(E_sdm,1e-30));
                fprintf(['[EnergyCapture][%s] SNR=%2d frm=%3d  ' ...
                         'E_phys=%.3e  E_sdm=%.3e  E_wdm=%.3e  E_wdm/E_sdm=%.2f dB\n'], ...
                        scenario_short_labels{iScenario}, SNR_dB, frm, ...
                        E_phys, E_sdm, E_wdm, ratio_dB);
            end

            if use_tx_svd_precoding_for_ber
                cfg_sc = reset_stream_mapping(cfg_sc);
            end
        end

        ber_ofdm(iScenario, iSNR) = err_ofdm / max(tot_ofdm, 1);
        ber_afdm(iScenario, iSNR) = err_afdm / max(tot_afdm, 1);
        if do_ber_op && tot_afwdm > 0
            ber_afwdm(iScenario, iSNR) = err_afwdm / tot_afwdm;
        end
        if do_ber_blk && tot_afwdm_blk_sc > 0
            ber_afwdm_blk(iScenario, iSNR) = err_afwdm_blk_sc / tot_afwdm_blk_sc;
        end

        line_msg = sprintf('[%s] SNR=%2d dB: BER OFDM=%.3e AFDM=%.3e', ...
            scenario_short_labels{iScenario}, SNR_dB, ...
            ber_ofdm(iScenario, iSNR), ber_afdm(iScenario, iSNR));
        if do_ber_op
            line_msg = [line_msg, sprintf(' AFWDM=%.3e', ber_afwdm(iScenario, iSNR))]; %#ok<AGROW>
        end
        if do_ber_blk
            line_msg = [line_msg, sprintf(' AFWDMblk=%.3e', ber_afwdm_blk(iScenario, iSNR))]; %#ok<AGROW>
        end
        fprintf('%s\n', line_msg);
    end
end
if do_cap_p_sweep
    fprintf('\n================ Capacity Sweep vs P(dBW) over PAS Scenarios ================\n');
    fprintf('  chi^2 = %.2f dBW (linear %.4g)\n', chi2_dBW, chi2_lin);

    for iScenario = 1:num_pas_scenarios
        rt = scenario_runs{iScenario};
        cfg_sc = rt.cfg;

        fprintf('\n--- Capacity Scenario %d/%d: %s ---\n', ...
            iScenario, num_pas_scenarios, scenario_labels{iScenario});

        for iP = 1:length(P_dBW_list)
            P_dBW = P_dBW_list(iP);
            P_lin = 10^(P_dBW / 10);
            snrLin = P_lin / chi2_lin;
            snrLin_from_P(iP) = snrLin;

            cap_blk_ofdm_acc = 0;
            cap_blk_sdm_acc = 0;
            cap_blk_wdm_acc = 0;

            for frm = 1:numFrames
                H_phys = generate_channel_taps(cfg_sc, rt.Sigma2, rt.Dr, rt.Ds, 200000 + 1000*frm, channel_norm_mode, rt.Wr_sel, rt.Wt_sel);
                [tau_vec, nu_vec, ~, ~] = generate_phys_dd_paths(cfg_sc, cfg_sc.Lch, 200000 + 1000*frm);
                [H_eff, G_eff, ~] = build_effective_channels(H_phys, cfg_sc, rt.Wr_sel, rt.Wt_sel);

                if frm <= numFrames_block
                    cfg_ofdm_cap = cfg_sc;
                    cfg_ofdm_cap.c1 = 0;
                    cfg_ofdm_cap.c2 = 0;

                    H_blk_ofdm = build_block_matrix_afdm(H_eff, tau_vec, nu_vec, cfg_ofdm_cap);
                    H_blk_afdm = build_block_matrix_afdm(H_eff, tau_vec, nu_vec, cfg_sc);
                    H_blk_afwdm = build_block_matrix_afwdm(G_eff, tau_vec, nu_vec, cfg_sc);

                    cap_blk_ofdm_acc = cap_blk_ofdm_acc + block_capacity_total(H_blk_ofdm, P_lin, chi2_lin, false, cfg_sc.Nblk);
                    cap_blk_sdm_acc = cap_blk_sdm_acc + block_capacity_total(H_blk_afdm, P_lin, chi2_lin, false, cfg_sc.Nblk);
                    cap_blk_wdm_acc = cap_blk_wdm_acc + block_capacity_total(H_blk_afwdm, P_lin, chi2_lin, false, cfg_sc.Nblk);
                end
            end

            n_blk = min(numFrames, numFrames_block);
            capP_blk_ofdm(iScenario, iP) = cap_blk_ofdm_acc / n_blk;
            capP_blk_sdm(iScenario, iP) = cap_blk_sdm_acc / n_blk;
            capP_blk_wdm(iScenario, iP) = cap_blk_wdm_acc / n_blk;

            fprintf('[%s] P=%+5.1f dBW: BlkTotal OFDM=%.2f AFDM=%.2f AFWDM=%.2f\n', ...
                scenario_short_labels{iScenario}, P_dBW, ...
                capP_blk_ofdm(iScenario, iP), ...
                capP_blk_sdm(iScenario, iP), ...
                capP_blk_wdm(iScenario, iP));
        end
    end
end

%% ---------------- Plot: BER (All PAS Scenarios in One Figure) ----------------
figure('Name', 'BER Across PAS Scenarios');
hold on;
wave_colors = [0.4 0.8 0.4; 0 0.45 0.74; 0.85 0.33 0.10; 0.49 0.18 0.56];
scenario_styles = {'-', '--', ':'};
wave_markers = {'o', 's', '^', 'd'};

for iScenario = 1:num_pas_scenarios
    style_idx = min(iScenario, numel(scenario_styles));
    semilogy(SNR_dB_list, ber_ofdm(iScenario, :), ...
        'LineStyle', scenario_styles{style_idx}, 'Marker', wave_markers{1}, ...
        'LineWidth', 1.6, 'MarkerSize', 7, 'Color', wave_colors(1, :), ...
        'DisplayName', sprintf('%s | OFDM', scenario_short_labels{iScenario}));
    semilogy(SNR_dB_list, ber_afdm(iScenario, :), ...
        'LineStyle', scenario_styles{style_idx}, 'Marker', wave_markers{2}, ...
        'LineWidth', 1.6, 'MarkerSize', 7, 'Color', wave_colors(2, :), ...
        'DisplayName', sprintf('%s | AFDM', scenario_short_labels{iScenario}));
    if do_ber_op
        semilogy(SNR_dB_list, ber_afwdm(iScenario, :), ...
            'LineStyle', scenario_styles{style_idx}, 'Marker', wave_markers{3}, ...
            'LineWidth', 1.6, 'MarkerSize', 7, 'Color', wave_colors(3, :), ...
            'DisplayName', sprintf('%s | AFWDM', scenario_short_labels{iScenario}));
    end
    if do_ber_blk
        semilogy(SNR_dB_list, ber_afwdm_blk(iScenario, :), ...
            'LineStyle', scenario_styles{style_idx}, 'Marker', wave_markers{4}, ...
            'LineWidth', 1.3, 'MarkerSize', 6, 'Color', wave_colors(4, :), ...
            'DisplayName', sprintf('%s | AFWDM-blk', scenario_short_labels{iScenario}));
    end
end
grid on;
ylim([1e-5, 1]);
set(gca, 'YScale', 'log');
yticks(10.^(-5:0));
xlabel('SNR (dB)');
ylabel('BER');
legend('show', 'Location', 'southwest');
title(sprintf('BER across PAS scenarios (%s, Nblk=%d, Ns=%d, wbb=%s)', ...
    experiment_profile, cfg.Nblk, cfg.Nstreams, cfg.wbb_mode));

%% ---------------- Plot: Capacity vs P(dBW) (All PAS Scenarios in One Figure) ----------------
if do_cap_p_sweep
    unit_scale = 1;
    y_unit_label = 'bit/s/Hz';
    if strcmp(cap_p_unit_val, 'kbit')
        unit_scale = 1e-3;
        y_unit_label = 'kbit/s/Hz';
    end

    figure('Name', 'Capacity vs P(dBW) Across PAS Scenarios');
    hold on;
    for iScenario = 1:num_pas_scenarios
        style_idx = min(iScenario, numel(scenario_styles));
        plot(P_dBW_list, unit_scale * capP_blk_ofdm(iScenario, :), ...
            'LineStyle', scenario_styles{style_idx}, 'Marker', wave_markers{1}, ...
            'LineWidth', 1.8, 'MarkerSize', 7, 'Color', wave_colors(1, :), ...
            'DisplayName', sprintf('%s | OFDM', scenario_short_labels{iScenario}));
        plot(P_dBW_list, unit_scale * capP_blk_sdm(iScenario, :), ...
            'LineStyle', scenario_styles{style_idx}, 'Marker', wave_markers{2}, ...
            'LineWidth', 1.8, 'MarkerSize', 7, 'Color', wave_colors(2, :), ...
            'DisplayName', sprintf('%s | AFDM', scenario_short_labels{iScenario}));
        plot(P_dBW_list, unit_scale * capP_blk_wdm(iScenario, :), ...
            'LineStyle', scenario_styles{style_idx}, 'Marker', wave_markers{3}, ...
            'LineWidth', 1.8, 'MarkerSize', 7, 'Color', wave_colors(3, :), ...
            'DisplayName', sprintf('%s | AFWDM', scenario_short_labels{iScenario}));
    end
    grid on;
    xlabel('P (dBW)');
    ylabel(sprintf('Block Total Capacity (%s)', y_unit_label));
    legend('show', 'Location', 'northwest');
    title(sprintf('C_H vs P(dBW) across PAS scenarios (%s, chi^2=%.1f dBW)', ...
        experiment_profile, chi2_dBW));
end

fprintf('\n--- BER Summary (All PAS Scenarios) ---\n');
for iScenario = 1:num_pas_scenarios
    fprintf('  [%s]\n', scenario_short_labels{iScenario});
    for ii = 1:length(SNR_dB_list)
        if do_ber_op
            fprintf('    SNR=%2d dB: OFDM=%9.3e AFDM=%9.3e AFWDM=%9.3e\n', ...
                SNR_dB_list(ii), ber_ofdm(iScenario, ii), ber_afdm(iScenario, ii), ber_afwdm(iScenario, ii));
        else
            fprintf('    SNR=%2d dB: OFDM=%9.3e AFDM=%9.3e AFWDMblk=%9.3e\n', ...
                SNR_dB_list(ii), ber_ofdm(iScenario, ii), ber_afdm(iScenario, ii), ber_afwdm_blk(iScenario, ii));
        end
    end
end

if do_cap_p_sweep
    fprintf('\n--- Capacity Summary vs P(dBW) (All PAS Scenarios) ---\n');
    for iScenario = 1:num_pas_scenarios
        fprintf('  [%s]\n', scenario_short_labels{iScenario});
        for ii = 1:length(P_dBW_list)
            fprintf('    P=%+5.1f dBW: OFDM=%8.3f AFDM=%8.3f AFWDM=%8.3f\n', ...
                P_dBW_list(ii), capP_blk_ofdm(iScenario, ii), ...
                capP_blk_sdm(iScenario, ii), capP_blk_wdm(iScenario, ii));
        end
    end
end

if false
%% ===================== Main Simulation Loop =====================
for iSNR = 1:length(SNR_dB_list)
    SNR_dB = SNR_dB_list(iSNR);
    err_ofdm = 0;  tot_ofdm = 0;   % OFDM (c1=c2=0)
    err_afdm = 0;  tot_afdm = 0;   % AFDM (c1>0)
    err_afwdm= 0;  tot_afwdm= 0;   % AFWDM (WDM)
    err_afwdm_blk = 0;  tot_afwdm_blk = 0;
    cap_ofdm_acc = 0;  % OFDM capacity
    cap_sdm_acc = 0;
    cap_wdm_acc = 0;
    cap_blk_sdm_acc = 0;
    cap_blk_wdm_acc = 0;

    for frm = 1:numFrames
        % ----- Generate physical channel taps (2D planar) -----
        H_phys = cell(1, cfg.Lch);
        for ell = 1:cfg.Lch
            H_phys{ell} = beamspace_apd_channel_2d(cfg.Mr, cfg.Ms, Sigma2, Dr, Ds, 1000*frm+ell, Ur_plain_full, Us_plain_full);
        end

        % Normalize total channel power: sum_ell ||H_ell||_F^2 = Mr*Ms
        % H_phys = normalize_channel_taps(H_phys, cfg.Mr*cfg.Ms);
        H_phys = normalize_channel_taps(H_phys_v, 1);
        % Generate physically meaningful delay-Doppler indices
        % First path is reference (tau=0), Doppler via Jakes spectrum
        [tau_vec, nu_vec, ~, ~] = generate_phys_dd_paths(cfg, cfg.Lch, 1000*frm);

        % ----- AFDM baseline: SDM via sparse point selection -----
        H_eff = cell(1, cfg.Lch);  % mr x ms
        for ell = 1:cfg.Lch
            H_eff{ell} = Wr_sel' * H_phys{ell} * Wt_sel;
        end

        % ----- AFWDM: full physical channel for Tx/Rx aperture -----
        G_eff = H_phys;   % (Mr x Ms per tap) for AFWDM forward/adjoint

        % Projected channel (mr x ms) for capacity computation
        G_wdm = cell(1, cfg.Lch);
        for ell = 1:cfg.Lch
            G_wdm{ell} = cfg.Ur' * H_phys{ell} * cfg.Us;
        end

        % BER channels (optional equal-energy normalization per tap)
        H_eff_ber = H_eff;
        G_eff_ber = G_eff;
        if do_equal_energy_norm
            tap1_sdm_pre = 0;
            tap1_wdm_pre = 0;
            tap1_sdm_post = 0;
            tap1_wdm_post = 0;
            for ell = 1:cfg.Lch
                n_sdm = norm(H_eff{ell}, 'fro');
                n_wdm = norm(G_wdm{ell}, 'fro');
                target = sqrt(0.5 * (n_sdm^2 + n_wdm^2));

                if ell == 1
                    tap1_sdm_pre = n_sdm;
                    tap1_wdm_pre = n_wdm;
                end

                if n_sdm > 0
                    H_eff_ber{ell} = (target / n_sdm) * H_eff{ell};
                end
                if n_wdm > 0
                    % Scale full-aperture channel so projected WDM channel matches target energy.
                    G_eff_ber{ell} = (target / n_wdm) * G_eff{ell};
                end

                if ell == 1
                    tap1_sdm_post = norm(H_eff_ber{ell}, 'fro');
                    tap1_wdm_post = norm((cfg.Ur' * G_eff_ber{ell} * cfg.Us), 'fro');
                end
            end

            if do_equal_energy_norm_log && (mod(frm, eqnorm_log_every) == 0 || frm == numFrames)
                r_sdm = tap1_sdm_post / max(tap1_sdm_pre, 1e-15);
                r_wdm = tap1_wdm_post / max(tap1_wdm_pre, 1e-15);
                fprintf(['[EqNorm] SNR=%2d dB frm=%3d tap1 | ' ...
                         'SDM %.3e->%.3e (x%.3f), WDM %.3e->%.3e (x%.3f)\n'], ...
                        SNR_dB, frm, tap1_sdm_pre, tap1_sdm_post, r_sdm, ...
                        tap1_wdm_pre, tap1_wdm_post, r_wdm);
            end
        end

        % ----- Ergodic capacity: Method 1 — Block with modulation (DFT/DAFT included) -----
        snrLin = 10^(SNR_dB/10);
        if do_cap_bin
            % OFDM: DFT modulation (c1=c2=0), SDM channel
            cap_ofdm_acc = cap_ofdm_acc + wideband_capacity_block(H_eff, tau_vec, nu_vec, cfg, snrLin, 'ofdm');
            % AFDM: DAFT modulation (c1>0), SDM channel
            cap_sdm_acc = cap_sdm_acc + wideband_capacity_block(H_eff, tau_vec, nu_vec, cfg, snrLin, 'afdm');
            % AFWDM: DAFT modulation (c1>0), WDM channel (full aperture projected)
            cap_wdm_acc = cap_wdm_acc + wideband_capacity_block(G_wdm, tau_vec, nu_vec, cfg, snrLin, 'afdm');
        end

        H_blk_afwdm = [];

        % ----- Ergodic capacity: Method 2 — Strict block matrix (slow) -----
        if do_cap_blk && frm <= numFrames_block
            H_blk_afdm  = build_block_matrix_afdm(H_eff, tau_vec, nu_vec, cfg);
            H_blk_afwdm = build_block_matrix_afwdm(G_eff, tau_vec, nu_vec, cfg);
            % BER-aligned SNR sweep:
            %   total power Ptot = Nblk, noise variance chi2 = 1/snrLin
            % but report WHOLE-BLOCK total capacity (no /Nblk).
            cap_blk_sdm_acc = cap_blk_sdm_acc + block_capacity_total(H_blk_afdm, cfg.Nblk, 1/snrLin, false, cfg.Nblk);
            cap_blk_wdm_acc = cap_blk_wdm_acc + block_capacity_total(H_blk_afwdm, cfg.Nblk, 1/snrLin, false, cfg.Nblk);
        end

        % ====== Three-Waveform Simulation ======
        % OFDM: DFT (c1=c2=0) + SDM
        % AFDM: DAFT (c1>0) + SDM
        % AFWDM: DAFT (c1>0) + WDM

        % --- 可选: SVD 子空间预编码 (补充 BER 图) ---
        if use_tx_svd_precoding_for_ber
            % 聚合多径信道 (sum over taps) → 小维度 SVD
            % SDM: 聚合 H_eff_ber
            H_agg_sdm = zeros(cfg.mr, cfg.ms);
            for ell = 1:cfg.Lch
                H_agg_sdm = H_agg_sdm + H_eff_ber{ell};
            end
            [U_sdm, ~, V_sdm] = svd(H_agg_sdm, 'econ');
            cfg.Fbb_sdm = V_sdm(:, 1:Ns);   % ms x Ns (strongest Tx subspace)
            cfg.Wbb_sdm = U_sdm(:, 1:Ns);   % mr x Ns (strongest Rx subspace)

            % WDM: 聚合 Ur' * G_eff_ber * Us
            G_agg_wdm = zeros(cfg.mr, cfg.ms);
            for ell = 1:cfg.Lch
                G_agg_wdm = G_agg_wdm + cfg.Ur' * G_eff_ber{ell} * cfg.Us;
            end
            [U_wdm, ~, V_wdm] = svd(G_agg_wdm, 'econ');
            cfg.Fbb_wdm = V_wdm(:, 1:Ns);   % ms x Ns
            cfg.Wbb_wdm = U_wdm(:, 1:Ns);   % mr x Ns
        end

        % ----- Build block matrices once per frame (shared by OFDM/AFDM/AFWDM) -----
        cfg_ofdm = cfg;  % copy config
        cfg_ofdm.c1 = 0;
        cfg_ofdm.c2 = 0;
        H_blk_ofdm_blk = build_block_matrix_afdm(H_eff_ber,  tau_vec, nu_vec, cfg_ofdm);
        H_blk_afdm_blk = build_block_matrix_afdm(H_eff_ber,  tau_vec, nu_vec, cfg);
        H_blk_afwdm    = build_block_matrix_afwdm(G_eff_ber, tau_vec, nu_vec, cfg);

        % ----- 1) OFDM+SDM via symmetric block-matrix LMMSE -----
        [e_ofdm, b_ofdm] = simulate_afdm_snr_block(cfg_ofdm, H_blk_ofdm_blk, QAM_order, SNR_dB);
        err_ofdm = err_ofdm + e_ofdm;
        tot_ofdm = tot_ofdm + b_ofdm;

        % ----- 2) AFDM+SDM via symmetric block-matrix LMMSE -----
        [e_afdm, b_afdm] = simulate_afdm_snr_block(cfg, H_blk_afdm_blk, QAM_order, SNR_dB);
        err_afdm = err_afdm + e_afdm;
        tot_afdm = tot_afdm + b_afdm;

        % ----- 3) AFWDM operator-chain (optional reference) -----
        if do_ber_op
            [e_afwdm, b_afwdm] = simulate_afwdm_snr(cfg, G_eff_ber, tau_vec, nu_vec, QAM_order, SNR_dB);
            err_afwdm = err_afwdm + e_afwdm;
            tot_afwdm = tot_afwdm + b_afwdm;
        end

        % ----- 4) AFWDM strict block-matrix path (default reported curve) -----
        if do_ber_blk && frm <= numFrames_block
            [e4, b4] = simulate_afwdm_snr_block(cfg, H_blk_afwdm, QAM_order, SNR_dB);
            err_afwdm_blk = err_afwdm_blk + e4;
            tot_afwdm_blk = tot_afwdm_blk + b4;
        end

        % --- 恢复默认 Fbb/Wbb (如果 SVD precoding 改了它们) ---
        if use_tx_svd_precoding_for_ber
            cfg.Fbb_wdm = zeros(cfg.ms, Ns); cfg.Fbb_wdm(1:Ns,1:Ns) = eye(Ns);
            cfg.Wbb_wdm = zeros(cfg.mr, Ns); cfg.Wbb_wdm(1:Ns,1:Ns) = eye(Ns);
            cfg.Fbb_sdm = zeros(cfg.ms, Ns); cfg.Fbb_sdm(1:Ns,1:Ns) = eye(Ns);
            cfg.Wbb_sdm = zeros(cfg.mr, Ns); cfg.Wbb_sdm(1:Ns,1:Ns) = eye(Ns);
        end
    end

    % ====== Store Results (Three-Waveform) ======
    ber_ofdm(iSNR)  = err_ofdm / tot_ofdm;
    ber_afdm(iSNR)  = err_afdm / tot_afdm;
    if do_ber_op && tot_afwdm > 0
        ber_afwdm(iSNR) = err_afwdm / tot_afwdm;
    else
        ber_afwdm(iSNR) = NaN;
    end
    if do_ber_blk && tot_afwdm_blk > 0
        ber_afwdm_blk(iSNR) = err_afwdm_blk / tot_afwdm_blk;
    else
        ber_afwdm_blk(iSNR) = NaN;
    end
    if do_cap_bin
        cap_ofdm(iSNR) = cap_ofdm_acc / numFrames;
        cap_sdm(iSNR) = cap_sdm_acc / numFrames;
        cap_wdm(iSNR) = cap_wdm_acc / numFrames;
    else
        cap_ofdm(iSNR) = NaN;
        cap_sdm(iSNR) = NaN;
        cap_wdm(iSNR) = NaN;
    end

    if do_cap_blk
        n_blk = min(numFrames, numFrames_block);
        cap_blk_sdm(iSNR) = cap_blk_sdm_acc / n_blk;
        cap_blk_wdm(iSNR) = cap_blk_wdm_acc / n_blk;
    else
        cap_blk_sdm(iSNR) = NaN;
        cap_blk_wdm(iSNR) = NaN;
    end

    % Print progress
    ber_msg = sprintf('BER: OFDM=%.3e AFDM=%.3e', ber_ofdm(iSNR), ber_afdm(iSNR));
    if do_ber_op
        ber_msg = [ber_msg, sprintf(' AFWDM=%.3e', ber_afwdm(iSNR))]; %#ok<AGROW>
    end

    cap_msg = '';
    if do_cap_bin
        cap_msg = [cap_msg, sprintf(' Cap(w/mod): OFDM=%.2f AFDM=%.2f AFWDM=%.2f', cap_ofdm(iSNR), cap_sdm(iSNR), cap_wdm(iSNR))]; %#ok<AGROW>
    end
    if do_cap_blk
        cap_msg = [cap_msg, sprintf(' Cap(block total): AFDM=%.2f AFWDM=%.2f', cap_blk_sdm(iSNR), cap_blk_wdm(iSNR))]; %#ok<AGROW>
    end

    fprintf('SNR=%2d dB: %s |%s\n', SNR_dB, ber_msg, cap_msg);
end

%% ---------------- Plot: BER (Three-Waveform Comparison) ----------------
figure;
hold on;
semilogy(SNR_dB_list, ber_ofdm,  '-o', 'LineWidth', 1.5, 'MarkerSize', 8);
semilogy(SNR_dB_list, ber_afdm, '-s', 'LineWidth', 1.5, 'MarkerSize', 8);
ber_legend = {'OFDM (SDM, c1=c2=0)', 'AFDM (SDM, c1>0)'};
if do_ber_op
    semilogy(SNR_dB_list, ber_afwdm, '-^', 'LineWidth', 1.5, 'MarkerSize', 8);
    ber_legend{end+1} = 'AFWDM (WDM, c1>0)';
end
if do_ber_blk
    semilogy(SNR_dB_list, ber_afwdm_blk, '--d', 'LineWidth', 1.5, 'MarkerSize', 8);
    ber_legend{end+1} = 'AFWDM block-matrix';
end
grid on;
ylim([1e-5, 1]);
set(gca, 'YScale', 'log');
yticks(10.^(-5:0));
xlabel('SNR (dB)');
ylabel('BER');
legend(ber_legend, 'Location', 'southwest');
title(sprintf('BER (%s, Nblk=%d, ms=%d, Ns=%d, %s PAS, %d frames, wbb=%s)', ...
    experiment_profile, cfg.Nblk, cfg.ms, cfg.Nstreams, cfg.pas_model, numFrames, cfg.wbb_mode));

%% ---------------- Plot: Ergodic Capacity (Three-Waveform) ----------------
figure;
hold on;
cap_legend = {};
if do_cap_bin
    plot(SNR_dB_list, cap_ofdm, '-o', 'LineWidth', 2, 'MarkerSize', 8, 'Color', [0.4 0.8 0.4]);
    plot(SNR_dB_list, cap_sdm,  '-s', 'LineWidth', 2, 'MarkerSize', 8, 'Color', [0 0.45 0.74]);
    plot(SNR_dB_list, cap_wdm,  '-^', 'LineWidth', 2, 'MarkerSize', 8, 'Color', [0.85 0.33 0.10]);
    cap_legend{end+1} = 'OFDM (DFT+SDM)';
    cap_legend{end+1} = 'AFDM (DAFT+SDM)';
    cap_legend{end+1} = 'AFWDM (DAFT+WDM)';
end
if do_cap_blk
    plot(SNR_dB_list, cap_blk_sdm, '--s', 'LineWidth', 2, 'MarkerSize', 8, 'Color', [0 0.45 0.74]);
    plot(SNR_dB_list, cap_blk_wdm, '--^', 'LineWidth', 2, 'MarkerSize', 8, 'Color', [0.85 0.33 0.10]);
    cap_legend{end+1} = 'AFDM block total (strict)';
    cap_legend{end+1} = 'AFWDM block total (strict)';
end
grid on;
xlabel('SNR (dB)');
if do_cap_bin && do_cap_blk
    ylabel('Capacity (bin avg / block total)');
elseif do_cap_blk
    ylabel('Block Total Capacity (strict)');
else
    ylabel('Ergodic Capacity (bit/s/Hz)');
end
legend(cap_legend, 'Location', 'northwest');
title(sprintf('Capacity (%s, Nblk=%d, ms=%d, %s PAS)', ...
    experiment_profile, cfg.Nblk, cfg.ms, cfg.pas_model));

% Print capacity summary (Three-Waveform)
fprintf('\n--- Ergodic Capacity Summary (w/ Modulation, bit/s/Hz) ---\n');
if do_cap_bin
    fprintf('  SNR     OFDM     AFDM    AFWDM   AFWDM/AFDM ratio\n');
    for ii = 1:length(SNR_dB_list)
        ratio = cap_wdm(ii) / max(cap_sdm(ii), 1e-10);
        fprintf('  %2d    %7.2f %7.2f %7.2f   %5.2fx\n', ...
            SNR_dB_list(ii), cap_ofdm(ii), cap_sdm(ii), cap_wdm(ii), ratio);
    end
end

if do_cap_blk
    fprintf('  [Block-Strict, total]  SNR     SDM      WDM    ratio\n');
    for ii = 1:length(SNR_dB_list)
        g2 = cap_blk_wdm(ii) / max(cap_blk_sdm(ii), 1e-10);
        fprintf('  %2d            %6.2f   %6.2f  %5.2fx\n', ...
            SNR_dB_list(ii), cap_blk_sdm(ii), cap_blk_wdm(ii), g2);
    end
end

% Print BER summary (Three-Waveform)
fprintf('\n--- BER Summary (Three-Waveform) ---\n');
fprintf('  SNR     OFDM        AFDM        AFWDM\n');
for ii = 1:length(SNR_dB_list)
    fprintf('  %2d    %9.3e  %9.3e  %9.3e\n', ...
        SNR_dB_list(ii), ber_ofdm(ii), ber_afdm(ii), ber_afwdm(ii));
end

% Print BER gain: AFWDM vs AFDM vs OFDM
fprintf('\n--- BER Gain (dB): 10*log10(BER_ref/BER_x) ---\n');
fprintf('  SNR    AFWDM/AFDM  AFDM/OFDM  AFWDM/OFDM\n');
for ii = 1:length(SNR_dB_list)
    if ber_afdm(ii) > 0 && ber_afwdm(ii) > 0 && ber_ofdm(ii) > 0
        gain_afwdm_afdm = 10 * log10(ber_afdm(ii) / ber_afwdm(ii));
        gain_afdm_ofdm = 10 * log10(ber_ofdm(ii) / ber_afdm(ii));
        gain_afwdm_ofdm = 10 * log10(ber_ofdm(ii) / ber_afwdm(ii));
        fprintf('  %2d    %+8.2f    %+8.2f    %+8.2f\n', ...
            SNR_dB_list(ii), gain_afwdm_afdm, gain_afdm_ofdm, gain_afwdm_ofdm);
    end
end

%% ---------------- Capacity Reproduction: C_H vs P(dBW) ----------------
if do_cap_p_sweep
    fprintf('\n--- Capacity Reproduction: C_H vs P(dBW) (w/ Modulation) ---\n');
    fprintf('  Model: fixed chi^2, sweep total transmit power P.\n');
    fprintf('  chi^2 = %.2f dBW (linear %.4g).\n', chi2_dBW, chi2_lin);
    fprintf('  Mapping: P_lin = 10^(P_dBW/10), snrLin = P_lin/chi^2.\n');
    fprintf('  Core capacity outputs are bit/s/Hz; display unit can be bit or kbit.\n\n');

    for iP = 1:length(P_dBW_list)
        P_dBW = P_dBW_list(iP);
        P_lin = 10^(P_dBW / 10);
        snrLin = P_lin / chi2_lin;
        snrLin_from_P(iP) = snrLin;

        cap_ofdm_acc = 0;
        cap_sdm_acc = 0;
        cap_wdm_acc = 0;
        cap_blk_sdm_acc = 0;
        cap_blk_wdm_acc = 0;

        for frm = 1:numFrames
            % ----- Generate physical channel taps (2D planar) -----
            H_phys = cell(1, cfg.Lch);
            for ell = 1:cfg.Lch
                H_phys{ell} = beamspace_apd_channel_2d(cfg.Mr, cfg.Ms, Sigma2, Dr, Ds, 200000 + 1000*frm + ell, Ur_plain_full, Us_plain_full);
            end

            % Normalize total channel power: sum_ell ||H_ell||_F^2 = Mr*Ms
            % H_phys = normalize_channel_taps(H_phys, cfg.Mr*cfg.Ms);
            H_phys = normalize_channel_taps(H_phys_v, 1);
            % Generate physically meaningful delay-Doppler indices
            [tau_vec, nu_vec, ~, ~] = generate_phys_dd_paths(cfg, cfg.Lch, 200000 + 1000*frm);

            % ----- AFDM baseline: SDM via sparse point selection -----
            H_eff = cell(1, cfg.Lch);  % mr x ms
            for ell = 1:cfg.Lch
                H_eff{ell} = Wr_sel' * H_phys{ell} * Wt_sel;
            end

            % ----- AFWDM: full physical channel for Tx/Rx aperture -----
            G_eff = H_phys;

            % Projected channel (mr x ms) for capacity computation
            G_wdm = cell(1, cfg.Lch);
            for ell = 1:cfg.Lch
                G_wdm{ell} = cfg.Ur' * H_phys{ell} * cfg.Us;
            end

            if do_cap_bin
                % OFDM: DFT modulation (c1=c2=0), SDM channel
                cap_ofdm_acc = cap_ofdm_acc + wideband_capacity_block(H_eff, tau_vec, nu_vec, cfg, snrLin, 'ofdm');
                % AFDM: DAFT modulation (c1>0), SDM channel
                cap_sdm_acc = cap_sdm_acc + wideband_capacity_block(H_eff, tau_vec, nu_vec, cfg, snrLin, 'afdm');
                % AFWDM: DAFT modulation (c1>0), WDM channel (full aperture projected)
                cap_wdm_acc = cap_wdm_acc + wideband_capacity_block(G_wdm, tau_vec, nu_vec, cfg, snrLin, 'afdm');
            end

            if do_cap_blk && frm <= numFrames_block
                H_blk_afdm  = build_block_matrix_afdm(H_eff, tau_vec, nu_vec, cfg);
                H_blk_afwdm = build_block_matrix_afwdm(G_eff, tau_vec, nu_vec, cfg);
                cap_blk_sdm_acc = cap_blk_sdm_acc + block_capacity_total(H_blk_afdm, P_lin, chi2_lin, false, cfg.Nblk);
                cap_blk_wdm_acc = cap_blk_wdm_acc + block_capacity_total(H_blk_afwdm, P_lin, chi2_lin, false, cfg.Nblk);
            end
        end

        if do_cap_bin
            capP_ofdm(iP) = cap_ofdm_acc / numFrames;
            capP_sdm(iP) = cap_sdm_acc / numFrames;
            capP_wdm(iP) = cap_wdm_acc / numFrames;
        end

        if do_cap_blk
            n_blk = min(numFrames, numFrames_block);
            capP_blk_sdm(iP) = cap_blk_sdm_acc / n_blk;
            capP_blk_wdm(iP) = cap_blk_wdm_acc / n_blk;
        end

        line_msg = sprintf('P=%+5.1f dBW (SNR=%.4g):', P_dBW, snrLin);
        if do_cap_bin
            line_msg = [line_msg, sprintf(' OFDM=%.2f AFDM=%.2f AFWDM=%.2f', capP_ofdm(iP), capP_sdm(iP), capP_wdm(iP))]; %#ok<AGROW>
        end
        if do_cap_blk
            line_msg = [line_msg, sprintf(' BlkTotal AFDM=%.2f AFWDM=%.2f', capP_blk_sdm(iP), capP_blk_wdm(iP))]; %#ok<AGROW>
        end
        fprintf('%s\n', line_msg);
    end

    unit_scale = 1;
    y_unit_label = 'bit/s/Hz';
    if strcmp(cap_p_unit_val, 'kbit')
        unit_scale = 1e-3;
        y_unit_label = 'kbit/s/Hz';
    end

    figure;
    hold on;
    capP_legend = {};
    if do_cap_bin
        plot(P_dBW_list, unit_scale * capP_ofdm, '-o', 'LineWidth', 2, 'MarkerSize', 8, 'Color', [0.4 0.8 0.4]);
        plot(P_dBW_list, unit_scale * capP_sdm, '-s', 'LineWidth', 2, 'MarkerSize', 8, 'Color', [0 0.45 0.74]);
        plot(P_dBW_list, unit_scale * capP_wdm, '-^', 'LineWidth', 2, 'MarkerSize', 8, 'Color', [0.85 0.33 0.10]);
        capP_legend{end+1} = 'OFDM (DFT+SDM)';
        capP_legend{end+1} = 'AFDM (DAFT+SDM)';
        capP_legend{end+1} = 'AFWDM (DAFT+WDM)';
    end
    if do_cap_blk
        plot(P_dBW_list, unit_scale * capP_blk_sdm, '--s', 'LineWidth', 2, 'MarkerSize', 8, 'Color', [0 0.45 0.74]);
        plot(P_dBW_list, unit_scale * capP_blk_wdm, '--^', 'LineWidth', 2, 'MarkerSize', 8, 'Color', [0.85 0.33 0.10]);
        capP_legend{end+1} = 'SDM block total (strict)';
        capP_legend{end+1} = 'WDM block total (strict)';
    end
    grid on;
    xlabel('P (dBW)');
    ylabel(sprintf('C_H (%s)', y_unit_label));
    legend(capP_legend, 'Location', 'northwest');
    title(sprintf('C_H vs P (%s, chi^2=%.1f dBW, ms=%d, %s PAS)', ...
        experiment_profile, chi2_dBW, cfg.ms, cfg.pas_model));

    fprintf('\n--- Unit & Dimension Audit (C_H vs P, w/ Modulation) ---\n');
    fprintf('  chi^2_dBW = %.2f, chi^2_lin = %.6g\n', chi2_dBW, chi2_lin);
    if do_cap_bin
        fprintf('  [Block-Matrix w/ Modulation] P_dBW   P_lin      snrLin    OFDM(bit)  AFDM(bit)  AFWDM(bit)  ratio\n');
        for ii = 1:length(P_dBW_list)
            p_lin_ii = 10^(P_dBW_list(ii)/10);
            g1 = capP_wdm(ii) / max(capP_sdm(ii), 1e-10);
            fprintf('  %+6.1f  %8.4g  %8.4g   %8.3f  %8.3f  %8.3f  %5.2fx\n', ...
                P_dBW_list(ii), p_lin_ii, snrLin_from_P(ii), capP_ofdm(ii), capP_sdm(ii), capP_wdm(ii), g1);
        end
    end
    if do_cap_blk
        fprintf('  [Block-Strict, total] P_dBW   P_lin      snrLin    AFDM(bit)  AFWDM(bit)  ratio\n');
        for ii = 1:length(P_dBW_list)
            p_lin_ii = 10^(P_dBW_list(ii)/10);
            g2 = capP_blk_wdm(ii) / max(capP_blk_sdm(ii), 1e-10);
            fprintf('  %+6.1f  %8.4g  %8.4g   %8.3f  %8.3f  %5.2fx\n', ...
                P_dBW_list(ii), p_lin_ii, snrLin_from_P(ii), capP_blk_sdm(ii), capP_blk_wdm(ii), g2);
        end
    end
end
end

function pas_scenarios = build_pas_scenarios(do_multi_pas_compare, cfg)
if do_multi_pas_compare
    if ~strcmpi(cfg.pas_model, 'vmf')
        error('do_multi_pas_compare=true currently expects cfg.pas_model=''vmf'' so anisotropic PAS can be generated.');
    end

    if isempty(cfg.vmf_circular_var) || isempty(cfg.vmf_mean_theta_deg) || isempty(cfg.vmf_mean_phi_deg)
        error('cfg.vmf_* parameters must be set before build_pas_scenarios when do_multi_pas_compare=true.');
    end

    num_clusters = numel(cfg.vmf_circular_var);
    large_var_scale = 8;

    if numel(cfg.vmf_mean_theta_deg) ~= num_clusters || numel(cfg.vmf_mean_phi_deg) ~= num_clusters
        error('vMF parameter length mismatch: circular_var/theta/phi must have the same number of clusters.');
    end

    switch lower(strtrim(cfg.pas_config))
        case '2cluster'
            cluster_desc = '2-Cluster';
            small_pas_config = '2cluster_smallvar';
            large_pas_config = '2cluster_largevar';

        case '4cluster'
            cluster_desc = '4-Cluster';
            small_pas_config = '4cluster_smallvar';
            large_pas_config = '4cluster_largevar';

        otherwise
            cluster_desc = sprintf('%d-Cluster', num_clusters);
            small_pas_config = sprintf('%dcluster_smallvar', num_clusters);
            large_pas_config = sprintf('%dcluster_largevar', num_clusters);
    end

    vmf_small = cfg.vmf_circular_var;
    %vMF circular variance must be in (0, 1]; clamp effective scale so that
    %max(vmf_large) stays just below 1, otherwise function_channelPAS' fzero
    %fails the endpoint sign-check (myfun is negative at both ends when v>1).
    vmf_safe_upper = 0.99;
    effective_scale = min(large_var_scale, vmf_safe_upper / max(vmf_small));
    if effective_scale < large_var_scale
        fprintf(['[build_pas_scenarios] requested large_var_scale=%g would push ' ...
                 'max(vmf_large)=%.3f above %.2f (vMF circular_var must be <=1); ' ...
                 'clamping effective scale to %.3f.\n'], ...
                large_var_scale, large_var_scale*max(vmf_small), ...
                vmf_safe_upper, effective_scale);
    end
    vmf_large = effective_scale * vmf_small;

    pas_scenarios = struct( ...
        'label', {'Isotropic', ...
                  sprintf('Anisotropic (%s, Small Var)', cluster_desc), ...
                  sprintf('Anisotropic (%s, Large Var)', cluster_desc)}, ...
        'short_label', {'ISO', 'ANISO-S', 'ANISO-L'}, ...
        'pas_model', {'isotropic', 'vmf', 'vmf'}, ...
        'pas_config', {'isotropic', small_pas_config, large_pas_config}, ...
        'vmf_circular_var', {[], vmf_small, vmf_large}, ...
        'vmf_mean_theta_deg', {[], cfg.vmf_mean_theta_deg, cfg.vmf_mean_theta_deg}, ...
        'vmf_mean_phi_deg', {[], cfg.vmf_mean_phi_deg, cfg.vmf_mean_phi_deg});
else
    pas_scenarios = struct( ...
        'label', {sprintf('Single PAS (%s)', cfg.pas_model)}, ...
        'short_label', {'SINGLE'}, ...
        'pas_model', {cfg.pas_model}, ...
        'pas_config', {cfg.pas_config}, ...
        'vmf_circular_var', {cfg.vmf_circular_var}, ...
        'vmf_mean_theta_deg', {cfg.vmf_mean_theta_deg}, ...
        'vmf_mean_phi_deg', {cfg.vmf_mean_phi_deg});
end
end

function runtime = prepare_pas_runtime(cfg_base, pas_case, experiment_profile, rf_budget, Ut2, Ur2)
cfg = cfg_base;
cfg.pas_model = pas_case.pas_model;
cfg.pas_config = pas_case.pas_config;
if strcmpi(cfg.pas_model, 'vmf')
    cfg.vmf_circular_var = pas_case.vmf_circular_var;
    cfg.vmf_mean_theta_deg = pas_case.vmf_mean_theta_deg;
    cfg.vmf_mean_phi_deg = pas_case.vmf_mean_phi_deg;
end

Ur_plain_full = cfg.Ur_full;
Us_plain_full = cfg.Us_full;
Lsx_phys = cfg.Msx * cfg.dx; Lsy_phys = cfg.Msy * cfg.dy;
Lrx_phys = cfg.Mrx * cfg.dx; Lry_phys = cfg.Mry * cfg.dy;

assert(mod(Lsx_phys, 1) == 0 && mod(Lsy_phys, 1) == 0, '发送端天线尺寸(波长)必须是整数！');
assert(mod(Lrx_phys, 1) == 0 && mod(Lry_phys, 1) == 0, '接收端天线尺寸(波长)必须是整数！');

switch cfg.pas_model
    case 'isotropic'
        fprintf('  PAS 模型: 各向同性 (function_computeVar)\n');
        [var_s_my_mx, ~] = function_computeVar(Lsx_phys, Lsy_phys);
        [var_r_my_mx, ~] = function_computeVar(Lrx_phys, Lry_phys);
        Ps_shift_raw = var_s_my_mx.';
        Pr_shift_raw = var_r_my_mx.';

    case 'vmf'
        fprintf('  PAS 模型: von Mises-Fisher mixture (各向异性)\n');
        fprintf('    Clusters: %d\n', length(cfg.vmf_circular_var));
        for cc = 1:length(cfg.vmf_circular_var)
            fprintf('    Cluster %d: cv=%.4f, theta=%.1f°, phi=%.1f°\n', ...
                cc, cfg.vmf_circular_var(cc), cfg.vmf_mean_theta_deg(cc), cfg.vmf_mean_phi_deg(cc));
        end
        mean_theta_rad = cfg.vmf_mean_theta_deg / 180 * pi;
        mean_phi_rad = cfg.vmf_mean_phi_deg / 180 * pi;
        pas_channel = function_channelPAS(cfg.vmf_circular_var, mean_theta_rad, mean_phi_rad);
        fprintf('  Computing Tx variance matrix (may take a while)...\n');
        var_s_raw = function_channelVAR(Lsx_phys, Lsy_phys, pas_channel);
        fprintf('  Computing Rx variance matrix...\n');
        var_r_raw = function_channelVAR(Lrx_phys, Lry_phys, pas_channel);
        Ps_shift_raw = var_s_raw.';
        Pr_shift_raw = var_r_raw.';

    otherwise
        error('Unknown PAS model: %s', cfg.pas_model);
end

[idx_s_prop, n_prop_s] = select_center_modes_2d_overlap(cfg.Msx, cfg.Msy, 0, cfg.dx, cfg.dy);
[idx_r_prop, n_prop_r] = select_center_modes_2d_overlap(cfg.Mrx, cfg.Mry, 0, cfg.dx, cfg.dy);
cfg.idx_s_prop = idx_s_prop;
cfg.idx_r_prop = idx_r_prop;
cfg.ns_prop = n_prop_s;
cfg.nr_prop = n_prop_r;

[KX_s, KY_s] = ndgrid((0:cfg.Msx-1)-floor(cfg.Msx/2), (0:cfg.Msy-1)-floor(cfg.Msy/2));
[KX_r, KY_r] = ndgrid((0:cfg.Mrx-1)-floor(cfg.Mrx/2), (0:cfg.Mry-1)-floor(cfg.Mry/2));
KX_s_phys = KX_s / Lsx_phys; KY_s_phys = KY_s / Lsy_phys;
KX_r_phys = KX_r / Lrx_phys; KY_r_phys = KY_r / Lry_phys;
kappa2_s = KX_s_phys.^2 + KY_s_phys.^2;
kappa2_r = KX_r_phys.^2 + KY_r_phys.^2;
prop_mask_s = kappa2_s <= 1.0;
prop_mask_r = kappa2_r <= 1.0;
if isfield(cfg,'disable_prop_mask') && cfg.disable_prop_mask
    prop_mask_s(:) = true; prop_mask_r(:) = true;   % AF-21 去传播盘mask, 默认off (经 cfg 传入)
end

Ps_shift = Ps_shift_raw .* prop_mask_s;
Pr_shift = Pr_shift_raw .* prop_mask_r;
Ps = ifftshift(Ps_shift); Ps = Ps / sum(Ps(:));
Pr = ifftshift(Pr_shift); Pr = Pr / sum(Pr(:));
Sigma2 = Pr(:) * (Ps(:).');
Sigma2 = Sigma2 / sum(Sigma2(:));

fprintf('\n--- Mode Analysis & Profile Front-End Configuration ---\n');
Ps_vec_all = Ps(:);
Pr_vec_all = Pr(:);
Ps_prop = Ps_vec_all(idx_s_prop);
Pr_prop = Pr_vec_all(idx_r_prop);
[Ps_sorted, s_order_prop] = sort(Ps_prop, 'descend');
[Pr_sorted, r_order_prop] = sort(Pr_prop, 'descend');
cum_s = cumsum(Ps_sorted) / max(sum(Ps_sorted), 1e-15);
cum_r = cumsum(Pr_sorted) / max(sum(Pr_sorted), 1e-15);
ns_eff = find(cum_s >= cfg.eff_energy_capture, 1, 'first');
nr_eff = find(cum_r >= cfg.eff_energy_capture, 1, 'first');
if isempty(ns_eff), ns_eff = length(idx_s_prop); end
if isempty(nr_eff), nr_eff = length(idx_r_prop); end
idx_s_eff = idx_s_prop(s_order_prop(1:ns_eff));
idx_r_eff = idx_r_prop(r_order_prop(1:nr_eff));
cfg.idx_s_eff = idx_s_eff;
cfg.idx_r_eff = idx_r_eff;
cfg.ns_eff = ns_eff;
cfg.nr_eff = nr_eff;

fprintf('  Propagation disk: Tx=%d, Rx=%d modes\n', n_prop_s, n_prop_r);
fprintf('  Significant set (%.0f%% energy): ns_eff=%d, nr_eff=%d\n', ...
    cfg.eff_energy_capture*100, ns_eff, nr_eff);

switch experiment_profile
    case 'supported_dof_baseline'
        fprintf('\n=== Profile: supported_dof_baseline ===\n');
        fprintf('  WDM: propagation-disk plain 2D DFT basis (%d Tx modes, %d Rx modes)\n', ...
            n_prop_s, n_prop_r);
        fprintf('  SDM: sparse sampled array with %d Tx / %d Rx antennas\n', ...
            n_prop_s, n_prop_r);
        cfg.ms = n_prop_s;
        cfg.mr = n_prop_r;
        cfg.ms_rf = n_prop_s;
        cfg.mr_rf = n_prop_r;
        cfg.Nstreams = resolve_stream_count(cfg, min(cfg.ms, cfg.mr));
        cfg.Us = Ut2(:, idx_s_prop);
        cfg.Ur = Ur2(:, idx_r_prop);
        idx_s = idx_s_prop;
        idx_r = idx_r_prop;

        idx_s_ant = select_farthest_uniform_2d(cfg.Msx, cfg.Msy, cfg.ms);
        idx_r_ant = select_farthest_uniform_2d(cfg.Mrx, cfg.Mry, cfg.mr);
        Wt_sel = zeros(cfg.Ms, cfg.ms);
        Wr_sel = zeros(cfg.Mr, cfg.mr);
        for ii = 1:cfg.ms, Wt_sel(idx_s_ant(ii), ii) = 1; end
        for ii = 1:cfg.mr, Wr_sel(idx_r_ant(ii), ii) = 1; end

    case 'full_digital_baseline'
        fprintf('\n=== Profile: full_digital_baseline ===\n');
        fprintf('  SDM: %d-antenna full-digital (Wt=I, Wr=I)\n', cfg.Ms);
        fprintf('  WDM: %d-mode plain 2D DFT basis (no PAS sorting)\n', cfg.Ms);
        cfg.ms = cfg.Ms;
        cfg.mr = cfg.Mr;
        cfg.ms_rf = cfg.Ms;
        cfg.mr_rf = cfg.Mr;
        cfg.Nstreams = resolve_stream_count(cfg, min(cfg.ms, cfg.mr));
        cfg.Us = Ut2;
        cfg.Ur = Ur2;
        Wt_sel = eye(cfg.Ms);
        Wr_sel = eye(cfg.Mr);
        idx_s = 1:cfg.Ms;
        idx_r = 1:cfg.Mr;

    case 'supported_dof_baseline_v5'
        fprintf('\n=== Profile: supported_dof_baseline_v5 (PAS-sorted, Ns capped to ns_eff) ===\n');
        fprintf('  V5 patch test: 按 PAS 能量排序 + Ns <= min(ns_eff, nr_eff)\n');
        fprintf('  (新 profile, 完全不影响 supported_dof_baseline)\n');

        % PAS-sort propagation-disk modes (replaces geometric ordering)
        Ps_in_prop = Ps_vec_all(idx_s_prop);
        Pr_in_prop = Pr_vec_all(idx_r_prop);
        [~, s_sort] = sort(Ps_in_prop, 'descend');
        [~, r_sort] = sort(Pr_in_prop, 'descend');
        idx_s = idx_s_prop(s_sort);
        idx_r = idx_r_prop(r_sort);

        cfg.ms = n_prop_s;
        cfg.mr = n_prop_r;
        cfg.ms_rf = n_prop_s;
        cfg.mr_rf = n_prop_r;

        % 关键: Nstreams 上限改成 min(ns_eff, nr_eff), 避免硬塞 17 个
        cfg.Nstreams = resolve_stream_count(cfg, min(ns_eff, nr_eff));

        cfg.Us = Ut2(:, idx_s);
        cfg.Ur = Ur2(:, idx_r);

        idx_s_ant = select_farthest_uniform_2d(cfg.Msx, cfg.Msy, cfg.ms);
        idx_r_ant = select_farthest_uniform_2d(cfg.Mrx, cfg.Mry, cfg.mr);
        Wt_sel = zeros(cfg.Ms, cfg.ms);
        Wr_sel = zeros(cfg.Mr, cfg.mr);
        for ii = 1:cfg.ms, Wt_sel(idx_s_ant(ii), ii) = 1; end
        for ii = 1:cfg.mr, Wr_sel(idx_r_ant(ii), ii) = 1; end

    case 'rf_limited_baseline'
        fprintf('\n=== Profile: rf_limited_baseline (RF budget=%d) ===\n', rf_budget);
        n_s = min(rf_budget, ns_eff);
        n_r = min(rf_budget, nr_eff);
        idx_s = idx_s_eff(1:n_s);
        idx_r = idx_r_eff(1:n_r);
        cfg.ms_rf = n_s;
        cfg.mr_rf = n_r;
        cfg.ms = n_s;
        cfg.mr = n_r;
        cfg.Nstreams = resolve_stream_count(cfg, min(cfg.ms, cfg.mr));
        cfg.Us = Ut2(:, idx_s);
        cfg.Ur = Ur2(:, idx_r);
        idx_s_ant = select_farthest_uniform_2d(cfg.Msx, cfg.Msy, cfg.ms);
        idx_r_ant = select_farthest_uniform_2d(cfg.Mrx, cfg.Mry, cfg.mr);
        Wt_sel = zeros(cfg.Ms, cfg.ms);
        Wr_sel = zeros(cfg.Mr, cfg.mr);
        for ii = 1:cfg.ms, Wt_sel(idx_s_ant(ii), ii) = 1; end
        for ii = 1:cfg.mr, Wr_sel(idx_r_ant(ii), ii) = 1; end

    otherwise
        error('Unknown experiment_profile: %s', experiment_profile);
end

energy_captured_s = sum(Ps_vec_all(idx_s)) / sum(Ps_vec_all);
energy_captured_r = sum(Pr_vec_all(idx_r)) / sum(Pr_vec_all);
fprintf('  Tx energy capture (WDM modes): %.4f (%.1f%%)\n', energy_captured_s, energy_captured_s*100);
fprintf('  Rx energy capture (WDM modes): %.4f (%.1f%%)\n', energy_captured_r, energy_captured_r*100);
fprintf('  ms=%d, mr=%d, Nstreams=%d\n', cfg.ms, cfg.mr, cfg.Nstreams);

cfg.Phi_s_H_paper = cfg.Us.';
cfg.Phi_s_T_paper = cfg.Us';
cfg.Phi_r_paper = conj(cfg.Ur);
cfg.Phi_r_star_paper = cfg.Ur;
cfg.Phi_r_T_paper = cfg.Ur';
cfg.Phi_r_H_paper = cfg.Ur.';
cfg = reset_stream_mapping(cfg);

if (isfield(cfg, 'sz') && cfg.sz ~= 0) || (isfield(cfg, 'rz') && cfg.rz ~= 0)
    gamma_s_shift = 2*pi * sqrt(max(1 - kappa2_s, 0) .* prop_mask_s);
    gamma_s_vec = reshape(ifftshift(gamma_s_shift), [], 1);
    gamma_r_shift = 2*pi * sqrt(max(1 - kappa2_r, 0) .* prop_mask_r);
    gamma_r_vec = reshape(ifftshift(gamma_r_shift), [], 1);
    Ds = exp(-1j * gamma_s_vec * cfg.sz);
    Dr = exp( 1j * gamma_r_vec * cfg.rz);
else
    Ds = ones(cfg.Ms, 1);
    Dr = ones(cfg.Mr, 1);
end

runtime = struct('cfg', cfg, 'Sigma2', Sigma2, 'Dr', Dr, 'Ds', Ds, ...
    'Wt_sel', Wt_sel, 'Wr_sel', Wr_sel, 'idx_s', idx_s, 'idx_r', idx_r, ...
    'Ur_plain_full', Ur_plain_full, 'Us_plain_full', Us_plain_full);
end

function Ns = resolve_stream_count(cfg, max_supported)
mode_val = 'fixed';
if isfield(cfg, 'stream_loading_mode') && ~isempty(cfg.stream_loading_mode)
    mode_val = lower(strtrim(cfg.stream_loading_mode));
end

switch mode_val
    case 'full_load'
        Ns = max_supported;
    case 'fixed'
        if ~isfield(cfg, 'requested_Nstreams') || isempty(cfg.requested_Nstreams)
            error('cfg.requested_Nstreams must be set when stream_loading_mode=''fixed''.');
        end
        Ns = min(cfg.requested_Nstreams, max_supported);
    otherwise
        error('Unknown cfg.stream_loading_mode: %s. Use ''full_load'' or ''fixed''.', mode_val);
end
end

function cfg = reset_stream_mapping(cfg)
Ns = cfg.Nstreams;

% Fbb 截断 (Ns 个流 → Ns 个 Tx 模式)
% cc-0501-02 fix: SDM 端当 Ns<ms 且 ms=Msx*Msy (full_digital baseline 物理阵列) 时
% 用 select_farthest_uniform_2d 选 Ns 真 uniform 分布的 ant 发射,
% 避免 grid round quirk (select_uniform_points_2d 对 N=5/17 等数会跳过整列或集中边角)
% farthest-point greedy 算法从中心开始, 后续点最大化与已选点的最小距离
% → 给出 well-distributed 点云 (例如 5 ant = 4 角 + 中心 quincunx)
% WDM 端不需要 (mode 顺序由 idx_s 决定, 取前 Ns 是按 PAS 排序后的高能 mode)
cfg.Fbb_sdm = zeros(cfg.ms, Ns);
if Ns < cfg.ms && isfield(cfg,'Msx') && isfield(cfg,'Msy') && (cfg.ms == cfg.Msx * cfg.Msy)
    idx_uniform_tx = select_farthest_uniform_2d(cfg.Msx, cfg.Msy, Ns);
    for kk = 1:Ns
        cfg.Fbb_sdm(idx_uniform_tx(kk), kk) = 1;
    end
else
    cfg.Fbb_sdm(1:Ns, 1:Ns) = eye(Ns);
end
cfg.Fbb_wdm = zeros(cfg.ms, Ns);  cfg.Fbb_wdm(1:Ns, 1:Ns) = eye(Ns);

% Wbb 按 cfg.wbb_mode 切换 Rx 接收架构
wbb_mode_local = 'hybrid';   % 默认
if isfield(cfg, 'wbb_mode') && ~isempty(cfg.wbb_mode)
    wbb_mode_local = lower(cfg.wbb_mode);
end
switch wbb_mode_local
    case 'hybrid'
        cfg.Wbb_sdm = zeros(cfg.mr, Ns);  cfg.Wbb_sdm(1:Ns, 1:Ns) = eye(Ns);
        cfg.Wbb_wdm = zeros(cfg.mr, Ns);  cfg.Wbb_wdm(1:Ns, 1:Ns) = eye(Ns);
    case 'fully_digital'
        cfg.Wbb_sdm = eye(cfg.mr);
        cfg.Wbb_wdm = eye(cfg.mr);
    otherwise
        error('Unknown cfg.wbb_mode: %s. Use ''hybrid'' or ''fully_digital''.', wbb_mode_local);
end
end

function H_phys = generate_channel_taps(cfg, Sigma2, Dr, Ds, seed_base, channel_norm_mode, Wr_sel, Wt_sel)
H_phys = cell(1, cfg.Lch);
for ell = 1:cfg.Lch
    H_phys{ell} = beamspace_apd_channel_2d(cfg.Mr, cfg.Ms, Sigma2, Dr, Ds, ...
        seed_base + ell, cfg.Ur_full, cfg.Us_full);
end

switch lower(strtrim(channel_norm_mode))
    case 'none'
        % no-op
    case 'unit'
        H_phys = normalize_channel_taps(H_phys, 1);
    case 'mrms'
        H_phys = normalize_channel_taps(H_phys, cfg.Mr * cfg.Ms);
    case 'post_sdm'
        % RF 后端等能量: sum ||Wr_sel' * H_phys * Wt_sel||_F^2 = ms * mr
        tot_sdm = 0;
        for ell = 1:cfg.Lch
            P = Wr_sel' * H_phys{ell} * Wt_sel;
            tot_sdm = tot_sdm + norm(P, 'fro')^2;
        end
        if tot_sdm > 0
            s = sqrt((cfg.ms * cfg.mr) / tot_sdm);
            for ell = 1:cfg.Lch
                H_phys{ell} = s * H_phys{ell};
            end
        end
    otherwise
        error('Unknown channel_norm_mode: %s', channel_norm_mode);
end
end

function [H_eff, G_eff, G_wdm] = build_effective_channels(H_phys, cfg, Wr_sel, Wt_sel)
H_eff = cell(1, cfg.Lch);
G_wdm = cell(1, cfg.Lch);
for ell = 1:cfg.Lch
    H_eff{ell} = Wr_sel' * H_phys{ell} * Wt_sel;
    G_wdm{ell} = cfg.Ur' * H_phys{ell} * cfg.Us;
end
G_eff = H_phys;
end

function vec = expand_per_snr_param(val, nS, name)
if isscalar(val)
    vec = repmat(val, 1, nS);
elseif isvector(val) && numel(val) == nS
    vec = reshape(val, 1, []);
else
    error('%s must be a scalar or a length-%d vector.', name, nS);
end
end

function diag_out = run_aniso_s_afwdm_diagnostics(results_struct, rt, channel_norm_mode, num_rank_samples, num_tail_points)
cfg = rt.cfg;
diag_out = struct();
diag_out.timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
diag_out.wbb_mode = cfg.wbb_mode;
diag_out.Nblk = cfg.Nblk;
diag_out.Nstreams = cfg.Nstreams;
diag_out.ms = cfg.ms;
diag_out.mr = cfg.mr;

tail_fit = fit_diversity_order_from_ber(results_struct.snr_db, results_struct.ber, ...
    results_struct.err_bits, num_tail_points);
diag_out.tail_fit = tail_fit;

rank_diag = diagnose_afwdm_block_rank(rt, channel_norm_mode, num_rank_samples);
diag_out.rank_diag = rank_diag;

fprintf('\n=== ANISO-S AFWDM Tail Diagnostics ===\n');
if tail_fit.valid
    fprintf(['  Tail fit using SNR = [%s] dB\n' ...
             '  log10(BER) = %.4f %+.4f * log10(SNRlin)\n' ...
             '  => estimated d_eff = %.4f, weighted R^2 = %.4f\n'], ...
        num2str(tail_fit.snr_db_used), ...
        tail_fit.intercept, tail_fit.slope_log10_snr, ...
        tail_fit.d_eff, tail_fit.r2_weighted);
else
    fprintf('  Tail fit skipped: %s\n', tail_fit.reason);
end

fprintf(['  Effective block dims: %d x %d (rows x cols)\n' ...
         '  Full-column-rank ratio over %d channels: %.3f\n' ...
         '  Rank min/median/max: %d / %d / %d\n' ...
         '  sigma_min min/median/p05: %.3e / %.3e / %.3e\n' ...
         '  cond median / p95: %.3e / %.3e\n'], ...
    rank_diag.n_rows, rank_diag.n_cols, rank_diag.num_samples, rank_diag.full_column_rank_ratio, ...
    rank_diag.rank_min, rank_diag.rank_median, rank_diag.rank_max, ...
    rank_diag.sigma_min_min, rank_diag.sigma_min_median, rank_diag.sigma_min_p05, ...
    rank_diag.cond_median, rank_diag.cond_p95);
end

function fit = fit_diversity_order_from_ber(snr_db, ber, err_bits, num_tail_points)
fit = struct('valid', false, 'reason', '', 'snr_db_used', [], ...
    'intercept', NaN, 'slope_log10_snr', NaN, 'd_eff', NaN, 'r2_weighted', NaN);

valid = isfinite(snr_db) & isfinite(ber) & isfinite(err_bits) & (ber > 0);
snr_db = double(snr_db(valid(:)));
ber = double(ber(valid(:)));
err_bits = double(err_bits(valid(:)));

if numel(snr_db) < max(2, num_tail_points)
    fit.reason = 'not enough positive-BER points';
    return;
end

[snr_db, order] = sort(snr_db(:));
ber = ber(order);
err_bits = err_bits(order);

n_use = min(num_tail_points, numel(snr_db));
idx = (numel(snr_db) - n_use + 1):numel(snr_db);
log10_snr = snr_db(idx) / 10;
log10_ber = log10(ber(idx));
weights = max(err_bits(idx), 1);
X = [ones(numel(log10_snr), 1), log10_snr(:)];
W = diag(weights(:));
beta = (X' * W * X) \ (X' * W * log10_ber(:));
fit_line = X * beta;

ss_res = sum(weights(:) .* (log10_ber(:) - fit_line(:)).^2);
avg_y = sum(weights(:) .* log10_ber(:)) / sum(weights(:));
ss_tot = sum(weights(:) .* (log10_ber(:) - avg_y).^2);

fit.valid = true;
fit.snr_db_used = snr_db(idx).';
fit.intercept = beta(1);
fit.slope_log10_snr = beta(2);
fit.d_eff = -beta(2);
fit.r2_weighted = 1 - ss_res / max(ss_tot, 1e-15);
end

function rank_diag = diagnose_afwdm_block_rank(rt, channel_norm_mode, num_samples)
cfg = rt.cfg;
Ns = min(cfg.Nstreams, min(cfg.ms, cfg.mr));
if isfield(cfg, 'Wbb_wdm') && ~isempty(cfg.Wbb_wdm)
    Prx = size(cfg.Wbb_wdm, 2);
else
    Prx = cfg.mr;
end

n_rows = Prx * cfg.Nblk;
n_cols = Ns * cfg.Nblk;
ranks = zeros(num_samples, 1);
sigma_min = zeros(num_samples, 1);
cond_vals = zeros(num_samples, 1);
full_rank_flags = false(num_samples, 1);

for ii = 1:num_samples
    seed_base = 900000 + 1000 * ii;
    H_phys = generate_channel_taps(cfg, rt.Sigma2, rt.Dr, rt.Ds, seed_base, ...
        channel_norm_mode, rt.Wr_sel, rt.Wt_sel);
    [tau_vec, nu_vec, ~, ~] = generate_phys_dd_paths(cfg, cfg.Lch, seed_base);
    [~, G_eff, ~] = build_effective_channels(H_phys, cfg, rt.Wr_sel, rt.Wt_sel);
    H_blk = build_block_matrix_afwdm(G_eff, tau_vec, nu_vec, cfg);
    H_eff_blk = apply_stream_mapping_to_block(H_blk, cfg, 'wdm');

    s = svd(H_eff_blk);
    tol = max(size(H_eff_blk)) * eps(max(s));
    ranks(ii) = sum(s > tol);
    sigma_min(ii) = s(end);
    cond_vals(ii) = s(1) / max(s(end), 1e-15);
    full_rank_flags(ii) = (ranks(ii) == n_cols);
end

rank_diag = struct();
rank_diag.num_samples = num_samples;
rank_diag.n_rows = n_rows;
rank_diag.n_cols = n_cols;
rank_diag.full_column_rank_ratio = mean(full_rank_flags);
rank_diag.rank_min = min(ranks);
rank_diag.rank_median = median(ranks);
rank_diag.rank_max = max(ranks);
rank_diag.sigma_min_min = min(sigma_min);
rank_diag.sigma_min_median = median(sigma_min);
rank_diag.sigma_min_p05 = percentile_local(sigma_min, 5);
rank_diag.cond_median = median(cond_vals);
rank_diag.cond_p95 = percentile_local(cond_vals, 95);
end

function H_eff_blk = apply_stream_mapping_to_block(H_blk, cfg, domain_tag)
Nblk = cfg.Nblk;
ms = cfg.ms;
mr = cfg.mr;
Ns = min(cfg.Nstreams, min(ms, mr));

switch lower(domain_tag)
    case 'wdm'
        if ~isfield(cfg, 'Fbb_wdm') || isempty(cfg.Fbb_wdm)
            Fbb = zeros(ms, Ns);
            Fbb(1:Ns, 1:Ns) = eye(Ns);
        else
            Fbb = cfg.Fbb_wdm;
        end
        if ~isfield(cfg, 'Wbb_wdm') || isempty(cfg.Wbb_wdm)
            Wbb = eye(mr);
        else
            Wbb = cfg.Wbb_wdm;
        end
    case 'sdm'
        if ~isfield(cfg, 'Fbb_sdm') || isempty(cfg.Fbb_sdm)
            Fbb = zeros(ms, Ns);
            Fbb(1:Ns, 1:Ns) = eye(Ns);
        else
            Fbb = cfg.Fbb_sdm;
        end
        if ~isfield(cfg, 'Wbb_sdm') || isempty(cfg.Wbb_sdm)
            Wbb = eye(mr);
        else
            Wbb = cfg.Wbb_sdm;
        end
    otherwise
        error('Unknown domain tag: %s', domain_tag);
end

Ttx = kron(conj(Fbb), eye(Nblk));
Trx = kron(Wbb.', eye(Nblk));
H_eff_blk = Trx * H_blk * Ttx;
end

function v = percentile_local(x, p)
x = sort(x(:));
if isempty(x)
    v = NaN;
    return;
end
if numel(x) == 1
    v = x;
    return;
end
pos = 1 + (numel(x) - 1) * (p / 100);
lo = floor(pos);
hi = ceil(pos);
if lo == hi
    v = x(lo);
else
    alpha = pos - lo;
    v = (1 - alpha) * x(lo) + alpha * x(hi);
end
end
