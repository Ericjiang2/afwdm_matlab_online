function tests = test_paired_ber_harness
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repo_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(repo_root);
testCase.TestData.repo_root = repo_root;
end

function testSharedBitsAndNoiseProduceIdenticalDecisionsForIdenticalArms(testCase)
cfg = minimal_cfg();
H = eye(cfg.Nblk * cfg.Nstreams);
opts = struct( ...
    'bits', logical([0; 0; 0; 1; 1; 0; 1; 1]), ...
    'unit_noise', zeros(size(H, 1), 1), ...
    'detector', 'block_lmmse');

pair = simulate_paired_waveform_frame(cfg, H, cfg, H, 4, 30, opts);

verifyEqual(testCase, pair.error_a, pair.error_b);
verifyTrue(testCase, pair.audit.shared_bits);
verifyTrue(testCase, pair.audit.shared_unit_noise);
verifyEqual(testCase, pair.bits, opts.bits);
end

function testAdaptiveStopRequiresBetterArmErrorTarget(testCase)
cfg = struct('target_errors', 100, 'min_frames', 10, 'max_frames', 50);

[stop_early, reason_early] = paired_stop_decision([120, 99], 10, cfg);
[stop_target, reason_target] = paired_stop_decision([120, 100], 10, cfg);
[stop_limit, reason_limit] = paired_stop_decision([1, 0], 50, cfg);

verifyFalse(testCase, stop_early);
verifyEqual(testCase, reason_early, 'continue');
verifyTrue(testCase, stop_target);
verifyEqual(testCase, reason_target, 'target_errors');
verifyTrue(testCase, stop_limit);
verifyEqual(testCase, reason_limit, 'max_frames_noise_limited');
end

function testPairedStatisticsAreReproducibleAndExposeDiscordance(testCase)
error_a = logical([1 0 0; 0 1 0; 1 0 0; 0 0 0]);
error_b = logical([0 1 0; 0 1 0; 1 0 0; 0 0 0]);
opts = struct('target_errors', 3, 'bootstrap_samples', 200, ...
    'bootstrap_seed', 20260715, 'confidence', 0.95);

first = paired_ber_statistics(error_a, error_b, opts);
second = paired_ber_statistics(error_a, error_b, opts);

verifyEqual(testCase, first.ber_ratio_ci, second.ber_ratio_ci, 'AbsTol', 0);
verifyEqual(testCase, first.discordant_a_only, 1);
verifyEqual(testCase, first.discordant_b_only, 1);
verifyEqual(testCase, first.mcnemar_p, 1, 'AbsTol', 1e-12);
verifyFalse(testCase, first.noise_limited);
verifyTrue(testCase, first.claim_eligible);
end

function cfg = minimal_cfg()
cfg = struct();
cfg.Nblk = 2;
cfg.ms = 2;
cfg.mr = 2;
cfg.Nstreams = 2;
cfg.Fbb_wdm = [];
cfg.Wbb_wdm = [];
cfg.block_lmmse_solver = 'direct';
cfg.pcg_tol = 1e-8;
cfg.pcg_max_iter = 50;
end
