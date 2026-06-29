function C = block_capacity_total(H, Ptot, chi2, do_normalize, Nblk)
    % BLOCK_CAPACITY_TOTAL  Whole-block MIMO capacity with global water-filling.
    %
    % Input-output model:
    %   y = H x + w,   w ~ CN(0, chi2 * I)
    %
    % Capacity with CSI at Tx/Rx:
    %   C = max_{Q>=0, tr(Q)<=Ptot} log2 det(I + H Q H^H / chi2)
    %
    % This routine computes the SVD/water-filling solution on the full block
    % equivalent channel matrix H.
    %
    % Inputs:
    %   H            - full block equivalent matrix
    %   Ptot         - total transmit power budget (linear)
    %   chi2         - noise variance/power (linear)
    %   do_normalize - true: return C/Nblk, false: return whole-block C
    %   Nblk         - block size, required if do_normalize=true
    %
    % Output:
    %   C            - capacity in bit/s/Hz (whole-block or normalized)

    if nargin < 4
        do_normalize = false;
    end
    if nargin < 5
        Nblk = 1;
    end

    s = svd(H);
    lambda = s.^2;
    lambda = lambda(lambda > 1e-14);

    if isempty(lambda)
        C = 0;
        return;
    end

    lambda = sort(lambda, 'descend');
    a = chi2 ./ lambda;  % chi2 / lambda_i
    csum = cumsum(a);

    mu = 0;
    K = 0;
    r = length(lambda);

    for k = r:-1:1
        mu_try = (Ptot + csum(k)) / k;
        if mu_try > a(k)
            mu = mu_try;
            K = k;
            break;
        end
    end

    if K == 0
        C = 0;
        return;
    end

    p = mu - a(1:K);
    Ctot = sum(log2(1 + p .* lambda(1:K) / chi2));

    if do_normalize
        C = Ctot / Nblk;
    else
        C = Ctot;
    end
end
