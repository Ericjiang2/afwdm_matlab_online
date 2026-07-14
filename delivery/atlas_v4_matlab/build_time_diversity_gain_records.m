function gains = build_time_diversity_gain_records(summary, doppler_modes)
%BUILD_TIME_DIVERSITY_GAIN_RECORDS Gate scientific decisions on paired tests.
%
% A Doppler result is claim-eligible only when both co-primary detectors
% have a finite fixed-BER gain, sufficient error evidence, a BER-ratio CI
% wholly above one, and an exact McNemar p-value below 0.05.

empty = struct( ...
    'doppler_mode', '', ...
    'gain_db', NaN, ...
    'claim_eligible', false, ...
    'statistically_significant', false, ...
    'significance_rule', 'ratio_ci_low>1 and mcnemar_p<0.05 for both detectors');
gains = repmat(empty, 1, numel(doppler_modes));

for ii = 1:numel(doppler_modes)
    mode = doppler_modes{ii};
    selected = strcmp(summary.doppler_mode, mode) & ...
        ismember(summary.detector, {'block_lmmse', 'gabp'});
    values = summary.snr_gain_db(selected);
    enough_evidence = numel(values) == 2 && all(isfinite(values)) && ...
        all(~summary.noise_limited(selected));
    significant = enough_evidence && ...
        all(summary.ratio_ci_low(selected) > 1) && ...
        all(summary.mcnemar_p(selected) < 0.05);

    gains(ii).doppler_mode = mode;
    gains(ii).statistically_significant = significant;
    gains(ii).claim_eligible = significant;
    if significant
        % Both co-primary detectors must remain below 1 dB to escalate.
        gains(ii).gain_db = max(values);
    end
end
end
