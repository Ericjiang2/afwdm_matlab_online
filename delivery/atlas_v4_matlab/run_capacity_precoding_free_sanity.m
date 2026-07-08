%% run_capacity_precoding_free_sanity.m
% Precoding-free capacity sanity runner for MATLAB Online.
%
% Public outputs:
%   - C_spatial: static physical-only capacity from H_spatial = sum_l H_l
%   - C_spacetime_total: block capacity from sum_l kron(Theta_l, H_l)
%   - C_spacetime_per_use: C_spacetime_total / Nblk
%   - capacity_precoding_free_vs_power.png
%   - capacity_spacing_sanity.png
%   - aperture18 mode: 18x18, lambda/2, physical-only capacity check
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
if cfg_run.run_spacing_sanity
    spacing_results = run_spacing_sanity(cfg_run);
else
    spacing_results = [];
end

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
metadata.capacity_run_spacetime = cfg_run.capacity_run_spacetime;
metadata.run_spacing_sanity = cfg_run.run_spacing_sanity;

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
cfg_run.capacity_run_spacetime = true;
cfg_run.run_spacing_sanity = true;
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

    case "aperture18"
        cfg_run.array_shape = [18, 18];
        cfg_run.dx = 0.5;
        cfg_run.dy = 0.5;
        cfg_run.Nblk = 64;
        cfg_run.capacity_run_spacetime = false;
        cfg_run.run_spacing_sanity = false;
        cfg_run.capacity_numFrames = get_optional_field(cfg_run, ...
            'capacity_aperture18_numFrames', 30);
        cfg_run.capacity_P_dBW_list = get_optional_field(cfg_run, ...
            'capacity_aperture18_P_dBW_list', 0:5:30);
        cfg_run.capacity_scenarios = struct( ...
            'label', {'aperture18_isotropic', 'aperture18_vmf_cv030'}, ...
            'pas_model', {'isotropic', 'vmf'}, ...
            'cv', {1.0, 0.30}, ...
            'use_perpath_sigma', {false, true});
        cfg_run.spacing_numFrames = 0;
        cfg_run.spacing_P_dBW = 20;
        cfg_run.spacing_list_lambda = [];

    otherwise
        error('run_capacity_precoding_free_sanity:unknownMode', ...
            'Unknown capacity_sanity_mode "%s". Use smoke, paper, or aperture18.', mode);
end
end

function value = get_optional_field(s, field_name, default_value)
if isfield(s, field_name) && ~isempty(s.(field_name))
    value = s.(field_name);
else
    value = default_value;
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
        H_taps = build_delivery_channel_taps(scenario, seed_base);

        H_spatial = coherent_sum_taps(H_taps);
        if cfg_run.capacity_run_spacetime
            [tau_vec, nu_vec] = generate_phys_dd_paths(cfg, cfg.Lch, seed_base);
            H_spacetime = build_spacetime_channel(H_taps, tau_vec, nu_vec, cfg.Nblk);
        else
            H_spacetime = [];
        end

        for iP = 1:nP
            Ptot = 10^(cfg_run.capacity_P_dBW_list(iP) / 10);
            C_spatial(iScenario, iP, frm) = block_capacity_total( ...
                H_spatial, Ptot, cfg_run.capacity_sigma2_fixed, false, cfg.Nblk);
            if cfg_run.capacity_run_spacetime
                C_spacetime_total(iScenario, iP, frm) = block_capacity_total( ...
                    H_spacetime, Ptot, cfg_run.capacity_sigma2_fixed, false, cfg.Nblk);
                C_spacetime_per_use(iScenario, iP, frm) = ...
                    C_spacetime_total(iScenario, iP, frm) / cfg.Nblk;
            end
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
power_results.spacetime_enabled = cfg_run.capacity_run_spacetime;
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

    scenario = prepare_spacing_physical_scenario(cfg_spacing, cfg_spacing.spacing_scenario);
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
phys_mean = mean(physical_model, 2, 'omitnan');
iid_mean = mean(iid_rayleigh, 2, 'omitnan');
spacing_results.physical_growth_ratio = phys_mean(end) / phys_mean(1);
spacing_results.iid_growth_ratio = iid_mean(end) / iid_mean(1);
spacing_results.growth_ratio_test = spacing_results.physical_growth_ratio < ...
    spacing_results.iid_growth_ratio;
spacing_results.sanity_question = 'Does the physical_model avoid iid_rayleigh black-line oversampling growth?';
end

function scenario = prepare_spacing_physical_scenario(cfg_run, scenario_spec)
cfg = make_precoding_free_base_cfg(cfg_run);
cfg.pas_model = scenario_spec.pas_model;

