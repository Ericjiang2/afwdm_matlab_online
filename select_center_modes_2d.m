function [idx, n_propagating] = select_center_modes_2d(Mx, My, m, dx, dy)
%SELECT_CENTER_MODES_2D Select 2D DFT modes whose centres lie in kappa^2 <= 1.
if nargin < 4 || isempty(dx); dx = 0.5; end
if nargin < 5 || isempty(dy); dy = 0.5; end

Lx = Mx * dx;
Ly = My * dy;
kx = -floor(Mx/2):ceil(Mx/2)-1;
ky = -floor(My/2):ceil(My/2)-1;
cand = [];
for iy = 1:numel(ky)
    for ix = 1:numel(kx)
        r2 = (kx(ix) / Lx)^2 + (ky(iy) / Ly)^2;
        ix0 = mod(kx(ix), Mx) + 1;
        iy0 = mod(ky(iy), My) + 1;
        cand = [cand; r2, ix0 + (iy0 - 1) * Mx]; %#ok<AGROW>
    end
end
cand = sortrows(cand, 1);
n_propagating = sum(cand(:, 1) <= 1.0);
if m == 0
    idx = cand(1:n_propagating, 2);
else
    if m > n_propagating
        warning('select_center_modes_2d:RequestedTooManyModes', ...
            'Requested %d modes but only %d lie in the propagation disk.', m, n_propagating);
    end
    idx = cand(1:m, 2);
end
end
