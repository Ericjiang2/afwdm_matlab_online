function [limits, ticks] = delivery_ber_axis_scale(plotted_ber, explicit_limits)
%DELIVERY_BER_AXIS_SCALE  Complete-decade limits and ticks for BER plots.

if nargin < 2
    explicit_limits = [];
end

if ~isempty(explicit_limits)
    limits = double(explicit_limits(:).');
    if numel(limits) ~= 2 || any(~isfinite(limits)) || ...
            any(limits <= 0) || limits(1) >= limits(2)
        error('delivery_ber_axis_scale:invalidExplicitLimits', ...
            'Explicit BER limits must be two finite, positive, increasing values.');
    end
    lower_exp = ceil(log10(limits(1)));
    upper_exp = floor(log10(limits(2)));
    ticks = 10.^(lower_exp:upper_exp);
    return;
end

positive = double(plotted_ber(isfinite(plotted_ber) & plotted_ber > 0));
if isempty(positive)
    error('delivery_ber_axis_scale:noPositiveData', ...
        'Cannot derive BER axis limits without finite positive plotted values.');
end

lower_exp = floor(log10(min(positive)));
upper_exp = ceil(log10(max(positive)));
if lower_exp == upper_exp
    upper_exp = lower_exp + 1;
end

limits = 10.^[lower_exp, upper_exp];
ticks = 10.^(lower_exp:upper_exp);
end
