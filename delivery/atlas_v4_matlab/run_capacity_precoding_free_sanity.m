%% run_capacity_precoding_free_sanity.m
% Precoding-free capacity sanity runner for MATLAB Online.
%
% Public outputs:
%   - C_spatial: static physical-only capacity from H_spatial = sum_l H_l
%   - C_spacetime_total: block capacity from sum_l kron(Theta_l, H_l)
%   - C_spacetime_per_use: C_spacetime_total / Nblk
%   - capacity_precoding_free_vs_power.png
%   - capacity_spacing_sanity.png
%
% This runner intentionally uses no AFWDM/DFT/SVD precoding, no mode
% selection, no RF truncation, and no beamspace stream adaptation.

clearvars -except capacity_sanity_mode cfg_override; clc; close all;

this_dir = fileparts(mfilename('fullpath'));
addpath(this_dir);

if ~exist('capacity_sanity_mode', 'var') || isempty(capacity_sanity_mode)
    capacity_sanity_mode = "smoke";
end
capacity_sanity_mode = lower(string(capacity_sanity_mode));

cfg_run = make_delivery_config("quick");
if exist('cfg_override', 'var') && ~isempty(cfg_override)
    cfg_run = merge_delivery_config(cfg_run, cfg_override);
end
cfg_run = configure_precoding_free_sanity(cfg_run, capacity_sanity_mode);

for ii = 1:numel(cfg_run.path_dirs)
    if exist(cfg_run.path_dirs{ii}, 'dir')
        addpath(cfg_run.path_dirs{ii});
    end
end
if ~exist(cfg_run.output_dir, 'dir')
    mkdir(cfg_run.output_dir);
end

out_dir = fullfile(cfg_run.output_dir, 'capacity_precoding_free_sanity');
fig_dir = fullfile(out_dir, 'figures');
if ~exist(out_dir, 'dir'); mkdir(out_dir); end
if ~exist(fig_dir, 'dir'); mkdir(fig_dir); end

fprintf('\n============================================================\n');
fprintf(' Precoding-free capacity sanity (%s mode)\n', cfg_run.capacity_sanity_mode);
fprintf(' Output: %s\n', out_dir);
fprintf(' Matrix A: H_spatial = sum_l H_l\n');
fprintf(' Matrix B: H_spacetime = sum_l kron(Theta_l, H_l), plotted / Nblk\n');
fprintf('============================================================\n');

power_results = run_power_sanity(cfg_run);
spacing_results = run_spacing_sanity(cfg_run);

results = struct();
results.power = power_results;
results.spacing = spacing_results;

metadata = struct();
metadata.generated_by = 'delivery/atlas_v4_matlab/run_capacity_precoding_free_sanity.m';
metadata.capacity_sanity_mode = cfg_run.capacity_sanity_mode;
metadata.capacity_contract = 'precoding_free_physical_only_and_physical_plus_delay_doppler';
metadata.spatial_matrix = 'H_spatial = coherent sum of physical NLoS taps';
metadata.spacetime_matrix = 'H_spacetime = sum kron(delay_doppler_operator, physical_tap)';
metadata.time_operator = 'build_theta_p(tau, nu, Nblk, 0): delay+Doppler, no chirp CPP';
metadata.capacity_units_main_plot = 'C_spatial and C_spacetime_per_use in bit/s/Hz per use';
metadata.saved_fields = {'C_spatial', 'C_spacetime_total', 'C_spacetime_per_use', ...
    'physical_model', 'iid_rayleigh'};
metadata.excluded_processing = {'spatial_precoding', 'mode_selection', ...
    'rf_truncation', 'beamspace_stream_adaptation'};
metadata.Nblk = cfg_run.Nblk;
metadata.capacity_sigma2_fixed = cfg_run.capacity_sigma2_fixed;

timestamp = datestr(now, 'yyyymmdd_HHMMSS');
out_mat = fullfile(out_dir, sprintf('capacity_precoding_free_sanity_%s_%s.mat', ...
    cfg_run.capacity_sanity_mode, timestamp));
