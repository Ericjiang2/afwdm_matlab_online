function states = initialize_time_diversity_mode_states(doppler_modes)
%INITIALIZE_TIME_DIVERSITY_MODE_STATES Persistent per-Doppler outcome ledger.

empty = struct('doppler_mode', '', 'status', 'pending', ...
    'evidence_stage', '', 'gain_db', NaN, 'claim_eligible', false);
states = repmat(empty, 1, numel(doppler_modes));
for ii = 1:numel(doppler_modes)
    states(ii).doppler_mode = doppler_modes{ii};
end
end
