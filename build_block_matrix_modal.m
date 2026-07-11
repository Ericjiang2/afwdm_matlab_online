function H_blk = build_block_matrix_modal(modal_by_candidate, candidate_pairs, cfg)
%BUILD_BLOCK_MATRIX_MODAL Build the AFDM block channel from modal DD matrices.

    N = cfg.Nblk;
    d_r = size(modal_by_candidate{1}, 1);
    d_s = size(modal_by_candidate{1}, 2);
    A = build_daft_matrix(cfg);
    H_blk = zeros(N * d_r, N * d_s);

    for q = 1:numel(modal_by_candidate)
        tau = candidate_pairs(q, 1);
        nu = candidate_pairs(q, 2);
        D_q = A * build_theta_p(tau, nu, N, cfg.c1) * A';
        H_blk = H_blk + kron(modal_by_candidate{q}, D_q);
    end
end
