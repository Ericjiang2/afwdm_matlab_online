function outcome = build_time_diversity_outcome(final_plan, final_stage, cfg_final, mode_states)
%BUILD_TIME_DIVERSITY_OUTCOME Machine-readable scientific workflow outcome.

if nargin < 4 || isempty(mode_states)
    mode_states = initialize_time_diversity_mode_states( ...
        cfg_final.time_diversity.doppler_modes);
    fallback = fallback_status(final_plan.next_stage);
    for ii = 1:numel(mode_states)
        mode_states(ii).status = fallback;
    end
end
status = aggregate_status({mode_states.status});

outcome = struct();
outcome.status = status;
outcome.state_machine_status = final_plan.next_stage;
outcome.final_stage = final_stage;
outcome.per_doppler = mode_states;
outcome.parameters = struct( ...
    'v_max_kmh', cfg_final.v_max_kmh, ...
    'kmax', final_plan.kmax, ...
    'Lch_values', cfg_final.time_diversity.Lch_values, ...
    'doppler_modes', {cfg_final.time_diversity.doppler_modes}, ...
    'detectors', {cfg_final.time_diversity.detectors}, ...
    'spatial_pairs', {cfg_final.time_diversity.spatial_pairs});
outcome.production_result_available = strcmp(cfg_final.mode, 'time_diversity_online');
outcome.production_result_available = outcome.production_result_available && ...
    ismember(status, {'complete', 'fail_closed', 'partial'});
end

function status = fallback_status(plan_status)
switch plan_status
    case 'complete'
        status = 'complete';
    case 'await_evidence'
        status = 'inconclusive';
    case 'fail_closed'
        status = 'fail_closed';
    otherwise
        error('build_time_diversity_outcome:nonterminalPlan', ...
            'Outcome requires a terminal plan, got "%s".', plan_status);
end
end

function status = aggregate_status(statuses)
if all(strcmp(statuses, 'complete'))
    status = 'complete';
elseif all(strcmp(statuses, 'fail_closed'))
    status = 'fail_closed';
elseif any(strcmp(statuses, 'inconclusive')) || any(strcmp(statuses, 'pending'))
    status = 'inconclusive';
else
    status = 'partial';
end
end
