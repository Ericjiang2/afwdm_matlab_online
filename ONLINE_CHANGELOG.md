# MATLAB Online Repo Log

This document is the lightweight change/provenance log for the standalone
`afwdm_matlab_online` repository. It records what changed, why it changed,
the expected effect, and the observed result. For MATLAB Online-only edits,
this file is the preferred log. The main research repo keeps only a compact
mirror/index at `docs/Matlab_Online_Repo_Log.md` so the two repos stay linked
without duplicating long notes everywhere.

## Current Workflow

- Main research repo remains local and is not pushed to the online GitHub repo.
- `tools/prepare_matlab_online_bundle.py` refreshes `matlab_online_repo/`.
- `matlab_online_repo/` is the only repository pushed to GitHub.
- MATLAB Online-only edits are logged first in this file.
- Main-repo `docs/Matlab_Online_Repo_Log.md` is a compact mirror/pointer; main
  `docs/Code_Changes.md` is used only when the online change also affects main
  wrappers, bundling/import tools, or experiment semantics.
- MATLAB Online users should run the specific `run_online_*.m` runner for the
  target experiment.
- Results are downloaded as `results/online_runs/<run_id>/` and imported into
  the main project with `tools/import_online_results.py`.

## Entries

### [online-20260710-02] Increase Full-Stream Screen to 200 Frames per SNR

**Changed**:
- The default `fullstream_screen_numFrames` in
  `run_online_fullstream_waveform_screen.m` is now `200` rather than `20`.

**Why**:
- The 20-frame screen can reveal a large error floor but has only 28,160 bits
  at each SNR point, which is insufficient to distinguish a low high-SNR
  plateau from zero observed errors.
- A direct 20-frame spatial-channel diagnostic for the exact 4x4/
  `N_s=m_s=11` setup found the 1D-DFT effective channel full rank (11/11) in
  every frame, unlike the 8x8 DFT case (57/60). The longer BER run tests the
  remaining statistical high-SNR behaviour, not a known structural rank loss.

**Expected effect**:
- The full sweep is 7 SNR points × 200 frames = 1,400 frames, approximately
  35–40 minutes from the measured local one-frame timing. The runner remains
  resumable per SNR point; a local smoke can still override the variable to 1.

---

### [online-20260710-01] Full-Stream Six-Line Waveform Screen

**Changed**:
- Added `delivery/atlas_v4_matlab/run_online_fullstream_waveform_screen.m`.
- Extended `run_delivery_online_resumable.m` with a profile that checkpoints
  this screen once per SNR point, then merges the six-line result.
- A string request `N_s='full'` in `run_low_mimo_precoding_ber.m` now uses
  `select_modes_main_eq45_reference`, i.e. main.pdf Eq.(4)-(5)'s centre
  ellipse, rather than the atlas overlap/nomask selector.
- Added `select_center_modes_2d.m` to make the strict selector self-contained
  in MATLAB Online.

**Why**:
- The old delivery Fig.4 used `N_s=1`, which changes the spatial-stream
  loading and can obscure the intended time-waveform comparison.
- For a 4x4 half-wavelength array, the paper-defined centre ellipse has
  `m_s=11`; the atlas overlap/nomask candidate set has 16 bins and must not be
  substituted for `m_s` in this experiment.

**Expected effect**:

```matlab
run('delivery/atlas_v4_matlab/run_online_fullstream_waveform_screen.m')
```

The default run is strict-isotropic, 4x4, `N_s=m_s=11`, `v=860 km/h`,
`tau_max=32 us`, fractional Doppler, QPSK, 20 frames per SNR, and
`SNR=-10:5:20`. It writes resumable per-SNR checkpoints under
`delivery/atlas_v4_matlab/outputs/fullstream_waveform_screen/online_runs/`.

**Result**:
- Local MATLAB R2025a one-frame/10 dB smoke passed on 2026-07-10.
- The saved result recorded `N_s=11`; the final generated figure was
  `ber_low_mimo_4x4_ns11_precoding.png`.

### [online-20260709-01] Strict-ISO AFWDM Perfect-CSI 15 dB Tail Runner

**Commit**: `22f5552`

