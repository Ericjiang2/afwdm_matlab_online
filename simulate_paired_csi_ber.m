function result = simulate_paired_csi_ber(H_true, detectors, qam_order, snr_db, opts)
%SIMULATE_PAIRED_CSI_BER Detect the same received vector with each CSI branch.

    bits = opts.bits(:);
    symbols = qam_modulate(bits, qam_order);
    noise_variance = 10^(-snr_db / 10);
    y = apply_channel(H_true, symbols) + opts.noise(:);

    n_detectors = numel(detectors.H);
    bits_est = cell(1, n_detectors);
    x_est = cell(1, n_detectors);
    error_bits = zeros(1, n_detectors);
    solver_flag = zeros(1, n_detectors);
    solver_relres = zeros(1, n_detectors);
    solver_iter = zeros(1, n_detectors);
    solve_time_s = zeros(1, n_detectors);

    for j = 1:n_detectors
        H_detector = detectors.H{j};
        t_solve = tic;
        switch lower(opts.solver)
            case 'direct'
                if isstruct(H_detector)
                    error('simulate_paired_csi_ber:operatorNeedsPcg', ...
                        'Operator detectors require the "pcg" solver.');
                end
                gram = H_detector' * H_detector + ...
                    noise_variance * eye(size(H_detector, 2));
                x_est{j} = gram \ (H_detector' * y);
            case 'pcg'
                rhs = apply_channel_adjoint(H_detector, y);
                normal_operator = @(z) apply_channel_adjoint(H_detector, ...
                    apply_channel(H_detector, z)) + noise_variance * z;
                [x_est{j}, solver_flag(j), solver_relres(j), ...
                    solver_iter(j)] = pcg( ...
                    normal_operator, rhs, opts.pcg_tol, opts.pcg_max_iter);
            otherwise
                error('simulate_paired_csi_ber:unknownSolver', ...
                    'Unsupported detector solver "%s".', opts.solver);
        end
        solve_time_s(j) = toc(t_solve);
        bits_est{j} = qam_demodulate(x_est{j}, qam_order);
        error_bits(j) = sum(bits_est{j} ~= bits);
    end

    result = struct();
    result.names = detectors.names;
    result.bits = bits;
    result.symbols = symbols;
    result.noise = opts.noise(:);
    result.y = y;
    result.x_est = x_est;
    result.bits_est = bits_est;
    result.error_bits = error_bits;
    result.solver_flag = solver_flag;
    result.solver_relres = solver_relres;
    result.solver_iter = solver_iter;
    result.solve_time_s = solve_time_s;
    result.total_bits = numel(bits);
    result.ber = error_bits / numel(bits);
end

function out = apply_channel(H, x)
    if isstruct(H)
        out = H.apply(x);
    else
        out = H * x;
    end
end

function out = apply_channel_adjoint(H, y)
    if isstruct(H)
        out = H.applyH(y);
    else
        out = H' * y;
    end
end
