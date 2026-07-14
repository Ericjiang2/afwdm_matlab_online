function [cfg_afwdm, cfg_ofwdm, audit] = make_time_diversity_waveform_pair( ...
    cfg_base, Us, Ur, N_s, cfg_run)
%MAKE_TIME_DIVERSITY_WAVEFORM_PAIR Build a pure temporal AFWDM/OFWDM pair.

if N_s ~= cfg_run.time_diversity.N_s
    error('make_time_diversity_waveform_pair:streamCount', ...
        'Time-diversity main pair requires N_s=%d, got %d.', ...
        cfg_run.time_diversity.N_s, N_s);
end

cfg_afwdm = make_delivery_scheme_cfg(cfg_base, Us, Ur, N_s, cfg_run);
cfg_afwdm.c1 = (2 * cfg_base.kmax + 1) / (2 * cfg_base.Nblk);
cfg_afwdm.c2 = 0.1 / cfg_base.Nblk;

cfg_ofwdm = cfg_afwdm;
cfg_ofwdm.c1 = 0;
cfg_ofwdm.c2 = 0;

same_spatial_basis = isequal(cfg_afwdm.Us, cfg_ofwdm.Us) && ...
    isequal(cfg_afwdm.Ur, cfg_ofwdm.Ur);
same_non_temporal = cfg_afwdm.Nstreams == cfg_ofwdm.Nstreams && ...
    cfg_afwdm.ms == cfg_ofwdm.ms && cfg_afwdm.mr == cfg_ofwdm.mr && ...
    strcmp(cfg_afwdm.block_lmmse_solver, cfg_ofwdm.block_lmmse_solver);

audit = struct();
audit.same_spatial_basis = same_spatial_basis;
audit.only_temporal_basis_differs = same_spatial_basis && same_non_temporal;
audit.N_s = N_s;
audit.afwdm_c1 = cfg_afwdm.c1;
audit.afwdm_c2 = cfg_afwdm.c2;
audit.ofwdm_c1 = cfg_ofwdm.c1;
audit.ofwdm_c2 = cfg_ofwdm.c2;

if ~audit.only_temporal_basis_differs
    error('make_time_diversity_waveform_pair:isolation', ...
        'AFWDM/OFWDM arms differ outside the temporal basis.');
end
end