**Changed**:
- Added
  `delivery/atlas_v4_matlab/run_online_iso_afwdm_perfect_snr15_tail.m`.
- Updated `delivery/atlas_v4_matlab/main_atlas_v4_delivery.m` progress
  printing to support single-scheme runs instead of assuming all three
  schemes are always enabled.
- The runner targets exactly one BER point:
  `strict_isotropic | AFWDM | full | perfect CSI | SNR=15 dB`.
- Default run is `1000` frames split into `100`-frame chunks.
- Default `frame_start_offset=100` continues after the existing paperfig
  `100` frames, avoiding duplicate seeds when pooling with the archived point.
- Each chunk writes a MAT file and checkpoint; rerunning skips completed chunks.
- Final combine writes
  `ISO_AFWDM_PERFECT_SNR15_TAIL_SUMMARY.txt` and a summary MAT containing
  raw `err_total`, `bit_total`, measured `BER`, and `half_error_marker`.

**Why**:
- The archived delivery figure plotted the AFWDM perfect-CSI 15 dB point near
  `1e-6` only because zero observed errors were displayed as
  `0.5 / bit_total` for log-scale visualization.
- The actual archived count was `0 errors / 768000 bits`.
- This runner accumulates additional bits for the same point so the high-SNR
  tail can be reported with raw error counts.

**Expected effect**:
- In MATLAB Online, run:

```matlab
run('delivery/atlas_v4_matlab/run_online_iso_afwdm_perfect_snr15_tail.m')
```

- Optional larger target:

```matlab
iso_afwdm_tail_total_frames = 1500;
run('delivery/atlas_v4_matlab/run_online_iso_afwdm_perfect_snr15_tail.m')
```

**Result**:
- Local MATLAB R2025a 1-frame smoke passed on 2026-07-09 with
  `iso_afwdm_tail_total_frames=1` and `iso_afwdm_tail_chunk_frames=1`.
- Smoke generated one chunk MAT and
  `ISO_AFWDM_PERFECT_SNR15_TAIL_SUMMARY.txt`, with `err=0`, `bits=7680`.
- Pending MATLAB Online execution for the default 1000-frame run.

### [online-20260708-04] 18x18 Aperture Capacity Magnitude Check

**Commit**: `93d4acf`

**Changed**:
- Added `delivery/atlas_v4_matlab/run_capacity_18x18_aperture_check.m`.
- Added `aperture18` mode to
  `delivery/atlas_v4_matlab/run_capacity_precoding_free_sanity.m`.
- The new mode uses an `18x18` UPA with `dx=dy=lambda/2`, giving an aperture
  of roughly `9 lambda x 9 lambda`.
- The mode runs physical-only capacity from `H_spatial=sum_l H_l` for
  `P=0:5:30 dBW` over 30 Monte Carlo frames by default.
- The mode skips delay-Doppler spacetime capacity and spacing sanity.

**Why**:
- The reference NLoS WDM capacity figure uses a much larger line aperture
  (`Ls=Lr=128 lambda`) than the earlier `8x8` UPA check.
- A `9 lambda x 9 lambda` planar aperture has physical DoF on the order of
  `pi*9*9`, close to the reference line-aperture isotropic DoF scale.
- The capacity metric is ergodic, so Monte Carlo averaging is appropriate.
  Thirty frames matches the previous `paper` sanity run; users can set
  `capacity_aperture18_numFrames = 10` before running for a quicker first
  check.
- The delay-Doppler block channel would be `20736 x 20736` for `Nblk=64` and
  `18x18`, so it is intentionally skipped for this magnitude sanity check.

**Expected effect**:
- In MATLAB Online, run:

```matlab
run('delivery/atlas_v4_matlab/run_capacity_18x18_aperture_check.m')
```

- Optional quick check:

```matlab
capacity_aperture18_numFrames = 10;
run('delivery/atlas_v4_matlab/run_capacity_18x18_aperture_check.m')
```

**Result**:
- Local MATLAB R2025a 1-frame smoke passed on 2026-07-08 with
  `capacity_aperture18_P_dBW_list=30`.
