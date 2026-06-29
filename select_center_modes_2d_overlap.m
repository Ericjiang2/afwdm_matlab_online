function [idx, n_propagating] = select_center_modes_2d_overlap(Mx, My, m, dx, dy)
    % SELECT_CENTER_MODES_2D_OVERLAP  Select 2D DFT modes via bin-overlap criterion
    % (propagation disk: any bin corner inside kappa^2 <= 1 qualifies).
    %
    % DIFFERS FROM select_center_modes_2d:
    %   - select_center_modes_2d: bin CENTER kappa^2 <= 1  (47 modes for 8x8 UPA)
    %   - THIS FUNCTION: bin MIN-CORNER kappa^2 <= 1       (60 modes for 8x8 UPA)
    %
    % PHYSICAL MOTIVATION:
    %   Grazing waves (theta->pi/2) couple to edge bins. Center criterion discards
    %   13 edge bins carrying ~24% energy (ISO 8x8). Overlap criterion preserves
    %   physical fidelity by including bins with partial disk overlap.
    %
    % TWO MODES OF OPERATION:
    %   m = 0  ('auto'):  return ALL modes with bin overlap to propagation disk.
    %                     Mode count determined by bin geometry.
    %   m > 0  ('fixed'): return exactly m modes sorted by ascending |kappa|.
    %                     Warns if m exceeds the overlapping mode count.
    %
    % Physical wavenumber for discrete index (kx, ky):
    %   kappa_x = kx / (Mx*dx),  kappa_y = ky / (My*dy)   (dx,dy in lambda units)
    %
    % Bin rectangle for (kx, ky):
    %   kappa_x in [kx/Lx, (kx+1)/Lx],  kappa_y in [ky/Ly, (ky+1)/Ly]
    %
    % Overlap criterion:
    %   min(corner kappa^2 over 4 bin corners) <= 1.0
    %
    % Inputs:
    %   Mx, My - array dimensions (number of elements)
    %   m      - number of modes to select (0 = auto, >0 = fixed)
    %   dx, dy - element spacing in units of lambda (default 0.5)
    %
    % Outputs:
    %   idx           - column vector of selected DFT linear indices (1-based)
    %   n_propagating - total number of modes with bin overlap to disk
    %
    % EXAMPLE:
    %   % 8x8 UPA, half-wavelength spacing
    %   [idx, n] = select_center_modes_2d_overlap(8, 8, 0, 0.5, 0.5);
    %   % n = 60 (vs 47 from select_center_modes_2d)
    %
    % See also: select_center_modes_2d

    % Default: half-wavelength spacing
    if nargin < 4 || isempty(dx)
        dx = 0.5;
    end
    if nargin < 5 || isempty(dy)
        dy = 0.5;
    end

    Lx = Mx * dx;  % aperture in wavelengths
    Ly = My * dy;

    % Centered wavenumber index ranges (shifted coordinates)
    kx = (-floor(Mx/2):ceil(Mx/2)-1);   % length Mx
    ky = (-floor(My/2):ceil(My/2)-1);   % length My

    cand = [];
    for iy = 1:length(ky)
        for ix = 1:length(kx)
            % Bin corners in physical wavenumber space
            kx_vals = [kx(ix), kx(ix)+1] / Lx;
            ky_vals = [ky(iy), ky(iy)+1] / Ly;

            % Four corners: (kx_min, ky_min), (kx_min, ky_max), ...
            r2_corners = [kx_vals(1)^2 + ky_vals(1)^2, ...
                          kx_vals(1)^2 + ky_vals(2)^2, ...
                          kx_vals(2)^2 + ky_vals(1)^2, ...
                          kx_vals(2)^2 + ky_vals(2)^2];

            % Overlap criterion: min corner kappa^2 <= 1.0
            r2_min = min(r2_corners);

            % For sorting: use bin CENTER kappa (same as select_center_modes_2d)
            r2_center = (kx(ix)/Lx)^2 + (ky(iy)/Ly)^2;

            % Map centered index to DFT native index (1-based, DC at index 1)
            ix0 = mod(kx(ix), Mx) + 1;
            iy0 = mod(ky(iy), My) + 1;
            lin = ix0 + (iy0-1)*Mx;

            cand = [cand; r2_center, r2_min, lin]; %#ok<AGROW>
        end
    end

    % Sort by physical wavenumber radius (ascending = low-wavenumber first)
    cand = sortrows(cand, 1);  % sort by center kappa for consistency

    % Propagation cutoff: bin min-corner kappa^2 <= 1.0
    n_propagating = sum(cand(:,2) <= 1.0);

    if m == 0
        % AUTO mode: return all overlapping modes
        idx = cand(cand(:,2) <= 1.0, 3);
    else
        % FIXED mode: return exactly m modes (warn if exceeding disk)
        if m > n_propagating
            warning('select_center_modes_2d_overlap: Requested m=%d exceeds %d overlapping modes (d/lambda=[%.2f,%.2f]).', ...
                    m, n_propagating, dx, dy);
        end
        % Take first m modes from sorted list (lowest kappa first)
        overlap_idx = cand(:,2) <= 1.0;
        candidates = cand(overlap_idx, :);
        if m <= size(candidates, 1)
            idx = candidates(1:m, 3);
        else
            % Pad with next-closest modes if m > n_propagating
            idx = [candidates(:,3); cand(~overlap_idx, 3)];
            idx = idx(1:m);
        end
    end
end
