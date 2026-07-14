function labels = time_diversity_pair_labels(spatial_pair)
%TIME_DIVERSITY_PAIR_LABELS Spec-locked names for each paired comparison.

switch char(spatial_pair)
    case 'wdm'
        labels = {'AFWDM', 'OFWDM'};
    case 'dft'
        labels = {'AFDM-DFT', 'OFDM-DFT'};
    case 'svd'
        labels = {'AFDM-SVD', 'OFDM-SVD'};
    otherwise
        error('time_diversity_pair_labels:unknownPair', ...
            'Unknown spatial pair "%s".', spatial_pair);
end
end
