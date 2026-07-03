function ref = select_modes_main_eq45_reference(cfg, Sigma2)
%SELECT_MODES_MAIN_EQ45_REFERENCE  Strict main.pdf Eq.(4)-(5) reference.
%
% main.pdf Eq.(4)-(5):
%   E_s = { (l,m): kappa_s^2 <= 1 },  m_s = |E_s|
%   E_r = { (l,m): kappa_r^2 <= 1 },  m_r = |E_r|
%
% 这个函数只作为论文对照保留，不参与默认 atlas v4 delivery 主流程。
% 最新结果使用 select_modes_atlas_v4.m 的 overlap/nomask selector。

[idx_s_center, n_s_center] = select_center_modes_2d(cfg.Msx, cfg.Msy, 0, cfg.dx, cfg.dy);
[idx_r_center, n_r_center] = select_center_modes_2d(cfg.Mrx, cfg.Mry, 0, cfg.dx, cfg.dy);
idx_s_center = idx_s_center(:).';
idx_r_center = idx_r_center(:).';

col_e_s = sum(Sigma2, 1);
col_e_r = sum(Sigma2, 2).';
[~, o_s] = sort(col_e_s(idx_s_center), 'descend');
[~, o_r] = sort(col_e_r(idx_r_center), 'descend');

ref = struct();
ref.selector = 'main_pdf_eq4_eq5_center_ellipse_reference_only';
ref.idx_s = idx_s_center;
ref.idx_r = idx_r_center;
ref.sort_s = idx_s_center(o_s);
ref.sort_r = idx_r_center(o_r);
ref.N_s = min(n_s_center, n_r_center);
ref.N_r = ref.N_s;
ref.formula_status = 'Reference implementation of main.pdf Eq.(4)-(5); not used by latest atlas v4 delivery default.';

end
