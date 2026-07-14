function next = apply_time_diversity_escalation(cfg_run, plan)
%APPLY_TIME_DIVERSITY_ESCALATION Turn an approved conditional plan into config.

if isempty(plan.triggered_doppler_modes)
    error('apply_time_diversity_escalation:noTriggeredModes', ...
        'Escalation config requires at least one evidence-backed Doppler mode.');
end
if ismember(plan.next_stage, {'complete', 'await_evidence', 'fail_closed'})
    error('apply_time_diversity_escalation:terminalPlan', ...
        'Stage "%s" does not create another simulation config.', plan.next_stage);
end

next = cfg_run;
next.v_max_kmh = plan.v_max_kmh;
next.time_diversity.Lch_values = plan.Lch_values;
next.time_diversity.doppler_modes = plan.triggered_doppler_modes;
next.time_diversity.detectors = plan.detectors;
next.time_diversity.escalation_stage = plan.next_stage;
next.time_diversity.escalation_audit = plan;

locked_equal = isequal(next.array_shape, cfg_run.array_shape) && ...
    next.Nblk == cfg_run.Nblk && next.fc == cfg_run.fc && ...
    next.Deltaf == cfg_run.Deltaf && next.tau_max_us == cfg_run.tau_max_us && ...
    next.time_diversity.N_s == cfg_run.time_diversity.N_s;
if ~locked_equal
    error('apply_time_diversity_escalation:lockedParameter', ...
        'Conditional escalation changed a locked physical parameter.');
end
end
