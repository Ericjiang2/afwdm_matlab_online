function phi = compute_cpp_phase(zeta, N, c1)
    % COMPUTE_CPP_PHASE  Cyclic Prefix Phase (CPP) correction vector.
    %
    % Per Eq.(40): for sample index n < zeta,
    %   phi(n) = exp(-j*2*pi*c1*(N^2 - 2*N*(zeta - n)))
    % For n >= zeta: phi(n) = 1 (no correction needed).
    %
    % Inputs:
    %   zeta  - integer delay of the current path
    %   N     - AFDM block length
    %   c1    - chirp parameter
    %
    % Output:
    %   phi   - N x 1 phase vector

    phi = ones(N, 1);
    if zeta > 0
        q = (zeta:-1:1).';
        phi(1:zeta) = exp(-1j * 2*pi * c1 * (N^2 - 2*N*q));
    end
end
