function [final_results, final_stage] = select_time_diversity_final_results(baseline, stages)
%SELECT_TIME_DIVERSITY_FINAL_RESULTS Choose the last evidence-producing stage.

if ~isfield(baseline, 'runs') || isempty(baseline.runs)
    error('select_time_diversity_final_results:missingBaseline', ...
        'Baseline results must contain runs.');
end

baseline_lch = max([baseline.runs.Lch]);
composite_runs = baseline.runs([baseline.runs.Lch] == baseline_lch);
final_stage = sprintf('lch%d', baseline_lch);

for ii = 1:numel(stages)
    stage_runs = stages{ii}.results.runs;
    stage_lch = max([stage_runs.Lch]);
    stage_runs = stage_runs([stage_runs.Lch] == stage_lch);
    for jj = 1:numel(stage_runs)
        match = find(same_identity(composite_runs, stage_runs(jj)), 1);
        if isempty(match)
            composite_runs(end+1) = stage_runs(jj); %#ok<AGROW>
        else
            composite_runs(match) = stage_runs(jj);
        end
    end
    final_stage = stages{ii}.name;
end

final_results = baseline;
final_results.runs = composite_runs;
target_ber = baseline.summary_table.target_ber(1);
final_results.summary_table = build_time_diversity_summary( ...
    composite_runs, [], target_ber);
final_results.primary_evidence = 'composite_latest_per_doppler_detector_spatial_pair';
end

function matches = same_identity(runs, candidate)
matches = strcmp({runs.doppler_mode}, candidate.doppler_mode) & ...
    strcmp({runs.detector}, candidate.detector) & ...
    strcmp({runs.spatial_pair}, candidate.spatial_pair);
end
