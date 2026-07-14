function files = plot_time_diversity_results(results, cfg_run, output_dir, file_prefix)
%PLOT_TIME_DIVERSITY_RESULTS MIMO main/appendix figures and four-row table.

if nargin < 4 || isempty(file_prefix)
    file_prefix = 'time_diversity';
end
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end
lch_values = unique([results.runs.Lch]);
if isscalar(lch_values)
    lch_label = sprintf('%d', lch_values);
else
    lch_label = 'latest per subscenario';
end
main_file = fullfile(output_dir, [file_prefix '_mimo_main.png']);
appendix_file = fullfile(output_dir, [file_prefix '_svd_appendix.png']);
table_file = fullfile(output_dir, [file_prefix '_summary.csv']);

plot_pair_grid(results.runs, {'wdm', 'dft'}, main_file, ...
    sprintf('AFWDM vs OFWDM MIMO BER (N_s=%d, Lch=%s)', results.N_s, lch_label));
writetable(results.summary_table, table_file);
files = {main_file, table_file};
if any(strcmp({results.runs.spatial_pair}, 'svd'))
    svd_runs = results.runs(strcmp({results.runs.spatial_pair}, 'svd'));
    svd_lch = max([svd_runs.Lch]);
    plot_pair_grid(results.runs, {'svd'}, appendix_file, ...
        sprintf('SVD-pair appendix (N_s=%d, Lch=%d)', results.N_s, svd_lch));
    files{end+1} = appendix_file;
end

if isfield(cfg_run, 'mode') && strcmp(cfg_run.mode, 'time_diversity_smoke')
    fprintf('  time-diversity plots are smoke artifacts; noise-limited points are omitted.\n');
end
end

function plot_pair_grid(runs, spatial_pairs, output_file, title_text)
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
            candidates = find(strcmp({runs.doppler_mode}, doppler_modes{iDoppler}) & ...
                strcmp({runs.detector}, detectors{iDetector}) & ...
                strcmp({runs.spatial_pair}, spatial));
            if isempty(candidates)
                continue;
            end
            [~, newest] = max([runs(candidates).Lch]);
            match = candidates(newest);
            run = runs(match);
            afwdm = eligible_curve(run.points, 'ber_a');
            ofwdm = eligible_curve(run.points, 'ber_b');
            plotted = [plotted, afwdm, ofwdm]; %#ok<AGROW>
            semilogy(run.SNR_dB, afwdm, '-o', 'Color', colors.(spatial), ...
                'LineWidth', 1.6, 'MarkerSize', 5);
            semilogy(run.SNR_dB, ofwdm, '--s', 'Color', colors.(spatial), ...
                'LineWidth', 1.6, 'MarkerSize', 5);
            pair_labels = time_diversity_pair_labels(spatial);
            labels{end+1} = pair_labels{1}; %#ok<AGROW>
            labels{end+1} = pair_labels{2}; %#ok<AGROW>
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
