function Sigma2_p = build_perpath_sigma(cfg)
% build_perpath_sigma  per-path 方差矩阵 Σ_p = A(:,pr)⊗B(:,ps) (论文 Eq.26 product 结构)
%
% 提自 smoke_perpath_sigmap.m (cc-0614-01/02)。
% 权重 = mass-implied (lsqnonneg 解, =F-F.1 取 b); 去 mask (=F-F.2 BER 中性, 不打传播盘 mask)。
% 守恒: Σ_p Sigma2_p == 去mask 聚合 Sigma2 (机器精度, 见 smoke CHECK1)。
%
% INPUT  cfg.vmf_mean_theta_deg / vmf_mean_phi_deg / vmf_circular_var (1×C 簇参数)
%        cfg.Mrx/Mry/Msx/Msy/dx/dy
% OUTPUT Sigma2_p  cell{1,P}, P=C², 每个 Mr×Ms per-path 方差 (ifftshift 域, 同 aggregate Sigma2)

mt = cfg.vmf_mean_theta_deg/180*pi;
mp = cfg.vmf_mean_phi_deg/180*pi;
cv = cfg.vmf_circular_var;
Pr = numel(mt); Ps = Pr; P = Pr*Ps;
Lrx=cfg.Mrx*cfg.dx; Lry=cfg.Mry*cfg.dy; Lsx=cfg.Msx*cfg.dx; Lsy=cfg.Msy*cfg.dy;
Mr=cfg.Mrx*cfg.Mry; Ms=cfg.Msx*cfg.Msy;

% 单瓣归一 var (function_channelVAR 内部 sum=1 each); 朝向 .' 对齐 Pr_shift_raw
NLr=zeros(Mr,Pr); NLs=zeros(Ms,Ps);
for pr=1:Pr; v=function_channelVAR(Lrx,Lry,function_channelPAS(cv(pr),mt(pr),mp(pr))).'; NLr(:,pr)=v(:); end
for ps=1:Ps; v=function_channelVAR(Lsx,Lsy,function_channelPAS(cv(ps),mt(ps),mp(ps))).'; NLs(:,ps)=v(:); end

% 聚合 var (mixture, cv 向量) — 复刻 Compare 的等密度混合
var_r=function_channelVAR(Lrx,Lry,function_channelPAS(cv,mt,mp)).'; var_r=var_r(:);
var_s=function_channelVAR(Lsx,Lsy,function_channelPAS(cv,mt,mp)).'; var_s=var_s(:);

% mass-implied 权重 (b): var_agg = NL*w, Σw=1, lsqnonneg 精确分解
wr=lsqnonneg(NLr,var_r); ws=lsqnonneg(NLs,var_s);

% 去 mask (F-F.2): 无传播盘 mask; ifftshift + 一致归一 (复刻 Compare Pr=ifftshift(Pr_shift)/sum)
Zr=sum(var_r); Zs=sum(var_s);
A=zeros(Mr,Pr); B=zeros(Ms,Ps);
for pr=1:Pr; t=ifftshift(reshape(wr(pr)*NLr(:,pr),cfg.Mrx,cfg.Mry)); A(:,pr)=t(:)/Zr; end
for ps=1:Ps; t=ifftshift(reshape(ws(ps)*NLs(:,ps),cfg.Msx,cfg.Msy)); B(:,ps)=t(:)/Zs; end

Sigma2_p=cell(1,P); p=0;
for pr=1:Pr
    for ps=1:Ps
        p=p+1;
        Sigma2_p{p}=A(:,pr)*B(:,ps).';
    end
end

sigma_mass_sum=0;
for p=1:P
    sigma_mass_sum=sigma_mass_sum+sum(Sigma2_p{p}(:));
end
mass_tol=1e-8;
if abs(sigma_mass_sum-1)>mass_tol
    error('build_perpath_sigma:massNotUnit', ...
        'Expected sum_p sum(Sigma2_p{p}(:)) = 1 within %.1e, got %.16g.', ...
        mass_tol, sigma_mass_sum);
end
end
