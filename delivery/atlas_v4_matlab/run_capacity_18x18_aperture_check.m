%% run_capacity_18x18_aperture_check.m
% Standalone MATLAB Online entry for the 18x18, lambda/2 aperture sanity check.
%
% Goal:
%   Check whether a roughly 9 lambda x 9 lambda UPA gives a physical-only
%   NLoS capacity magnitude closer to the reference line-aperture paper's
%   isotropic curve near P = 30 dBW.
%
% Default settings:
%   - array_shape = [18, 18], dx = dy = lambda/2
%   - Nblk = 64 only for shared config compatibility
%   - no AFWDM/DFT/SVD precoding
%   - physical-only capacity from H_spatial = sum_l H_l
%   - spacetime/DD block capacity is skipped to avoid a 20736 x 20736 SVD
%   - spacing sanity is skipped
%
% Optional override before running:
%   capacity_aperture18_numFrames = 10;      % quick check
%   capacity_aperture18_numFrames = 30;      % default, matches paper mode

clearvars -except capacity_aperture18_numFrames capacity_aperture18_P_dBW_list;
clc; close all;

if ~exist('capacity_aperture18_numFrames', 'var') || isempty(capacity_aperture18_numFrames)
    capacity_aperture18_numFrames = 30;
end
if ~exist('capacity_aperture18_P_dBW_list', 'var') || isempty(capacity_aperture18_P_dBW_list)
    capacity_aperture18_P_dBW_list = 0:5:30;
end

capacity_sanity_mode = "aperture18";
cfg_override = struct();
cfg_override.capacity_aperture18_numFrames = capacity_aperture18_numFrames;
cfg_override.capacity_aperture18_P_dBW_list = capacity_aperture18_P_dBW_list;

this_dir = fileparts(mfilename('fullpath'));
run(fullfile(this_dir, 'run_capacity_precoding_free_sanity.m'));
