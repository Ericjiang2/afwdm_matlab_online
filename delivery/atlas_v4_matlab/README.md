# Atlas v4 MATLAB Delivery Code

这是一套干净交付版 MATLAB 入口，用来向老师解释最新 atlas v4 结果是怎么从代码跑出来的。

主入口:

```matlab
mode = "quick";
run_capacity = false;
run('delivery/atlas_v4_matlab/main_atlas_v4_delivery.m')
```

当前建议主图入口:

```matlab
mode = "paperfig";
run('delivery/atlas_v4_matlab/main_atlas_v4_delivery.m')
```

MATLAB Online 推荐断点续跑入口:

```matlab
run('delivery/atlas_v4_matlab/run_delivery_online_resumable.m')
```

最新 strict-isotropic 8x8、`N_s=60` 的 GaBP-only 自适应 BER 入口：

```matlab
addpath('delivery/atlas_v4_matlab');
package = run_online_iso_gabp_sweep();
```

该入口只生成 GaBP 的六条曲线：
`AFWDM / DFT_precoded / SVD_paper` ×
`perfect CSI / fixed-var CSI (sigma_e^2=5e-4)`。图中平均参考 SNR 固定为
`0:5:20 dB`，内部每流 SNR 自动按
`SNR_stream=SNR_average-10log10(60)` 换算为约
`[-17.7815 -12.7815 -7.7815 -2.7815 2.2185] dB`。不重跑也不绘制已有
LMMSE 数据。每条曲线独立统计：
至少 5 帧，累计 100 errors 后停止，最多 200 帧；因此同一 SNR 下六条
曲线的最终帧数可以不同。每个共享 frame 使用相同信道实现、bits 和单位噪声，
但 imperfect-CSI 检测器只接收 `H_hat`，真实传播始终使用 `H_real`。

运行按 SNR 保存原子 checkpoint。重复同一命令会读取
`_ACTIVE_ISO_GABP_SWEEP_V3_ID.txt` 并续跑；配置、代码指纹、Git commit 或 MATLAB
release 不一致时会明确报 `manifestMismatch`，不会静默拼接数据。最终目录包含
MAT、逐曲线 CSV 和仅含六条 GaBP 曲线的 PNG。零观测误码点在图中按
95% rule-of-three 上界 `3/bit_count` 标记，原始 `errors/bits/frames` 仍完整保存。
方案名、CSI 标签、SNR/停止规则和最终资产文件名只在
`make_delivery_config("iso_gabp_adaptive")` 中定义；runner、CSV、MAT 和绘图
均从该配置或其生成的 `package` 读取，避免维护第二套标签。

v2 引入与四点枚举数学等价的闭式 QPSK Gaussian posterior，避免每次 GaBP
迭代对四个星座点执行多轮全矩阵 `exp`。`max_iterations=40` 和
`tolerance=1e-3` 未改变。v3 只改变 SNR 口径和网格，同时在 MAT/CSV 中保存
`SNR_average_reference_dB` 与 `SNR_stream_dB`。旧 v1/v2
active-id/checkpoint 保留为历史，但不能被 v3 续跑。

本次六线时间波形筛查的专用入口:

```matlab
run('delivery/atlas_v4_matlab/run_online_fullstream_waveform_screen.m')
```

strict-ISO、perfect-CSI、full、15 dB 的 SVD_paper 单点补跑入口：

```matlab
run('delivery/atlas_v4_matlab/run_online_iso_svd_perfect_snr15_tail.m')
```

默认补跑 750 帧，是已完成 AFWDM 1500 个 tail 帧的一半；按 100 帧分块，
最后一块 50 帧。`frame_start_offset=100` 使其与 AFWDM tail 的前 750 帧共享
frame seeds。输出保留逐块和汇总的帧数、bit 数、错误数及 BER；零错误按
rule-of-three 上界解释。重复同一命令会在 `RUN_CONTRACT.mat` 一致时续跑。

同一口径的 SVD_paper 20 dB error-floor 诊断入口：

```matlab
run('delivery/atlas_v4_matlab/run_online_iso_svd_perfect_snr20_tail.m')
```

默认 2250 帧，是上述 15 dB SVD 补跑 750 帧的 3 倍；仍按 100 帧分块，
最后一块 50 帧。它使用独立 run id、active file 和 `RUN_CONTRACT.mat`，不会
误接 15 dB checkpoint；`frame_start_offset=100` 使前 750 帧与 15 dB 补跑
共享 frame seeds，便于比较同一批信道实现。该单点只用于检查瀑布区是否继续
下降；是否形成 error floor 仍须结合 raw error/bit 数和相邻 SNR 点判断。

