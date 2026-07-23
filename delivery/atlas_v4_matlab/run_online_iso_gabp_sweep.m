function package = run_online_iso_gabp_sweep(run_id, output_root, cfg_override)
%RUN_ONLINE_ISO_GABP_SWEEP Resumable 8x8/Ns=60 GaBP-only BER sweep.
%
% package = run_online_iso_gabp_sweep()
% package = run_online_iso_gabp_sweep(run_id)
% package = run_online_iso_gabp_sweep(run_id, output_root)
%
% The scientific profile is frozen in make_delivery_config:
% strict isotropic, full atlas-v4 mode set, average-reference SNR=0:5:20 dB,
% internally converted to per-stream Es/N0, three spatial
% schemes, perfect/fixed-var CSI, GaBP only, and independent 5/100/200
% frame/error stopping for every scheme x CSI curve.

if nargin < 1
    run_id = '';
end
if nargin < 2
    output_root = '';
end
if nargin < 3
    cfg_override = struct();
end
if isempty(cfg_override)
    cfg_override = struct();
end
if ~isstruct(cfg_override) || ~isscalar(cfg_override)
    error('run_online_iso_gabp_sweep:override', ...
        'cfg_override must be an empty or scalar struct.');
end

this_dir = fileparts(mfilename('fullpath'));
addpath(this_dir);
cfg_run = make_delivery_config("iso_gabp_adaptive");
if ~isempty(fieldnames(cfg_override))
    if isempty(run_id) || isempty(output_root)
        error('run_online_iso_gabp_sweep:fixtureIdentity', ...
            ['A cfg_override is fixture-only and requires an explicit run_id ' ...
             'and output_root so it cannot adopt the scientific active id.']);
    end
    cfg_run = merge_delivery_config(cfg_run, cfg_override);
    cfg_run.iso_gabp.scientific_label = 'fixture';
end
for ii = 1:numel(cfg_run.path_dirs)
    if exist(cfg_run.path_dirs{ii}, 'dir')
        addpath(cfg_run.path_dirs{ii});
    end
end
validate_profile(cfg_run);

if isempty(output_root)
    output_root = fullfile(cfg_run.output_dir, 'online_runs');
end
ensure_dir(output_root);
active_file = fullfile( ...
    output_root, cfg_run.iso_gabp.assets.active_run_id_file);
run_id = resolve_run_id(run_id, active_file);
run_root = fullfile(output_root, run_id);
checkpoint_dir = fullfile(run_root, 'checkpoints');
final_dir = fullfile(run_root, 'final');
ensure_dir(run_root);
ensure_dir(checkpoint_dir);
ensure_dir(final_dir);

run_contract = build_run_contract(cfg_run, run_id);
validate_or_write_contract(run_root, run_contract);
final_file = fullfile(final_dir, cfg_run.iso_gabp.assets.result_mat);
if exist(final_file, 'file')
    saved = load(final_file, 'package');
    if ~isfield(saved, 'package') || ...
            ~isequaln(saved.package.run_contract, run_contract)
        error('run_online_iso_gabp_sweep:manifestMismatch', ...
            'Final result does not match the requested immutable run contract.');
    end
    package = saved.package;
    fprintf('[iso-gabp] Existing compatible final result: %s\n', final_file);
    return;
end

scenario = prepare_delivery_scenario(cfg_run, cfg_run.ber_scenarios);
cfg_base = scenario.cfg;
modes = select_modes_atlas_v4( ...
    cfg_base, scenario.Sigma2, cfg_run.adapt_power_floor);
N_s = resolve_stream_count(modes, cfg_run);
if strcmp(cfg_run.iso_gabp.scientific_label, 'candidate') && ...
        N_s ~= cfg_run.iso_gabp.reference_stream_count
    error('run_online_iso_gabp_sweep:streamCount', ...
        'Frozen scientific contract requires N_s=%d, got %d.', ...
        cfg_run.iso_gabp.reference_stream_count, N_s);
end

Us_afwdm = cfg_base.Us_full(:, modes.sort_s(1:N_s));
Ur_afwdm = cfg_base.Ur_full(:, modes.sort_r(1:N_s));
[Us_dft, Ur_dft] = build_dft_precoder( ...
    cfg_base.Ms, cfg_base.Mr, N_s, N_s);
n_snr = numel(cfg_run.SNR_dB_list);
average_reference_snr_db_list = ...
    cfg_run.iso_gabp.average_reference_SNR_dB_list;
