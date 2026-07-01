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
