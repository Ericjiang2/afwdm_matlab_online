function stages = build_time_diversity_exploration_stages(cfg_run)
%BUILD_TIME_DIVERSITY_EXPLORATION_STAGES Materialize an explicit stage plan.

expected_modes = {'time_diversity_fractional_gabp_exploration', ...
    'time_diversity_lch6_tau48_followup'};
if ~ismember(cfg_run.mode, expected_modes)
    error('build_time_diversity_exploration_stages:profile', ...
        'Profile "%s" does not define an explicit exploration.', cfg_run.mode);
end
if ~isfield(cfg_run.time_diversity, 'explicit_stages') || ...
        isempty(cfg_run.time_diversity.explicit_stages)
    error('build_time_diversity_exploration_stages:missingPlan', ...
        'Exploration profile has no explicit stage plan.');
end

specs = cfg_run.time_diversity.explicit_stages;
stages = repmat(struct('name', '', 'cfg', struct(), 'audit', struct(), ...
    'single_variable_change', ''), 1, numel(specs));
previous = [];
for ii = 1:numel(specs)
    stage_cfg = cfg_run;
    stage_cfg.v_max_kmh = specs(ii).v_max_kmh;
    stage_cfg.tau_max_us = specs(ii).tau_max_us;
    stage_cfg.time_diversity.Lch_values = specs(ii).Lch;
    stage_cfg.time_diversity.escalation_stage = specs(ii).name;
    audit = audit_time_diversity_dimensions(stage_cfg);

    if ii == 1
        require_equal(specs(ii).Lch, ...
            cfg_run.time_diversity.Lch_values, 'profile anchor Lch');
        require_equal(specs(ii).v_max_kmh, ...
            cfg_run.v_max_kmh, 'profile anchor velocity');
        require_equal(specs(ii).tau_max_us, ...
            cfg_run.tau_max_us, 'profile anchor delay');
    else
        assert_single_change(previous, specs(ii), ii);
    end

    stages(ii).name = specs(ii).name;
    stages(ii).cfg = stage_cfg;
    stages(ii).audit = audit;
    stages(ii).single_variable_change = specs(ii).single_variable_change;
    previous = specs(ii);
end
end

function assert_single_change(previous, current, index)
changed = [previous.Lch ~= current.Lch, ...
    previous.v_max_kmh ~= current.v_max_kmh, ...
    previous.tau_max_us ~= current.tau_max_us];
if sum(changed) ~= 1
    error('build_time_diversity_exploration_stages:singleVariable', ...
        'Stage %d must change exactly one of Lch, velocity, or tau_max.', index);
end
end

function require_equal(actual, expected, label)
if actual ~= expected
    error('build_time_diversity_exploration_stages:anchor', ...
        'Expected %s=%g, got %g.', label, expected, actual);
end
end
