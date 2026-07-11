function estimate = estimate_modal_channel_ce(training, candidate_pairs, ~, opts)
%ESTIMATE_MODAL_CHANNEL_CE Estimate selected-modal DD matrices from pilots.

    rows = training.observation_rows;
    Phi = training.pilot_atoms(rows, :);
    n_candidates = size(candidate_pairs, 1);
    if isfield(opts, 'raw_modal_observations')
        ls_by_candidate = opts.raw_modal_observations;
    else
        Y_mmv = zeros(numel(rows), training.d_r * training.d_s);
        for s = 1:training.d_s
            columns = (s - 1) * training.d_r + (1:training.d_r);
            Y_mmv(:, columns) = training.Y(rows, :, s);
        end
        coefficients = Phi \ Y_mmv;
        ls_by_candidate = cell(1, n_candidates);
        for q = 1:n_candidates
            ls_by_candidate{q} = reshape( ...
                coefficients(q, :), [training.d_r, training.d_s]);
        end
    end

    switch lower(opts.method)
        case 'full_grid_ls'
            active_mask = true(n_candidates, 1);
            modal_by_candidate = ls_by_candidate;
            detection = [];

        case 'full_grid_lmmse'
            active_mask = true(n_candidates, 1);
            detection = [];
            modal_by_candidate = apply_lmmse( ...
                ls_by_candidate, active_mask, training, opts.spatial_variance);

        case 'threshold_ls'
            detection = detect_dd_support_cfar( ...
                ls_by_candidate, candidate_pairs, ...
                struct('noise_variance', training.noise_variance, ...
                       'pilot_energy', training.pilot_energy, ...
                       'pfa_total', opts.pfa_total, ...
                       'correction', opts.correction));
            active_mask = detection.active_mask;
            modal_by_candidate = apply_mask(ls_by_candidate, active_mask);

        case 'threshold_lmmse'
            detection = detect_dd_support_cfar( ...
                ls_by_candidate, candidate_pairs, ...
                struct('noise_variance', training.noise_variance, ...
                       'pilot_energy', training.pilot_energy, ...
                       'pfa_total', opts.pfa_total, ...
                       'correction', opts.correction));
            active_mask = detection.active_mask;
            modal_by_candidate = apply_lmmse( ...
                ls_by_candidate, active_mask, training, opts.spatial_variance);

        case 'oracle_support_lmmse'
            active_mask = logical(opts.oracle_mask(:));
            detection = [];
            modal_by_candidate = apply_lmmse( ...
                ls_by_candidate, active_mask, training, opts.spatial_variance);

        otherwise
            error('estimate_modal_channel_ce:unknownMethod', ...
                'Unsupported method "%s".', opts.method);
    end

    estimate = struct();
    estimate.method = opts.method;
    estimate.raw_modal_observations = ls_by_candidate;
    estimate.active_mask = active_mask;
    estimate.support_pairs = candidate_pairs(active_mask, :);
    estimate.detection = detection;
    estimate.modal_by_candidate = modal_by_candidate;
end

function masked = apply_mask(values, active_mask)
    masked = cell(size(values));
    zero_value = zeros(size(values{1}));
    for q = 1:numel(values)
        if active_mask(q)
            masked{q} = values{q};
        else
            masked{q} = zero_value;
        end
    end
end

function shrunk = apply_lmmse(values, active_mask, training, spatial_variance)
    if isscalar(spatial_variance)
        spatial_variance = spatial_variance * ...
            ones(training.d_r, training.d_s);
    end
    coefficient_noise_variance = ...
        training.noise_variance / training.pilot_energy;
    gain = spatial_variance ./ ...
        (spatial_variance + coefficient_noise_variance);

    shrunk = apply_mask(values, active_mask);
    for q = 1:numel(values)
        if active_mask(q)
            shrunk{q} = gain .* values{q};
        end
    end
end