- Smoke result at 30 dBW:
  `aperture18_isotropic C_spatial=2443 bit/s/Hz` and
  `aperture18_vmf_cv030 C_spatial=2230 bit/s/Hz`, i.e., about
  `2.44` and `2.23 kbit/s/Hz`.
- This supports the intended magnitude check: increasing the planar aperture
  from roughly `4 lambda x 4 lambda` to `9 lambda x 9 lambda` brings the
  isotropic physical-only capacity close to the reference paper's
  `~2 kbit/s/Hz` scale near 30 dBW.

### [online-20260708-03] Low-MIMO Figure Uses 4x4 Array

**Commit**: `4d07fb7`

**Changed**:
- Changed the delivery Fig.4 low-MIMO comparison from `5x5` to `4x4`,
  keeping `N_s=1`, `v=860 km/h`, `tau_max=32 us`, and fractional Doppler.
- Updated status text and README wording to avoid hard-coded `5x5` labels.

**Why**:
- With half-wavelength spacing, `5x5` gives an aperture of `2.5 lambda`.
- The strict isotropic variance helper `function_computeVar` expects integer
  aperture dimensions and fails on `zeros(2.5,2.5)`.
- `4x4` preserves the low-MIMO diagnostic purpose while using integer aperture
  `4*0.5 = 2 lambda`.

**Expected effect**:
- `paperfig_low_mimo` should pass scenario preparation in MATLAB Online.
- Existing completed BER/capacity checkpoints remain usable; only the low-MIMO
  task outputs change to `ber_low_mimo_4x4_ns1_precoding.png`.

**Result**:
- Pending MATLAB Online execution.

### [online-20260708-02] Precoding-Free Capacity Sanity Runner

**Commit**: `298c416`

**Changed**:
- Added `delivery/atlas_v4_matlab/run_capacity_precoding_free_sanity.m`.
- The runner compares two capacity matrices built from the same NLoS physical
  taps: `H_spatial=sum_l H_l` and
  `H_spacetime=sum_l kron(Theta_l,H_l)`.
- It saves `C_spatial`, `C_spacetime_total`, and
  `C_spacetime_per_use = C_spacetime_total / Nblk`.
- It also generates a spacing sanity figure with a physically consistent 2D
  NLoS curve and an `iid_rayleigh` negative control.

**Why**:
- The current capacity question is about physical-channel capacity with
  no AFWDM/DFT/SVD precoding, not about waveform or spatial-precoder
  comparison.
- The spacetime block channel contains `Nblk` time uses, so the main comparison
  uses the per-use value to avoid an artificial block-length multiplier.
- The spacing sanity check tests whether the 2D physical model avoids the
  unrealistic i.i.d. Rayleigh oversampling growth seen in the reference
  literature's black-line baseline.

**Expected effect**:
- In MATLAB Online, run:

```matlab
capacity_sanity_mode = "smoke";
run('delivery/atlas_v4_matlab/run_capacity_precoding_free_sanity.m')
```

- For the fuller run, set:

```matlab
capacity_sanity_mode = "paper";
run('delivery/atlas_v4_matlab/run_capacity_precoding_free_sanity.m')
```

**Result**:
- Local MATLAB R2025a smoke passed on 2026-07-08 after adding fixed-aperture
  mode-grid embedding for the spacing sanity branch.
- Smoke output generated both expected figures and reported
  `growth ratio physical/iid = 2.127 / 3.961 (pass=1)`. This is only a
  one-frame smoke diagnostic, not a paper-quality average.

### [online-20260708-01] Per-SNR Checkpoints Use MAT-Only Completion

**Commit**: `02d55a4`

**Changed**:
- Per-SNR BER and low-MIMO tasks now set `skip_plots=true`.
- A per-SNR task is considered complete when its `.mat` output exists; it no
  longer requires a one-point PNG.
- Final combined tasks still load all per-SNR MAT files and generate the
  multi-SNR PNG figures under `online_runs/<run_id>/final/`.

**Why**:
- MATLAB Online repeatedly timed out inside `saveas/print` while exporting
  one-point per-SNR PNGs, after the BER calculation and MAT save had already
  completed.
- Treating MAT as the per-SNR checkpoint avoids rerunning completed SNR points
  and keeps graphics export concentrated in the final combine stage.