AFWDM vs OFWDM 时间分集正式入口:

```matlab
addpath('delivery/atlas_v4_matlab');
run_online_time_diversity();
```

首次建议先跑约 4--6 小时的自适应 pilot：

```matlab
addpath('delivery/atlas_v4_matlab');
package = run_online_time_diversity('time_diversity_pilot', ...
    'time_diversity_pilot_v5_20260715');
```

pilot 与正式版使用相同的 7 点 SNR、物理参数、检测器、公平配对和停止逻辑：
每点至少 10 帧，较优臂累计 100 errors 后立即停止；差别仅是高 SNR 的
兜底上限从 1500 降到 150 帧。本机标定的 7 点基线全满约 4.2 小时，
加上条件阶段通常约 4--6 小时。pilot 的 noise-limited 点和统计量只用于
选正式运行范围、检查耗时与趋势，不作为 production claim。

针对 pilot 中 GaBP 全部或几乎零错，使用新的低 SNR 诊断 profile：

```matlab
addpath('delivery/atlas_v4_matlab');
package = run_online_time_diversity('time_diversity_low_snr_pilot', ...
    'time_diversity_low_snr_pilot_v6_20260715');
```

该 profile 使用 `[-10 -6 -2 0 2 8 10 12] dB`，只跑 WDM、`Lch=6`、
integer/fractional Doppler 和 Block-LMMSE/GaBP。每点仍采用 10--150 帧、
100-error 自适应停止，但禁用后续条件升级；SISO anchor 仅在 0 dB 跑 1 帧。
它用于同时定位 GaBP 的低 SNR 转折和 Block-LMMSE 的 8--12 dB 转折，
不是 production profile，也不复用旧 pilot 的 run id/checkpoint。

低 SNR 审计后的独立 4 dB 补点入口：

```matlab
addpath('delivery/atlas_v4_matlab');
package = run_online_time_diversity('time_diversity_4db_followup', ...
    'time_diversity_4db_followup_v7_20260716');
```

该 profile 只跑 4 dB、WDM、`Lch=6`、两种 Doppler 和两种 detector，保持
10--150 帧/100 errors、GaBP 20 iterations 和禁用条件升级。GaBP 函数允许
最多 60 iterations 仅用于本地敏感性诊断；4 dB 补点不采用该诊断上限，因而
可与 v6 的 20-iteration 结果直接比较。

Fractional GaBP 单变量阶段探索入口：

```matlab
addpath('delivery/atlas_v4_matlab');
package = run_online_time_diversity( ...
    'time_diversity_fractional_gabp_exploration', ...
    'time_diversity_fractional_gabp_exploration_v9_20260717');
```

该 candidate profile 只跑 fractional Doppler、WDM 和
`[-8 -6 -4 -2 0 1 2 4] dB`，每点 10--500 帧/100 errors。GaBP 两臂统一使用
40 iterations；supplemental per-stream LMMSE 在所有阶段同时运行，不根据结果
选择性加入。一个入口依次执行并 checkpoint：`Lch6/kmax2/tau32` 锚点、
`Lch8/kmax2/tau32`、`Lch8/kmax3@1100kmh/tau32`、
`Lch8/kmax3@1100kmh/tau48`。各阶段只改变一类物理量，最后一个阶段的
`kmax=3,lmax=7,diversity_lhs=55<64`。输出是 exploration evidence，不是
production result；浏览器中断后使用同一 v9 run id 续跑。v8 的 5 点/300 帧
checkpoint 与结果只保留作历史证据，不得混入本次 v9 重跑。

Lch6、tau=48 us 独立 follow-up 入口：

```matlab
addpath('delivery/atlas_v4_matlab');
package = run_time_diversity_lch6_tau48_followup();
```

该入口固定使用 run id `time_diversity_lch6_tau48_followup_v10_20260718`，
重复执行会续跑同一批兼容 checkpoint。它只跑一个
`Lch=6, kmax=2@860km/h, tau_max=48 us` 阶段，以原 v9
`Lch6/kmax2/tau32` 为单变量对照；SNR 仍为
`[-8 -6 -4 -2 0 1 2 4] dB`，10--1000 帧/100 errors，只保留 fractional
WDM GaBP，双臂共同 40 iterations。导出的维度审计应为
`kmax=2,lmax=7,diversity_lhs=39<64`。1000 是兜底上限；已达到 100 errors
的低 SNR 点仍会提前停止。该输出是 candidate follow-up，不是 production
result，也不得复用 v9 checkpoint。

