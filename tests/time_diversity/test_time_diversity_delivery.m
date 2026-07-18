function tests = test_time_diversity_delivery
tests = functiontests(localfunctions);
end

function setupOnce(~)
repo_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(repo_root, fullfile(repo_root, 'tools'), ...
    fullfile(repo_root, 'delivery', 'atlas_v4_matlab'));
end

function testSummaryHasFourPrimaryRowsAndPositiveFixedBerGain(testCase)
runs = synthetic_runs();

summary = build_time_diversity_summary(runs, 6, 1e-3);

verifyEqual(testCase, height(summary), 4);
verifyEqual(testCase, sort(string(summary.doppler_mode)), ...
    sort(["integer"; "integer"; "fractional"; "fractional"]));
verifyTrue(testCase, all(summary.snr_gain_db > 1));
verifyTrue(testCase, all(summary.ber_ratio_ofwdm_over_afwdm == 2));
verifyTrue(testCase, all(~summary.noise_limited));
end

function testSummaryUsesAvailableExplorationDetectors(testCase)
runs = synthetic_runs('wdm');
fractional_gabp = runs(strcmp({runs.doppler_mode}, 'fractional') & ...
    strcmp({runs.detector}, 'gabp'));
fractional_per_stream = fractional_gabp;
fractional_per_stream.detector = 'per_stream_lmmse';

summary = build_time_diversity_summary( ...
    [fractional_gabp, fractional_per_stream], 6, 1e-3);

verifyEqual(testCase, height(summary), 2);
verifyEqual(testCase, string(summary.doppler_mode), ...
    ["fractional"; "fractional"]);
verifyEqual(testCase, string(summary.detector), ...
    ["gabp"; "per_stream_lmmse"]);
verifyTrue(testCase, all(summary.snr_gain_db > 1));
end

function testDeliveryPlotWritesMimoMainAppendixAndTableOnly(testCase)
runs = [synthetic_runs('wdm'), synthetic_runs('dft'), synthetic_runs('svd')];
results = struct('runs', runs, 'N_s', 11, 'Nblk', 64, ...
    'array_shape', [4, 4], 'summary_table', ...
    build_time_diversity_summary(runs, 6, 1e-3));
cfg = make_delivery_config("time_diversity_smoke");
out_dir = tempname;
mkdir(out_dir);
cleanup = onCleanup(@() rmdir(out_dir, 's'));

files = plot_time_diversity_results(results, cfg, out_dir);

verifyTrue(testCase, isfile(fullfile(out_dir, 'time_diversity_mimo_main.png')));
verifyTrue(testCase, isfile(fullfile(out_dir, 'time_diversity_svd_appendix.png')));
verifyTrue(testCase, isfile(fullfile(out_dir, 'time_diversity_summary.csv')));
verifyFalse(testCase, any(contains(string(files), 'siso')));
end

function testExplorationPlotShowsAvailableFractionalDetectors(testCase)
runs = synthetic_runs('wdm');
fractional_gabp = runs(strcmp({runs.doppler_mode}, 'fractional') & ...
    strcmp({runs.detector}, 'gabp'));
fractional_per_stream = fractional_gabp;
fractional_per_stream.detector = 'per_stream_lmmse';
runs = [fractional_gabp, fractional_per_stream];
results = struct('runs', runs, 'N_s', 11, 'Nblk', 64, ...
    'array_shape', [4, 4], 'summary_table', ...
    build_time_diversity_summary(runs, 6, 1e-3));
cfg = make_delivery_config("time_diversity_fractional_gabp_exploration");
out_dir = tempname;
mkdir(out_dir);
cleanup = onCleanup(@() rmdir(out_dir, 's'));

files = plot_time_diversity_results(results, cfg, out_dir, 'exploration');

verifyTrue(testCase, isfile(fullfile(out_dir, 'exploration_mimo_main.png')));
verifyTrue(testCase, isfile(fullfile(out_dir, 'exploration_summary.csv')));
verifyEqual(testCase, numel(files), 2);
end

