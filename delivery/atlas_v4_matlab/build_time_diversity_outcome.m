function outcome = build_time_diversity_outcome(final_plan, final_stage, cfg_final)
%BUILD_TIME_DIVERSITY_OUTCOME Machine-readable scientific workflow outcome.

switch final_plan.next_stage
    case 'complete'
        status = 'complete';
    case 'await_evidence'
        status = 'inconclusive';
    case 'fail_closed'
        status = 'fail_closed';
    otherwise
        error('build_time_diversity_outcome:nonterminalPlan', ...
            'Outcome requires a terminal plan, got "%s".', final_plan.next_stage);
end

outcome = struct();
outcome.status = status;
outcome.state_machine_status = final_plan.next_stage;
outcome.final_stage = final_stage;
outcome.parameters = struct( ...
    'v_max_kmh', cfg_final.v_max_kmh, ...
    'kmax', final_plan.kmax, ...
    'Lch_values', cfg_final.time_diversity.Lch_values, ...
    'doppler_modes', {cfg_final.time_diversity.doppler_modes}, ...
    'detectors', {cfg_final.time_diversity.detectors}, ...
    'spatial_pairs', {cfg_final.time_diversity.spatial_pairs});
outcome.production_result_available = strcmp(cfg_final.mode, 'time_diversity_online');
outcome.production_result_available = outcome.production_result_available && ...
    ~strcmp(status, 'inconclusive');
end
