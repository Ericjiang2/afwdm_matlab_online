function symbols = qam_modulate(bits, QAM_order)
    % QAM_MODULATE  Gray-coded QAM modulation with unit average power.
    %
    % Inputs:
    %   bits      - column vector of bits (length = k * num_symbols)
    %   QAM_order - modulation order (4, 16, 64, ...)
    %
    % Output:
    %   symbols   - complex column vector of QAM symbols (num_symbols x 1)

    k = log2(QAM_order);
    bits_reshaped = reshape(bits, k, []).';
    sym_idx = bi2de(bits_reshaped, 'left-msb');
    symbols = qammod(sym_idx, QAM_order, 'UnitAveragePower', true);
end