function testExplorationCompletionRemainsCandidateAndAuditable(testCase)
cfg = make_delivery_config("time_diversity_fractional_gabp_exploration");
stages = build_time_diversity_exploration_stages(cfg);
runs = synthetic_runs('wdm');
fractional_gabp = runs(strcmp({runs.doppler_mode}, 'fractional') & ...
    strcmp({runs.detector}, 'gabp'));
fractional_per_stream = fractional_gabp;
fractional_per_stream.detector = 'per_stream_lmmse';
final_results = struct('summary_table', build_time_diversity_summary( ...
    [fractional_gabp, fractional_per_stream], 8, 1e-3));

[plan, states, outcome] = build_time_diversity_exploration_completion( ...
    stages, final_results, stages(end).cfg);

verifyEqual(testCase, plan.next_stage, 'exploration_complete');
verifyEqual(testCase, plan.stage_order, {stages.name});
verifyEqual(testCase, plan.diversity_lhs, 55);
verifyEqual(testCase, states.status, 'candidate');
verifyEqual(testCase, states.evidence_stage, 'lch8_kmax3_tau48');
verifyEqual(testCase, outcome.status, 'candidate');
verifyEqual(testCase, outcome.parameters.tau_max_us, 48);
verifyEqual(testCase, outcome.parameters.detectors, ...
    {'gabp', 'per_stream_lmmse'});
verifyFalse(testCase, outcome.production_result_available);
end

function testSisoAnchorIsInternalAndUsesSamePhysicalParameters(testCase)
cfg = make_delivery_config("time_diversity_smoke");
cfg.time_diversity.siso_frames = 1;
cfg.time_diversity.siso_SNR_dB_list = 12;

anchor = run_time_diversity_siso_anchor(cfg);

verifyEqual(testCase, anchor.N_s, 1);
verifyEqual(testCase, anchor.Nblk, cfg.Nblk);
verifyEqual(testCase, anchor.Lch, 6);
verifyEqual(testCase, sort(string({anchor.runs.doppler_mode})), ...
    sort(["integer", "fractional"]));
verifyTrue(testCase, anchor.internal_diagnostic_only);
end

function testOnlineSmokeIsCheckpointedAndResumable(testCase)
out_root = tempname;
mkdir(out_root);
cleanup = onCleanup(@() rmdir(out_root, 's'));

package = run_online_time_diversity( ...
    "time_diversity_smoke", "unit_test_run", out_root);
checkpoint = fullfile(out_root, 'unit_test_run', 'checkpoints', ...
    'baseline_snr_p12.mat');
final_mat = fullfile(out_root, 'unit_test_run', 'final', ...
    'time_diversity_final.mat');

verifyTrue(testCase, isfile(checkpoint));
verifyTrue(testCase, isfile(final_mat));
verifyEqual(testCase, package.final_plan.next_stage, 'await_evidence');
verifyEqual(testCase, package.final_stage, 'lch6');
verifyEqual(testCase, package.outcome.status, 'inconclusive');
baseline_primary = package.baseline.runs([package.baseline.runs.Lch] == 6);
verifyEqual(testCase, package.final_results.runs, baseline_primary);
verifyTrue(testCase, package.siso_anchor.internal_diagnostic_only);
verifyTrue(testCase, isfile(fullfile(out_root, 'unit_test_run', 'final', ...
    'time_diversity_mimo_main.png')));
verifyTrue(testCase, isfile(fullfile(out_root, 'unit_test_run', 'final', ...
    'time_diversity_baseline_mimo_main.png')));

before = dir(checkpoint);
pause(0.05);
resumed = run_online_time_diversity( ...
    "time_diversity_smoke", "unit_test_run", out_root);
after = dir(checkpoint);
verifyEqual(testCase, after.datenum, before.datenum);
verifyEqual(testCase, resumed.metadata.run_id, 'unit_test_run');

verifyError(testCase, @() run_online_time_diversity( ...
    "time_diversity_online", "unit_test_run", out_root), ...
    'run_online_time_diversity:manifestMismatch');
end

