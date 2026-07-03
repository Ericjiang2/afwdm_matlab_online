function plot_files = plot_delivery_results(results, cfg_run)
%PLOT_DELIVERY_RESULTS  Save delivery BER/capacity figures as PNG.

fig_dir = fullfile(cfg_run.output_dir, 'figures');
if ~exist(fig_dir, 'dir')
    mkdir(fig_dir);
end

plot_files = {};

ber = results.BER;
for iScenario = 1:numel(results.scenario_labels)
    if cfg_run.plot_csi_cases_together
        f = figure('Visible', 'off', 'Color', 'w');
        hold on; grid on;
        colors = lines(numel(results.schemes));
        markers = {'o', 's', '^'};
        leg = {};
        for iCsi = 1:numel(results.kappa_list)
            line_style = '-';
            if iCsi > 1
                line_style = '--';
            end
            for k = 1:numel(results.schemes)
                y = squeeze(ber(k, 1, :, iCsi, iScenario));
                bits = squeeze(results.bit_total(k, 1, :, iCsi, iScenario));
                y = ber_for_plot(y, bits);
                semilogy(results.SNR_dB, y, ...
                    [line_style markers{1 + mod(k-1, numel(markers))}], ...
                    'Color', colors(k, :), 'LineWidth', 1.5, 'MarkerSize', 5);
                leg{end+1} = sprintf('%s | %s', results.schemes{k}, ...
                    results.csi_case_labels{iCsi}); %#ok<AGROW>
            end
        end
        format_ber_axes(cfg_run);
        title(sprintf('BER: %s, perfect vs fixed-var CSI', ...
            results.scenario_labels{iScenario}), 'Interpreter', 'none');
        legend(leg, 'Location', 'southwest', 'Interpreter', 'none');
        out_png = fullfile(fig_dir, sprintf('ber_%s_perfect_vs_fixedvar.png', ...
            results.scenario_labels{iScenario}));
        save_png(f, out_png);
        close(f);
        plot_files{end+1} = out_png; %#ok<AGROW>
    else
        for iK = 1:numel(results.kappa_list)
            f = figure('Visible', 'off', 'Color', 'w');
            hold on; grid on;
            styles = {'-o', '-s', '-^', '--o', '--s', '--^'};
            leg = {};
            jj = 0;
            for iStrategy = 1:numel(results.strategies)
                for k = 1:numel(results.schemes)
                    jj = jj + 1;
                    y = squeeze(ber(k, iStrategy, :, iK, iScenario));
                    bits = squeeze(results.bit_total(k, iStrategy, :, iK, iScenario));
                    y = ber_for_plot(y, bits);
                    semilogy(results.SNR_dB, y, styles{1 + mod(jj-1, numel(styles))}, ...
                        'LineWidth', 1.4, 'MarkerSize', 5);
                    leg{end+1} = sprintf('%s-%s', results.schemes{k}, results.strategies{iStrategy}); %#ok<AGROW>
                end
            end
            format_ber_axes(cfg_run);
            title(sprintf('Delivery BER: %s, kappa=%.2g', ...
                results.scenario_labels{iScenario}, results.kappa_list(iK)), 'Interpreter', 'none');
            legend(leg, 'Location', 'southwest', 'Interpreter', 'none');
            out_png = fullfile(fig_dir, sprintf('ber_%s_kappa%g.png', ...
                results.scenario_labels{iScenario}, results.kappa_list(iK)));
            save_png(f, out_png);
            close(f);
            plot_files{end+1} = out_png; %#ok<AGROW>
        end
    end
end

if isfield(results, 'capacity') && ~isempty(results.capacity)
    cap = results.capacity;
    f = figure('Visible', 'off', 'Color', 'w');
    hold on; grid on;
    styles = {'-o', '-s', '-^'};
    leg = {};
    for iScenario = 1:numel(cap.labels)
        y = squeeze(mean(cap.Cap_wf(iScenario, :, :), 3, 'omitnan'));
        plot(cap.P_dBW_list, y, styles{1 + mod(iScenario-1, numel(styles))}, ...
            'LineWidth', 1.5, 'MarkerSize', 5);
        leg{end+1} = cap.labels{iScenario}; %#ok<AGROW>
    end
    xlabel('Total transmit power P (dBW)');
    ylabel('Raw channel capacity (bits/symbol)');
    title('Raw doubly-selective channel capacity, water-filling');
    legend(leg, 'Location', 'northwest', 'Interpreter', 'none');
    out_png = fullfile(fig_dir, 'capacity_raw_doubly_selective.png');
    save_png(f, out_png);
    close(f);
    plot_files{end+1} = out_png; %#ok<AGROW>
end

if isfield(results, 'low_mimo') && ~isempty(results.low_mimo)
    low = results.low_mimo;
    f = figure('Visible', 'off', 'Color', 'w');
    hold on; grid on;
    styles = {'-o', '-s', '-^', '--o', '--s', '--^'};
    for k = 1:numel(low.schemes)
        y = ber_for_plot(low.BER(k, :).', low.bit_total(k, :).');
        semilogy(low.SNR_dB, y, styles{1 + mod(k-1, numel(styles))}, ...
            'LineWidth', 1.5, 'MarkerSize', 5);
    end
    format_ber_axes(cfg_run);
    title(sprintf('Low-MIMO waveform/precoding BER (%dx%d, N_s=%d)', ...
        low.array_shape(1), low.array_shape(2), low.N_s), 'Interpreter', 'none');
    legend(low.schemes, 'Location', 'southwest', 'Interpreter', 'none');
    out_png = fullfile(fig_dir, sprintf('ber_low_mimo_%dx%d_ns%d_precoding.png', ...
        low.array_shape(1), low.array_shape(2), low.N_s));
    save_png(f, out_png);
    close(f);
    plot_files{end+1} = out_png; %#ok<AGROW>
end

end

function y = ber_for_plot(y, bits)
y = y(:);
bits = bits(:);
zero_mask = isfinite(y) & y <= 0;
if any(zero_mask)
    % Plot zero-observed-error points as a conservative half-error upper marker.
    y(zero_mask) = 0.5 ./ max(bits(zero_mask), 1);
end
y(y <= 0) = NaN;
end

function format_ber_axes(cfg_run)
set(gca, 'YScale', 'log');
xlabel('SNR (dB)');
ylabel('BER');
ylim(cfg_run.ber_y_limits);
yticks(10.^(-6:0));
end

function save_png(fig_handle, out_png)
try
    exportgraphics(fig_handle, out_png, 'Resolution', 160);
catch
    saveas(fig_handle, out_png);
end
end