n_scheme = numel(cfg_run.schemes);
n_csi = numel(cfg_run.kappa_list);
state_grid = cell(1, n_snr);

fprintf('\n============================================================\n');
fprintf(' Strict-isotropic GaBP-only adaptive BER sweep\n');
fprintf(' run_id=%s | 8x8 | N_s=%d\n', run_id, N_s);
fprintf(' average-reference SNR=[%s] dB\n', ...
    num2str(average_reference_snr_db_list));
fprintf(' internal per-stream SNR=[%s] dB\n', ...
    num2str(cfg_run.SNR_dB_list));
fprintf(' stop: min=%d frames, target=%d errors, max=%d frames\n', ...
    cfg_run.iso_gabp.stop.min_frames, ...
    cfg_run.iso_gabp.stop.target_errors, ...
    cfg_run.iso_gabp.stop.max_frames);
fprintf('============================================================\n');

for i_snr = 1:n_snr
    stream_snr_db = cfg_run.SNR_dB_list(i_snr);
    average_reference_snr_db = average_reference_snr_db_list(i_snr);
    checkpoint_file = fullfile(checkpoint_dir, ...
        sprintf('snr_avg_%s.mat', number_slug(average_reference_snr_db)));
    [states, next_frame] = load_or_initialize_checkpoint( ...
        checkpoint_file, run_contract, n_scheme, n_csi, ...
        cfg_run.iso_gabp.stop.max_frames);
    fprintf(['\n[average-reference SNR=%g dB | internal stream SNR=%g dB] ' ...
        'resume at shared frame %d\n'], ...
        average_reference_snr_db, stream_snr_db, next_frame);

    for frame_index = next_frame:cfg_run.iso_gabp.stop.max_frames
        if all_curves_stopped(states)
            break;
        end
        seed_base = cfg_run.seed.frame_stride * ...
            (cfg_run.frame_start_offset + frame_index);
        [tau_vec, nu_vec] = generate_phys_dd_paths( ...
            cfg_base, cfg_base.Lch, seed_base);
        H_phys = build_delivery_channel_taps(scenario, seed_base);

        rng(seed_base + 31, 'twister');
        bits = logical(randi([0, 1], N_s * cfg_base.Nblk * ...
            log2(cfg_run.QAM_order), 1));
        rng(seed_base + 53, 'twister');
        unit_noise = (randn(N_s * cfg_base.Nblk, 1) + ...
            1j * randn(N_s * cfg_base.Nblk, 1)) / sqrt(2);

        for i_csi = 1:n_csi
            if all(arrayfun(@(state) ~is_curve_active( ...
                    state, cfg_run.iso_gabp.stop), states(:, i_csi)))
                continue;
            end
            csi_value = cfg_run.kappa_list(i_csi);
            rng(seed_base * cfg_run.seed.csi_stride + ...
                i_csi * cfg_run.seed.csi_case_offset, 'twister');
            H_hat = inject_csi_error( ...
                H_phys, csi_value, 10^(stream_snr_db / 10), ...
                cfg_base.Mr, cfg_base.Ms, cfg_base.Lch, ...
                cfg_run.csi_error_mode);
            G_hat = build_G_paper_eq31(H_hat, 'sum_taps');
            [Us_svd, Ur_svd] = svd_precoder_from_G(G_hat, N_s, N_s);

            for i_scheme = 1:n_scheme
                if ~is_curve_active(states(i_scheme, i_csi), ...
                        cfg_run.iso_gabp.stop)
                    continue;
                end
                [Us, Ur] = resolve_scheme_basis( ...
                    cfg_run.schemes{i_scheme}, ...
                    Us_afwdm, Ur_afwdm, Us_dft, Ur_dft, Us_svd, Ur_svd);
                cfg_scheme = make_delivery_scheme_cfg( ...
                    cfg_base, Us, Ur, N_s, cfg_run);
                H_real = build_block_matrix_afwdm( ...
                    H_phys, tau_vec, nu_vec, cfg_scheme);
                if csi_value <= 0
                    % inject_csi_error returns H_phys unchanged for perfect
                    % CSI, so this is exact reuse rather than an approximation.
                    H_detector = H_real;
                else
                    H_detector = build_block_matrix_afwdm( ...
                        H_hat, tau_vec, nu_vec, cfg_scheme);
                end
                frame_opts = struct( ...
                    'bits', bits, ...
                    'unit_noise', unit_noise, ...
                    'detector_options', cfg_run.iso_gabp.detector_options);
                frame_timer = tic;
                frame = simulate_imperfect_csi_gabp_frame( ...
                    cfg_scheme, H_real, H_detector, ...
                    cfg_run.QAM_order, stream_snr_db, frame_opts);
                elapsed = toc(frame_timer);
                states(i_scheme, i_csi) = update_curve_state( ...
                    states(i_scheme, i_csi), frame, elapsed, ...
                    cfg_run.iso_gabp.stop);
                fprintf(['  frame=%d | %s | %s | err=%d/%d cumulative=%d/%d ' ...
                    '| iter=%d conv=%d\n'], ...
                    frame_index, cfg_run.schemes{i_scheme}, ...
                    cfg_run.csi_case_labels{i_csi}, ...
                    frame.error_count, frame.bit_count, ...
                    states(i_scheme, i_csi).error_count, ...
                    states(i_scheme, i_csi).bit_count, ...
                    frame.detector.iterations, frame.detector.converged);
                clear H_real H_detector frame
            end
            clear H_hat G_hat Us_svd Ur_svd
        end

        next_frame = frame_index + 1;
        save_checkpoint_atomic(checkpoint_file, run_contract, states, ...
            next_frame, average_reference_snr_db, stream_snr_db);
        clear H_phys
    end
    if ~all_curves_stopped(states)
        error('run_online_iso_gabp_sweep:incompleteSNR', ...
            ['Average-reference SNR=%g dB reached the frame loop without ' ...
             'closing all curves.'], average_reference_snr_db);
    end
    state_grid{i_snr} = states;
