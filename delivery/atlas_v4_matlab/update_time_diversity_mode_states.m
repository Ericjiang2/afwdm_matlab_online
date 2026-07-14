function states = update_time_diversity_mode_states(states, gains, stage_name, plan_status)
%UPDATE_TIME_DIVERSITY_MODE_STATES Preserve independent Doppler conclusions.

for ii = 1:numel(gains)
    index = find(strcmp({states.doppler_mode}, gains(ii).doppler_mode), 1);
    if isempty(index)
        error('update_time_diversity_mode_states:unknownMode', ...
            'Unknown Doppler mode "%s".', gains(ii).doppler_mode);
    end
    states(index).evidence_stage = char(stage_name);
    states(index).gain_db = gains(ii).gain_db;
    states(index).claim_eligible = gains(ii).claim_eligible;
    if ~gains(ii).claim_eligible
        states(index).status = 'inconclusive';
    elseif gains(ii).gain_db >= 1
        states(index).status = 'complete';
    elseif strcmp(plan_status, 'fail_closed')
        states(index).status = 'fail_closed';
    else
        states(index).status = 'escalating';
    end
end
end
