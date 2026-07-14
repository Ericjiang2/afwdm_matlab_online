function cfg_run = make_delivery_config(mode)
%MAKE_DELIVERY_CONFIG  Delivery-version switches for atlas v4 simulations.
%
% 用法:
%   cfg_run = make_delivery_config("quick");
%   cfg_run = make_delivery_config("smoke");
%   cfg_run = make_delivery_config("fullmini");
%   cfg_run = make_delivery_config("local2min");
%   cfg_run = make_delivery_config("paper");
%   cfg_run = make_delivery_config("paperfig");
%   cfg_run = make_delivery_config("paperfig_iso");
%   cfg_run = make_delivery_config("paperfig_vmf");
%   cfg_run = make_delivery_config("paperfig_capacity");
%   cfg_run = make_delivery_config("paperfig_low_mimo");
%
% 交付版主路线:
%   - BER: AFWDM / DFT_precoded / SVD_paper
%   - CSI: snr_coupled 或 fixed_var, 由 mode 决定
%   - Channel: paper Eq.(32), sqrt(Mr*Ms)*Sigma_p, no frame renormalization
%   - Mode set: latest atlas v4 overlap/nomask selector

if nargin < 1 || isempty(mode)
    mode = "quick";
end
mode = lower(string(mode));

this_dir = fileparts(mfilename('fullpath'));
repo_root = fileparts(fileparts(this_dir));

cfg_run = struct();
cfg_run.mode = char(mode);
cfg_run.repo_root = repo_root;
cfg_run.delivery_dir = this_dir;
cfg_run.output_dir = fullfile(this_dir, 'outputs');

% MATLAB path dependencies used by the clean delivery scripts.
cfg_run.path_dirs = { ...
    repo_root, ...
    fullfile(repo_root, 'tools'), ...
    fullfile(repo_root, 'variance'), ...
    fullfile(repo_root, 'variance_aniso'), ...
    fullfile(repo_root, '方差计算'), ...
    fullfile(repo_root, '方差计算', '各向异性')};

% Shared physical / waveform setup, matching the current atlas v4 chain.
cfg_run.array_shape = [8, 8];
cfg_run.fc = 4e9;
cfg_run.v_max_kmh = 540;
cfg_run.Deltaf = 2e3;
cfg_run.Nblk = 64;
cfg_run.tau_max_us = 16;
cfg_run.dx = 0.5;
cfg_run.dy = 0.5;
cfg_run.pas_config = '2cluster';
cfg_run.vmf_mean_theta_deg = [30, 10];
cfg_run.vmf_mean_phi_deg = [15, 180];
cfg_run.disable_prop_mask = true;       % atlas v4: overlap/nomask route
cfg_run.use_perpath_sigma = true;       % main.pdf Eq.(26)-(32) route for vMF
cfg_run.channel_norm_mode = 'paper_eq32';
cfg_run.mode_selector = 'atlas_v4_overlap_nomask';
cfg_run.adapt_power_floor = 0.10;

% BER definitions.
cfg_run.schemes = {'AFWDM', 'DFT_precoded', 'SVD_paper'};
cfg_run.strategies = {'full', 'adaptive'};
cfg_run.QAM_order = 4;
cfg_run.csi_error_mode = 'snr_coupled';
cfg_run.csi_case_labels = {};
cfg_run.snr_definition = 'per_symbol_unit_qam';
cfg_run.block_lmmse_solver = 'direct';
cfg_run.frame_start_offset = 0;
cfg_run.plot_csi_cases_together = false;
cfg_run.ber_y_limits = [];              % empty = complete-decade auto limits
cfg_run.seed = struct( ...
    'frame_stride', 1000, ...
    'csi_stride', 100, ...
    'csi_case_offset', 7919, ...
    'capacity_scenario_offset', 99991, ...
    'low_mimo_base', 700000);

