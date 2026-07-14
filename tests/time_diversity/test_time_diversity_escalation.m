function tests = test_time_diversity_escalation
tests = functiontests(localfunctions);
end

function setupOnce(~)
repo_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(repo_root, fullfile(repo_root, 'delivery', 'atlas_v4_matlab'));
end

function testEscalationSequenceIsSingleVariableAndDopplerSpecific(testCase)
cfg = make_delivery_config("time_diversity_smoke");
gains = [ ...
    struct('doppler_mode', 'integer', 'gain_db', 0.6, 'claim_eligible', true), ...
    struct('doppler_mode', 'fractional', 'gain_db', 1.3, 'claim_eligible', true)];

lch8 = resolve_time_diversity_escalation('lch6', gains, cfg);
kmax3 = resolve_time_diversity_escalation('lch8', gains, cfg);
per_stream = resolve_time_diversity_escalation('kmax3', gains, cfg);
closed = resolve_time_diversity_escalation('per_stream_lmmse', gains, cfg);

verifyEqual(testCase, lch8.next_stage, 'lch8');
verifyEqual(testCase, lch8.triggered_doppler_modes, {'integer'});
verifyEqual(testCase, lch8.Lch_values, 8);
verifyEqual(testCase, lch8.v_max_kmh, 860);
verifyEqual(testCase, kmax3.next_stage, 'kmax3');
verifyEqual(testCase, kmax3.Lch_values, 8);
verifyEqual(testCase, kmax3.v_max_kmh, 1100);
verifyEqual(testCase, kmax3.kmax, 3);
verifyEqual(testCase, kmax3.diversity_lhs, 41);
verifyEqual(testCase, per_stream.next_stage, 'per_stream_lmmse');
verifyTrue(testCase, ismember('per_stream_lmmse', per_stream.detectors));
verifyTrue(testCase, ismember('block_lmmse', per_stream.detectors));
verifyTrue(testCase, ismember('gabp', per_stream.detectors));
verifyEqual(testCase, closed.next_stage, 'fail_closed');
verifyTrue(testCase, closed.fail_closed);
end

function testInsufficientEvidenceDoesNotTriggerEscalation(testCase)
cfg = make_delivery_config("time_diversity_smoke");
gains = struct('doppler_mode', 'fractional', 'gain_db', 0.2, ...
    'claim_eligible', false);

plan = resolve_time_diversity_escalation('lch6', gains, cfg);

verifyEqual(testCase, plan.next_stage, 'await_evidence');
verifyEmpty(testCase, plan.triggered_doppler_modes);
end

function testScientificCompletionRequiresCiAndMcnemar(testCase)
cfg = make_delivery_config("time_diversity_smoke");
summary = significance_summary([1.2, 1.3], [0.9, 1.1], [0.01, 0.01]);

gains = build_time_diversity_gain_records(summary, {'fractional'});
plan = resolve_time_diversity_escalation('lch6', gains, cfg);

verifyFalse(testCase, gains.claim_eligible);
verifyEqual(testCase, plan.next_stage, 'await_evidence');
end

function testScientificCompletionAcceptsTwoSignificantDetectors(testCase)
cfg = make_delivery_config("time_diversity_smoke");
summary = significance_summary([1.2, 1.3], [1.05, 1.10], [0.01, 0.02]);

gains = build_time_diversity_gain_records(summary, {'fractional'});
plan = resolve_time_diversity_escalation('lch6', gains, cfg);

verifyTrue(testCase, gains.claim_eligible);
verifyEqual(testCase, plan.next_stage, 'complete');
end

function testSignificantSubDbEvidenceTriggersEscalation(testCase)
cfg = make_delivery_config("time_diversity_smoke");
summary = significance_summary([0.5, 0.7], [1.05, 1.10], [0.01, 0.02]);

gains = build_time_diversity_gain_records(summary, {'fractional'});
plan = resolve_time_diversity_escalation('lch6', gains, cfg);

verifyTrue(testCase, gains.claim_eligible);
verifyEqual(testCase, plan.next_stage, 'lch8');
end

function testPerStreamLmmseRemainsSupplementalAndDeterministic(testCase)
cfg = minimal_cfg();
H = eye(cfg.Nblk * cfg.Nstreams);
opts = struct( ...
    'bits', logical([0; 0; 0; 1; 1; 0; 1; 1]), ...
    'unit_noise', zeros(size(H, 1), 1), ...
    'detector', 'per_stream_lmmse');

pair = simulate_paired_waveform_frame(cfg, H, cfg, H, 4, 30, opts);

verifyEqual(testCase, pair.error_a, pair.error_b);
verifyEqual(testCase, pair.detector_a.solver, 'per_stream_lmmse');
verifyEqual(testCase, pair.detector_a.stream_count, cfg.Nstreams);
end

function testEscalationPlanProducesRunnableSingleChangeConfig(testCase)
cfg = make_delivery_config("time_diversity_smoke");
gains = struct('doppler_mode', 'integer', 'gain_db', 0.5, ...
    'claim_eligible', true);
plan = resolve_time_diversity_escalation('lch8', gains, cfg);

next = apply_time_diversity_escalation(cfg, plan);

verifyEqual(testCase, next.time_diversity.Lch_values, 8);
verifyEqual(testCase, next.time_diversity.doppler_modes, {'integer'});
verifyEqual(testCase, next.v_max_kmh, 1100);
verifyEqual(testCase, next.tau_max_us, cfg.tau_max_us);
verifyEqual(testCase, next.array_shape, cfg.array_shape);
verifyEqual(testCase, next.time_diversity.N_s, cfg.time_diversity.N_s);
verifyEqual(testCase, next.time_diversity.detectors, {'block_lmmse', 'gabp'});
verifyEqual(testCase, next.time_diversity.spatial_pairs, {'wdm'});
end

function cfg = minimal_cfg()
cfg = struct('Nblk', 2, 'ms', 2, 'mr', 2, 'Nstreams', 2, ...
    'Fbb_wdm', [], 'Wbb_wdm', [], 'block_lmmse_solver', 'direct', ...
    'pcg_tol', 1e-8, 'pcg_max_iter', 50);
end

function summary = significance_summary(gains, ci_low, p_values)
summary = table( ...
    {'fractional'; 'fractional'}, ...
    {'block_lmmse'; 'gabp'}, ...
    gains(:), ci_low(:), [2; 2], p_values(:), [false; false], ...
    'VariableNames', {'doppler_mode', 'detector', 'snr_gain_db', ...
    'ratio_ci_low', 'ratio_ci_high', 'mcnemar_p', 'noise_limited'});
end
