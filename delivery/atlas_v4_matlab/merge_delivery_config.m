function cfg = merge_delivery_config(cfg, override)
%MERGE_DELIVERY_CONFIG  Recursively apply a small run-time config override.
%
% The delivery main script stays readable by keeping special runner needs
% outside make_delivery_config. This helper is intentionally tiny: every
% field in override replaces or recursively updates the matching cfg field.

if isempty(override)
    return;
end

fields = fieldnames(override);
for ii = 1:numel(fields)
    name = fields{ii};
    value = override.(name);
    if isstruct(value) && isscalar(value) && isfield(cfg, name) && ...
            isstruct(cfg.(name)) && isscalar(cfg.(name))
        cfg.(name) = merge_delivery_config(cfg.(name), value);
    else
        cfg.(name) = value;
    end
end
end
