function X_est = lmmse_detect_afwdm(Y, G_eff, tau_vec, nu_vec, cfg, alpha)
    % LMMSE_DETECT_AFWDM  LMMSE equalizer for AFWDM via PCG on the normal equations.
    %
    %   (A^H*A + alpha*I) x = A^H y
    %
    % where A is the composite AFWDM forward operator:
    %   x -> [reshape] -> IDAFT -> PhiS^T -> channel -> DAFT -> conj(PhiR) -> y
    %
    % alpha = N0 * ms is the regularization (noise power times number of Tx modes).
    %
    % Inputs:
    %   Y       - (N x mr) received signal in DAFT + wavenumber-projected domain
    %   G_eff   - {1 x Lch} cell of (Mr x Ms) full-aperture channel matrices
    %   tau_vec - [1 x Lch] integer delays
    %   nu_vec  - [1 x Lch] integer Dopplers
    %   cfg     - struct with fields: Nblk, c1, c2, ms, mr, PhiS, PhiS_H, PhiR,
    %             PhiR_H, pcg_tol, pcg_max_iter
    %   alpha   - regularization parameter (= N0 * ms)
    %
    % Output:
    %   X_est   - (N x ms) estimated Tx symbols in DAFT+wavenumber domain

    [N, Prx] = size(Y);
    % Ns = min(cfg.Nstreams, size(cfg.PhiS, 2));
    Ns = min(cfg.Nstreams, size(cfg.Us, 2));

    y_vec = Y(:);

    Atb = afwdm_adjoint_local(y_vec, G_eff, tau_vec, nu_vec, cfg);

    Afun = @(x) afwdm_normal_eq_local(x, G_eff, tau_vec, nu_vec, cfg, alpha, N, Ns, Prx);

    x0 = zeros(N * Ns, 1);
    [x_sol, ~] = pcg(Afun, Atb, cfg.pcg_tol, cfg.pcg_max_iter, [], [], x0);

    X_est = reshape(x_sol, [N, Ns]);
end

function y = afwdm_normal_eq_local(x, G_eff, tau_vec, nu_vec, cfg, alpha, N, Ns, Prx)
    hx  = afwdm_forward_local(x, G_eff, tau_vec, nu_vec, cfg, N, Ns, Prx);
    hhx = afwdm_adjoint_local(hx, G_eff, tau_vec, nu_vec, cfg);
    y   = hhx + alpha * x;
end

function y = afwdm_forward_local(x, G_eff, tau_vec, nu_vec, cfg, N, Ns, Prx)
    Smat = reshape(x, [N, Ns]);
    % ms = size(cfg.PhiS, 2);
    % mr = size(cfg.PhiR, 2);
    ms = size(cfg.Us, 2);
    mr = size(cfg.Ur, 2);
    if isfield(cfg, 'Fbb_wdm') && ~isempty(cfg.Fbb_wdm) && all(size(cfg.Fbb_wdm) == [ms, Ns])
        Fbb = cfg.Fbb_wdm;
    else
        Fbb = zeros(ms, Ns);
        Fbb(1:min(ms, Ns), 1:min(ms, Ns)) = eye(min(ms, Ns));
    end
    if isfield(cfg, 'Wbb_wdm') && ~isempty(cfg.Wbb_wdm) && all(size(cfg.Wbb_wdm) == [mr, Prx])
        Wbb = cfg.Wbb_wdm;
    else
        Wbb = eye(mr, Prx);
    end

    Xmat = Smat * Fbb';
    % Xbar = afdm_idaft(Xmat, cfg) * cfg.PhiS.';      % Tx: transpose (not Hermitian)
    Xbar = afdm_idaft(Xmat, cfg) * cfg.Phi_s_H_paper;  % Tx: paper Phi_s^H = Us^T
    Ybar = apply_ts_channel_afwdm(Xbar, G_eff, tau_vec, nu_vec, cfg);
    % Yf   = afdm_daft(Ybar, cfg) * conj(cfg.PhiR);   % Rx: conjugate (matched filter)
    Yf   = afdm_daft(Ybar, cfg) * cfg.Phi_r_paper;      % Rx: paper Phi_r = conj(Ur)
    Y    = Yf * Wbb;
    y    = Y(:);