**Expected effect**:
- If a run previously failed after printing a BER line but before writing a
  `.done` checkpoint, rerunning the resumable script can recover that task
  from the existing `.mat` instead of recomputing it.

**Result**:
- Pending MATLAB Online execution.

### [online-20260705-01] Delivery Runner Per-SNR Checkpoints

**Commit**: `04cd28d`

**Changed**:
- `run_delivery_online_resumable.m` now splits BER and low-MIMO sweeps into
  one task per SNR point.
- Each completed SNR point writes its own checkpoint under
  `delivery/atlas_v4_matlab/outputs/online_runs/<run_id>/checkpoints/`.
- Final multi-SNR figures are rebuilt from the per-SNR MAT files under
  `delivery/atlas_v4_matlab/outputs/online_runs/<run_id>/final/`.
- Added `merge_delivery_config.m`, a small recursive override helper used by
  the runner to set a single SNR point and task-specific output directory.

**Why**:
- MATLAB Online browser/session interruptions should lose at most the current
  SNR point, not an entire scenario.
- The checkpoint logic stays in the Online runner instead of thickening the
  main delivery simulation script.

**Expected effect**:
- Re-running

```matlab
run('delivery/atlas_v4_matlab/run_delivery_online_resumable.m')
```

  skips completed SNR checkpoints and continues from the first missing point.

**Result**:
- Pending MATLAB Online execution.

### [online-20260703-01] Delivery Figure Workflow Mirror

**Commit**: `<PENDING>`

**Changed**:
- Added `delivery/atlas_v4_matlab/` to the MATLAB Online repo.
- New main entry:

```matlab
mode = "paperfig";
run('delivery/atlas_v4_matlab/main_atlas_v4_delivery.m')
```

- `paperfig` generates four current delivery figures:
  1. strict isotropic BER, perfect CSI + fixed-var CSI in one 6-line plot;
  2. vMF `cv=0.30` anisotropic BER, same 6-line format;
  3. raw doubly-selective channel water-filling capacity, no precoder loop;
  4. low-MIMO `5x5`, `N_s=1` waveform/precoding comparison.
- Added standalone `pilot_demo_embedded_channel_estimation.m` for embedded-pilot
  channel-estimation prototyping.

**Why**:
- The delivery scripts are now the preferred maintainable entry point.
- `fixed_var` CSI is reintroduced as a controlled error-floor experiment, while
  raw capacity is separated from precoding comparisons.

**Expected effect**:
- MATLAB Online can run the same delivery workflow as the main repo without
  relying on old atlas refresh wrappers.
- Outputs are written under `delivery/atlas_v4_matlab/outputs/`.

**Result**:
- Pending MATLAB Online execution.

### [online-20260701-01] cv0.10 Adaptive Perfect High-SNR 500-Frame Runner

**Commit**: `<PENDING>`

**Changed**:
- Added `run_online_cv010_adaptive_highsnr_v4.m`.
- Scope is intentionally narrow: vMF `cv=0.10`, adaptive only, perfect CSI
  only (`kappa=0`), `SNR=[10 15]`, and 500 serial frames per SNR.
- Output is isolated under
  `results/online_runs/<run_id>/phase_e_v4_cv010_adaptive_perfect_highsnr_500f/`.
- The runner uses `frame_start_offset=35`, so its samples do not repeat the
  existing 35-frame atlas data and can later be pooled as 535 total frames.
- `run_phase_e_3scheme_csi_grid.m` now saves raw `results.err_total` and
  `results.tot_total` alongside BER.

**Why**:
- The atlas `ber3-vmf-cv010-adaptive` high-SNR tail had too few errors:
  around 25/4 errors at 10 dB and 2/1 errors at 15 dB for AFWDM/SVD.
- The new run raises high-SNR statistical confidence without rerunning the
  whole atlas grid.

**Expected effect**:
- In MATLAB Online, run:

```matlab
run('run_online_cv010_adaptive_highsnr_v4.m')
```

- The summary file `HIGH_SNR_500F_SUMMARY.txt` reports BER, raw errors, raw
  total bits, and zero-error 95% upper bounds for each scheme/SNR.

