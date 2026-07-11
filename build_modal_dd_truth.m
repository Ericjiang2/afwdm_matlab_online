function truth = build_modal_dd_truth(H_phys, tau_vec, nu_vec, Us, Ur, cfg, opts)
%BUILD_MODAL_DD_TRUTH Project physical paths, merge DD collisions, build H_blk.
%
% This is the deterministic truth seam for the channel-estimation study.
% It returns only the selected-modal channel, which is the channel observable
% by the configured Tx/Rx wavenumber bases.

    path_pairs = [tau_vec(:), nu_vec(:)];
    [support_pairs, ~, support_index] = unique(path_pairs, 'rows', 'sorted');

    n_support = size(support_pairs, 1);
    modal_by_support = cell(1, n_support);
    for q = 1:n_support
        modal_by_support{q} = zeros(size(Ur, 2), size(Us, 2));
    end

    for p = 1:numel(H_phys)
        q = support_index(p);
        modal_by_support{q} = modal_by_support{q} + Ur' * H_phys{p} * Us;
    end

    if nargin < 7 || ~isfield(opts, 'build_block') || opts.build_block
        H_blk = build_block_matrix_modal(modal_by_support, support_pairs, cfg);
    else
        H_blk = [];
    end

    truth = struct();
    truth.support_pairs = support_pairs;
    truth.modal_by_support = modal_by_support;
    truth.H_blk = H_blk;
end
