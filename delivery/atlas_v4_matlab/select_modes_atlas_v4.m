function modes = select_modes_atlas_v4(cfg, Sigma2, adapt_power_floor)
%SELECT_MODES_ATLAS_V4  Latest atlas v4 overlap/nomask mode selection.
%
% 现役 atlas v4 做法:
%   1. 候选池: select_center_modes_2d_overlap(...), overlap/nomask
%   2. 排序: 在候选池内按 Sigma2 的 Tx/Rx marginal energy 降序
%   3. full: 使用全部非零 overlap modes
%   4. adaptive: 每模能量 >= adapt_power_floor * max_energy
%
% 和 main.pdf Eq.(4)-(5) 的差异:
%   main.pdf 写的是 center-lattice ellipse E_s/E_r, m_s=|E_s|;
%   最新 atlas v4 为保留跨边界 grazing bin, 使用 overlap/nomask。
%   严格 Eq.(4)-(5) 参考版见 select_modes_main_eq45_reference.m。

if nargin < 3 || isempty(adapt_power_floor)
    adapt_power_floor = 0.10;
end

[idx_s_prop, ~] = select_center_modes_2d_overlap(cfg.Msx, cfg.Msy, 0, cfg.dx, cfg.dy);
[idx_r_prop, ~] = select_center_modes_2d_overlap(cfg.Mrx, cfg.Mry, 0, cfg.dx, cfg.dy);
idx_s_prop = idx_s_prop(:).';
idx_r_prop = idx_r_prop(:).';

col_e_s = sum(Sigma2, 1);
col_e_r = sum(Sigma2, 2).';
[~, o_s] = sort(col_e_s(idx_s_prop), 'descend');
[~, o_r] = sort(col_e_r(idx_r_prop), 'descend');
sort_s = idx_s_prop(o_s);
sort_r = idx_r_prop(o_r);

max_s = max(col_e_s(idx_s_prop));
max_r = max(col_e_r(idx_r_prop));
nnz_modes = min( ...
    nnz(col_e_s(idx_s_prop) > 1e-12 * max_s), ...
    nnz(col_e_r(idx_r_prop) > 1e-12 * max_r));

N_full = min([cfg.ms, cfg.mr, nnz_modes]);
N_adapt = min( ...
    nnz(col_e_s(idx_s_prop) >= adapt_power_floor * max_s), ...
    nnz(col_e_r(idx_r_prop) >= adapt_power_floor * max_r));
N_adapt = max(1, min(N_adapt, N_full));

modes = struct();
modes.selector = 'atlas_v4_overlap_nomask';
modes.idx_s_prop = idx_s_prop;
modes.idx_r_prop = idx_r_prop;
modes.sort_s = sort_s;
modes.sort_r = sort_r;
modes.N_full = N_full;
modes.N_adapt = N_adapt;
modes.nnz_modes = nnz_modes;
modes.adapt_power_floor = adapt_power_floor;
modes.col_e_s = col_e_s;
modes.col_e_r = col_e_r;
modes.formula_status = ['Current atlas v4 implementation; differs from main.pdf ' ...
    'Eq.(4)-(5) center-lattice ellipse by using overlap/nomask candidates.'];

end