end

function x_adj = afwdm_adjoint_local(y, G_eff, tau_vec, nu_vec, cfg)
    N    = cfg.Nblk;
    if mod(numel(y), N) ~= 0
        error('afwdm_adjoint_local: length(y)=%d is not divisible by N=%d.', numel(y), N);
    end
    Prx  = numel(y) / N;
    Ymat = reshape(y, N, Prx);
    % Ns   = min(cfg.Nstreams, size(cfg.PhiS, 2));
    Ns   = min(cfg.Nstreams, size(cfg.Us, 2));

    % ms = size(cfg.PhiS, 2);
    % mr = size(cfg.PhiR, 2);
    ms = size(cfg.Us, 2);
    mr = size(cfg.Ur, 2);
    if isfield(cfg, 'Wbb_wdm') && ~isempty(cfg.Wbb_wdm) && all(size(cfg.Wbb_wdm) == [mr, Prx])
        Wbb = cfg.Wbb_wdm;
    else
        Wbb = eye(mr, Prx);
    end
    if isfield(cfg, 'Fbb_wdm') && ~isempty(cfg.Fbb_wdm) && all(size(cfg.Fbb_wdm) == [ms, Ns])
        Fbb = cfg.Fbb_wdm;
    else
        Fbb = zeros(ms, Ns);
        Fbb(1:min(ms, Ns), 1:min(ms, Ns)) = eye(min(ms, Ns));
    end

    Yf   = Ymat * Wbb';
    % Ybar = afdm_idaft(Yf, cfg) * cfg.PhiR.';          % adjoint Rx: transpose (adjoint of conj(PhiR))
    Ybar = afdm_idaft(Yf, cfg) * cfg.Phi_r_H_paper;      % adjoint of right-multiply by Phi_r_paper
    Xbar_back = apply_ts_channel_afwdm_adj_local(Ybar, G_eff, tau_vec, nu_vec, cfg);
    % Xf_back   = afdm_daft(Xbar_back, cfg) * conj(cfg.PhiS); % adjoint Tx: conj (adjoint of PhiS^T)
    Xf_back   = afdm_daft(Xbar_back, cfg) * conj(cfg.Us);   % adjoint of right-multiply by Us^T
    Sadj      = Xf_back * Fbb;
    x_adj = Sadj(:);
end

function Xbar_back = apply_ts_channel_afwdm_adj_local(Ybar, G_eff, tau_vec, nu_vec, cfg)
    % Adjoint of apply_ts_channel_afwdm.
    % Forward order: delay -> Doppler -> CPP -> spatial(G^T)
    % Adjoint order: spatial(G^*) -> CPP^H -> Doppler^H -> delay^H
    % [N, Mr] = size(Ybar);
    [N, ~] = size(Ybar);
    Ms  = size(G_eff{1}, 2);
    Lch = length(G_eff);

    Xbar_back = zeros(N, Ms);
    n = (0:N-1).';

    for ell = 1:Lch
        tau = round(real(tau_vec(ell)));
        nu  = resolve_doppler(nu_vec(ell), cfg);

        % 1. Adjoint of spatial mixing (reverse of step 4)
        Z = Ybar * conj(G_eff{ell});   % N x Ms

        % 2. Adjoint of CPP (reverse of step 3)
        if tau > 0
            phi = compute_cpp_phase(tau, N, cfg.c1);
            Z(1:tau, :) = Z(1:tau, :) .* (conj(phi(1:tau)) * ones(1, Ms));
        end

        % 3. Adjoint of Doppler modulation (reverse of step 2)
        dopp_conj = exp(-1j * 2*pi * nu * n / N);
        Z = Z .* (dopp_conj * ones(1, Ms));

        % 4. Adjoint of delay shift (reverse of step 1)
        Z = circshift(Z, -tau, 1);

        Xbar_back = Xbar_back + Z;
    end
end


