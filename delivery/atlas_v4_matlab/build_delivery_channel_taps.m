function H_phys = build_delivery_channel_taps(scenario, seed_base)
%BUILD_DELIVERY_CHANNEL_TAPS  Draw per-delay physical channel taps.

cfg = scenario.cfg;
if scenario.use_perpath_sigma
    Sig_taps = scenario.Sigma2_p;
else
    Sig_taps = repmat({scenario.Sigma2 / cfg.Lch}, 1, cfg.Lch);
end

H_phys = cell(1, cfg.Lch);
for ell = 1:cfg.Lch
    H_phys{ell} = beamspace_apd_channel_2d_perpath( ...
        cfg.Mr, cfg.Ms, Sig_taps{ell}, scenario.Dr, scenario.Ds, ...
        seed_base + ell, cfg.Ur_full, cfg.Us_full, ones(cfg.Ms,1), ones(cfg.Mr,1));
end
end
