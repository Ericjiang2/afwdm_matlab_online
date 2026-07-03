%% main_atlas_v4_delivery.m
% 交付版 MATLAB 主脚本: latest atlas v4 BER + optional capacity.
%
% 探索阶段 wrapper 链条整理成清楚的通信仿真流程。
%
% 使用:
%   mode = "quick";   % M 默认: 很少帧, 只验证流程
%   mode = "paper";   % 对齐 atlas v4 范围, 建议在 Win MATLAB / 远程机器跑
%   run_capacity = false;  % 默认 false; 需要容量曲线时改 true
%   run('delivery/atlas_v4_matlab/main_atlas_v4_delivery.m')
%
% 与 main.pdf 对应:
%   - Eq.(1): 2D Fourier / wavenumber basis
%   - Eq.(21)-(32): PAS, per-path Sigma_p, paper Eq.(32) channel scaling
%   - Eq.(45),(48): AFWDM block equivalent channel
%   - Eq.(49)-(56): SVD-precoded MIMO-AFDM benchmark
%
% 最新 atlas v4 口径:
%   - SNR 是 per-symbol unit-QAM SNR, N0=1/SNR
%   - imperfect CSI 可使用 snr_coupled 或 fixed_var, 由 cfg_run.csi_error_mode 控制
%   - mode selection 用 overlap/nomask; main.pdf Eq.(4)-(5) strict center
%     ellipse 只保留在 select_modes_main_eq45_reference.m 做对照

clearvars -except mode run_capacity; clc; close all;

this_dir = fileparts(mfilename('fullpath'));
addpath(this_dir);

if ~exist('mode', 'var') || isempty(mode)
    mode = "quick";
end
cfg_run = make_delivery_config(mode);
if exist('run_capacity', 'var') && ~isempty(run_capacity)
    cfg_run.run_capacity = logical(run_capacity);
end
for ii = 1:numel(cfg_run.path_dirs)
    if exist(cfg_run.path_dirs{ii}, 'dir')
        addpath(cfg_run.path_dirs{ii});
    end
end
if ~exist(cfg_run.output_dir, 'dir')
    mkdir(cfg_run.output_dir);
end

warning('off', 'svd_precoder_from_G:RankDeficient');

fprintf('\n============================================================\n');
fprintf(' Atlas v4 delivery simulation (%s mode)\n', cfg_run.mode);
fprintf(' Output: %s\n', cfg_run.output_dir);
fprintf(' Capacity enabled: %d\n', cfg_run.run_capacity);
fprintf('============================================================\n');

%% 1. 结果容器
nScheme = numel(cfg_run.schemes);
nStrategy = numel(cfg_run.strategies);
nSNR = numel(cfg_run.SNR_dB_list);
nCsi = numel(cfg_run.kappa_list);
nScenario = numel(cfg_run.ber_scenarios);

BER = nan(nScheme, nStrategy, nSNR, nCsi, nScenario);
err_total = zeros(nScheme, nStrategy, nSNR, nCsi, nScenario);
bit_total = zeros(nScheme, nStrategy, nSNR, nCsi, nScenario);
Ns_used = nan(nStrategy, nScenario);
mode_summary = cell(1, nScenario);
scenario_labels = cell(1, nScenario);
csi_modes = cell(1, nCsi);
csi_case_labels = cell(1, nCsi);
for iCsi = 1:nCsi
    [csi_modes{iCsi}, ~, csi_case_labels{iCsi}] = resolve_csi_case(cfg_run, iCsi);
end