function testExplicitExplorationConsumesAllCompatibleStageCheckpoints(testCase)
out_root = tempname;
run_id = 'explicit_fixture_run';
checkpoint_dir = fullfile(out_root, run_id, 'checkpoints');
mkdir(checkpoint_dir);
cleanup = onCleanup(@() rmdir(out_root, 's'));
cfg = make_delivery_config("time_diversity_fractional_gabp_exploration");
stage_plan = build_time_diversity_exploration_stages(cfg);

for iStage = 1:numel(stage_plan)
    stage = stage_plan(iStage);
    manifest = build_time_diversity_run_manifest(stage.cfg, stage.name);
    for snr_db = stage.cfg.time_diversity.SNR_dB_list
        checkpoint = struct( ...
            'stage', stage.name, ...
            'snr_db', snr_db, ...
            'manifest', manifest, ...
            'results', synthetic_exploration_pack(stage.cfg, snr_db));
        save(fullfile(checkpoint_dir, sprintf('%s_snr_%s.mat', ...
            stage.name, fixture_snr_tag(snr_db))), 'checkpoint', '-v7');
    end
end

package = run_online_time_diversity( ...
    "time_diversity_fractional_gabp_exploration", run_id, out_root);

verifyEqual(testCase, numel(package.escalation_stages), 3);
verifyEqual(testCase, package.final_stage, 'lch8_kmax3_tau48');
verifyEqual(testCase, package.final_plan.next_stage, 'exploration_complete');
verifyEqual(testCase, package.outcome.status, 'candidate');
verifyFalse(testCase, package.outcome.production_result_available);
verifyEqual(testCase, package.metadata.scientific_label, ...
    'candidate_exploration');
verifyEqual(testCase, height(package.final_results.summary_table), 2);
verifyEqual(testCase, string(package.final_results.summary_table.detector), ...
    ["gabp"; "per_stream_lmmse"]);
verifyTrue(testCase, isfile(fullfile(out_root, run_id, 'final', ...
    'time_diversity_mimo_main.png')));
end

function testLch6Tau48WrapperConsumesOneStageCheckpoints(testCase)
out_root = tempname;
run_id = 'time_diversity_lch6_tau48_followup_v10_20260718';
checkpoint_dir = fullfile(out_root, run_id, 'checkpoints');
mkdir(checkpoint_dir);
cleanup = onCleanup(@() rmdir(out_root, 's'));
cfg = make_delivery_config("time_diversity_lch6_tau48_followup");
stage_plan = build_time_diversity_exploration_stages(cfg);
stage = stage_plan(1);
manifest = build_time_diversity_run_manifest(stage.cfg, stage.name);

for snr_db = stage.cfg.time_diversity.SNR_dB_list
    checkpoint = struct( ...
        'stage', stage.name, ...
        'snr_db', snr_db, ...
        'manifest', manifest, ...
        'results', synthetic_exploration_pack(stage.cfg, snr_db));
    save(fullfile(checkpoint_dir, sprintf('%s_snr_%s.mat', ...
        stage.name, fixture_snr_tag(snr_db))), 'checkpoint', '-v7');
end

package = run_time_diversity_lch6_tau48_followup(out_root);

verifyEmpty(testCase, package.escalation_stages);
verifyEqual(testCase, package.final_stage, 'lch6_kmax2_tau48');
verifyEqual(testCase, package.final_plan.next_stage, 'exploration_complete');
verifyEqual(testCase, package.outcome.status, 'candidate');
verifyEqual(testCase, package.outcome.parameters.kmax, 2);
verifyEqual(testCase, package.outcome.parameters.lmax, 7);
verifyEqual(testCase, package.outcome.parameters.tau_max_us, 48);
verifyEqual(testCase, package.metadata.profile, ...
    'time_diversity_lch6_tau48_followup');
verifyEqual(testCase, package.metadata.scientific_label, ...
    'candidate_exploration');
verifyEqual(testCase, height(package.final_results.summary_table), 1);
verifyEqual(testCase, string(package.final_results.summary_table.detector), ...
    "gabp");
verifyTrue(testCase, isfile(fullfile(out_root, run_id, 'final', ...
    'time_diversity_final.mat')));
end

function testLastEscalationStageBecomesCanonicalFinal(testCase)
baseline_runs = [synthetic_runs('wdm'), synthetic_runs('dft'), ...
    synthetic_runs('svd')];