end

package = assemble_package( ...
    cfg_run, run_contract, modes, N_s, state_grid);
write_results_csv(package, fullfile(final_dir, ...
    cfg_run.iso_gabp.assets.summary_csv));
package.plot_file = plot_iso_gabp_results(package, final_dir);
save_final_atomic(final_file, package);
write_run_info(run_root, package);

fprintf('\n[iso-gabp] Complete: %s\n', final_dir);
end

function validate_profile(cfg)
if ~strcmp(cfg.csi_error_mode, 'fixed_var')
    error('run_online_iso_gabp_sweep:profile', ...
        'CSI mode must be fixed_var.');
end
if cfg.QAM_order ~= 4 || numel(cfg.ber_scenarios) ~= 1 || ...
        ~strcmp(cfg.ber_scenarios.pas_model, 'isotropic')
    error('run_online_iso_gabp_sweep:profile', ...
        'This runner supports strict-isotropic QPSK only.');
end
stop = cfg.iso_gabp.stop;
validateattributes(stop.min_frames, {'numeric'}, ...
    {'scalar', 'integer', 'positive'});
validateattributes(stop.target_errors, {'numeric'}, ...
    {'scalar', 'integer', 'positive'});
validateattributes(stop.max_frames, {'numeric'}, ...
    {'scalar', 'integer', '>=', stop.min_frames});
expected_stream_snr = cfg.iso_gabp.average_reference_SNR_dB_list - ...
    10 * log10(cfg.iso_gabp.reference_stream_count);
if ~isequal(size(expected_stream_snr), size(cfg.SNR_dB_list)) || ...
        any(abs(expected_stream_snr - cfg.SNR_dB_list) > 10 * eps)
    error('run_online_iso_gabp_sweep:snrMapping', ...
        'Internal stream SNR must equal average-reference SNR - 10log10(N_s).');
end
end

function N_s = resolve_stream_count(modes, cfg)
N_s = modes.N_full;
if ~isempty(cfg.quick_stream_cap)
    N_s = min(N_s, cfg.quick_stream_cap);
end
end

function active = is_curve_active(state, stop)
active = state.frame_count < stop.min_frames || ...
    (state.error_count < stop.target_errors && ...
     state.frame_count < stop.max_frames);
end

function stopped = all_curves_stopped(states)
stopped = all(arrayfun(@(state) ~isempty(state.stop_reason), states), 'all');
end

