function Y = afdm_daft(R, cfg)
    % AFDM_DAFT  Discrete Affine Fourier Transform (DAFT)
    % Demodulates time-domain samples R into frequency-domain symbols Y.
    %
    % Y = A * R,  where A = Lambda_c2 * F * Lambda_c1
    %   Lambda_ci = diag(exp(-j2pi*ci*n^2)), n=0..N-1
    N = cfg.Nblk;
    c1 = cfg.c1;
    c2 = cfg.c2;

    n = (0:N-1).';
    F = dftmtx(N) / sqrt(N);

    Lambda_c1 = diag(exp(-1j * 2*pi * c1 * (n.^2)));
    Lambda_c2 = diag(exp(-1j * 2*pi * c2 * (n.^2)));

    A = Lambda_c2 * F * Lambda_c1;
    Y = A * R;
end