% Capacity definitions.
cfg_run.run_capacity = false;           % quick 默认不跑容量, 但代码保留
cfg_run.capacity_mode = 'raw_channel';
cfg_run.capacity_sigma2_fixed = 1;
cfg_run.capacity_scenarios = struct( ...
    'label', {'raw_vmf_cv030'}, ...
    'pas_model', {'vmf'}, ...
    'cv', {0.30}, ...
    'use_perpath_sigma', {true});

% Optional low-MIMO waveform/precoding comparison.
cfg_run.run_low_mimo_precoding = false;
cfg_run.low_mimo = struct( ...
    'array_shape', [4, 4], ...
    'N_s', 1, ...
    'v_max_kmh', 860, ...
    'tau_max_us', 32, ...
    'SNR_dB_list', -10:5:15, ...
    'numFrames', 200, ...
    'use_fractional_doppler', true, ...
    'scenario', struct('label', 'low_mimo_strict_isotropic', ...
        'pas_model', 'isotropic', 'cv', 1.0, 'use_perpath_sigma', false));

% AFWDM-vs-OFWDM time-diversity experiment (disabled outside its modes).
cfg_run.run_time_diversity = false;
cfg_run.time_diversity = struct();

switch mode
    case "quick"
        % 老师最关心的最小演示: perfect CSI + isotropic-like BER.
        % cv=1.0 在 vMF 中等价 isotropic density；严格 isotropic reference
        % 代码保留在 prepare_delivery_scenario(...,'isotropic_reference')。
        % 注意: full atlas 的 N_s≈60, 对 MacBook Air 太重；quick 是流程
        % smoke test, 临时把 N_s cap 到 8。paper 模式不做这个 cap。
        cfg_run.quick_stream_cap = 8;
        cfg_run.numFrames_BER = 1;
        cfg_run.SNR_dB_list = 10;
        cfg_run.kappa_list = 0;
        cfg_run.ber_scenarios = struct( ...
            'label', {'cv100_isotropic_like'}, ...
            'pas_model', {'vmf'}, ...
            'cv', {1.0}, ...
            'use_perpath_sigma', {true});

        cfg_run.capacity_numFrames = 1;
        cfg_run.capacity_P_dBW_list = [0, 10];
        cfg_run.capacity_scenarios = vmf_capacity_scenarios(1.0);

    case "smoke"
        % 信息量稍大的本机 smoke: 仍 cap N_s=8, 但覆盖两个 SNR、
        % perfect/imperfect CSI 和 iso-like/vMF-cv0.30 两个场景。
        cfg_run.quick_stream_cap = 8;
        cfg_run.numFrames_BER = 2;
        cfg_run.SNR_dB_list = [0, 10];
        cfg_run.kappa_list = [0, 0.1];
        cfg_run.ber_scenarios = struct( ...
            'label', {'cv100_isotropic_like', 'cv030_vmf'}, ...
            'pas_model', {'vmf', 'vmf'}, ...
            'cv', {1.0, 0.30}, ...
            'use_perpath_sigma', {true, true});

        cfg_run.capacity_numFrames = 1;
        cfg_run.capacity_P_dBW_list = [0, 10];
        cfg_run.capacity_scenarios = vmf_capacity_scenarios([1.0, 0.30]);

    case "fullmini"
        % 最轻量 full-load 验收: 不 cap N_s, 只跑严格 isotropic
        % reference / 一个SNR / perfect CSI / 少量帧 / full strategy。
        % 目的: 验证 ms=Nstreams=60 的完整 block channel + LMMSE
        % 链路可运行, 并和 atlas ber3-iso-perfect 口径作量级对照。
        cfg_run.quick_stream_cap = [];
        cfg_run.numFrames_BER = 3;
        cfg_run.SNR_dB_list = 5;
        cfg_run.kappa_list = 0;
        cfg_run.strategies = {'full'};
        cfg_run.ber_scenarios = struct( ...
            'label', {'strict_isotropic_reference'}, ...
            'pas_model', {'isotropic_reference'}, ...
            'cv', {1.0}, ...
            'use_perpath_sigma', {false});

        cfg_run.run_capacity = false;
        cfg_run.capacity_numFrames = 1;
        cfg_run.capacity_P_dBW_list = [0, 10];
        cfg_run.capacity_scenarios = vmf_capacity_scenarios(1.0);

    case "local2min"
        % 本机约 2 分钟验收: 比 smoke 多 SNR 点、多帧, 并默认打开
        % optional capacity helper；仍 cap N_s=8, 不代表正式 atlas 数值。
        cfg_run.quick_stream_cap = 8;
        cfg_run.numFrames_BER = 20;
        cfg_run.SNR_dB_list = [0, 5, 10];
        cfg_run.kappa_list = [0, 0.1];
        cfg_run.ber_scenarios = struct( ...
            'label', {'cv100_isotropic_like', 'cv030_vmf'}, ...
            'pas_model', {'vmf', 'vmf'}, ...
            'cv', {1.0, 0.30}, ...
            'use_perpath_sigma', {true, true});

        cfg_run.run_capacity = true;
        cfg_run.capacity_numFrames = 1;
        cfg_run.capacity_P_dBW_list = [0, 10, 20];
        cfg_run.capacity_scenarios = vmf_capacity_scenarios([1.0, 0.30]);

    case "paper"
        % 对齐最新 atlas v4: BER 用 full/adaptive 两种策略, fixed_var 排除。
        % cv=1.0 作为 isotropic-like vMF；单独 isotropic reference 默认不跑。
        cfg_run.numFrames_BER = 35;
        cfg_run.SNR_dB_list = -5:5:15;
        cfg_run.kappa_list = [0, 0.1, 1.0];
        cfg_run.ber_scenarios = struct( ...
            'label', {'cv100_isotropic_like', 'cv010_vmf', 'cv030_vmf'}, ...
            'pas_model', {'vmf', 'vmf', 'vmf'}, ...
            'cv', {1.0, 0.10, 0.30}, ...
            'use_perpath_sigma', {true, true, true});

        cfg_run.capacity_numFrames = 30;
        cfg_run.capacity_P_dBW_list = 0:5:30;
        cfg_run.capacity_scenarios = vmf_capacity_scenarios([0.01, 0.30, 1.00]);
        cfg_run.quick_stream_cap = [];

    case {"time_diversity_smoke", "time_diversity_online"}
        cfg_run.array_shape = [4, 4];
        cfg_run.v_max_kmh = 860;      % kmax=2 at fc=4 GHz, Deltaf=2 kHz.
        cfg_run.tau_max_us = 32;      % lmax=5; diversity lhs=29<64.
        cfg_run.quick_stream_cap = [];
        cfg_run.numFrames_BER = 0;
        cfg_run.SNR_dB_list = [];
        cfg_run.kappa_list = 0;
        cfg_run.strategies = {'full'};
        cfg_run.ber_scenarios = empty_scenario_list();
        cfg_run.run_capacity = false;
        cfg_run.run_low_mimo_precoding = false;
        cfg_run.run_time_diversity = true;
        cfg_run.time_diversity = struct( ...
            'N_s', 11, ...
            'scenario', struct('label', 'time_diversity_strict_isotropic', ...
                'pas_model', 'isotropic', 'cv', 1.0, 'use_perpath_sigma', false), ...
            'doppler_modes', {{'integer', 'fractional'}}, ...
            'detectors', {{'block_lmmse'}}, ...
            'spatial_pairs', {{'wdm'}}, ...
            'SNR_dB_list', 12:2:28, ...
            'target_errors', 100, ...
            'min_frames', 10, ...
            'max_frames', 1500, ...
            'bootstrap_samples', 2000, ...
            'bootstrap_seed', 20260715, ...
            'seed_base', 1700000, ...
            'bits_seed_offset', 17000000);
        if mode == "time_diversity_smoke"
            cfg_run.time_diversity.SNR_dB_list = 12;
            cfg_run.time_diversity.min_frames = 1;
            cfg_run.time_diversity.max_frames = 1;
            cfg_run.time_diversity.bootstrap_samples = 200;
        end

    case {"paperfig", "paperfig_iso", "paperfig_vmf", "paperfig_capacity", "paperfig_low_mimo"}
        % 新交付主图模式:
        %   Fig.1 strict isotropic: perfect CSI + fixed_var CSI in one plot.
        %   Fig.2 vMF cv=0.30: same six-line BER plot.
        %   Fig.3 raw doubly-selective channel capacity, no precoder loop.
        %   Fig.4 low-MIMO 4x4/Ns=1 waveform + precoding comparison.
        cfg_run.numFrames_BER = 100;
        cfg_run.SNR_dB_list = -10:5:15;
        cfg_run.kappa_list = [0, 0.0005];  % fixed_var mode: val is sigma_e^2.
        cfg_run.csi_error_mode = 'fixed_var';
        cfg_run.csi_case_labels = {'perfect CSI', 'fixed-var CSI, sigma_e^2=5e-4'};
        cfg_run.strategies = {'full'};
        cfg_run.plot_csi_cases_together = true;
        cfg_run.ber_scenarios = struct( ...
            'label', {'strict_isotropic', 'vmf_cv030'}, ...
            'pas_model', {'isotropic', 'vmf'}, ...
            'cv', {1.0, 0.30}, ...
            'use_perpath_sigma', {false, true});

        cfg_run.run_capacity = true;
        cfg_run.capacity_numFrames = 30;
        cfg_run.capacity_P_dBW_list = 0:5:30;
        cfg_run.capacity_scenarios = struct( ...
            'label', {'raw_doubly_selective_vmf_cv030'}, ...
            'pas_model', {'vmf'}, ...
            'cv', {0.30}, ...
            'use_perpath_sigma', {true});
        cfg_run.quick_stream_cap = [];
        cfg_run.run_low_mimo_precoding = true;

        switch mode
            case "paperfig_iso"
                cfg_run.ber_scenarios = cfg_run.ber_scenarios(1);
                cfg_run.run_capacity = false;
                cfg_run.run_low_mimo_precoding = false;
            case "paperfig_vmf"
                cfg_run.ber_scenarios = cfg_run.ber_scenarios(2);
                cfg_run.run_capacity = false;
                cfg_run.run_low_mimo_precoding = false;
            case "paperfig_capacity"
                cfg_run.ber_scenarios = empty_scenario_list();
                cfg_run.run_capacity = true;
                cfg_run.run_low_mimo_precoding = false;
            case "paperfig_low_mimo"
                cfg_run.ber_scenarios = empty_scenario_list();
                cfg_run.run_capacity = false;
                cfg_run.run_low_mimo_precoding = true;
        end

    otherwise
        error('make_delivery_config:unknownMode', ...
            ['Unknown mode "%s". Use quick, smoke, fullmini, local2min, paper, ' ...
             'paperfig*, time_diversity_smoke, or time_diversity_online.'], mode);
end

end

function specs = empty_scenario_list()
specs = repmat(struct('label', '', 'pas_model', '', 'cv', NaN, 'use_perpath_sigma', false), 1, 0);
end

function specs = vmf_capacity_scenarios(cv_list)
specs = repmat(struct( ...
    'label', '', ...
    'pas_model', 'vmf', ...
    'cv', NaN, ...
    'use_perpath_sigma', true), 1, numel(cv_list));

for ii = 1:numel(cv_list)
    cv = cv_list(ii);
    specs(ii).label = sprintf('raw_vmf_cv%03d', round(100 * cv));
    specs(ii).cv = cv;
end
end
