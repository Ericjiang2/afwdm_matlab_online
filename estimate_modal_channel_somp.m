function estimate = estimate_modal_channel_somp(training, candidate_pairs, ~, opts)
%ESTIMATE_MODAL_CHANNEL_SOMP Recover common DD support across modal channels.

    rows = training.observation_rows;
    Phi = training.pilot_atoms(rows, :);
    n_candidates = size(candidate_pairs, 1);
    n_measurements = training.d_r * training.d_s;

    Y_mmv = zeros(numel(rows), n_measurements);
    for s = 1:training.d_s
        for r = 1:training.d_r
            column = (s - 1) * training.d_r + r;
            Y_mmv(:, column) = training.Y(rows, r, s);
        end
    end

    selected = false(n_candidates, 1);
    selection_order = zeros(0, 1);
    residual = Y_mmv;
    coefficients = zeros(0, n_measurements);
    reference_norm = max(norm(Y_mmv, 'fro'), 1);

    while numel(selection_order) < n_candidates
        if norm(residual, 'fro') <= opts.residual_tolerance * reference_norm
            break;
        end

        remaining = find(~selected);
        candidate_modal = cell(1, numel(remaining));
        candidate_score = zeros(numel(remaining), 1);
        for j = 1:numel(remaining)
            q = remaining(j);
            phi_q = Phi(:, q);
            coeff_q = (phi_q' * residual) / real(phi_q' * phi_q);
            candidate_modal{j} = reshape( ...
                coeff_q, [training.d_r, training.d_s]);
            candidate_score(j) = norm(candidate_modal{j}, 'fro')^2;
        end

        if training.noise_variance > 0
            detection = detect_dd_support_cfar( ...
                candidate_modal, candidate_pairs(remaining, :), ...
                struct('noise_variance', training.noise_variance, ...
                       'pilot_energy', training.pilot_energy, ...
                       'pfa_total', opts.pfa_total, ...
                       'correction', opts.correction));
            candidate_score(~detection.active_mask) = -inf;
        end

        [best_score, best_local] = max(candidate_score);
        if ~isfinite(best_score) || best_score <= 0
            break;
        end

        best = remaining(best_local);
        selected(best) = true;
        selection_order(end + 1, 1) = best; %#ok<AGROW>
        coefficients = Phi(:, selection_order) \ Y_mmv;
        residual = Y_mmv - Phi(:, selection_order) * coefficients;
    end

    modal_by_candidate = cell(1, n_candidates);
    for q = 1:n_candidates
        modal_by_candidate{q} = zeros(training.d_r, training.d_s);
    end
    for j = 1:numel(selection_order)
        q = selection_order(j);
        modal_by_candidate{q} = reshape( ...
            coefficients(j, :), [training.d_r, training.d_s]);
    end

    estimate = struct();
    estimate.method = 'somp_ls';
    estimate.active_mask = selected;
    estimate.support_pairs = candidate_pairs(selected, :);
    estimate.selection_order = selection_order;
    estimate.modal_by_candidate = modal_by_candidate;
    estimate.residual_norm = norm(residual, 'fro');
end
