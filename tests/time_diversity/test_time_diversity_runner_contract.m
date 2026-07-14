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
verifyEqual(testCase, cfg.time_diversity.detectors, {'block_lmmse'});
verifyEqual(testCase, cfg.time_diversity.SNR_dB_list, 12);
verifyEqual(testCase, cfg.time_diversity.max_frames, 1);
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