正式入口使用 `time_diversity_online` 配置，按“阶段 × SNR”保存 checkpoint；浏览器
中断后重跑同一命令会复用 `_ACTIVE_TIME_DIVERSITY_RUN_ID.txt` 并跳过已完成点。
每个 run/stage 都保存配置、代码、seed 与场景指纹；指纹不一致时会明确失败，
必须换新的 run id，禁止静默混用旧 checkpoint。
正式配置锁定 `4x4`、`N_s=m_s=11`、`Nblk=64`、QPSK，并使用
`[8 10 12 14 17 20 23] dB` 的非均匀 SNR 网格：目标 BER 附近保留 2 dB
分辨率，高 SNR 尾部改为 3 dB 间隔并去掉最耗时的 26/28 dB 点。同时跑
integer/fractional Doppler 与 block-LMMSE/GaBP。基线包含 WDM 主隔离、DFT
robustness 和 SVD 附录；条件升级只跑证据触发的 Doppler 子场景和 WDM 主对。
GaBP 两臂共用 damping 0.4、最多 20 次迭代和 `1e-3` 相对消息阈值；结果同时
保存逐帧最终 residual、平均 residual、平均迭代数与未收敛率，禁止只调一臂。
最终 MAT、主图、适用阶段的 SVD 附录与四行定量表写入
`outputs/online_runs/<run_id>/final/`。固定名称产物对应最后一个证据阶段；
`time_diversity_baseline_*` 明确保留 Lch=6 基线。最终 MAT 同时保存
`final_stage`、`final_results` 和机器可读 `outcome`。SISO anchor 仅保存在 MAT 内部诊断字段，
不会进入交付图。低误码点未达到错误数门槛时标为 `noise_limited`，不会据此
触发升级或绘制伪测量点。

其默认设置为 strict-isotropic、4x4、`N_s=m_s=11`（main.pdf Eq.(4)-(5)
中心格椭圆，不是 atlas overlap/nomask 的 16 个候选 bin）、高多普勒
`860 km/h`、`tau_max=32 us`、分数 Doppler、20 帧和 `-10:5:20 dB`。该入口
按 SNR checkpoint，可在 MATLAB Online 中断后直接重跑。

如果浏览器或会话中断，重新运行同一条命令即可。BER 和 low-MIMO
会按每个 SNR 点写 checkpoint；per-SNR task 只保存 `.mat`，不导出单点
PNG，已完成 SNR 点会跳过；最终多 SNR 图会从这些 per-SNR `.mat` 合并生成到
`delivery/atlas_v4_matlab/outputs/online_runs/<run_id>/final/`。

`quick` 默认只跑最小 BER 流程: `cv=1.0` isotropic-like、perfect CSI、`AFWDM / DFT_precoded / SVD_paper`、`full + adaptive`。这是给 MacBook Air 和课堂解释用的轻量验收模式，所以会临时把 `N_s` cap 到 8；它用于检查流程，不用于报告 atlas 数字。

`smoke` 是信息量稍大的本机验收: 仍然 `N_s` cap 到 8，但跑 `cv=1.0 / 0.30`、`SNR=[0,10]`、`kappa=[0,0.1]`、每点 2 帧，用来检查 CSI、各向异性和多 SNR 维度是否都通。

`fullmini` 是最轻量 full-load 验收: 不 cap `N_s`，只跑 strict isotropic reference、`SNR=5`、`kappa=0`、3 帧、`full` 策略。它用于验证代码能跑通 `ms=Nstreams=60` 的完整 block channel + LMMSE 链路，并和 atlas `ber3-iso-perfect` 作量级对照。

`local2min` 是约 2 分钟的本机验收: 仍然 `N_s` cap 到 8，但跑 `cv=1.0 / 0.30`、`SNR=[0,5,10]`、`kappa=[0,0.1]`、每点 20 帧，并默认跑一个很小的 capacity sweep。

`paper` 对齐最新 atlas v4 范围: BER 使用 `cv=1.0 / 0.10 / 0.30`、`kappa=[0,0.1,1.0]`、`SNR=-5:5:15`；capacity 使用 `cv=[0.01,0.30,1.00]`、固定噪声、water-filling 扫总功率。完整 `paper` 模式建议在 Win MATLAB 或远程机器跑。

