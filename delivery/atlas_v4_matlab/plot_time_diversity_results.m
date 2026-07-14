function files = plot_time_diversity_results(results, cfg_run, output_dir)
%PLOT_TIME_DIVERSITY_RESULTS MIMO main/appendix figures and four-row table.

if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end
primary_lch = max([results.runs.Lch]);
main_file = fullfile(output_dir, 'time_diversity_mimo_main.png');
appendix_file = fullfile(output_dir, 'time_diversity_svd_appendix.png');
table_file = fullfile(output_dir, 'time_diversity_summary.csv');

plot_pair_grid(results.runs, primary_lch, {'wdm', 'dft'}, main_file, ...
    sprintf('AFWDM vs OFWDM MIMO BER (N_s=%d, Lch=%d)', results.N_s, primary_lch));
plot_pair_grid(results.runs, primary_lch, {'svd'}, appendix_file, ...
    sprintf('SVD-pair appendix (N_s=%d, Lch=%d)', results.N_s, primary_lch));
writetable(results.summary_table, table_file);
files = {main_file, appendix_file, table_file};

if isfield(cfg_run, 'mode') && strcmp(cfg_run.mode, 'time_diversity_smoke')
    fprintf('  time-diversity plots are smoke artifacts; noise-limited points are omitted.\n');
end
end

function plot_pair_grid(runs, Lch, spatial_pairs, output_file, title_text)
doppler_modes = {'integer', 'fractional'};
detectors = {'block_lmmse', 'gabp'};
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 1100, 760]);
layout = tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
colors = struct('wdm', [0.00, 0.35, 0.75], 'dft', [0.55, 0.70, 0.88], ...
    'svd', [0.35, 0.35, 0.35]);

for iDoppler = 1:2
    for iDetector = 1:2
        nexttile;
        hold on; grid on;
        plotted = [];
        labels = {};
        for iSpatial = 1:numel(spatial_pairs)
            spatial = spatial_pairs{iSpatial};
            match = find([runs.Lch] == Lch & ...
                strcmp({runs.doppler_mode}, doppler_modes{iDoppler}) & ...
                strcmp({runs.detector}, detectors{iDetector}) & ...
                strcmp({runs.spatial_pair}, spatial), 1);
            if isempty(match)
                continue;
            end
            run = runs(match);
            afwdm = eligible_curve(run.points, 'ber_a');
            ofwdm = eligible_curve(run.points, 'ber_b');
            plotted = [plotted, afwdm, ofwdm]; %#ok<AGROW>
            semilogy(run.SNR_dB, afwdm, '-o', 'Color', colors.(spatial), ...
                'LineWidth', 1.6, 'MarkerSize', 5);
            semilogy(run.SNR_dB, ofwdm, '--s', 'Color', colors.(spatial), ...
                'LineWidth', 1.6, 'MarkerSize', 5);
            labels{end+1} = sprintf('AFDM | %s', upper(spatial)); %#ok<AGROW>
            labels{end+1} = sprintf('OFDM | %s', upper(spatial)); %#ok<AGROW>
        end
        positive = plotted(isfinite(plotted) & plotted > 0);
        if isempty(positive)
            text(0.5, 0.5, 'No claim-eligible points (noise-limited)', ...
                'Units', 'normalized', 'HorizontalAlignment', 'center');
            set(gca, 'YScale', 'log');
            ylim([1e-5, 1]);
        else
            [limits, ticks] = delivery_ber_axis_scale(positive, []);
            ylim(limits); yticks(ticks);
        end
        xlabel('SNR (dB)'); ylabel('BER');
        title(sprintf('%s | %s', doppler_modes{iDoppler}, detectors{iDetector}), ...
            'Interpreter', 'none');
        if ~isempty(labels)
            legend(labels, 'Location', 'southwest', 'Interpreter', 'none');
        end
    end
end
title(layout, title_text, 'Interpreter', 'none');
save_png(fig, output_file);
close(fig);
end

function values = eligible_curve(points, field_name)
values = nan(1, numel(points));
for ii = 1:numel(points)
    if points(ii).claim_eligible
        values(ii) = points(ii).(field_name);
    end
end
end

function save_png(fig, output_file)
try
    exportgraphics(fig, output_file, 'Resolution', 160);
catch
    saveas(fig, output_file);
end
end