%% 2. BER 主流程: 参数 -> PAS -> 模式 -> 信道 -> CSI -> block channel -> LMMSE
for iScenario = 1:nScenario
    scenario_spec = cfg_run.ber_scenarios(iScenario);
    scenario_labels{iScenario} = scenario_spec.label;

    fprintf('\n------------------------------------------------------------\n');
    fprintf('BER scenario %d/%d: %s\n', iScenario, nScenario, scenario_spec.label);
    fprintf('------------------------------------------------------------\n');

    % 2.1 PAS 与统计信道准备
    % 代码动作: 得到 Sigma2 / Sigma2_p / cfg_base / Dr / Ds.
    % 公式对应: main.pdf Eq.(21)-(32).
    scenario = prepare_delivery_scenario(cfg_run, scenario_spec);
    cfg_base = scenario.cfg;

    % 2.2 模式选择
    % 代码动作: 最新 atlas v4 overlap/nomask 候选池 + 能量排序.
    % 公式关系: 不是 main.pdf Eq.(4)-(5) strict center ellipse; reference helper 保留。
    modes = select_modes_atlas_v4(cfg_base, scenario.Sigma2, cfg_run.adapt_power_floor);
    mode_summary{iScenario} = modes;

    fprintf('  selector=%s, full=%d, adaptive=%d, nnz=%d\n', ...
        modes.selector, modes.N_full, modes.N_adapt, modes.nnz_modes);
    fprintf('  strict Eq.(4)-(5) reference exists but is not used in atlas v4 default.\n');

    % 2.3 strategy loop: full / adaptive
    for iStrategy = 1:nStrategy
        strategy = cfg_run.strategies{iStrategy};
        N_s = resolve_delivery_streams(strategy, modes, cfg_run);
        Ns_used(iStrategy, iScenario) = N_s;
        fprintf('\n  Strategy=%s, N_s=%d\n', strategy, N_s);

        % AFWDM: 2D wavenumber basis, selected by atlas v4 modal energy.
        Us_afwdm = cfg_base.Us_full(:, modes.sort_s(1:N_s));
        Ur_afwdm = cfg_base.Ur_full(:, modes.sort_r(1:N_s));

        % DFT_precoded: geometry-blind 1D DFT baseline.
        [W_s_dft, W_r_dft] = build_dft_precoder(cfg_base.Ms, cfg_base.Mr, N_s, N_s);

        for iSNR = 1:nSNR
            SNR_dB = cfg_run.SNR_dB_list(iSNR);
            fprintf('    SNR=%g dB: ', SNR_dB);

            err_acc = zeros(nScheme, nCsi);
            bit_acc = zeros(nScheme, nCsi);

            for frm = 1:cfg_run.numFrames_BER
                seed_base = cfg_run.seed.frame_stride * (cfg_run.frame_start_offset + frm);

                % 2.4 DD path indices
                % 公式对应: main.pdf Eq.(33)-(40) 的离散 delay-Doppler path.
                [tau_vec, nu_vec] = generate_phys_dd_paths(cfg_base, cfg_base.Lch, seed_base);

                % 2.5 真实物理信道 H_phys
                % 公式对应: main.pdf Eq.(31)-(32).
                H_phys = build_delivery_channel_taps(scenario, seed_base);

                for iCsi = 1:nCsi
                    [csi_mode, csi_val] = resolve_csi_case(cfg_run, iCsi);

                    % 2.6 CSI estimate
                    % snr_coupled: sigma_e^2 = kappa/(SNR*Lch).
                    % fixed_var:   sigma_e^2 = csi_val, independent of SNR.
                    rng(seed_base * cfg_run.seed.csi_stride + iCsi * cfg_run.seed.csi_case_offset);
                    H_hat = inject_csi_error(H_phys, csi_val, 10^(SNR_dB/10), ...
                        cfg_base.Mr, cfg_base.Ms, cfg_base.Lch, csi_mode);

                    % 2.7 SVD_paper precoder uses estimated channel.
                    % 公式对应: main.pdf Eq.(49)-(56).
                    G_hat = build_G_paper_eq31(H_hat, 'sum_taps');
                    [W_s_svd, W_r_svd] = svd_precoder_from_G(G_hat, N_s, N_s);

                    Us_list = {Us_afwdm, W_s_dft, W_s_svd};
                    Ur_list = {Ur_afwdm, W_r_dft, W_r_svd};

                    for k = 1:nScheme
                        cfg_k = make_delivery_scheme_cfg(cfg_base, Us_list{k}, Ur_list{k}, N_s, cfg_run);

                        % 2.8 Block equivalent channel
                        % Hr 是真实传播信道, Hd 是接收机估计信道.
                        % 公式对应: main.pdf Eq.(45),(48).
                        Hr = build_block_matrix_afwdm(H_phys, tau_vec, nu_vec, cfg_k);
                        Hd = build_block_matrix_afwdm(H_hat, tau_vec, nu_vec, cfg_k);

                        % 2.9 QPSK + LMMSE detection
                        % 基础仿真操作: unit-average QAM, N0=1/SNR, alpha=N0.
                        [e, b] = simulate_imperfect_csi_block(cfg_k, Hr, Hd, ...
                            cfg_run.QAM_order, SNR_dB);
                        err_acc(k, iCsi) = err_acc(k, iCsi) + e;
                        bit_acc(k, iCsi) = bit_acc(k, iCsi) + b;
                    end
                end
            end

            for iCsi = 1:nCsi
                err_total(:, iStrategy, iSNR, iCsi, iScenario) = err_acc(:, iCsi);
                bit_total(:, iStrategy, iSNR, iCsi, iScenario) = bit_acc(:, iCsi);
                BER(:, iStrategy, iSNR, iCsi, iScenario) = ...
                    err_acc(:, iCsi) ./ max(bit_acc(:, iCsi), 1);
            end

            for iCsi = 1:nCsi
                fprintf('%s [A %.2e D %.2e S %.2e] ', ...
                    csi_case_labels{iCsi}, ...
                    BER(1,iStrategy,iSNR,iCsi,iScenario), ...
                    BER(2,iStrategy,iSNR,iCsi,iScenario), ...
                    BER(3,iStrategy,iSNR,iCsi,iScenario));
            end
            fprintf('\n');
        end
    end
