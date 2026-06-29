% function H = beamspace_apd_channel_2d(Mrx, Mry, Msx, Msy, sigma_ang, seed, dx, dy, sz, rz)
%     % 2D planar beamspace APD channel with PHYSICAL wavenumber normalization
%     % and optional z-direction propagation phase (paper Eq.(31)).
%     %
%     % sigma_ang: spread parameter in physical wavenumber space (units: 1/lambda)
%     %   The APD is: P(kappa) = exp(-kappa^2 / (2*sigma_ang^2))
%     %   where kappa^2 = kappa_x^2 + kappa_y^2
%     %   and kappa_x = kx/(Mx*dx), kappa_y = ky/(My*dy)  (dx,dy in lambda units)
%     %
%     % sz, rz: Tx/Rx z-coordinates in lambda units (default 0 = no z-phase).
%     %   When nonzero, applies the deterministic z-propagation phase per mode:
%     %     Htilde = diag(e^{+j*gamma_r*rz}) * H_a * diag(e^{-j*gamma_s*sz})
%     %   where gamma = 2*pi*sqrt(1 - kx_phys^2 - ky_phys^2) is the z-wavenumber.
%     %   For purely statistical (Rayleigh) channels this is statistically
%     %   equivalent to omitting it (sz=rz=0), but needed for LoS/Rician or
%     %   when coherent phase structure matters.
%     %
%     % KEY FIX: Use ndgrid (not meshgrid) for consistent dimension ordering
%     % with kron(Fy, Fx), and apply ifftshift to align APD peak with DFT DC.
%     % APD computed in physical wavenumber space for consistency with
%     % select_center_modes_2d and the paper's propagation disk model.
% 
%     % Default: half-wavelength spacing
%     if nargin < 7 || isempty(dx)
%         dx = 0.5;
%     end
%     if nargin < 8 || isempty(dy)
%         dy = 0.5;
%     end
%     if nargin < 9 || isempty(sz)
%         sz = 0;
%     end
%     if nargin < 10 || isempty(rz)
%         rz = 0;
%     end
% 
%     rng(seed);
% 
%     Mr = Mrx*Mry;
%     Ms = Msx*Msy;
% 
%     % Aperture sizes in wavelengths
%     Lsx = Msx * dx;   % e.g., 7*0.5 = 3.5 lambda
%     Lsy = Msy * dy;   % e.g., 3*0.5 = 1.5 lambda
%     Lrx = Mrx * dx;
%     Lry = Mry * dy;
% 
%     % Unitary 2D DFT matrices (beamspace)
%     Ur = make_2d_dft(Mrx, Mry);  % Mr x Mr
%     Ut = make_2d_dft(Msx, Msy);  % Ms x Ms
% 
%     % Use NDGRID (not meshgrid) for consistent ordering with kron(Fy, Fx)
%     % ndgrid: first output varies along first dimension (rows = x index)
%     % This matches the vec() convention: linear_idx = ix + (iy-1)*Mx
% 
%     % Centered wavenumber index grids (shift coordinates: DC at center)
%     kx_s = (0:Msx-1) - floor(Msx/2);  % e.g., for Msx=7: [-3,-2,-1,0,1,2,3]
%     ky_s = (0:Msy-1) - floor(Msy/2);  % e.g., for Msy=3: [-1,0,1]
%     [KX_s, KY_s] = ndgrid(kx_s, ky_s);   % (Msx x Msy) - first dim is x
% 
%     kx_r = (0:Mrx-1) - floor(Mrx/2);
%     ky_r = (0:Mry-1) - floor(Mry/2);
%     [KX_r, KY_r] = ndgrid(kx_r, ky_r);   % (Mrx x Mry)
% 
%     % Map discrete indices to PHYSICAL wavenumber (units: 1/lambda, omitting 2*pi)
%     % kappa_x = kx / Lx,  kappa_y = ky / Ly
%     KX_s_phys = KX_s / Lsx;
%     KY_s_phys = KY_s / Lsy;
%     KX_r_phys = KX_r / Lrx;
%     KY_r_phys = KY_r / Lry;
% 
%     % ===== APD from function_computeVar (paper-style Fourier random coefficients) =====
%     % Lsx,Lsy,Lrx,Lry are in wavelengths. Must be integers.
%     assert(abs(Lsx - round(Lsx)) < 1e-12 && abs(Lsy - round(Lsy)) < 1e-12, ...
%         'Lsx,Lsy must be integers (in lambda) to use function_computeVar.');
%     assert(abs(Lrx - round(Lrx)) < 1e-12 && abs(Lry - round(Lry)) < 1e-12, ...
%         'Lrx,Lry must be integers (in lambda) to use function_computeVar.');
% 
%     % function_computeVar returns std on grid size (2Ly x 2Lx):
%     % rows correspond to ky (m index), cols correspond to kx (l index),
%     % and DC is at the CENTER (fftshift order).
%     [std_s_my_mx, ~] = function_computeVar(Lsx, Lsy);  % size should be (Msy x Msx) = 4x6
%     [std_r_my_mx, ~] = function_computeVar(Lrx, Lry);  % size should be (Mry x Mrx) = 4x6
% 
%     % Sanity check: dimensions must match
%     assert(isequal(size(std_s_my_mx), [Msy, Msx]), 'std_s size mismatch: expected [Msy,Msx].');
%     assert(isequal(size(std_r_my_mx), [Mry, Mrx]), 'std_r size mismatch: expected [Mry,Mrx].');
% 
%     % Transpose to match ndgrid ordering: (Msx x Msy) and (Mrx x Mry)
%     std_s_shift = std_s_my_mx.';  % 6x4, DC at center
%     std_r_shift = std_r_my_mx.';  % 6x4, DC at center
% 
%     % Convert std -> power
%     Ps_shift = std_s_shift;
%     Pr_shift = std_r_shift;
%     prop_mask_s = (KX_s_phys.^2 + KY_s_phys.^2) <= 1.0;
%     prop_mask_r = (KX_r_phys.^2 + KY_r_phys.^2) <= 1.0;
%     % Apply propagation disk mask (your masks are already in centered coords)
%     Ps_shift = Ps_shift .* prop_mask_s;
%     Pr_shift = Pr_shift .* prop_mask_r;
% 
%     % CRITICAL: move DC from center to (1,1) exactly ONCE
%     Ps = ifftshift(Ps_shift);
%     Pr = ifftshift(Pr_shift);
% 
%     % Normalize
%     Ps = Ps / sum(Ps(:));
%     Pr = Pr / sum(Pr(:));
%     % % 2D APD: isotropic Gaussian in PHYSICAL wavenumber space
%     % % P(kappa) = exp(-(kappa_x^2 + kappa_y^2) / (2*sigma_ang^2))
%     % % This is isotropic in physical space even when Mx != My or dx != dy
%     % Ps_shift = exp(-(KX_s_phys.^2 + KY_s_phys.^2) / (2*sigma_ang^2));
%     % Pr_shift = exp(-(KX_r_phys.^2 + KY_r_phys.^2) / (2*sigma_ang^2));
%     % 
%     % % MASK OUT EVANESCENT MODES: set APD = 0 where kappa^2 > 1
%     % % For d in lambda units, the propagation disk is kappa_x^2 + kappa_y^2 <= 1.
%     % % Evanescent modes (outside the disk) carry no far-field energy.
%     % % This ensures sqrt(1 - kappa^2) in gamma is always real (no need for max).
%     % prop_mask_s = (KX_s_phys.^2 + KY_s_phys.^2) <= 1.0;
%     % prop_mask_r = (KX_r_phys.^2 + KY_r_phys.^2) <= 1.0;
%     % Ps_shift = Ps_shift .* prop_mask_s;
%     % Pr_shift = Pr_shift .* prop_mask_r;
%     % 
%     % % CRITICAL: Apply ifftshift to move DC from center to index (1,1)
%     % % This aligns the APD with DFT native indexing where DC is at index 1
%     % Ps = ifftshift(Ps_shift);
%     % Pr = ifftshift(Pr_shift);
%     % 
%     % % Normalize
%     % Ps = Ps / sum(Ps(:));
%     % Pr = Pr / sum(Pr(:));
% 
%     Ps_vec = Ps(:).';   % 1 x Ms, now DC (max power) is at index 1
%     Pr_vec = Pr(:);     % Mr x 1, now DC (max power) is at index 1
% 
%     Sigma2 = Pr_vec * Ps_vec;  % Mr x Ms
%     Sigma2 = Sigma2 / sum(Sigma2(:));
% 
%     Hw = (randn(Mr,Ms)+1j*randn(Mr,Ms))/sqrt(2);
%     Hw_weighted = Hw .* sqrt(Sigma2);
% 
%     % ---- z-direction propagation phase: Gamma_s, Gamma_r (paper Eq.(31)) ----
%     % gamma(kx,ky) = 2*pi * sqrt(1 - kx_phys^2 - ky_phys^2)
%     % Evanescent modes (kappa^2 > 1) have already been masked to zero APD,
%     % so Hw_weighted = 0 for those modes and their gamma is irrelevant.
%     % No max(arg,0) needed — the mask guarantees arg >= 0 where it matters.
%     if sz ~= 0 || rz ~= 0
%         % Tx side: gamma_s in centered (shift) coords, then ifftshift
%         arg_s = 1 - (KX_s_phys.^2 + KY_s_phys.^2);
%         gamma_s_shift = 2*pi * sqrt(arg_s .* prop_mask_s);  % (Msx x Msy)
%         gamma_s = ifftshift(gamma_s_shift);
%         gamma_s_vec = gamma_s(:);                            % Ms x 1
% 
%         % Rx side: gamma_r in centered (shift) coords, then ifftshift
%         arg_r = 1 - (KX_r_phys.^2 + KY_r_phys.^2);
%         gamma_r_shift = 2*pi * sqrt(arg_r .* prop_mask_r);  % (Mrx x Mry)
%         gamma_r = ifftshift(gamma_r_shift);
%         gamma_r_vec = gamma_r(:);                            % Mr x 1
% 
%         % Phase vectors (paper Eq.(31)):
%         %   e^{-j * gamma_s * sz}  for Tx side
%         %   e^{+j * gamma_r * rz}  for Rx side
%         Ds = exp(-1j * gamma_s_vec * sz);   % Ms x 1
%         Dr = exp( 1j * gamma_r_vec * rz);   % Mr x 1
% 
%         % Apply: Htilde = diag(Dr) * Hw_weighted * diag(Ds)
%         % Using implicit expansion: (Mr x 1) .* (Mr x Ms) .* (1 x Ms)
%         Hw_weighted = (Dr .* Hw_weighted) .* (Ds.');
%     end
% 
%     H = Ur * Hw_weighted * Ut';  % WDM Applying WDM to the NLoS component yields H=Ur​Ha​UsH​ Ha​=A(k,κ)W(k,κ)
% end

% 
% function U = make_2d_dft(Mx, My)
%     Fx = dftmtx(Mx)/sqrt(Mx);
%     Fy = dftmtx(My)/sqrt(My);
%     U  = kron(Fy, Fx);  % (My*Mx) x (My*Mx)
% end

function H = beamspace_apd_channel_2d(Mr, Ms, Sigma2, Dr, Ds, seed, Ur_plain, Us_plain)
    % 快速版：所有大尺度参数(Sigma2, Dr, Ds, Ur_plain, Us_plain)都在外部算好传进来
    % Ur_plain: Mr x Mr full receive plain Fourier basis columns
    % Us_plain: Ms x Ms full transmit plain Fourier basis columns
    % Spatial synthesis: H_phys = Ur_plain * H_a * Us_plain^H
    rng(seed);
    
    % 1. 掷骰子：生成小尺度随机白噪声
    Hw = (randn(Mr,Ms)+1j*randn(Mr,Ms))/sqrt(2);
    
    % 2. 乘方差：H_a = W * sqrt(Sigma2)
    Hw_weighted = Hw .* sqrt(Sigma2);

    % 3. 乘相位：(Eq. 34)
    Hw_weighted = (Dr .* Hw_weighted) .* (Ds.');

    % 4. 转换回空间域
    H = Ur_plain * Hw_weighted * Us_plain';
end