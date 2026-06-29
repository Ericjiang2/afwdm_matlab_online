function A = build_daft_matrix(cfg)
    % BUILD_DAFT_MATRIX  Construct the N×N DAFT (Discrete Affine Fourier Transform) matrix.
    %
    %   A = Lambda_c2 * F * Lambda_c1
    %
    % where F is the unitary DFT, Lambda_ci = diag(exp(-j2pi*ci*n^2)).
    %
    % Input:
    %   cfg  - struct with fields: Nblk, c1, c2
    %
    % Output:
    %   A    - (Nblk × Nblk) DAFT matrix

    N  = cfg.Nblk;
    c1 = cfg.c1;
    c2 = cfg.c2;

    n = (0:N-1).';
    F = dftmtx(N) / sqrt(N);

    Lambda_c1 = diag(exp(-1j * 2*pi * c1 * (n.^2)));
    Lambda_c2 = diag(exp(-1j * 2*pi * c2 * (n.^2)));

    A = Lambda_c2 * F * Lambda_c1;
end