function state = empty_curve_state(max_frames)
state = struct( ...
    'error_count', 0, ...
    'bit_count', 0, ...
    'frame_count', 0, ...
    'stop_reason', '', ...
    'iteration_sum', 0, ...
    'nonconverged_count', 0, ...
    'elapsed_seconds', 0, ...
    'frame_errors', nan(max_frames, 1), ...
    'frame_bits', nan(max_frames, 1), ...
    'iterations', nan(max_frames, 1), ...
    'residuals', nan(max_frames, 1), ...
    'converged', nan(max_frames, 1));
end

function state = update_curve_state(state, frame, elapsed, stop)
index = state.frame_count + 1;
state.error_count = state.error_count + frame.error_count;
state.bit_count = state.bit_count + frame.bit_count;
state.frame_count = index;
state.iteration_sum = state.iteration_sum + frame.detector.iterations;
state.nonconverged_count = state.nonconverged_count + ...
    double(~frame.detector.converged);
state.elapsed_seconds = state.elapsed_seconds + elapsed;
state.frame_errors(index) = frame.error_count;
state.frame_bits(index) = frame.bit_count;
state.iterations(index) = frame.detector.iterations;
state.residuals(index) = frame.detector.residual;
state.converged(index) = double(frame.detector.converged);
if state.frame_count >= stop.min_frames && ...
        state.error_count >= stop.target_errors
    state.stop_reason = 'target_errors';
elseif state.frame_count >= stop.max_frames
    state.stop_reason = 'max_frames';
end
end

function [states, next_frame] = load_or_initialize_checkpoint( ...
    checkpoint_file, run_contract, n_scheme, n_csi, max_frames)
if exist(checkpoint_file, 'file')
    saved = load(checkpoint_file, ...
        'run_contract', 'states', 'next_frame');
    if ~isfield(saved, 'run_contract') || ...
            ~isequaln(saved.run_contract, run_contract)
        error('run_online_iso_gabp_sweep:manifestMismatch', ...
            'Checkpoint does not match the requested immutable run contract.');
    end
    states = saved.states;
    next_frame = saved.next_frame;
    return;
end
states = repmat(empty_curve_state(max_frames), n_scheme, n_csi);
next_frame = 1;
end

function save_checkpoint_atomic( ...
    file, run_contract, states, next_frame, ...
    average_reference_snr_db, stream_snr_db)
temporary = [file '.tmp.mat'];
save(temporary, 'run_contract', 'states', 'next_frame', ...
    'average_reference_snr_db', 'stream_snr_db', '-v7.3');
[ok, message] = movefile(temporary, file, 'f');
if ~ok
    error('run_online_iso_gabp_sweep:checkpointWrite', ...
        'Cannot publish checkpoint: %s', message);
end
end

function save_final_atomic(file, package)
temporary = [file '.tmp.mat'];
save(temporary, 'package', '-v7.3');
[ok, message] = movefile(temporary, file, 'f');
if ~ok
    error('run_online_iso_gabp_sweep:finalWrite', ...
        'Cannot publish final package: %s', message);
end
end

function [Us, Ur] = resolve_scheme_basis( ...
    scheme, Us_afwdm, Ur_afwdm, Us_dft, Ur_dft, Us_svd, Ur_svd)
switch scheme
    case 'AFWDM'
        Us = Us_afwdm;
        Ur = Ur_afwdm;
    case 'DFT_precoded'
        Us = Us_dft;
        Ur = Ur_dft;
    case 'SVD_paper'
        Us = Us_svd;
        Ur = Ur_svd;
    otherwise
        error('run_online_iso_gabp_sweep:scheme', ...
            'Unknown scheme "%s".', scheme);
end
end

function package = assemble_package(cfg, run_contract, modes, N_s, state_grid)
n_scheme = numel(cfg.schemes);
n_snr = numel(cfg.SNR_dB_list);
n_csi = numel(cfg.kappa_list);
error_count = zeros(n_scheme, n_snr, n_csi);
bit_count = zeros(n_scheme, n_snr, n_csi);
frame_count = zeros(n_scheme, n_snr, n_csi);
ber = zeros(n_scheme, n_snr, n_csi);
upper = nan(n_scheme, n_snr, n_csi);
average_iterations = zeros(n_scheme, n_snr, n_csi);
nonconvergence_rate = zeros(n_scheme, n_snr, n_csi);
elapsed_seconds = zeros(n_scheme, n_snr, n_csi);
stop_reason = cell(n_scheme, n_snr, n_csi);

