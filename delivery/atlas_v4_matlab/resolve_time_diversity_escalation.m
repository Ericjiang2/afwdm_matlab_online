function plan = resolve_time_diversity_escalation(current_stage, gains, cfg_run)
%RESOLVE_TIME_DIVERSITY_ESCALATION Apply the Spec's fail-closed stage order.
%
% Each Doppler mode is judged independently. Noise-limited evidence never
% triggers an escalation because it cannot establish a sub-1 dB gap.

eligible = [gains.claim_eligible];
failing = eligible & [gains.gain_db] < 1;
triggered_modes = {gains(failing).doppler_mode};

plan = base_plan(cfg_run);
plan.current_stage = char(current_stage);
plan.triggered_doppler_modes = triggered_modes;
if isempty(triggered_modes)
    if any(eligible)
        plan.next_stage = 'complete';
    else
        plan.next_stage = 'await_evidence';
    end
    return;
end

switch char(current_stage)
    case 'lch6'
        plan.next_stage = 'lch8';
        plan.Lch_values = 8;
        plan.single_variable_change = 'Lch:6->8';
    case 'lch8'
        plan.next_stage = 'kmax3';
        plan.Lch_values = 8;
        plan.v_max_kmh = 1100;
        plan.single_variable_change = 'v_max_kmh:860->1100 (kmax:2->3)';
    case 'kmax3'
        plan.next_stage = 'per_stream_lmmse';
        plan.Lch_values = 8;
        plan.v_max_kmh = 1100;
        plan.detectors = unique([plan.detectors, {'per_stream_lmmse'}], 'stable');
        plan.single_variable_change = 'add supplemental per_stream_lmmse';
    case 'per_stream_lmmse'
        plan.next_stage = 'fail_closed';
        plan.Lch_values = 8;
        plan.v_max_kmh = 1100;
        plan.detectors = unique([plan.detectors, {'per_stream_lmmse'}], 'stable');
        plan.fail_closed = true;
        plan.single_variable_change = 'none; report sub-dB boundary';
    otherwise
        error('resolve_time_diversity_escalation:stage', ...
            'Unknown escalation stage "%s".', current_stage);
end

plan = update_dimension_audit(plan, cfg_run);
end

function plan = base_plan(cfg_run)
plan = struct();
plan.current_stage = '';
plan.next_stage = '';
plan.triggered_doppler_modes = {};
plan.Lch_values = 6;
plan.v_max_kmh = cfg_run.v_max_kmh;
plan.detectors = {'block_lmmse', 'gabp'};
plan.kmax = NaN;
plan.lmax = NaN;
plan.diversity_lhs = NaN;
plan.diversity_condition_passed = false;
plan.single_variable_change = '';
plan.fail_closed = false;
plan = update_dimension_audit(plan, cfg_run);
end

function plan = update_dimension_audit(plan, cfg_run)
lambda = 3e8 / cfg_run.fc;
v_max = plan.v_max_kmh / 3.6;
plan.kmax = ceil((v_max / lambda) / cfg_run.Deltaf);
Ts = 1 / (cfg_run.Nblk * cfg_run.Deltaf);
plan.lmax = ceil((cfg_run.tau_max_us * 1e-6) / Ts);
plan.diversity_lhs = 2 * plan.kmax * (plan.lmax + 1) + plan.lmax;
plan.diversity_condition_passed = plan.diversity_lhs < cfg_run.Nblk;
if ~plan.diversity_condition_passed
    error('resolve_time_diversity_escalation:diversityCondition', ...
        'Escalation violates AFDM diversity condition: %d < %d is false.', ...
        plan.diversity_lhs, cfg_run.Nblk);
end
end
