function Theta = build_theta_p(tau, nu, N, c1)
    % BUILD_THETA_P  Construct the N×N time-domain block matrix for one path.
    %
    % Per main.pdf / AFDM, the per-path time-domain operator is:
    %   Theta_p = diag(phi .* doppler) * Pi^{tau}
    %
    % where:
    %   Pi^{tau}  = circular downward shift permutation by tau samples
    %   doppler   = exp(+j*2*pi*nu*n/N),  n = 0..N-1
    %   phi       = CPP phase correction (modifies first tau samples, Eq.(40))
    %
    % Inputs:
    %   tau  - integer delay of this path
    %   nu   - integer Doppler of this path
    %   N    - AFDM block length
    %   c1   - chirp parameter
    %
    % Output:
    %   Theta - N×N time-domain block matrix for this path

    n = (0:N-1).';

    % Delay: circular shift permutation matrix (shift down by tau)
    Pi = circshift(eye(N), tau, 1);

    % Doppler: modulation diagonal
    dopp = exp(+1j * 2*pi * nu * n / N);

    % CPP phase (correction on first tau samples, 1 elsewhere)
    phi = compute_cpp_phase(tau, N, c1);

    % Combined: first delay-shift, then element-wise Doppler+CPP
    Theta = diag(phi .* dopp) * Pi;
end
