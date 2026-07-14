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

function testDeliveryPlotWritesMimoMainAppendixAndTableOnly(testCase)
runs = [synthetic_runs('wdm'), synthetic_runs('dft'), synthetic_runs('svd')];
results = struct('runs', runs, 'N_s', 11, 'Nblk', 64, ...
    'array_shape', [4, 4], 'summary_table', ...
    build_time_diversity_summary(runs, 6, 1e-3));
cfg = make_delivery_config("time_diversity_smoke");
out_dir = tempname;
mkdir(out_dir);
cleanup = onCleanup(@() rmdir(out_dir, 's')); %#ok<NASGU>

files = plot_time_diversity_results(results, cfg, out_dir);

verifyTrue(testCase, isfile(fullfile(out_dir, 'time_diversity_mimo_main.png')));
verifyTrue(testCase, isfile(fullfile(out_dir, 'time_diversity_svd_appendix.png')));
verifyTrue(testCase, isfile(fullfile(out_dir, 'time_diversity_summary.csv')));
verifyFalse(testCase, any(contains(string(files), 'siso')));
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
cleanup = onCleanup(@() rmdir(out_root, 's')); %#ok<NASGU>

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
verifyEqual(testCase, package.final_results.runs, package.baseline.runs);
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
