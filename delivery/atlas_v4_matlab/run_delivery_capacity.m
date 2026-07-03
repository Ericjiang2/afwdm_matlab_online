function cap_results = run_delivery_capacity(cfg_run)
%RUN_DELIVERY_CAPACITY  Raw doubly-selective channel water-filling capacity.
%
% Capacity 不是 BER 的发送-接收主循环，所以放在 helper 中保持主脚本清爽。
% 当前交付图口径:
%   C = sum_i log2(1 + P_i*rho_i/sigma2), rho_i = svd(H_blk)^2
%   P_i from water-filling, sigma2 fixed, sweep total P_dBW.
%   H_blk uses full spatial aperture (Us=I, Ur=I): no AFWDM/DFT/SVD precoder loop.

nScenario = numel(cfg_run.capacity_scenarios);
nP = numel(cfg_run.capacity_P_dBW_list);
nFrame = cfg_run.capacity_numFrames;

Cap_wf = nan(nScenario, nP, nFrame);
labels = cell(1, nScenario);

for iScenario = 1:nScenario
    spec = cfg_run.capacity_scenarios(iScenario);
    labels{iScenario} = spec.label;
    scenario = prepare_delivery_scenario(cfg_run, spec);
    cfg_base = scenario.cfg;

    cfg_raw = cfg_base;
    cfg_raw.Us = eye(cfg_base.Ms);
    cfg_raw.Ur = eye(cfg_base.Mr);
    cfg_raw.ms = cfg_base.Ms;
    cfg_raw.mr = cfg_base.Mr;
    cfg_raw.Nstreams = min(cfg_base.Ms, cfg_base.Mr);

    for frm = 1:nFrame
        seed_base = cfg_run.seed.frame_stride * frm + ...
            cfg_run.seed.capacity_scenario_offset * iScenario;
        [tau_vec, nu_vec] = generate_phys_dd_paths(cfg_base, cfg_base.Lch, seed_base);
        H_phys = build_delivery_channel_taps(scenario, seed_base);
        H_blk = build_block_matrix_afwdm(H_phys, tau_vec, nu_vec, cfg_raw);
        rho = svd(H_blk).^2;
        rho = rho(rho > 1e-12);
        for iP = 1:nP
            Ptot = 10^(cfg_run.capacity_P_dBW_list(iP) / 10);
            P_wf = delivery_water_filling(rho, cfg_run.capacity_sigma2_fixed, Ptot);
            Cap_wf(iScenario, iP, frm) = ...
                sum(log2(1 + (P_wf .* rho) / cfg_run.capacity_sigma2_fixed));
        end
    end
end

cap_results = struct();
cap_results.Cap_wf = Cap_wf;
cap_results.P_dBW_list = cfg_run.capacity_P_dBW_list;
cap_results.labels = labels;
cap_results.scenarios = cfg_run.capacity_scenarios;
cap_results.numFrames = nFrame;
cap_results.sigma2_fixed = cfg_run.capacity_sigma2_fixed;
cap_results.capacity_mode = 'raw_full_aperture_no_precoding';
cap_results.capacity_formula = 'water-filling sum log2(1 + P_i*rho_i/sigma2), rho=svd(H_blk_raw)^2, fixed noise';

end

function P = delivery_water_filling(rho, sigma2, Ptot)
rho = rho(:);
rho_safe = max(rho, 1e-20);
idx = 1:numel(rho_safe);
P = zeros(numel(rho_safe), 1);
while ~isempty(idx)
    mu = (Ptot + sum(sigma2 ./ rho_safe(idx))) / numel(idx);
    P_try = mu - sigma2 ./ rho_safe(idx);
    if all(P_try >= 0)
        P(idx) = P_try;
        break;
    end
    keep = P_try > 0;
    if ~any(keep)
        break;
    end
    idx = idx(keep);
end
end