save(out_mat, 'cfg_run', 'results', 'metadata', '-v7.3');

plot_files = plot_precoding_free_results(cfg_run, results, fig_dir);

fprintf('\nSaved MAT: %s\n', out_mat);
fprintf('Saved figures:\n');
for ii = 1:numel(plot_files)
    fprintf('  %s\n', plot_files{ii});
end

print_summary(results);
fprintf('Done.\n');

function cfg_run = configure_precoding_free_sanity(cfg_run, mode)
cfg_run.capacity_sanity_mode = char(mode);
cfg_run.capacity_sigma2_fixed = 1;
cfg_run.schemes = {};
cfg_run.strategies = {};
cfg_run.spacing_fixed_aperture_lambda = [4, 4];
cfg_run.spacing_scenario = struct('label', 'physical_model', ...
    'pas_model', 'isotropic', 'cv', 1.0, 'use_perpath_sigma', false);

switch mode
    case "smoke"
        cfg_run.array_shape = [4, 4];
        cfg_run.Nblk = 16;
        cfg_run.capacity_numFrames = 1;
        cfg_run.capacity_P_dBW_list = [0, 10];
        cfg_run.capacity_scenarios = struct( ...
            'label', {'physical_isotropic', 'physical_vmf_cv030'}, ...
            'pas_model', {'isotropic', 'vmf'}, ...
            'cv', {1.0, 0.30}, ...
            'use_perpath_sigma', {false, true});
        cfg_run.spacing_numFrames = 1;
        cfg_run.spacing_P_dBW = 10;
        cfg_run.spacing_list_lambda = [1/2, 1/4];

    case "paper"
        cfg_run.array_shape = [8, 8];
        cfg_run.Nblk = 64;
        cfg_run.capacity_numFrames = 30;
        cfg_run.capacity_P_dBW_list = 0:5:30;
        cfg_run.capacity_scenarios = struct( ...
            'label', {'physical_isotropic', 'physical_vmf_cv030'}, ...
            'pas_model', {'isotropic', 'vmf'}, ...
            'cv', {1.0, 0.30}, ...
            'use_perpath_sigma', {false, true});
        cfg_run.spacing_numFrames = 10;
        cfg_run.spacing_P_dBW = 20;
        cfg_run.spacing_list_lambda = [1/2, 1/4, 1/6, 1/8];

    otherwise
        error('run_capacity_precoding_free_sanity:unknownMode', ...
            'Unknown capacity_sanity_mode "%s". Use smoke or paper.', mode);
end
end

function power_results = run_power_sanity(cfg_run)
nScenario = numel(cfg_run.capacity_scenarios);
nP = numel(cfg_run.capacity_P_dBW_list);
nFrame = cfg_run.capacity_numFrames;

C_spatial = nan(nScenario, nP, nFrame);
C_spacetime_total = nan(nScenario, nP, nFrame);
C_spacetime_per_use = nan(nScenario, nP, nFrame);
labels = cell(1, nScenario);

for iScenario = 1:nScenario
    spec = cfg_run.capacity_scenarios(iScenario);
    labels{iScenario} = spec.label;
    scenario = prepare_delivery_scenario(cfg_run, spec);
    cfg = scenario.cfg;

    fprintf('\n[power] scenario %d/%d: %s\n', iScenario, nScenario, spec.label);
    for frm = 1:nFrame
        seed_base = cfg_run.seed.frame_stride * frm + ...
            cfg_run.seed.capacity_scenario_offset * iScenario;
        [tau_vec, nu_vec] = generate_phys_dd_paths(cfg, cfg.Lch, seed_base);
        H_taps = build_delivery_channel_taps(scenario, seed_base);

        H_spatial = coherent_sum_taps(H_taps);
        H_spacetime = build_spacetime_channel(H_taps, tau_vec, nu_vec, cfg.Nblk);

        for iP = 1:nP
            Ptot = 10^(cfg_run.capacity_P_dBW_list(iP) / 10);
            C_spatial(iScenario, iP, frm) = block_capacity_total( ...
                H_spatial, Ptot, cfg_run.capacity_sigma2_fixed, false, cfg.Nblk);
            C_spacetime_total(iScenario, iP, frm) = block_capacity_total( ...
                H_spacetime, Ptot, cfg_run.capacity_sigma2_fixed, false, cfg.Nblk);
            C_spacetime_per_use(iScenario, iP, frm) = ...
                C_spacetime_total(iScenario, iP, frm) / cfg.Nblk;
        end
    end