for i_snr = 1:n_snr
    states = state_grid{i_snr};
    for i_csi = 1:n_csi
        for i_scheme = 1:n_scheme
            state = states(i_scheme, i_csi);
            error_count(i_scheme, i_snr, i_csi) = state.error_count;
            bit_count(i_scheme, i_snr, i_csi) = state.bit_count;
            frame_count(i_scheme, i_snr, i_csi) = state.frame_count;
            ber(i_scheme, i_snr, i_csi) = ...
                state.error_count / state.bit_count;
            if state.error_count == 0
                upper(i_scheme, i_snr, i_csi) = 3 / state.bit_count;
            end
            average_iterations(i_scheme, i_snr, i_csi) = ...
                state.iteration_sum / state.frame_count;
            nonconvergence_rate(i_scheme, i_snr, i_csi) = ...
                state.nonconverged_count / state.frame_count;
            elapsed_seconds(i_scheme, i_snr, i_csi) = ...
                state.elapsed_seconds;
            stop_reason{i_scheme, i_snr, i_csi} = state.stop_reason;
        end
    end
end

package = struct();
package.profile = cfg.mode;
package.scientific_label = cfg.iso_gabp.scientific_label;
package.detector = 'GaBP';
package.SNR_average_reference_dB = ...
    cfg.iso_gabp.average_reference_SNR_dB_list;
