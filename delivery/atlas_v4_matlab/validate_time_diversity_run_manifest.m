function validate_time_diversity_run_manifest(expected, actual, artifact_name)
%VALIDATE_TIME_DIVERSITY_RUN_MANIFEST Reject incompatible resume artifacts.

required = {'schema_version', 'runner_version', 'stage', 'profile', ...
    'config_fingerprint', 'code_fingerprint', 'seed_contract', ...
    'doppler_modes', 'detectors', 'spatial_pairs', 'Lch_values', 'SNR_dB_list'};
if ~isstruct(actual) || ~all(isfield(actual, required))
    error('run_online_time_diversity:manifestMismatch', ...
        '%s has no compatible immutable run manifest; use a new run_id.', artifact_name);
end

for ii = 1:numel(required)
    field_name = required{ii};
    if ~isequaln(expected.(field_name), actual.(field_name))
        error('run_online_time_diversity:manifestMismatch', ...
            '%s manifest mismatch at "%s"; use a new run_id.', ...
            artifact_name, field_name);
    end
end
end