baseline = struct('runs', baseline_runs, 'N_s', 11, 'Nblk', 64, ...
    'array_shape', [4, 4], 'summary_table', ...
    build_time_diversity_summary(baseline_runs, 6, 1e-3), ...
    'lch_comparison', []);
stage_runs = synthetic_runs('wdm');
stage_runs = stage_runs(strcmp({stage_runs.doppler_mode}, 'integer'));
for ii = 1:numel(stage_runs)
    stage_runs(ii).Lch = 8;
end
stage_result = baseline;
stage_result.runs = stage_runs;
stage_result.summary_table = build_time_diversity_summary(stage_runs, 8, 1e-3);
stages = {struct('name', 'lch8', 'results', stage_result)};

[final_results, final_stage] = select_time_diversity_final_results(baseline, stages);

verifyEqual(testCase, final_stage, 'lch8');
verifyEqual(testCase, numel(final_results.runs), 12);
integer_wdm = strcmp({final_results.runs.doppler_mode}, 'integer') & ...
    strcmp({final_results.runs.spatial_pair}, 'wdm');
fractional_wdm = strcmp({final_results.runs.doppler_mode}, 'fractional') & ...
    strcmp({final_results.runs.spatial_pair}, 'wdm');
verifyEqual(testCase, unique([final_results.runs(integer_wdm).Lch]), 8);
verifyEqual(testCase, unique([final_results.runs(fractional_wdm).Lch]), 6);
verifyEqual(testCase, sum(strcmp({final_results.runs.spatial_pair}, 'dft')), 4);
verifyEqual(testCase, sum(strcmp({final_results.runs.spatial_pair}, 'svd')), 4);
verifyEqual(testCase, height(final_results.summary_table), 4);
verifyFalse(testCase, any(strcmp(final_results.summary_table.status, 'missing')));
end

function testNonmonotonicBerIsDiagnosedInsteadOfInterpolated(testCase)
runs = synthetic_runs();
run = runs(1);
p1 = run.points(1);
p2 = run.points(1);
p3 = run.points(2);
p1.ber_a = 1e-2; p1.ber_b = 2e-2;
p2.ber_a = 2e-2; p2.ber_b = 3e-2;
p3.ber_a = 1e-4; p3.ber_b = 2e-4;
run.SNR_dB = [10, 15, 20];
run.points = [p1, p2, p3];

summary = build_time_diversity_summary(run, 6, 1e-3);
row = strcmp(summary.doppler_mode, 'integer') & ...
    strcmp(summary.detector, 'block_lmmse');

verifyFalse(testCase, summary.monotonic(row));
verifyTrue(testCase, isnan(summary.snr_gain_db(row)));
verifyEqual(testCase, summary.status(row), {'nonmonotonic'});
end

function testSpatialPairLabelsMatchSpecNames(testCase)
verifyEqual(testCase, time_diversity_pair_labels('wdm'), {'AFWDM', 'OFWDM'});
verifyEqual(testCase, time_diversity_pair_labels('dft'), {'AFDM-DFT', 'OFDM-DFT'});
verifyEqual(testCase, time_diversity_pair_labels('svd'), {'AFDM-SVD', 'OFDM-SVD'});
end

function testManifestFingerprintCoversRecursivePathDependencies(testCase)
root = tempname;
delivery = fullfile(root, 'delivery');
variance = fullfile(root, 'variance', 'nested');
mkdir(delivery);
mkdir(variance);
cleanup = onCleanup(@() rmdir(root, 's'));
write_text(fullfile(delivery, 'runner.m'), 'function runner; end');
dependency = fullfile(variance, 'dependency.m');
write_text(dependency, 'function y=dependency; y=1; end');

cfg = make_delivery_config("time_diversity_smoke");
cfg.repo_root = root;
cfg.delivery_dir = delivery;
cfg.path_dirs = {delivery, fullfile(root, 'variance')};
before = build_time_diversity_run_manifest(cfg, 'baseline');
same = build_time_diversity_run_manifest(cfg, 'baseline');
write_text(dependency, 'function y=dependency; y=2; end');
after = build_time_diversity_run_manifest(cfg, 'baseline');

