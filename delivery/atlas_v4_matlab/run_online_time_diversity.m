function package = run_online_time_diversity(profile, run_id, output_root)
%RUN_ONLINE_TIME_DIVERSITY Resumable AFWDM-vs-OFWDM MATLAB Online runner.
%
% Production use from the repository root:
%   addpath('delivery/atlas_v4_matlab');
%   run_online_time_diversity();
%
% Each stage is checkpointed per SNR. Reusing the same run id skips valid
% checkpoints and a completed final package. Conditional stages follow the
% fail-closed order encoded by resolve_time_diversity_escalation.

if nargin < 1 || isempty(profile)
    profile = "time_diversity_online";
end
profile = lower(string(profile));
if ~ismember(profile, ["time_diversity_online", "time_diversity_pilot", ...
        "time_diversity_low_snr_pilot", "time_diversity_4db_followup", ...
        "time_diversity_fractional_gabp_exploration", ...
        "time_diversity_lch6_tau48_followup", ...
        "time_diversity_tau48_sixline", ...
        "time_diversity_smoke"])
    error('run_online_time_diversity:profile', ...
        ['Profile must be time_diversity_online, time_diversity_pilot, ' ...
         'time_diversity_low_snr_pilot, time_diversity_4db_followup, ' ...
         'time_diversity_fractional_gabp_exploration, ' ...
         'time_diversity_lch6_tau48_followup, ' ...
         'time_diversity_tau48_sixline, ' ...
         'or time_diversity_smoke.']);
end

cfg0 = make_delivery_config(profile);
for ii = 1:numel(cfg0.path_dirs)
    if exist(cfg0.path_dirs{ii}, 'dir')
        addpath(cfg0.path_dirs{ii});
    end
end
addpath(cfg0.delivery_dir);

if nargin < 3 || isempty(output_root)
    output_root = fullfile(cfg0.output_dir, 'online_runs');
end
ensure_dir(output_root);
if nargin < 2 || isempty(run_id)
    run_id = active_run_id(output_root);
else
    run_id = char(string(run_id));
end

run_root = fullfile(output_root, run_id);
checkpoint_dir = fullfile(run_root, 'checkpoints');
final_dir = fullfile(run_root, 'final');
ensure_dir(checkpoint_dir);
ensure_dir(final_dir);
final_mat = fullfile(final_dir, 'time_diversity_final.mat');
run_manifest = build_time_diversity_run_manifest(cfg0, 'run');
if isfile(final_mat)
    loaded = load(final_mat, 'package', 'run_manifest');
    if ~isfield(loaded, 'run_manifest')
        error('run_online_time_diversity:manifestMismatch', ...
            'Final MAT has no immutable run manifest; use a new run_id.');
    end
    validate_time_diversity_run_manifest(run_manifest, loaded.run_manifest, 'final MAT');
    package = loaded.package;
    return;
end

fprintf('Time-diversity run %s (%s)\n', run_id, profile);
is_explicit_exploration = isfield(cfg0.time_diversity, 'explicit_stages') && ...
    ~isempty(cfg0.time_diversity.explicit_stages);
if is_explicit_exploration
    stage_plan = build_time_diversity_exploration_stages(cfg0);
    baseline_cfg = stage_plan(1).cfg;
    baseline_stage_name = stage_plan(1).name;
else
    stage_plan = [];
    baseline_cfg = cfg0;
    baseline_stage_name = 'baseline';
end
baseline = run_stage(baseline_cfg, baseline_stage_name, checkpoint_dir);
current_cfg = baseline_cfg;
current_results = baseline;
current_stage = 'lch6';
mode_states = initialize_time_diversity_mode_states( ...
    cfg0.time_diversity.doppler_modes);
if is_explicit_exploration
    stages = cell(1, max(0, numel(stage_plan) - 1));
else
    stages = cell(1, 3);
end
stage_count = 0;

if is_explicit_exploration
    for ii = 2:numel(stage_plan)
        next_results = run_stage( ...
            stage_plan(ii).cfg, stage_plan(ii).name, checkpoint_dir);
        stage_count = stage_count + 1;
        trigger_plan = rmfield(stage_plan(ii), 'cfg');
        stages{stage_count} = struct('name', stage_plan(ii).name, ...
            'trigger_plan', trigger_plan, 'results', next_results);
        current_cfg = stage_plan(ii).cfg;
        current_results = next_results;
    end
    [plan, mode_states, outcome] = build_time_diversity_exploration_completion( ...
        stage_plan, current_results, current_cfg);
else
    while true
        gains = build_time_diversity_gain_records(current_results.summary_table, ...
            current_cfg.time_diversity.doppler_modes);
        plan = resolve_time_diversity_escalation(current_stage, gains, cfg0);
        mode_states = update_time_diversity_mode_states( ...
            mode_states, gains, current_stage, plan.next_stage);
        if ismember(plan.next_stage, {'complete', 'await_evidence', 'fail_closed'})
            break;
        end

        next_cfg = apply_time_diversity_escalation(current_cfg, plan);
        next_results = run_stage(next_cfg, plan.next_stage, checkpoint_dir);
        stage_count = stage_count + 1;
        stages{stage_count} = struct('name', plan.next_stage, ...
            'trigger_plan', plan, 'results', next_results);
        current_cfg = next_cfg;
        current_results = next_results;
        current_stage = plan.next_stage;
    end
end
stages = stages(1:stage_count);

siso_anchor = run_time_diversity_siso_anchor(cfg0);
[final_results, final_stage] = select_time_diversity_final_results(baseline, stages);
if is_explicit_exploration
    final_stage = stage_plan(end).name;
