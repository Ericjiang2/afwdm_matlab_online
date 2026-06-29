function U = make_2d_dft(Mx, My)
    % MAKE_2D_DFT  Construct a unitary 2D DFT matrix via Kronecker product.
    %
    % The vectorization convention is column-major (linear index = ix + (iy-1)*Mx),
    % consistent with kron(Fy, Fx) and ndgrid(kx, ky).
    %
    % Inputs:
    %   Mx, My - number of DFT points along x and y dimensions
    %
    % Output:
    %   U  - (Mx*My) x (Mx*My) unitary matrix

    Fx = dftmtx(Mx) / sqrt(Mx);
    Fy = dftmtx(My) / sqrt(My);
    U  = kron(Fy, Fx);
end
