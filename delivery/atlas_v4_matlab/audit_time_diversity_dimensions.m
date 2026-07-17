function audit = audit_time_diversity_dimensions(cfg_run)
%AUDIT_TIME_DIVERSITY_DIMENSIONS Derive and enforce AFDM dimension limits.

lambda = 3e8 / cfg_run.fc;
v_max = cfg_run.v_max_kmh / 3.6;
kmax = ceil((v_max / lambda) / cfg_run.Deltaf);
Ts = 1 / (cfg_run.Nblk * cfg_run.Deltaf);
lmax = ceil((cfg_run.tau_max_us * 1e-6) / Ts);
lhs = 2 * kmax * (lmax + 1) + lmax;

audit = struct( ...
    'kmax', kmax, ...
    'lmax', lmax, ...
    'diversity_lhs', lhs, ...
    'Nblk', cfg_run.Nblk, ...
    'diversity_condition_passed', lhs < cfg_run.Nblk);
if ~audit.diversity_condition_passed
    error('audit_time_diversity_dimensions:diversityCondition', ...
        'AFDM diversity condition fails: %d < %d is false.', lhs, cfg_run.Nblk);
end
end
