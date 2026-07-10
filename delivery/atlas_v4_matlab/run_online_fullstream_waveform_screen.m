% run_online_fullstream_waveform_screen.m
% Public MATLAB Online entry for the six-line, full-spatial-stream screen.
%
% Optional overrides before running:
%   fullstream_screen_numFrames = 1;       % local lightweight smoke
%   fullstream_screen_SNR_dB_list = 10;    % one checkpointed SNR point

clearvars -except fullstream_screen_array_shape fullstream_screen_numFrames ...
    fullstream_screen_SNR_dB_list fullstream_screen_N_s;
clc;

if ~exist('fullstream_screen_array_shape', 'var') || isempty(fullstream_screen_array_shape)
    fullstream_screen_array_shape = [4, 4];
end
if ~exist('fullstream_screen_numFrames', 'var') || isempty(fullstream_screen_numFrames)
    fullstream_screen_numFrames = 200;
end
if ~exist('fullstream_screen_SNR_dB_list', 'var') || isempty(fullstream_screen_SNR_dB_list)
    fullstream_screen_SNR_dB_list = -10:5:20;
end
if ~exist('fullstream_screen_N_s', 'var') || isempty(fullstream_screen_N_s)
    fullstream_screen_N_s = 'full';
end

delivery_online_profile = "fullstream_waveform_screen";
delivery_online_screen = struct( ...
    'array_shape', fullstream_screen_array_shape, ...
    'N_s', fullstream_screen_N_s, ...
    'v_max_kmh', 860, ...
    'tau_max_us', 32, ...
    'SNR_dB_list', fullstream_screen_SNR_dB_list, ...
    'numFrames', fullstream_screen_numFrames, ...
    'use_fractional_doppler', true, ...
    'scenario', struct('label', 'fullstream_strict_isotropic', ...
        'pas_model', 'isotropic', 'cv', 1.0, 'use_perpath_sigma', false));

this_dir = fileparts(mfilename('fullpath'));
run(fullfile(this_dir, 'run_delivery_online_resumable.m'));
