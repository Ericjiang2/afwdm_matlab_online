function output_file = plot_iso_gabp_results(package, output_dir)
%PLOT_ISO_GABP_RESULTS Plot only the six strict-isotropic GaBP curves.

if nargin < 2 || isempty(output_dir)
    output_dir = pwd;
end
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

figure_handle = figure('Visible', 'off', 'Color', 'w');
cleanup = onCleanup(@() close(figure_handle));
hold on;
grid on;
colors = lines(numel(package.schemes));
markers = {'o', 's', '^'};
n_curves = numel(package.schemes) * numel(package.csi_case_labels);
n_snr = numel(package.SNR_average_reference_dB);
legend_text = cell(1, n_curves);
plotted_values = nan(n_curves * n_snr, 1);
curve_index = 0;

for i_csi = 1:numel(package.csi_case_labels)
    line_style = '-';
    if i_csi > 1
        line_style = '--';
    end
    for i_scheme = 1:numel(package.schemes)
        curve_index = curve_index + 1;
        observed = squeeze(package.BER(i_scheme, :, i_csi));
        upper = squeeze(package.zero_error_95_upper(i_scheme, :, i_csi));
        plotted = observed(:);
        zero_mask = package.error_count(i_scheme, :, i_csi) == 0;
        plotted(zero_mask(:)) = upper(zero_mask(:));
        destination = (curve_index - 1) * n_snr + (1:n_snr);
        plotted_values(destination) = plotted;
        semilogy(package.SNR_average_reference_dB, plotted, ...
            [line_style markers{i_scheme}], ...
            'Color', colors(i_scheme, :), ...
            'LineWidth', 1.5, ...
            'MarkerSize', 5);
        legend_text{curve_index} = sprintf('%s | %s | GaBP', ...
            package.schemes{i_scheme}, package.csi_case_labels{i_csi});
    end
end

xlabel('Average reference SNR, N_s E_s/N_0 (dB)');
ylabel('BER');
title(sprintf( ...
    'BER: strict isotropic, 8x8, N_s=%d, GaBP only', package.N_s), ...
    'Interpreter', 'none');
legend(legend_text, 'Location', 'southwest', 'Interpreter', 'none');
[limits, ticks] = delivery_ber_axis_scale(plotted_values, []);
ylim(limits);
yticks(ticks);
annotation(figure_handle, 'textbox', [0.57, 0.12, 0.32, 0.07], ...
    'String', 'Zero observed errors: plotted at 95% rule-of-three upper bound', ...
    'FitBoxToText', 'on', 'EdgeColor', 'none', 'FontSize', 8);

output_file = fullfile(output_dir, package.asset_names.figure_png);
try
    exportgraphics(figure_handle, output_file, 'Resolution', 180);
catch
    saveas(figure_handle, output_file);
end
end