verifyEqual(testCase, same.code_fingerprint, before.code_fingerprint);
verifyNotEqual(testCase, after.code_fingerprint, before.code_fingerprint);
verifyError(testCase, @() validate_time_diversity_run_manifest( ...
    before, after, 'recursive dependency fixture'), ...
    'run_online_time_diversity:manifestMismatch');
end

function runs = synthetic_runs(spatial_pair)
if nargin < 1
    spatial_pair = 'wdm';
end

doppler = {'integer', 'fractional'};
detectors = {'block_lmmse', 'gabp'};
point_template = struct('ber_a', NaN, 'ber_b', NaN, ...
    'ber_ratio_b_over_a', NaN, 'ber_ratio_ci', [1.5, 2.5], ...
    'mcnemar_p', 0.01, 'noise_limited', false, 'claim_eligible', true);
runs = repmat(struct('doppler_mode', '', 'detector', '', ...
    'spatial_pair', spatial_pair, 'Lch', 6, 'kmax', 2, ...
    'SNR_dB', [10, 20], 'points', []), 1, 4);
index = 0;
for ii = 1:2
    for jj = 1:2
        index = index + 1;
        p1 = point_template;
        p1.ber_a = 1e-2;
        p1.ber_b = 2e-2;
        p1.ber_ratio_b_over_a = 2;
        p2 = point_template;
        p2.ber_a = 1e-4;
        p2.ber_b = 2e-4;
        p2.ber_ratio_b_over_a = 2;
        runs(index).doppler_mode = doppler{ii};
        runs(index).detector = detectors{jj};
        runs(index).points = [p1, p2];
    end
end
end

function pack = synthetic_exploration_pack(cfg, snr_db)
detectors = cfg.time_diversity.detectors;
base_ber = 10 ^ (-2 - 0.5 * (snr_db + 4));
point = struct( ...
    'ber_a', base_ber, ...
    'ber_b', 2 * base_ber, ...
    'ber_ratio_b_over_a', 2, ...
    'error_count_a', 120, ...
    'error_count_b', 240, ...
    'bit_count', 140800, ...
    'frame_count', 100, ...
    'discordant_a_only', 100, ...
    'discordant_b_only', 220, ...
    'mcnemar_p', 0.01, ...
    'noise_limited', false, ...
    'claim_eligible', true, ...
    'ber_ratio_ci', [1.5, 2.5], ...
    'stop_reason', 'target_errors', ...
    'average_iterations', [1; 1], ...
    'nonconvergence_rate', [0; 0], ...
    'final_residuals', nan(2, 0), ...
    'average_final_residual', [NaN; NaN], ...
    'error_table_afwdm', false(0, 0), ...
    'error_table_ofwdm', false(0, 0));
runs = repmat(struct( ...
    'doppler_mode', 'fractional', ...
    'detector', '', ...
    'spatial_pair', 'wdm', ...
    'Lch', cfg.time_diversity.Lch_values, ...
    'kmax', audit_time_diversity_dimensions(cfg).kmax, ...
    'SNR_dB', snr_db, ...
    'points', point, ...
    'waveform_audit', struct(), ...
    'lch_audit', struct()), 1, numel(detectors));
for ii = 1:numel(detectors)
    runs(ii).detector = detectors{ii};
end
pack = struct( ...
    'runs', runs, ...
    'N_s', cfg.time_diversity.N_s, ...
    'Nblk', cfg.Nblk, ...
    'array_shape', cfg.array_shape, ...
    'summary_table', build_time_diversity_summary( ...
        runs, cfg.time_diversity.Lch_values, ...
        cfg.time_diversity.summary_target_ber), ...
    'lch_comparison', []);
end

function tag = fixture_snr_tag(value)
if value < 0
    prefix = 'm';
else
    prefix = 'p';
end
tag = [prefix strrep(sprintf('%g', abs(value)), '.', 'p')];
end

function write_text(path_value, content)
fid = fopen(path_value, 'w');
assert(fid >= 0, 'Cannot write fixture: %s', path_value);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', content);
clear cleanup;
end
