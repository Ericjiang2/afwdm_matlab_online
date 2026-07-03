function cfg_k = make_delivery_scheme_cfg(cfg_base, Us, Ur, N_s, cfg_run)
%MAKE_DELIVERY_SCHEME_CFG  Attach spatial bases and stream count to cfg.

cfg_k = cfg_base;
cfg_k.Us = Us;
cfg_k.Ur = Ur;
cfg_k.ms = N_s;
cfg_k.mr = N_s;
cfg_k.Nstreams = N_s;
cfg_k.Wbb_wdm = [];
cfg_k.Wbb_sdm = [];
cfg_k.Fbb_wdm = [];
cfg_k.Fbb_sdm = [];
cfg_k.block_lmmse_solver = cfg_run.block_lmmse_solver;
end
