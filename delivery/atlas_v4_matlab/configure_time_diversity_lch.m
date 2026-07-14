function [updated, audit] = configure_time_diversity_lch(scenario, Lch)
%CONFIGURE_TIME_DIVERSITY_LCH Change only path count for the crowding sweep.

validateattributes(Lch, {'numeric'}, {'scalar', 'integer', '>=', 2});
if isfield(scenario, 'use_perpath_sigma') && scenario.use_perpath_sigma
    error('configure_time_diversity_lch:perPathSigma', ...
        'The controlled Lch sweep requires the strict-isotropic shared Sigma path.');
end

before = scenario.cfg;
updated = scenario;
updated.cfg.Lch = Lch;
after_without_lch = rmfield(updated.cfg, 'Lch');
before_without_lch = rmfield(before, 'Lch');

audit = struct();
audit.before_Lch = before.Lch;
audit.after_Lch = Lch;
audit.only_lch_changed = isequaln(before_without_lch, after_without_lch);
audit.diversity_lhs = updated.cfg.afdm_diversity_lhs;
audit.diversity_condition_passed = audit.diversity_lhs < updated.cfg.Nblk;
if ~audit.only_lch_changed || ~audit.diversity_condition_passed
    error('configure_time_diversity_lch:contract', ...
        'Lch sweep changed another parameter or violated the diversity condition.');
end
end
