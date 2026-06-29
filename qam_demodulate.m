function bits = qam_demodulate(symbols, QAM_order)
    % QAM_DEMODULATE  Gray-coded QAM hard-decision demodulation.
    %
    % Inputs:
    %   symbols   - complex column vector of (noisy) QAM symbols
    %   QAM_order - modulation order (4, 16, 64, ...)
    %
    % Output:
    %   bits      - column vector of hard-decided bits

    sym_idx = qamdemod(symbols, QAM_order, 'UnitAveragePower', true);
    k = log2(QAM_order);
    bits_mat = de2bi(sym_idx, k, 'left-msb');
    bits = bits_mat.';
    bits = bits(:);
end
