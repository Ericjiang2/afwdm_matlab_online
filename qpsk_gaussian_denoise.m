function [posterior_mean, posterior_variance] = ...
    qpsk_gaussian_denoise(mean_in, variance_in)
%QPSK_GAUSSIAN_DENOISE Closed-form QPSK posterior under complex Gaussian input.
%
% For unit-power Cartesian QPSK, the real and imaginary components are
% independent equiprobable values in {-1/sqrt(2), +1/sqrt(2)}. This closed
% form is mathematically equivalent to enumerating all four constellation
% points, but avoids eight full-array exponential passes in every GaBP
% iteration.

component_amplitude = 1 / sqrt(2);
log_likelihood_scale = sqrt(2) ./ variance_in;
posterior_mean = component_amplitude * ...
    (tanh(log_likelihood_scale .* real(mean_in)) + ...
     1j * tanh(log_likelihood_scale .* imag(mean_in)));
posterior_variance = max( ...
    1 - abs(posterior_mean).^2, 1e-10);
end
