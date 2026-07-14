function [Us, Ur] = resolve_time_diversity_spatial_pair( ...
    spatial_pair, cfg, H_phys, Us_wdm, Ur_wdm, N_s)
%RESOLVE_TIME_DIVERSITY_SPATIAL_PAIR Shared spatial basis for both waveforms.

switch char(spatial_pair)
    case 'wdm'
        Us = Us_wdm;
        Ur = Ur_wdm;
    case 'dft'
        [Us, Ur] = build_dft_precoder(cfg.Ms, cfg.Mr, N_s, N_s);
    case 'svd'
        G = build_G_paper_eq31(H_phys, 'sum_taps');
        [Us, Ur] = svd_precoder_from_G(G, N_s, N_s);
    otherwise
        error('resolve_time_diversity_spatial_pair:unknownPair', ...
            'Unknown spatial pair "%s".', spatial_pair);
end
end
