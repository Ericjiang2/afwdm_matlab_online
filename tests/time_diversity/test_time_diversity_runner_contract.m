function tests = test_time_diversity_runner_contract
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repo_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
delivery_dir = fullfile(repo_root, 'delivery', 'atlas_v4_matlab');
addpath(repo_root, fullfile(repo_root, 'tools'), delivery_dir, ...
    fullfile(repo_root, 'variance'), fullfile(repo_root, 'variance_aniso'));
testCase.TestData.repo_root = repo_root;
end

function testSmokeProfileKeepsLockedPhysicalParameters(testCase)
cfg = make_delivery_config("time_diversity_smoke");

verifyTrue(testCase, cfg.run_time_diversity);
verifyEqual(testCase, cfg.array_shape, [4, 4]);
verifyEqual(testCase, cfg.Nblk, 64);
verifyEqual(testCase, cfg.fc, 4e9);
verifyEqual(testCase, cfg.Deltaf, 2e3);
verifyEqual(testCase, cfg.time_diversity.N_s, 11);
verifyEqual(testCase, cfg.time_diversity.doppler_modes, {'integer', 'fractional'});
verifyEqual(testCase, cfg.time_diversity.detectors, {'block_lmmse', 'gabp'});
verifyEqual(testCase, cfg.time_diversity.gabp.damping, 0.4);
verifyEqual(testCase, cfg.time_diversity.gabp.max_iterations, 20);
verifyEqual(testCase, cfg.time_diversity.gabp.tolerance, 1e-3);
verifyEqual(testCase, cfg.time_diversity.SNR_dB_list, 12);
verifyEqual(testCase, cfg.time_diversity.max_frames, 1);
verifyEqual(testCase, cfg.time_diversity.Lch_values, [4, 6]);
verifyEqual(testCase, cfg.time_diversity.spatial_pairs, {'wdm', 'dft', 'svd'});
verifyEqual(testCase, cfg.time_diversity.summary_target_ber, 1e-3);
end

function testWaveformPairSharesSpatialBasisAndOnlyZerosOfdmChirps(testCase)
cfg_run = make_delivery_config("time_diversity_smoke");
cfg_base = minimal_base_cfg(cfg_run);
Us = eye(16, 11);
Ur = eye(16, 11);

[cfg_afwdm, cfg_ofwdm, audit] = make_time_diversity_waveform_pair( ...
    cfg_base, Us, Ur, 11, cfg_run);

verifyEqual(testCase, cfg_afwdm.Us, cfg_ofwdm.Us, 'AbsTol', 0);
verifyEqual(testCase, cfg_afwdm.Ur, cfg_ofwdm.Ur, 'AbsTol', 0);
verifyEqual(testCase, cfg_afwdm.Nstreams, 11);
verifyEqual(testCase, cfg_ofwdm.Nstreams, 11);
verifyEqual(testCase, cfg_afwdm.c1, (2 * cfg_base.kmax + 1) / (2 * cfg_base.Nblk), 'AbsTol', 0);
verifyEqual(testCase, cfg_afwdm.c2, 0.1 / cfg_base.Nblk, 'AbsTol', 0);
verifyEqual(testCase, cfg_ofwdm.c1, 0, 'AbsTol', 0);
verifyEqual(testCase, cfg_ofwdm.c2, 0, 'AbsTol', 0);
verifyTrue(testCase, audit.same_spatial_basis);
verifyTrue(testCase, audit.only_temporal_basis_differs);
end

function testGabpResultPersistsFinalResiduals(testCase)
cfg = make_delivery_config("time_diversity_smoke");
cfg.time_diversity.Lch_values = 6;
cfg.time_diversity.doppler_modes = {'integer'};
cfg.time_diversity.detectors = {'gabp'};
cfg.time_diversity.spatial_pairs = {'wdm'};

results = run_time_diversity_ber(cfg);
point = results.runs(1).points(1);

verifySize(testCase, point.final_residuals, [2, 1]);
verifyTrue(testCase, all(isfinite(point.final_residuals), 'all'));
verifyEqual(testCase, point.average_final_residual, point.final_residuals, ...
    'AbsTol', 1e-15);
end

function testLchSweepChangesOnlyPathCount(testCase)
scenario = struct();
scenario.cfg = minimal_base_cfg(make_delivery_config("time_diversity_smoke"));
scenario.cfg.Lch = 4;
scenario.cfg.afdm_diversity_lhs = 29;
scenario.cfg.Nblk = 64;

[updated, audit] = configure_time_diversity_lch(scenario, 6);

verifyEqual(testCase, updated.cfg.Lch, 6);
verifyTrue(testCase, audit.only_lch_changed);
verifyEqual(testCase, audit.before_Lch, 4);
verifyEqual(testCase, audit.after_Lch, 6);
verifyTrue(testCase, audit.diversity_condition_passed);
end

function testLchSummaryReportsNetTemporalGapChange(testCase)
point4 = struct('ber_ratio_b_over_a', 2, 'claim_eligible', true);
point6 = struct('ber_ratio_b_over_a', 3, 'claim_eligible', true);
runs = [ ...
    struct('doppler_mode', 'fractional', 'detector', 'gabp', 'Lch', 4, ...
        'spatial_pair', 'wdm', 'SNR_dB', 20, 'points', point4), ...
    struct('doppler_mode', 'fractional', 'detector', 'gabp', 'Lch', 6, ...
        'spatial_pair', 'wdm', 'SNR_dB', 20, 'points', point6)];

summary = compare_time_diversity_lch(runs, 4, 6);

verifyEqual(testCase, summary.ratio_lch4, 2);
verifyEqual(testCase, summary.ratio_lch6, 3);
verifyEqual(testCase, summary.net_ratio_change, 1.5, 'AbsTol', 1e-12);
verifyTrue(testCase, summary.claim_eligible);
end

function cfg = minimal_base_cfg(cfg_run)
cfg = struct();
cfg.Nblk = cfg_run.Nblk;
cfg.kmax = 2;
cfg.c1 = (2 * cfg.kmax + 1) / (2 * cfg.Nblk);
cfg.c2 = 0.1 / cfg.Nblk;
cfg.ms = 11;
cfg.mr = 11;
cfg.Nstreams = 11;
cfg.Ms = 16;
cfg.Mr = 16;
cfg.pcg_tol = 1e-7;
cfg.pcg_max_iter = 150;
end