**Result**:
- Pending MATLAB Online execution.

### [online-20260630-02] ISO Perfect/Full High-SNR Audit Runner

**Commit**: `2ac447b`; follow-up audit fix in `8bb47c3`

**Changed**:
- Added `run_online_iso_perfect_full_audit_v4.m`.
- First-round audit plan is 5 dB/20 frames, 10 dB/150 frames, and
  15 dB/350 frames.
- Each SNR point writes to its own subdirectory under
  `results/online_runs/<run_id>/iso_perfect_full_highsnr_audit/`.
- `run_phase_e_3scheme_csi_grid.m` accepts `frame_start_offset`, records it in
  result metadata, and uses it in frame seeding so continuation batches can
  avoid repeated samples.
- Follow-up fix: per-SNR records are stored in cells before concatenation,
  avoiding MATLAB struct-array assignment errors for dissimilar fields.
- Follow-up fix: online runners `cd` to the repository root, and
  `run_phase_e_3scheme_csi_grid.m` adds `tools/` from the script root.

**Why**:
- The timing smoke showed about 13.28 s per frame/SNR. The audit should collect
  enough errors at 10 dB and a useful zero-error upper bound at 15 dB without
  immediately jumping to 1000+ frames.

**Expected effect**:
- `run('run_online_iso_perfect_full_audit_v4.m')` produces
  `AUDIT_PLAN_SUMMARY.txt` with BER, estimated bit errors, elapsed time, and
  zero-error 95% upper bounds for AFWDM/DFT/SVD.

**Result**:
- Pushed initial audit runner at `2ac447b`; follow-up robustness fix at
  `8bb47c3`.

### [online-20260630-01] ISO Perfect/Full Timing Smoke

**Commit**: `92d233f`

**Changed**:
- Added `run_online_iso_perfect_full_smoke_v4.m`.
- Scope: ISO, perfect CSI (`kappa=0`), full-load, `SNR=[5 10 15]`, one serial
  frame per SNR.
- Fixed two runner issues caused by `run_phase_e_3scheme_csi_grid.m` clearing
  caller variables: switched timing to plain `tic/toc` and rebuilt the summary
  output path from preserved `out_dir_override`.

**Why**:
- The high-SNR ISO perfect/full BER point has too few bit errors to justify a
  large claim. A timing smoke is needed before selecting a larger frame budget.

**Expected effect**:
- MATLAB Online writes `TIMING_SUMMARY.txt` under
  `results/online_runs/<run_id>/iso_perfect_full_timing_smoke/`.

**Result**:
- MATLAB Online measured `elapsed_sec=39.842674` for 3 SNR points and one frame
  each, or about `13.280891` seconds per frame/SNR.

### [online-20260629-03] Resumable Online Master Runner

**Commit**: `86d90a1`

**Changed**:
- Added `run_online_all_v4.m`, with a stable active run id in
  `results/online_runs/_ACTIVE_RUN_ID.txt`.
- Each task writes `checkpoints/<task_id>.done` after its expected output
  appears.

**Why**:
- MATLAB Online sessions may disconnect or time out. The full v4 queue should
  be restartable without overwriting completed outputs.

**Result**:
- Pushed to `main`; use specific runners for targeted reruns.

### [online-20260629-02] Serial-Safe MATLAB Online Execution

**Commit**: `53650d0`

**Changed**:
- Online runners force serial Phase E execution.
- Old Win-oriented atlas refresh runners were removed from the online repo.

**Why**:
- MATLAB Online default sessions do not support the local/process pools used by
  the Win runners.

**Result**:
- Pushed to `main`; Online smoke/full/adaptive runners use serial-safe paths.

### [online-20260629-01] Initial Minimal Online Repository

**Commit**: `9de7274`

**Changed**:
- Created the standalone MATLAB Online repository with the v4 runner closure,
  tools, variance functions, and current seed result mats.

**Why**:
- The main research repo is too large/noisy for MATLAB Online. The online repo
  should contain only runnable code and a minimal current v4 baseline.

**Result**:
- Initial `main` branch pushed to
  `https://github.com/Ericjiang2/afwdm_matlab_online.git`.