mode_shape = max(1, round(cfg_run.spacing_fixed_aperture_lambda .* 2));
mode_cfg = cfg;
mode_cfg.Msx = mode_shape(1);
mode_cfg.Msy = mode_shape(2);
mode_cfg.Mrx = mode_shape(1);
mode_cfg.Mry = mode_shape(2);
mode_cfg.Lsx = cfg_run.spacing_fixed_aperture_lambda(1);
mode_cfg.Lsy = cfg_run.spacing_fixed_aperture_lambda(2);
mode_cfg.Lrx = cfg_run.spacing_fixed_aperture_lambda(1);
mode_cfg.Lry = cfg_run.spacing_fixed_aperture_lambda(2);

switch lower(cfg.pas_model)
    case {'isotropic', 'isotropic_reference'}
        [var_s_raw, ~] = function_computeVar(mode_cfg.Lsx, mode_cfg.Lsy);
        [var_r_raw, ~] = function_computeVar(mode_cfg.Lrx, mode_cfg.Lry);
        Ps_shift_raw = var_s_raw.';
        Pr_shift_raw = var_r_raw.';
    otherwise
        error('run_capacity_precoding_free_sanity:spacingPAS', ...
            'Spacing sanity currently supports isotropic physical mode variance, got "%s".', ...
            cfg.pas_model);
end

Ps_mode = physical_mode_variance_to_dft(Ps_shift_raw, mode_cfg.Msx, mode_cfg.Msy, ...
    mode_cfg.Lsx, mode_cfg.Lsy, cfg.disable_prop_mask);
Pr_mode = physical_mode_variance_to_dft(Pr_shift_raw, mode_cfg.Mrx, mode_cfg.Mry, ...
    mode_cfg.Lrx, mode_cfg.Lry, cfg.disable_prop_mask);

