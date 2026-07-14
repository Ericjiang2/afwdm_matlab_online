function manifest = build_time_diversity_run_manifest(cfg_run, stage_name)
%BUILD_TIME_DIVERSITY_RUN_MANIFEST Immutable resume identity for one stage.

contract = struct();
contract.mode = cfg_run.mode;
contract.array_shape = cfg_run.array_shape;
contract.fc = cfg_run.fc;
contract.v_max_kmh = cfg_run.v_max_kmh;
contract.Deltaf = cfg_run.Deltaf;
contract.Nblk = cfg_run.Nblk;
contract.tau_max_us = cfg_run.tau_max_us;
contract.QAM_order = cfg_run.QAM_order;
contract.seed = cfg_run.seed;
contract.time_diversity = cfg_run.time_diversity;

manifest = struct();
manifest.schema_version = 1;
manifest.runner_version = 'time-diversity-20260715.2';
manifest.stage = char(stage_name);
manifest.profile = cfg_run.mode;
manifest.config_fingerprint = sha256_bytes(unicode2native(jsonencode(contract), 'UTF-8'));
manifest.code_fingerprint = repository_code_fingerprint(cfg_run.repo_root, cfg_run.delivery_dir);
manifest.git_commit = git_commit(cfg_run.repo_root);
manifest.matlab_release = version('-release');
manifest.seed_contract = cfg_run.seed;
manifest.doppler_modes = cfg_run.time_diversity.doppler_modes;
manifest.detectors = cfg_run.time_diversity.detectors;
manifest.spatial_pairs = cfg_run.time_diversity.spatial_pairs;
manifest.Lch_values = cfg_run.time_diversity.Lch_values;
manifest.SNR_dB_list = cfg_run.time_diversity.SNR_dB_list;
end

function value = repository_code_fingerprint(repo_root, delivery_dir)
roots = {repo_root, fullfile(repo_root, 'tools'), delivery_dir};
records = {};
for ii = 1:numel(roots)
    files = dir(fullfile(roots{ii}, '*.m'));
    [~, order] = sort({files.name});
    files = files(order);
    for jj = 1:numel(files)
        path_value = fullfile(files(jj).folder, files(jj).name);
        relative = erase(path_value, [repo_root filesep]);
        records{end+1} = [relative newline fileread(path_value) newline]; %#ok<AGROW>
    end
end
value = sha256_bytes(unicode2native(strjoin(records, ''), 'UTF-8'));
end

function value = git_commit(repo_root)
[status, output] = system(sprintf('git -C "%s" rev-parse HEAD', repo_root));
if status == 0
    value = strtrim(output);
else
    value = 'unavailable';
end
end

function value = sha256_bytes(bytes)
digest = java.security.MessageDigest.getInstance('SHA-256');
digest.update(uint8(bytes));
value = lower(reshape(dec2hex(typecast(digest.digest(), 'uint8'), 2).', 1, []));
end
