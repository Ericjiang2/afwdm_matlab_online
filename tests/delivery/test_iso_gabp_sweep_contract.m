function tests = test_iso_gabp_sweep_contract
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
test_dir = fileparts(mfilename('fullpath'));
repo_root = fileparts(fileparts(test_dir));
delivery_dir = fullfile(repo_root, 'delivery', 'atlas_v4_matlab');
addpath(repo_root);
addpath(delivery_dir);
testCase.TestData.repo_root = repo_root;
testCase.TestData.delivery_dir = delivery_dir;
end

function testFrozenScientificProfile(testCase)
cfg = make_delivery_config("iso_gabp_adaptive");
for ii = 1:numel(cfg.path_dirs)
    if exist(cfg.path_dirs{ii}, 'dir')
        addpath(cfg.path_dirs{ii});
    end
end

verifyEqual(testCase, cfg.array_shape, [8, 8]);
verifyEqual(testCase, cfg.Nblk, 64);
verifyEqual(testCase, ...
    cfg.iso_gabp.average_reference_SNR_dB_list, 0:5:20);
verifyEqual(testCase, cfg.iso_gabp.reference_stream_count, 60);
verifyEqual(testCase, cfg.SNR_dB_list, ...
    (0:5:20) - 10 * log10(60), 'AbsTol', 10 * eps);
verifyEqual(testCase, cfg.schemes, {'AFWDM', 'DFT_precoded', 'SVD_paper'});
verifyEqual(testCase, cfg.strategies, {'full'});
verifyEqual(testCase, cfg.kappa_list, [0, 5e-4], 'AbsTol', eps);
verifyEqual(testCase, cfg.csi_error_mode, 'fixed_var');
verifyEqual(testCase, cfg.ber_scenarios.label, 'strict_isotropic');
verifyEqual(testCase, cfg.ber_scenarios.pas_model, 'isotropic');
verifyEmpty(testCase, cfg.quick_stream_cap);

stop = cfg.iso_gabp.stop;
verifyEqual(testCase, stop.min_frames, 5);
verifyEqual(testCase, stop.target_errors, 100);
verifyEqual(testCase, stop.max_frames, 200);
verifyEqual(testCase, cfg.iso_gabp.runner_version, ...
    'iso-gabp-adaptive-20260723.3');
verifyEqual(testCase, cfg.iso_gabp.assets.active_run_id_file, ...
    '_ACTIVE_ISO_GABP_SWEEP_V3_ID.txt');

detector = cfg.iso_gabp.detector_options;
verifyEqual(testCase, detector.damping, 0.4, 'AbsTol', eps);
verifyEqual(testCase, detector.max_iterations, 40);
verifyEqual(testCase, detector.tolerance, 1e-3, 'AbsTol', eps);
verifyEqual(testCase, detector.edge_threshold_rel, 0);
verifyEqual(testCase, detector.regularization, 1e-10, 'AbsTol', eps);
verifyEqual(testCase, cfg.iso_gabp.assets.result_mat, ...
    'iso_gabp_adaptive_results.mat');
verifyEqual(testCase, cfg.iso_gabp.assets.summary_csv, ...
    'iso_gabp_adaptive_summary.csv');
verifyEqual(testCase, cfg.iso_gabp.assets.figure_png, ...
    'ber_strict_isotropic_gabp_only.png');

scenario = prepare_delivery_scenario(cfg, cfg.ber_scenarios);
modes = select_modes_atlas_v4( ...
    scenario.cfg, scenario.Sigma2, cfg.adapt_power_floor);
verifyEqual(testCase, modes.N_full, 60);
end

function testFrameKernelUsesSeparatePropagationAndDetectorChannels(testCase)
cfg = struct('Nblk', 2, 'Nstreams', 2, 'ms', 2, 'mr', 2, ...
    'Fbb_wdm', [], 'Wbb_wdm', []);
H_real = eye(4) + 0.15 * ones(4);
H_detector = H_real + 0.02j * fliplr(eye(4));
bits = logical([0; 0; 0; 1; 1; 0; 1; 1]);
unit_noise = zeros(4, 1);
opts = struct( ...
    'bits', bits, ...
    'unit_noise', unit_noise, ...
    'detector_options', struct( ...
        'damping', 0.4, ...
        'max_iterations', 40, ...
        'tolerance', 1e-3, ...
        'edge_threshold_rel', 0, ...
        'regularization', 1e-10));

frame = simulate_imperfect_csi_gabp_frame( ...
    cfg, H_real, H_detector, 4, 10, opts);

verifyEqual(testCase, frame.bit_count, numel(bits));
verifyEqual(testCase, frame.bits, bits);
verifyEqual(testCase, frame.audit.propagation_channel, 'H_real');
verifyEqual(testCase, frame.audit.detector_channel, 'H_detector');
verifyEqual(testCase, frame.audit.noise_variance, 0.1, 'AbsTol', 10 * eps);
verifyEqual(testCase, frame.detector.max_iterations, 40);
verifyTrue(testCase, isfinite(frame.detector.residual));
end

function testRunnerContainsIndependentPerCurveStopAndImmutableContract(testCase)
runner_file = fullfile(testCase.TestData.delivery_dir, ...
    'run_online_iso_gabp_sweep.m');
source = fileread(runner_file);

verifyNotEmpty(testCase, strfind(source, 'state.frame_count < stop.min_frames'));
verifyNotEmpty(testCase, strfind(source, 'state.error_count < stop.target_errors'));
verifyNotEmpty(testCase, strfind(source, 'state.frame_count < stop.max_frames'));
verifyNotEmpty(testCase, strfind(source, 'run_contract'));
verifyNotEmpty(testCase, strfind(source, 'run_online_iso_gabp_sweep:manifestMismatch'));
verifyNotEmpty(testCase, strfind(source, ...
    'N_s ~= cfg_run.iso_gabp.reference_stream_count'));
verifyNotEmpty(testCase, strfind(source, 'H_detector = H_real'));
verifyNotEmpty(testCase, strfind(source, 'states(:, i_csi)'));
verifyLessThan(testCase, strfind(source, 'plot_iso_gabp_results'), ...
    strfind(source, 'save_final_atomic(final_file, package)'));
verifyNotEmpty(testCase, strfind(source, ...
    'run_online_iso_gabp_sweep:fixtureIdentity'));
verifyNotEmpty(testCase, strfind(source, ...
    'SNR_average_reference_dB'));
verifyNotEmpty(testCase, strfind(source, ...
    'SNR_stream_dB'));

kernel_file = fullfile(testCase.TestData.repo_root, ...
    'simulate_imperfect_csi_gabp_frame.m');
kernel_source = fileread(kernel_file);
verifyNotEmpty(testCase, strfind(kernel_source, ...
    'isempty(Fbb) && isempty(Wbb) && cfg.ms == Ns && cfg.mr == Ns'));
end
