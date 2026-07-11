function training = simulate_embedded_pilot_training(channel, candidate_pairs, cfg, opts)
%SIMULATE_EMBEDDED_PILOT_TRAINING Generate full selected-mode one-hot pilots.

    N = cfg.Nblk;
    d_r = size(channel.modal_by_support{1}, 1);
    d_s = size(channel.modal_by_support{1}, 2);
    pilot_index = opts.pilot_bin + 1;
    pilot_value = sqrt(opts.pilot_energy);

    pilot_vector = zeros(N, 1);
    pilot_vector(pilot_index) = pilot_value;
    A = build_daft_matrix(cfg);

    n_candidates = size(candidate_pairs, 1);
    pilot_atoms = zeros(N, n_candidates);
    D_by_candidate = cell(1, n_candidates);
    for q = 1:n_candidates
        tau = candidate_pairs(q, 1);
        nu = candidate_pairs(q, 2);
        D_q = A * build_theta_p(tau, nu, N, cfg.c1) * A';
        D_by_candidate{q} = D_q;
        pilot_atoms(:, q) = D_q * pilot_vector;
    end
    observation_rows = find(any(abs(pilot_atoms) > 1e-12, 2));
    guard_columns = false(N, 1);
    for q = 1:n_candidates
        guard_columns = guard_columns | ...
            any(abs(D_by_candidate{q}(observation_rows, :)) > 1e-12, 1).';
    end

    Y = zeros(N, d_r, d_s);
    for t_train = 1:d_s
        if opts.include_data
            X = opts.data_symbols(:, :, t_train);
            X(guard_columns, :) = 0;
        else
            X = zeros(N, d_s);
        end
        X(pilot_index, :) = 0;
        X(pilot_index, t_train) = pilot_value;
        Y_block = zeros(N, d_r);
        for q = 1:numel(channel.modal_by_support)
            tau = channel.support_pairs(q, 1);
            nu = channel.support_pairs(q, 2);
            D_q = A * build_theta_p(tau, nu, N, cfg.c1) * A';
            Y_block = Y_block + ...
                D_q * X * channel.modal_by_support{q}.';
        end
        Y(:, :, t_train) = Y_block;
    end

    if opts.noise_variance > 0
        sigma = sqrt(opts.noise_variance / 2);
        Y = Y + sigma * (randn(size(Y)) + 1i * randn(size(Y)));
    end

    training = struct();
    training.Y = Y;
    training.pilot_atoms = pilot_atoms;
    training.observation_rows = observation_rows;
    training.guard_columns = guard_columns;
    training.pilot_energy = opts.pilot_energy;
    training.noise_variance = opts.noise_variance;
    training.d_s = d_s;
    training.d_r = d_r;
end