Ps = embed_mode_variance_2d_local(Ps_mode, cfg.Msx, cfg.Msy);
Pr = embed_mode_variance_2d_local(Pr_mode, cfg.Mrx, cfg.Mry);
Ps = Ps / sum(Ps(:));
Pr = Pr / sum(Pr(:));
Sigma2 = Pr(:) * (Ps(:).');
Sigma2 = Sigma2 / sum(Sigma2(:));

scenario = struct();
scenario.label = scenario_spec.label;
scenario.cfg = cfg;
scenario.Sigma2 = Sigma2;
scenario.Sigma2_p = {};
scenario.Dr = ones(cfg.Mr, 1);
scenario.Ds = ones(cfg.Ms, 1);
scenario.Ps = Ps;
scenario.Pr = Pr;
scenario.use_perpath_sigma = false;
scenario.sigma_mass_sum = sum(Sigma2(:));
scenario.notes = struct( ...
    'spacing_model', 'fixed physical aperture; extra dense-sampling DFT bins get zero variance', ...
    'negative_control', 'iid_rayleigh uses all sample-space entries and should show oversampling growth');
end

function cfg = make_precoding_free_base_cfg(cfg_run)
cfg = struct();
c0 = 3e8;
cfg.fc = cfg_run.fc;
cfg.lambda = c0 / cfg.fc;
cfg.v_max_kmh = cfg_run.v_max_kmh;
cfg.v_max = cfg.v_max_kmh / 3.6;
cfg.Deltaf = cfg_run.Deltaf;
cfg.Tsym = 1 / cfg.Deltaf;
cfg.Nblk = cfg_run.Nblk;
cfg.Ts = 1 / (cfg.Nblk * cfg.Deltaf);
cfg.nu_max = cfg.v_max / cfg.lambda;
cfg.kmax = ceil(cfg.nu_max / cfg.Deltaf);
cfg.tau_max = cfg_run.tau_max_us * 1e-6;
cfg.lmax = ceil(cfg.tau_max / cfg.Ts);
cfg.Lch = 4;

cfg.Msx = cfg_run.array_shape(1);
cfg.Msy = cfg_run.array_shape(2);
cfg.Mrx = cfg_run.array_shape(1);
cfg.Mry = cfg_run.array_shape(2);
cfg.Ms = cfg.Msx * cfg.Msy;
cfg.Mr = cfg.Mrx * cfg.Mry;
cfg.dx = cfg_run.dx;
cfg.dy = cfg_run.dy;
cfg.Lsx = cfg_run.spacing_fixed_aperture_lambda(1);
cfg.Lsy = cfg_run.spacing_fixed_aperture_lambda(2);
cfg.Lrx = cfg_run.spacing_fixed_aperture_lambda(1);
cfg.Lry = cfg_run.spacing_fixed_aperture_lambda(2);
cfg.sz = 0;
cfg.rz = 0;
cfg.disable_prop_mask = cfg_run.disable_prop_mask;
cfg.channel_norm_mode = cfg_run.channel_norm_mode;
cfg.Us_full = make_2d_dft(cfg.Msx, cfg.Msy);
cfg.Ur_full = make_2d_dft(cfg.Mrx, cfg.Mry);
end

function P_dft = physical_mode_variance_to_dft(P_shift_raw, Mx, My, Lx, Ly, disable_prop_mask)
[KX, KY] = ndgrid((0:Mx-1) - floor(Mx/2), (0:My-1) - floor(My/2));
kappa2 = (KX / Lx).^2 + (KY / Ly).^2;
prop_mask = kappa2 <= 1.0;
if disable_prop_mask
    prop_mask(:) = true;
end
P_shift = P_shift_raw .* prop_mask;
P_dft = ifftshift(P_shift);
P_dft = P_dft / sum(P_dft(:));
end

function P_big = embed_mode_variance_2d_local(P_mode, Mx, My)
[nx, ny] = size(P_mode);
assert(Mx >= nx, 'embed_mode_variance_2d_local: Mx (%d) < mode nx (%d).', Mx, nx);
assert(My >= ny, 'embed_mode_variance_2d_local: My (%d) < mode ny (%d).', My, ny);

if Mx == nx && My == ny
    P_big = P_mode;
    return;
end

Lx = nx / 2;
Ly = ny / 2;
assert(abs(Lx - round(Lx)) < 1e-12, 'Mode grid nx must be even.');
assert(abs(Ly - round(Ly)) < 1e-12, 'Mode grid ny must be even.');
Lx = round(Lx);
Ly = round(Ly);

P_big = zeros(Mx, My);
pos_x_src = 1:Lx;
neg_x_src = Lx+1:nx;
pos_y_src = 1:Ly;
neg_y_src = Ly+1:ny;
pos_x_dst = 1:Lx;
neg_x_dst = Mx-Lx+1:Mx;
pos_y_dst = 1:Ly;
neg_y_dst = My-Ly+1:My;

P_big(pos_x_dst, pos_y_dst) = P_mode(pos_x_src, pos_y_src);
P_big(pos_x_dst, neg_y_dst) = P_mode(pos_x_src, neg_y_src);
P_big(neg_x_dst, pos_y_dst) = P_mode(neg_x_src, pos_y_src);
P_big(neg_x_dst, neg_y_dst) = P_mode(neg_x_src, neg_y_src);
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
    leg{end+1} = sprintf('%s physical only', power.labels{iScenario}); %#ok<AGROW>
    if any(isfinite(y_st(:)))
        plot(power.P_dBW_list, y_st, styles{1 + mod(2*iScenario-1, numel(styles))}, ...
            'LineWidth', 1.5, 'MarkerSize', 5);
        leg{end+1} = sprintf('%s physical + DD / Nblk', power.labels{iScenario}); %#ok<AGROW>
    end
end
xlabel('Total transmit power P (dBW)');
ylabel('Capacity per use (bit/s/Hz)');
if power.spacetime_enabled
    title('Precoding-free physical vs delay-Doppler capacity');
else
    title('Precoding-free physical-only capacity');
end
legend(leg, 'Location', 'northwest', 'Interpreter', 'none');
out_png = fullfile(fig_dir, 'capacity_precoding_free_vs_power.png');
save_png(f, out_png);
close(f);
plot_files{end+1} = out_png;

if ~isfield(results, 'spacing') || isempty(results.spacing)
    return;
end

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
    if isfinite(c1)
        fprintf('%s: C_spatial=%.4g, C_spacetime_per_use=%.4g\n', ...
            power.labels{iScenario}, c0, c1);
    else
        fprintf('%s: C_spatial=%.4g, C_spacetime_per_use=skipped\n', ...
            power.labels{iScenario}, c0);
    end
end

if ~isfield(results, 'spacing') || isempty(results.spacing)
    fprintf('\n=== Spacing sanity summary ===\n');
    fprintf('Skipped for this mode.\n');
    return;
end

spacing = results.spacing;
phys = mean(spacing.physical_model, 2, 'omitnan');
iid = mean(spacing.iid_rayleigh, 2, 'omitnan');
fprintf('\n=== Spacing sanity summary ===\n');
fprintf('physical_model first/last = %.4g / %.4g\n', phys(1), phys(end));
fprintf('iid_rayleigh first/last   = %.4g / %.4g\n', iid(1), iid(end));
fprintf('growth ratio physical/iid = %.4g / %.4g (pass=%d)\n', ...
    spacing.physical_growth_ratio, spacing.iid_growth_ratio, spacing.growth_ratio_test);
end

function save_png(fig_handle, out_png)
try
    exportgraphics(fig_handle, out_png, 'Resolution', 160);
catch
    saveas(fig_handle, out_png);
end
end