end

power_results = struct();
power_results.P_dBW_list = cfg_run.capacity_P_dBW_list;
power_results.labels = labels;
power_results.C_spatial = C_spatial;
power_results.C_spacetime_total = C_spacetime_total;
power_results.C_spacetime_per_use = C_spacetime_per_use;
power_results.Nblk = cfg_run.Nblk;
power_results.capacity_formula = 'water-filling over svd(H)^2 with fixed noise';
power_results.spatial_matrix = 'coherent sum of physical taps';
power_results.spacetime_matrix = 'sum kron(delay_doppler_operator, physical_tap)';
end

function spacing_results = run_spacing_sanity(cfg_run)
spacing_list = cfg_run.spacing_list_lambda;
nSpacing = numel(spacing_list);
nFrame = cfg_run.spacing_numFrames;
Ptot = 10^(cfg_run.spacing_P_dBW / 10);

physical_model = nan(nSpacing, nFrame);
iid_rayleigh = nan(nSpacing, nFrame);
array_shapes = nan(nSpacing, 2);

for iSpacing = 1:nSpacing
    d = spacing_list(iSpacing);
    cfg_spacing = cfg_run;
    cfg_spacing.dx = d;
    cfg_spacing.dy = d;
    cfg_spacing.array_shape = max(1, round(cfg_run.spacing_fixed_aperture_lambda ./ d));
    array_shapes(iSpacing, :) = cfg_spacing.array_shape;

    scenario = prepare_delivery_scenario(cfg_spacing, cfg_spacing.spacing_scenario);
    cfg = scenario.cfg;

    fprintf('[spacing] d=1/%d lambda, array=%dx%d\n', ...
        round(1 / d), cfg.Msx, cfg.Msy);

    for frm = 1:nFrame
        seed_base = 3100000 + 100000 * iSpacing + cfg_run.seed.frame_stride * frm;
        H_taps = build_delivery_channel_taps(scenario, seed_base);
        H_spatial = coherent_sum_taps(H_taps);
        physical_model(iSpacing, frm) = block_capacity_total( ...
            H_spatial, Ptot, cfg_run.capacity_sigma2_fixed, false, cfg.Nblk);

        rng(seed_base + 7919);
        H_iid = (randn(cfg.Mr, cfg.Ms) + 1j * randn(cfg.Mr, cfg.Ms)) / sqrt(2);
        iid_rayleigh(iSpacing, frm) = block_capacity_total( ...
            H_iid, Ptot, cfg_run.capacity_sigma2_fixed, false, cfg.Nblk);
    end
end

spacing_results = struct();
spacing_results.spacing_lambda = spacing_list;
spacing_results.spacing_labels = arrayfun(@(d) sprintf('1/%d', round(1 / d)), ...
    spacing_list, 'UniformOutput', false);
spacing_results.array_shapes = array_shapes;
spacing_results.P_dBW = cfg_run.spacing_P_dBW;
spacing_results.physical_model = physical_model;
spacing_results.iid_rayleigh = iid_rayleigh;
spacing_results.sanity_question = 'Does the physical_model avoid iid_rayleigh black-line oversampling growth?';
end

function H_sum = coherent_sum_taps(H_taps)
H_sum = zeros(size(H_taps{1}));
for ell = 1:numel(H_taps)
    H_sum = H_sum + H_taps{ell};
end
end

