function [stop, reason] = paired_stop_decision(error_counts, frames, cfg)
%PAIRED_STOP_DECISION Stop only after the better arm has enough errors.

validateattributes(error_counts, {'numeric'}, {'vector', 'nonnegative'});
validateattributes(frames, {'numeric'}, {'scalar', 'integer', 'nonnegative'});

if frames >= cfg.min_frames && min(error_counts) >= cfg.target_errors
    stop = true;
    reason = 'target_errors';
elseif frames >= cfg.max_frames
    stop = true;
    reason = 'max_frames_noise_limited';
else
    stop = false;
    reason = 'continue';
end
end
