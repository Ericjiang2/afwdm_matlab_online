function op = build_modal_block_operator(modal_by_candidate, candidate_pairs, cfg)
%BUILD_MODAL_BLOCK_OPERATOR Matrix-free apply/adjoint of the modal block channel.
%
% Represents H_blk = sum_q kron(S_q, D_q) without forming the N*d_r x N*d_s
% dense matrix, so full-selected-mode paired BER detection can run PCG on the
% normal equations. Candidates whose modal matrix is all-zero are skipped, so
% sparse estimates only pay for their active DD blocks.

    N = cfg.Nblk;
    d_r = size(modal_by_candidate{1}, 1);
    d_s = size(modal_by_candidate{1}, 2);
    A = build_daft_matrix(cfg);

    active_candidates = zeros(0, 1);
    D_list = {};
    S_list = {};
    for q = 1:numel(modal_by_candidate)
        if ~any(modal_by_candidate{q}(:))
            continue;
        end
        tau = candidate_pairs(q, 1);
        nu = candidate_pairs(q, 2);
        D_list{end + 1} = A * build_theta_p(tau, nu, N, cfg.c1) * A'; %#ok<AGROW>
        S_list{end + 1} = modal_by_candidate{q}; %#ok<AGROW>
        active_candidates(end + 1, 1) = q; %#ok<AGROW>
    end

    op = struct();
    op.is_operator = true;
    op.n_rows = N * d_r;
    op.n_cols = N * d_s;
    op.n_active = numel(active_candidates);
    op.active_candidates = active_candidates;
    op.apply = @(x) apply_forward(x, D_list, S_list, N, d_s, d_r);
    op.applyH = @(y) apply_adjoint(y, D_list, S_list, N, d_s, d_r);
end

function y = apply_forward(x, D_list, S_list, N, d_s, d_r)
    % kron(S_q, D_q) * vec(X) = vec(D_q * X * S_q.') with X of size N x d_s.
    X = reshape(x, N, d_s);
    Y = zeros(N, d_r);
    for q = 1:numel(D_list)
        Y = Y + D_list{q} * X * S_list{q}.';
    end
    y = Y(:);
end

function x = apply_adjoint(y, D_list, S_list, N, d_s, d_r)
    % kron(S_q, D_q)' * vec(Y) = vec(D_q' * Y * conj(S_q)) with Y of size N x d_r.
    Y = reshape(y, N, d_r);
    X = zeros(N, d_s);
    for q = 1:numel(D_list)
        X = X + D_list{q}' * Y * conj(S_list{q});
    end
    x = X(:);
end
