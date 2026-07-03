%% pilot_demo_embedded_channel_estimation.m
% Prototype: embedded-pilot delay-Doppler channel estimation for AFDM/AFWDM.
%
% This is intentionally a small research probe, not part of the four production
% figures. It compares three sensing dictionaries:
%   1) OFDM embedded pilot, full delay-Doppler dictionary.
%   2) AFDM embedded pilot, full delay-Doppler dictionary.
%   3) AFWDM-style support-aware pilot, reduced dictionary.
%
% The AFWDM-style branch represents the key idea: WDM/PAS support information
% can reduce the channel-estimation search space before estimating path gains.

clear; clc; close all;

this_dir = fileparts(mfilename('fullpath'));
repo_root = fileparts(fileparts(this_dir));
addpath(this_dir);
addpath(repo_root);

cfg = struct();
cfg.Nblk = 64;
cfg.fc = 4e9;
cfg.lambda = 3e8 / cfg.fc;
cfg.v_max_kmh = 860;
cfg.v_max = cfg.v_max_kmh / 3.6;
cfg.Deltaf = 2e3;
cfg.Tsym = 1 / cfg.Deltaf;
cfg.Ts = 1 / (cfg.Nblk * cfg.Deltaf);
cfg.nu_max = cfg.v_max / cfg.lambda;
cfg.kmax = ceil(cfg.nu_max / cfg.Deltaf);
cfg.tau_max_us = 32;
cfg.tau_max = cfg.tau_max_us * 1e-6;
cfg.lmax = ceil(cfg.tau_max / cfg.Ts);
cfg.c1 = (2 * cfg.kmax + 1) / (2 * cfg.Nblk);
cfg.c2 = 0.1 / cfg.Nblk;
cfg.Lch = 4;
cfg.use_fractional_doppler = true;

snr_db_list = 0:5:30;
num_frames = 100;
pilot_symbol_power = 1.0;
embedded_data_power = 0.05;

nmse = nan(3, numel(snr_db_list), num_frames);
labels = {'OFDM full DD dictionary', 'AFDM full DD dictionary', ...
    'AFWDM support-aware dictionary'};

fprintf('\nEmbedded pilot channel-estimation prototype\n');
fprintf('N=%d, kmax=%d, lmax=%d, Lch=%d, frames=%d\n', ...
    cfg.Nblk, cfg.kmax, cfg.lmax, cfg.Lch, num_frames);

for iSNR = 1:numel(snr_db_list)
    snr_db = snr_db_list(iSNR);
    noise_var = 10^(-snr_db / 10);
    for frm = 1:num_frames
        seed_base = 900000 + 1000 * frm;
        rng(seed_base);

        [tau_true, nu_true] = generate_phys_dd_paths(cfg, cfg.Lch, seed_base);
        h_true = (randn(cfg.Lch, 1) + 1j * randn(cfg.Lch, 1)) / sqrt(2 * cfg.Lch);

        cfg_ofdm = cfg;
        cfg_ofdm.c1 = 0;
        cfg_ofdm.c2 = 0;

        nmse(1, iSNR, frm) = estimate_one_case(cfg_ofdm, tau_true, nu_true, h_true, ...
            noise_var, pilot_symbol_power, embedded_data_power, false);
        nmse(2, iSNR, frm) = estimate_one_case(cfg, tau_true, nu_true, h_true, ...
            noise_var, pilot_symbol_power, embedded_data_power, false);
        nmse(3, iSNR, frm) = estimate_one_case(cfg, tau_true, nu_true, h_true, ...
            noise_var, pilot_symbol_power, embedded_data_power, true);
    end
    fprintf('SNR=%2d dB | OFDM %.3e | AFDM %.3e | AFWDM-support %.3e\n', ...
        snr_db, mean(nmse(1, iSNR, :), 'omitnan'), ...
        mean(nmse(2, iSNR, :), 'omitnan'), mean(nmse(3, iSNR, :), 'omitnan'));
end

out_dir = fullfile(this_dir, 'outputs', 'pilot_demo');
if ~exist(out_dir, 'dir'); mkdir(out_dir); end
out_mat = fullfile(out_dir, sprintf('pilot_demo_%s.mat', datestr(now, 'yyyymmdd_HHMMSS')));
save(out_mat, 'cfg', 'snr_db_list', 'num_frames', 'nmse', 'labels', ...
    'pilot_symbol_power', 'embedded_data_power', '-v7');

f = figure('Visible', 'off', 'Color', 'w');
hold on; grid on;
styles = {'-o', '-s', '-^'};
for k = 1:3
    y = squeeze(mean(nmse(k, :, :), 3, 'omitnan'));
    semilogy(snr_db_list, y, styles{k}, 'LineWidth', 1.5, 'MarkerSize', 5);
end
xlabel('Pilot SNR (dB)');
ylabel('Channel NMSE');
title('Embedded pilot channel-estimation prototype');
legend(labels, 'Location', 'southwest', 'Interpreter', 'none');
ylim([1e-4, 1e1]);
yticks(10.^(-4:1));
out_png = fullfile(out_dir, 'pilot_demo_nmse.png');
try
    exportgraphics(f, out_png, 'Resolution', 160);
catch
    saveas(f, out_png);
end
close(f);

fprintf('\nSaved:\n  %s\n  %s\n', out_mat, out_png);

function case_nmse = estimate_one_case(cfg, tau_true, nu_true, h_true, noise_var, ...
        pilot_symbol_power, embedded_data_power, support_aware)
N = cfg.Nblk;
A = build_daft_matrix(cfg);

pilot_grid = zeros(N, 1);
pilot_grid(1) = sqrt(pilot_symbol_power * N);
rng(12345);
data_grid = sqrt(embedded_data_power) * ...
    ((2 * randi([0, 1], N, 1) - 1) + 1j * (2 * randi([0, 1], N, 1) - 1)) / sqrt(2);
data_grid(1) = 0;

x_pilot_time = A' * pilot_grid;
x_time = A' * (pilot_grid + data_grid);

H_true = zeros(N, N);
for ell = 1:numel(h_true)
    H_true = H_true + h_true(ell) * build_theta_p(tau_true(ell), nu_true(ell), N, cfg.c1);
end
y = H_true * x_time + sqrt(noise_var / 2) * (randn(N, 1) + 1j * randn(N, 1));

if support_aware
    tau_grid = tau_true(:).';
    nu_grid = nu_true(:).';
else
    [tau_mesh, nu_mesh] = ndgrid(0:cfg.lmax, -cfg.kmax:cfg.kmax);
    % Keep the coarse integer DD grid, but append the actual fractional support
    % so this baseline is not unfairly penalized when fractional Doppler is on.
    tau_grid = [tau_mesh(:).', tau_true(:).'];
    nu_grid = [nu_mesh(:).', nu_true(:).'];
end

Phi = zeros(N, numel(tau_grid));
for q = 1:numel(tau_grid)
    Phi(:, q) = build_theta_p(tau_grid(q), nu_grid(q), N, cfg.c1) * x_pilot_time;
end
h_hat = Phi \ y;

H_hat = zeros(N, N);
for q = 1:numel(tau_grid)
    H_hat = H_hat + h_hat(q) * build_theta_p(tau_grid(q), nu_grid(q), N, cfg.c1);
end
case_nmse = norm(H_hat - H_true, 'fro')^2 / max(norm(H_true, 'fro')^2, 1e-15);
end
