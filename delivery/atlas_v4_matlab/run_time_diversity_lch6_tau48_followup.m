function package = run_time_diversity_lch6_tau48_followup(output_root)
%RUN_TIME_DIVERSITY_LCH6_TAU48_FOLLOWUP Fixed MATLAB Online follow-up entry.

profile = "time_diversity_lch6_tau48_followup";
run_id = "time_diversity_lch6_tau48_followup_v10_20260718";
if nargin < 1 || isempty(output_root)
    package = run_online_time_diversity(profile, run_id);
else
    package = run_online_time_diversity(profile, run_id, output_root);
end
end
