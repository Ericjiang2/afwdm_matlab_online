function package = run_time_diversity_tau48_sixline(output_root)
%RUN_TIME_DIVERSITY_TAU48_SIXLINE Fixed MATLAB Online six-line entry.

profile = "time_diversity_tau48_sixline";
run_id = "time_diversity_tau48_sixline_v11_20260718";
if nargin < 1 || isempty(output_root)
    package = run_online_time_diversity(profile, run_id);
else
    package = run_online_time_diversity(profile, run_id, output_root);
end
end