function H_st = build_spacetime_channel(H_taps, tau_vec, nu_vec, Nblk)
Mr = size(H_taps{1}, 1);
Ms = size(H_taps{1}, 2);
H_st = zeros(Nblk * Mr, Nblk * Ms);
for ell = 1:numel(H_taps)
    tau = round(real(tau_vec(ell)));
    nu = round(real(nu_vec(ell)));
    Theta = build_theta_p(tau, nu, Nblk, 0);
    H_st = H_st + kron(Theta, H_taps{ell});
end
end

function plot_files = plot_precoding_free_results(cfg_run, results, fig_dir)
plot_files = {};

power = results.power;
f = figure('Visible', 'off', 'Color', 'w');
hold on; grid on;
styles = {'-o', '--s', '-^', '--d'};
leg = {};
for iScenario = 1:numel(power.labels)
    y_spatial = squeeze(mean(power.C_spatial(iScenario, :, :), 3, 'omitnan'));
    y_st = squeeze(mean(power.C_spacetime_per_use(iScenario, :, :), 3, 'omitnan'));
    plot(power.P_dBW_list, y_spatial, styles{1 + mod(2*iScenario-2, numel(styles))}, ...
        'LineWidth', 1.5, 'MarkerSize', 5);
    plot(power.P_dBW_list, y_st, styles{1 + mod(2*iScenario-1, numel(styles))}, ...
        'LineWidth', 1.5, 'MarkerSize', 5);
    leg{end+1} = sprintf('%s physical only', power.labels{iScenario}); %#ok<AGROW>
    leg{end+1} = sprintf('%s physical + DD / Nblk', power.labels{iScenario}); %#ok<AGROW>
end
xlabel('Total transmit power P (dBW)');
ylabel('Capacity per use (bit/s/Hz)');
title('Precoding-free physical vs delay-Doppler capacity');
legend(leg, 'Location', 'northwest', 'Interpreter', 'none');
out_png = fullfile(fig_dir, 'capacity_precoding_free_vs_power.png');
save_png(f, out_png);
close(f);
plot_files{end+1} = out_png;

spacing = results.spacing;
f = figure('Visible', 'off', 'Color', 'w');
hold on; grid on;
x = 1 ./ spacing.spacing_lambda;
y_phys = mean(spacing.physical_model, 2, 'omitnan');
y_iid = mean(spacing.iid_rayleigh, 2, 'omitnan');
plot(x, y_phys, '-o', 'LineWidth', 1.5, 'MarkerSize', 5);
plot(x, y_iid, '-s', 'LineWidth', 1.5, 'MarkerSize', 5);
xlabel('Sampling density 1/d (per wavelength)');
ylabel(sprintf('Static spatial capacity at P=%g dBW', spacing.P_dBW));
title('Spacing sanity: physical_model vs iid_rayleigh');
legend({'physical_model', 'iid_rayleigh'}, 'Location', 'northwest', 'Interpreter', 'none');
out_png = fullfile(fig_dir, 'capacity_spacing_sanity.png');
save_png(f, out_png);
close(f);
plot_files{end+1} = out_png;
end

function print_summary(results)
power = results.power;
fprintf('\n=== Power summary at highest P ===\n');
idxP = numel(power.P_dBW_list);
for iScenario = 1:numel(power.labels)
    c0 = mean(power.C_spatial(iScenario, idxP, :), 'all', 'omitnan');
    c1 = mean(power.C_spacetime_per_use(iScenario, idxP, :), 'all', 'omitnan');
    fprintf('%s: C_spatial=%.4g, C_spacetime_per_use=%.4g\n', ...
        power.labels{iScenario}, c0, c1);
end

spacing = results.spacing;
phys = mean(spacing.physical_model, 2, 'omitnan');
iid = mean(spacing.iid_rayleigh, 2, 'omitnan');
fprintf('\n=== Spacing sanity summary ===\n');
fprintf('physical_model first/last = %.4g / %.4g\n', phys(1), phys(end));
fprintf('iid_rayleigh first/last   = %.4g / %.4g\n', iid(1), iid(end));
end

function save_png(fig_handle, out_png)
try
    exportgraphics(fig_handle, out_png, 'Resolution', 160);
catch
    saveas(fig_handle, out_png);
end
end
