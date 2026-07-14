function [final_results, final_stage] = select_time_diversity_final_results(baseline, stages)
%SELECT_TIME_DIVERSITY_FINAL_RESULTS Choose the last evidence-producing stage.

if isempty(stages)
    final_results = baseline;
    if isfield(baseline, 'runs') && ~isempty(baseline.runs)
        final_stage = sprintf('lch%d', max([baseline.runs.Lch]));
    else
        final_stage = 'lch6';
    end
    return;
end

final_results = stages{end}.results;
final_stage = stages{end}.name;
end