`paperfig` 是新的交付主图模式:

- Fig.1: strict isotropic BER, `full` only, perfect CSI + `fixed_var` CSI (`sigma_e^2=5e-4`) 合在一张 6 线图。
- Fig.2: vMF `cv=0.30` anisotropic BER, 同样 perfect + fixed-var 6 线图。
- Fig.3: raw doubly-selective channel capacity, no precoder loop, `sigma2=1`, `P_dBW=0:5:30`, water-filling。
- Fig.4: strict isotropic low-MIMO reveal, `4x4`, `N_s=1`, `v=860 km/h`, `tau_max=32 us`, fractional Doppler, 6 线: `AFWDM`, `AFDM+DFT`, `AFDM+SVD`, `OFWDM`, `OFDM+DFT`, `OFDM+SVD`。

## 代码结构

- `main_atlas_v4_delivery.m`: 老师主要看的主脚本，保留完整 BER 主循环。
- `make_delivery_config.m`: `quick` / `paper` 参数。
- `prepare_delivery_scenario.m`: 显式准备 PAS、`Sigma2`、`Sigma2_p`、`cfg_base`、`Dr/Ds`，不调用旧 `AFDM_AFWDM_Compare.m`。
- `select_modes_atlas_v4.m`: 最新 atlas v4 overlap/nomask 模式选择，含 `full` 和 `adaptive`。
- `select_modes_main_eq45_reference.m`: main.pdf Eq.(4)-(5) strict center ellipse 对照代码，默认不用。
- `run_delivery_capacity.m`: 可选 capacity helper。
- `run_delivery_online_resumable.m`: MATLAB Online 断点续跑 wrapper，BER/low-MIMO 按 SNR 点保存并最后合并主图。
- `merge_delivery_config.m`: 小型递归配置覆盖 helper，让 Online runner 能指定单个 SNR 和输出目录而不污染主配置表。
- `plot_delivery_results.m`: 保存 `.png`。
- `run_online_iso_gabp_sweep.m`: strict-ISO 8x8/`N_s=60` 的 GaBP-only
  自适应停止、断点续跑和最终打包入口。
- `plot_iso_gabp_results.m`: 只绘制三种方案 × 两种 CSI 的六条 GaBP 曲线。
- `../../simulate_imperfect_csi_gabp_frame.m`: 显式分离 `H_real` 传播和
  `H_detector` GaBP 检测的单帧内核。
- `pilot_demo_embedded_channel_estimation.m`: 独立 pilot 原型，不进入四张主图。

## 口径说明

- BER 横轴是 per-symbol unit-QAM SNR，`N0=1/SNR`。
- `paper` 仍可使用 `snr_coupled` simulated-pilot model: `sigma_e^2 = kappa/(SNR*Lch)`。
- `paperfig` 重新启用 `fixed_var`: `sigma_e^2=val`, 与 SNR 解耦，用来显示 error floor。
- 信道采用 main.pdf Eq.(32) 对应的 `sqrt(Mr*Ms)*sqrt(Sigma2_p)` per-path scaling，不做 frame-level renormalization。
- 最新 atlas v4 模式选择使用 overlap/nomask；这和 main.pdf Eq.(4)-(5) 的 strict center-lattice ellipse 不完全一致，reference helper 已保留用于解释差异。
- `cv=1.0` 在本交付版默认作为 isotropic-like vMF；严格 isotropic reference 可通过 `prepare_delivery_scenario` 的 `pas_model='isotropic_reference'` 使用，但默认不跑。

## 验收标准

- `quick` 模式能生成一个 `.mat` 和至少一张 BER `.png`。
- 主脚本从参数、PAS、模式选择、信道、CSI、block channel、LMMSE 到保存结果的流程可顺读。
- `paperfig` 生成 4 张主图 PNG，BER 图 y 轴使用 decade ticks。
- `fixed_var` 仅用于 controlled CSI-error floor 图；`snr_coupled` 仍保留给 atlas v4 口径。
- `select_modes_atlas_v4.m` 同时支持 `full` 和 `adaptive`。
- `select_modes_main_eq45_reference.m` 存在但不参与默认主流程。
- `prepare_delivery_scenario.m` 不再 `run` 旧 wrapper。
- 保存的 `metadata` 说明 SNR、CSI、channel scaling 和 mode selector 口径。