package.SNR_stream_dB = cfg.SNR_dB_list;
package.SNR_dB = package.SNR_average_reference_dB;
package.schemes = cfg.schemes;
package.csi_case_labels = cfg.csi_case_labels;
package.csi_error_variance = cfg.kappa_list;
package.N_s = N_s;
package.mode_summary = modes;
package.BER = ber;
package.error_count = error_count;
package.bit_count = bit_count;
package.frame_count = frame_count;
package.stop_reason = stop_reason;
package.zero_error_95_upper = upper;
package.average_iterations = average_iterations;
package.nonconvergence_rate = nonconvergence_rate;
package.elapsed_seconds = elapsed_seconds;
package.curve_states = state_grid;
package.stop_contract = cfg.iso_gabp.stop;
package.detector_options = cfg.iso_gabp.detector_options;
package.asset_names = cfg.iso_gabp.assets;
package.reference_stream_count = cfg.iso_gabp.reference_stream_count;
package.snr_definition = cfg.iso_gabp.average_reference_snr_definition;
package.internal_snr_definition = cfg.snr_definition;
package.run_contract = run_contract;
package.generated_at = char(datetime( ...
    'now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
end

function write_results_csv(package, output_file)
n_rows = numel(package.SNR_average_reference_dB) * ...
    numel(package.csi_case_labels) * ...
    numel(package.schemes);
rows = cell(n_rows, 12);
row_index = 0;
for i_snr = 1:numel(package.SNR_average_reference_dB)
    for i_csi = 1:numel(package.csi_case_labels)
        for i_scheme = 1:numel(package.schemes)
            row_index = row_index + 1;
            rows(row_index, :) = { ...
                package.schemes{i_scheme}, ...
                package.csi_case_labels{i_csi}, ...
                package.SNR_average_reference_dB(i_snr), ...
                package.SNR_stream_dB(i_snr), ...
                package.frame_count(i_scheme, i_snr, i_csi), ...
                package.error_count(i_scheme, i_snr, i_csi), ...
                package.bit_count(i_scheme, i_snr, i_csi), ...
                package.BER(i_scheme, i_snr, i_csi), ...
                package.zero_error_95_upper(i_scheme, i_snr, i_csi), ...
                package.average_iterations(i_scheme, i_snr, i_csi), ...
                package.nonconvergence_rate(i_scheme, i_snr, i_csi), ...
                package.stop_reason{i_scheme, i_snr, i_csi}};
        end
    end
end
summary = cell2table(rows, 'VariableNames', { ...
    'scheme', 'csi_case', 'average_reference_snr_db', ...
    'stream_snr_db', 'frames', 'errors', 'bits', ...
    'observed_ber', 'zero_error_95_upper', 'average_iterations', ...
    'nonconvergence_rate', 'stop_reason'});
writetable(summary, output_file);
end

function run_contract = build_run_contract(cfg, run_id)
contract_cfg = struct( ...
    'mode', cfg.mode, ...
    'array_shape', cfg.array_shape, ...
    'Nblk', cfg.Nblk, ...
    'SNR_dB_list', cfg.SNR_dB_list, ...
    'schemes', {cfg.schemes}, ...
    'strategies', {cfg.strategies}, ...
    'QAM_order', cfg.QAM_order, ...
    'kappa_list', cfg.kappa_list, ...
    'csi_error_mode', cfg.csi_error_mode, ...
    'scenario', cfg.ber_scenarios, ...
    'mode_selector', cfg.mode_selector, ...
    'seed', cfg.seed, ...
    'iso_gabp', cfg.iso_gabp);
run_contract = struct();
run_contract.schema_version = 1;
run_contract.runner_version = cfg.iso_gabp.runner_version;
run_contract.run_id = run_id;
run_contract.profile = cfg.mode;
run_contract.config_fingerprint = sha256_bytes( ...
    unicode2native(jsonencode(contract_cfg), 'UTF-8'));
run_contract.code_fingerprint = repository_code_fingerprint(cfg.repo_root);
run_contract.git_commit = git_commit(cfg.repo_root);
run_contract.matlab_release = version('-release');
run_contract.seed_contract = cfg.seed;
end

function validate_or_write_contract(run_root, run_contract)
contract_file = fullfile(run_root, 'RUN_CONTRACT.mat');
if exist(contract_file, 'file')
    saved = load(contract_file, 'run_contract');
    if ~isfield(saved, 'run_contract') || ...
            ~isequaln(saved.run_contract, run_contract)
        error('run_online_iso_gabp_sweep:manifestMismatch', ...
            ['RUN_CONTRACT.mat does not match this request. Use a new run ' ...
             'id; incompatible checkpoints are never reused silently.']);
    end
    return;
end
existing = dir(fullfile(run_root, 'checkpoints', '*.mat'));
if ~isempty(existing) || exist(fullfile(run_root, 'RUN_INFO.txt'), 'file')
    error('run_online_iso_gabp_sweep:manifestMismatch', ...
        'Existing artifacts have no compatible RUN_CONTRACT.mat.');
end
save(contract_file, 'run_contract', '-v7');
end

function fingerprint = repository_code_fingerprint(repo_root)
files = dir(fullfile(repo_root, '**', '*.m'));
paths = sort(fullfile({files.folder}, {files.name}));
records = cell(1, numel(paths));
for ii = 1:numel(paths)
    relative = erase(paths{ii}, [repo_root filesep]);
    records{ii} = [relative newline fileread(paths{ii}) newline];
end
fingerprint = sha256_bytes( ...
    unicode2native(strjoin(records, ''), 'UTF-8'));
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
value = lower(reshape(dec2hex( ...
    typecast(digest.digest(), 'uint8'), 2).', 1, []));
end

function run_id = resolve_run_id(requested, active_file)
if ~isempty(requested)
    run_id = char(requested);
    return;
end
if exist(active_file, 'file')
    run_id = strtrim(fileread(active_file));
    if isempty(run_id)
        error('run_online_iso_gabp_sweep:activeFile', ...
            'Active run id file is empty.');
    end
    return;
end
run_id = ['iso_gabp_adaptive_' ...
    char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'))];
fid = fopen(active_file, 'w');
if fid < 0
    error('run_online_iso_gabp_sweep:activeFile', ...
        'Cannot write active run id file: %s.', active_file);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', run_id);
end

function slug = number_slug(value)
if value < 0
    slug = ['m' num2str(abs(value))];
else
    slug = ['p' num2str(value)];
end
slug = strrep(slug, '.', 'p');
end

function write_run_info(run_root, package)
file = fullfile(run_root, 'RUN_INFO.txt');
fid = fopen(file, 'w');
if fid < 0
    error('run_online_iso_gabp_sweep:runInfo', ...
        'Cannot write %s.', file);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'profile=%s\n', package.profile);
fprintf(fid, 'detector=%s\n', package.detector);
fprintf(fid, 'N_s=%d\n', package.N_s);
fprintf(fid, 'average_reference_SNR_dB=%s\n', ...
    num2str(package.SNR_average_reference_dB));
fprintf(fid, 'internal_stream_SNR_dB=%s\n', ...
    num2str(package.SNR_stream_dB));
fprintf(fid, 'generated_at=%s\n', package.generated_at);
end

function ensure_dir(path_value)
if ~exist(path_value, 'dir')
    [ok, message] = mkdir(path_value);
    if ~ok
        error('run_online_iso_gabp_sweep:mkdir', ...
            'Cannot create %s: %s', path_value, message);
    end
end
end
