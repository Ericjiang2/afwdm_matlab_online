function C = afdm_idaft(X, cfg)
    % AFDM_IDAFT  Inverse Discrete Affine Fourier Transform (IDAFT)
    % Modulates frequency-domain symbols X into time-domain samples C.
    %
    % C = A^H * X,  where A = Lambda_c2 * F * Lambda_c1
    %   Lambda_ci = diag(exp(-j2pi*ci*n^2)), n=0..N-1
    N = cfg.Nblk;
    c1 = cfg.c1;
    c2 = cfg.c2;

    n = (0:N-1).';
    F = dftmtx(N) / sqrt(N);

    Lambda_c1 = diag(exp(-1j * 2*pi * c1 * (n.^2)));
    Lambda_c2 = diag(exp(-1j * 2*pi * c2 * (n.^2)));

    A = Lambda_c2 * F * Lambda_c1;
    C = A' * X;
end
