function summary = build_time_diversity_summary(runs, primary_lch, target_ber)
%BUILD_TIME_DIVERSITY_SUMMARY Four-row int/frac x LMMSE/GaBP claim table.

primary = runs([runs.Lch] == primary_lch & strcmp({runs.spatial_pair}, 'wdm'));
doppler_modes = {'integer', 'fractional'};
detectors = {'block_lmmse', 'gabp'};
rows = cell(4, 11);
row = 0;

for iDoppler = 1:2
    for iDetector = 1:2
        row = row + 1;
        match = find(strcmp({primary.doppler_mode}, doppler_modes{iDoppler}) & ...
            strcmp({primary.detector}, detectors{iDetector}), 1);
        if isempty(match)
            rows(row, :) = {doppler_modes{iDoppler}, detectors{iDetector}, ...
                primary_lch, target_ber, NaN, NaN, NaN, NaN, NaN, true, 'missing'};
            continue;
        end
        run = primary(match);
        eligible = [run.points.claim_eligible];
        ber_a = [run.points.ber_a];
        ber_b = [run.points.ber_b];
        snr_a = snr_at_target(run.SNR_dB(eligible), ber_a(eligible), target_ber);
        snr_b = snr_at_target(run.SNR_dB(eligible), ber_b(eligible), target_ber);
        gain = snr_b - snr_a;
        representative = representative_point(run.points, target_ber);
        noise_limited = ~isfinite(gain) || isempty(representative);
        if noise_limited
            ratio = NaN;
            ci = [NaN, NaN];
            p = NaN;
            status = 'noise_limited';
        else
            ratio = representative.ber_ratio_b_over_a;
            ci = representative.ber_ratio_ci;
            p = representative.mcnemar_p;
            status = 'eligible';
        end
        rows(row, :) = {doppler_modes{iDoppler}, detectors{iDetector}, ...
            primary_lch, target_ber, gain, ratio, ci(1), ci(2), p, noise_limited, status};
    end
end

summary = cell2table(rows, 'VariableNames', { ...
    'doppler_mode', 'detector', 'Lch', 'target_ber', 'snr_gain_db', ...
    'ber_ratio_ofwdm_over_afwdm', 'ratio_ci_low', 'ratio_ci_high', ...
    'mcnemar_p', 'noise_limited', 'status'});
end

function snr = snr_at_target(snr_values, ber_values, target)
valid = isfinite(snr_values) & isfinite(ber_values) & ber_values > 0;
snr_values = snr_values(valid);
log_ber = log10(ber_values(valid));
if numel(snr_values) < 2 || log10(target) < min(log_ber) || log10(target) > max(log_ber)
    snr = NaN;
    return;
end
[log_ber, order] = sort(log_ber);
snr_values = snr_values(order);
[log_ber, unique_index] = unique(log_ber, 'stable');
snr_values = snr_values(unique_index);
if numel(log_ber) < 2
    snr = NaN;
else
    snr = interp1(log_ber, snr_values, log10(target), 'linear');
end
end

function point = representative_point(points, target)
eligible = [points.claim_eligible];
if ~any(eligible)
    point = [];
    return;
end
candidates = points(eligible);
mid_ber = sqrt([candidates.ber_a] .* [candidates.ber_b]);
[~, index] = min(abs(log10(mid_ber) - log10(target)));
point = candidates(index);
end