end

%% 3. Optional capacity helper
capacity_results = [];
if cfg_run.run_capacity
    fprintf('\n[capacity] running optional water-filling capacity helper...\n');
    capacity_results = run_delivery_capacity(cfg_run);
end

low_mimo_results = [];
if cfg_run.run_low_mimo_precoding
    fprintf('\n[low-mimo] running 5x5/Ns=1 waveform+precoding comparison...\n');
    low_mimo_results = run_low_mimo_precoding_ber(cfg_run);
end

%% 4. 保存 .mat 和 .png
results = struct();
results.BER = BER;
results.err_total = err_total;
results.bit_total = bit_total;
results.SNR_dB = cfg_run.SNR_dB_list;
results.kappa_list = cfg_run.kappa_list;
results.schemes = cfg_run.schemes;
results.strategies = cfg_run.strategies;
results.scenario_labels = scenario_labels;
results.csi_modes = csi_modes;
results.csi_case_labels = csi_case_labels;
results.Ns_used = Ns_used;
results.mode_summary = mode_summary;
results.capacity = capacity_results;
results.low_mimo = low_mimo_results;

metadata = struct();
metadata.mode = cfg_run.mode;
metadata.generated_by = 'delivery/atlas_v4_matlab/main_atlas_v4_delivery.m';
metadata.timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
metadata.snr_definition = cfg_run.snr_definition;
metadata.csi_error_mode = cfg_run.csi_error_mode;
metadata.channel_norm_mode = cfg_run.channel_norm_mode;
metadata.paper_channel_scaling = 'sqrt_MrMs_sigma_p_no_frame_norm';
metadata.fixed_var_status = 'implemented for paperfig controlled CSI-error floor plots';
metadata.mode_selector = cfg_run.mode_selector;
metadata.main_eq4_eq5_status = 'reference helper exists, not used by latest atlas v4 default';
if ~isempty(cfg_run.quick_stream_cap)
    metadata.quick_stream_cap = cfg_run.quick_stream_cap;
end

out_mat = fullfile(cfg_run.output_dir, sprintf('atlas_v4_delivery_%s_%s.mat', ...
    cfg_run.mode, datestr(now, 'yyyymmdd_HHMMSS')));
save(out_mat, 'results', 'metadata', 'cfg_run', '-v7');
plot_files = plot_delivery_results(results, cfg_run);

fprintf('\n============================================================\n');
fprintf(' Delivery simulation done.\n');
fprintf(' MAT: %s\n', out_mat);
for ii = 1:numel(plot_files)
    fprintf(' PNG: %s\n', plot_files{ii});
end
fprintf('============================================================\n');

%% Local helpers kept inside the main script because they are part of BER flow.
function N_s = resolve_delivery_streams(strategy, modes, cfg_run)
if isnumeric(strategy)
    N_s = strategy;
elseif strcmp(strategy, 'full')
    N_s = modes.N_full;
elseif strcmp(strategy, 'adaptive')
    N_s = modes.N_adapt;
else
    error('main_atlas_v4_delivery:unknownStrategy', 'Unknown strategy "%s".', strategy);
end

N_s = min(N_s, modes.N_full);
if ~isempty(cfg_run.quick_stream_cap)
    N_s = min(N_s, cfg_run.quick_stream_cap);
end
end

function [csi_mode, csi_val, csi_label] = resolve_csi_case(cfg_run, iCsi)
csi_val = cfg_run.kappa_list(iCsi);
csi_mode = cfg_run.csi_error_mode;
if csi_val <= 0
    csi_label = 'perfect CSI';
else
    if strcmpi(csi_mode, 'fixed_var')
        csi_label = sprintf('fixed-var CSI, sigma_e^2=%g', csi_val);
    else
        csi_label = sprintf('CSI error, kappa=%g', csi_val);
    end
end
if numel(cfg_run.csi_case_labels) >= iCsi && ~isempty(cfg_run.csi_case_labels{iCsi})
    csi_label = cfg_run.csi_case_labels{iCsi};
end
end
