function tests = test_detect_gmp
tests = functiontests(localfunctions);
end

function setupOnce(~)
repo_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(repo_root);
end

function testIdentityChannelRecoversQpskAndReportsConvergence(testCase)
bits = logical([0; 0; 0; 1; 1; 0; 1; 1]);
x = qam_modulate(bits, 4);
opts = struct('damping', 0.5, 'max_iterations', 20, ...
    'tolerance', 1e-6, 'edge_threshold_rel', 0, 'regularization', 1e-10);

[x_hat, info] = detect_gmp(eye(numel(x)), x, 1e-6, 4, opts);

verifyEqual(testCase, qam_demodulate(x_hat, 4), double(bits));
verifyTrue(testCase, info.converged);
verifyLessThanOrEqual(testCase, info.iterations, opts.max_iterations);
verifyEqual(testCase, info.damping, opts.damping);
end

function testDenseMimoResultIsDeterministicAndComparableToLmmse(testCase)
rng(20260715, 'twister');
n = 12;
H = eye(n) + 0.08 * (randn(n) + 1j * randn(n)) / sqrt(2 * n);
bits = randi([0, 1], 2 * n, 1);
x = qam_modulate(bits, 4);
noise_variance = 10^(-25 / 10);
unit_noise = (randn(n, 1) + 1j * randn(n, 1)) / sqrt(2);
y = H * x + sqrt(noise_variance) * unit_noise;
opts = struct('damping', 0.4, 'max_iterations', 15, ...
    'tolerance', 1e-5, 'edge_threshold_rel', 0, 'regularization', 1e-10);

[first, first_info] = detect_gmp(H, y, noise_variance, 4, opts);
[second, second_info] = detect_gmp(H, y, noise_variance, 4, opts);
lmmse = (H' * H + noise_variance * eye(n)) \ (H' * y);
err_gmp = sum(qam_demodulate(first, 4) ~= bits);
err_lmmse = sum(qam_demodulate(lmmse, 4) ~= bits);

verifyEqual(testCase, first, second, 'AbsTol', 0);
verifyEqual(testCase, first_info.iterations, second_info.iterations);
verifyLessThanOrEqual(testCase, err_gmp, err_lmmse + 2);
verifyEqual(testCase, first_info.edge_count, numel(H));
end

function testDiagnosticIterationCapAllowsSixty(testCase)
bits = logical([0; 0; 0; 1; 1; 0; 1; 1]);
x = qam_modulate(bits, 4);
opts = struct('damping', 0.4, 'max_iterations', 60, ...
    'tolerance', 1e-6, 'edge_threshold_rel', 0, 'regularization', 1e-10);

[x_hat, info] = detect_gmp(eye(numel(x)), x, 1e-6, 4, opts);

verifyEqual(testCase, qam_demodulate(x_hat, 4), double(bits));
verifyEqual(testCase, info.max_iterations, 60);
end

function testDiagnosticIterationCapRejectsAboveSixty(testCase)
opts = struct('max_iterations', 61);

verifyError(testCase, ...
    @() detect_gmp(eye(2), ones(2, 1), 1, 4, opts), ...
    'MATLAB:notLessEqual');
end

function testInvalidDampingFailsExplicitly(testCase)
opts = struct('damping', 1.2);
verifyError(testCase, @() detect_gmp(eye(2), ones(2, 1), 1, 4, opts), ...
    'detect_gmp:damping');
end
