function tests = test_iso_perfect_snr15_tail_contract
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
test_dir = fileparts(mfilename('fullpath'));
repo_root = fileparts(fileparts(test_dir));
delivery_dir = fullfile(repo_root, 'delivery', 'atlas_v4_matlab');
addpath(delivery_dir);
testCase.TestData.delivery_dir = delivery_dir;
end

function testSvdUsesHalfCompletedAfwdmTailBudget(testCase)
cfg = make_iso_perfect_snr15_tail_config('SVD_paper');

verifyEqual(testCase, cfg.scheme, 'SVD_paper');
verifyEqual(testCase, cfg.total_frames, 750);
verifyEqual(testCase, cfg.chunk_frames, 100);
verifyEqual(testCase, cfg.frame_start_offset, 100);
verifyEqual(testCase, cfg.SNR_dB, 15);
verifyEqual(testCase, cfg.scenario, 'strict_isotropic');
verifyEqual(testCase, cfg.strategy, 'full');
verifyEqual(testCase, cfg.csi_label, 'perfect CSI');
end

function testAfwdmWrapperKeepsLegacyDefaults(testCase)
cfg = make_iso_perfect_snr15_tail_config('AFWDM');

verifyEqual(testCase, cfg.scheme, 'AFWDM');
verifyEqual(testCase, cfg.total_frames, 1000);
verifyEqual(testCase, cfg.chunk_frames, 100);
verifyEqual(testCase, cfg.frame_start_offset, 100);
end

function testUnknownSchemeFailsExplicitly(testCase)
verifyError(testCase, ...
    @() make_iso_perfect_snr15_tail_config('unknown'), ...
    'make_iso_perfect_snr15_tail_config:scheme');
end

function testDeliveryLoopDispatchesBySchemeName(testCase)
main_file = fullfile(testCase.TestData.delivery_dir, 'main_atlas_v4_delivery.m');
source = fileread(main_file);

verifyNotEmpty(testCase, strfind(source, 'switch cfg_run.schemes{k}'));
verifyNotEmpty(testCase, strfind(source, 'case ''SVD_paper'''));
verifyEmpty(testCase, strfind(source, 'Us_list{k}'));
end