end
if ~is_explicit_exploration
    outcome = build_time_diversity_outcome(plan, final_stage, current_cfg, mode_states);
end
plan.overall_status = outcome.status;
plan.per_doppler = mode_states;
package = struct();
package.baseline = baseline;
package.escalation_stages = stages;
package.final_plan = plan;
package.final_results = final_results;
package.final_stage = final_stage;
package.outcome = outcome;
package.siso_anchor = siso_anchor;
package.metadata = struct( ...
    'run_id', run_id, ...
    'profile', char(profile), ...
    'generated_by', 'delivery/atlas_v4_matlab/run_online_time_diversity.m', ...
    'checkpoint_granularity', 'stage_per_snr', ...
    'scientific_label', char(scientific_label(is_explicit_exploration)), ...
    'siso_internal_only', true, ...
    'timestamp', char(datetime('now', 'Format', "yyyyMMdd'T'HHmmss")));

plot_time_diversity_results(baseline, cfg0, final_dir, 'time_diversity_baseline');
plot_time_diversity_results(final_results, current_cfg, final_dir);
for ii = 1:numel(stages)
    stage_table = stages{ii}.results.summary_table;
    writetable(stage_table, fullfile(final_dir, ...
        sprintf('time_diversity_summary_%s.csv', stages{ii}.name)));
end
save(final_mat, 'package', 'cfg0', 'run_manifest', '-v7');
fprintf('Time-diversity final package: %s\n', final_mat);
end

function label = scientific_label(is_explicit_exploration)
if is_explicit_exploration
    label = "candidate_exploration";
else
    label = "profile_defined";
end
end

function results = run_stage(cfg_stage, stage_name, checkpoint_dir)
snrs = cfg_stage.time_diversity.SNR_dB_list;
snrs = sort(snrs);
packs = cell(1, numel(snrs));
stage_manifest = build_time_diversity_run_manifest(cfg_stage, stage_name);
for ii = 1:numel(snrs)
    snr_db = snrs(ii);
    checkpoint_file = fullfile(checkpoint_dir, sprintf('%s_snr_%s.mat', ...
        stage_name, snr_tag(snr_db)));
    if isfile(checkpoint_file)
        loaded = load(checkpoint_file, 'checkpoint');
        checkpoint = loaded.checkpoint;
        if ~isfield(checkpoint, 'manifest')
            error('run_online_time_diversity:manifestMismatch', ...
                'Checkpoint has no immutable run manifest: %s.', checkpoint_file);
        end
        validate_time_diversity_run_manifest( ...
            stage_manifest, checkpoint.manifest, checkpoint_file);
        if checkpoint.snr_db ~= snr_db || ~strcmp(checkpoint.stage, stage_name)
            error('run_online_time_diversity:manifestMismatch', ...
                'Checkpoint stage/SNR mismatch: %s.', checkpoint_file);
        end
        fprintf('  SKIP %s SNR=%g dB\n', stage_name, snr_db);
    else
        fprintf('  RUN  %s SNR=%g dB\n', stage_name, snr_db);
        cfg_one = cfg_stage;
        cfg_one.time_diversity.SNR_dB_list = snr_db;
        checkpoint = struct('stage', stage_name, 'snr_db', snr_db, ...
            'manifest', stage_manifest, ...
            'results', run_time_diversity_ber(cfg_one));
        save(checkpoint_file, 'checkpoint', '-v7');
    end
    packs{ii} = checkpoint.results;
end
results = combine_stage_results(packs, snrs, cfg_stage);
end

function results = combine_stage_results(packs, snrs, cfg_stage)
results = packs{1};
for iRun = 1:numel(results.runs)
    points = repmat(results.runs(iRun).points(1), 1, numel(snrs));
    for iSNR = 1:numel(snrs)
        candidate = packs{iSNR}.runs(iRun);
        if candidate.SNR_dB ~= snrs(iSNR) || ...
                ~same_run_identity(results.runs(iRun), candidate)
            error('run_online_time_diversity:combineMismatch', ...
                'Per-SNR checkpoint run identities do not match.');
        end
        points(iSNR) = candidate.points;
    end
    results.runs(iRun).SNR_dB = snrs;
    results.runs(iRun).points = points;
end
primary_lch = max(cfg_stage.time_diversity.Lch_values);
results.summary_table = build_time_diversity_summary( ...
    results.runs, primary_lch, cfg_stage.time_diversity.summary_target_ber);
if all(ismember([4, 6], cfg_stage.time_diversity.Lch_values))
    results.lch_comparison = compare_time_diversity_lch(results.runs, 4, 6);
else
    results.lch_comparison = [];
end
end

function same = same_run_identity(a, b)
same = strcmp(a.doppler_mode, b.doppler_mode) && ...
    strcmp(a.detector, b.detector) && strcmp(a.spatial_pair, b.spatial_pair) && ...
    a.Lch == b.Lch && a.kmax == b.kmax;
end

function tag = snr_tag(value)
if value < 0
    prefix = 'm';
else
    prefix = 'p';
end
tag = [prefix strrep(sprintf('%g', abs(value)), '.', 'p')];
end

function run_id = active_run_id(output_root)
active_file = fullfile(output_root, '_ACTIVE_TIME_DIVERSITY_RUN_ID.txt');
if isfile(active_file)
    run_id = strtrim(fileread(active_file));
    if ~isempty(run_id)
        return;
    end
end
run_id = ['time_diversity_' char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'))];
fid = fopen(active_file, 'w');
if fid < 0
    error('run_online_time_diversity:activeRunId', ...
        'Cannot write active run id: %s.', active_file);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', run_id);
clear cleanup;
end

function ensure_dir(path_value)
if ~exist(path_value, 'dir')
    mkdir(path_value);
end
end
