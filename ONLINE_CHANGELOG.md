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
- MATLAB Online users should run `run_online_smoke_v4.m` first, then
  `run_online_all_v4.m` for a resumable full queue.
- Results are downloaded as `results/online_runs/<run_id>/` and imported into
  the main project with `tools/import_online_results.py`.

## Entries

### [online-20260630-02] ISO Perfect/Full High-SNR Audit Runner

**Commit**: `<PENDING>`

**Changed**:
- Added `run_online_iso_perfect_full_audit_v4.m`.
- First-round audit plan is 5 dB/20 frames, 10 dB/150 frames, and
  15 dB/350 frames.
- Each SNR point writes to its own subdirectory under
  `results/online_runs/<run_id>/iso_perfect_full_highsnr_audit/`.
- `run_phase_e_3scheme_csi_grid.m` now accepts `frame_start_offset`, records it
  in result metadata, and uses it in frame seeding so continuation batches can
  avoid repeated samples.

**Why**:
- The timing smoke showed about 13.28 s per frame/SNR. The audit should collect
  enough errors at 10 dB and a useful zero-error upper bound at 15 dB without
  immediately jumping to 1000+ frames.

**Expected effect**:
- `run('run_online_iso_perfect_full_audit_v4.m')` produces
  `AUDIT_PLAN_SUMMARY.txt` with BER, estimated bit errors, elapsed time, and
  zero-error 95% upper bounds for AFWDM/DFT/SVD.

**Result**:
- Pending MATLAB Online run and push.

### [online-20260630-01] ISO Perfect/Full Timing Smoke

**Commit**: `92d233f`

**Changed**:
- Added `run_online_iso_perfect_full_smoke_v4.m`.
- Scope is intentionally narrow: ISO, perfect CSI (`kappa=0`), full-load,
  `SNR=[5 10 15]`, one serial frame per SNR.
- Fixed two runner issues caused by `run_phase_e_3scheme_csi_grid.m`
  clearing caller variables: switched timing to plain `tic/toc` and rebuilt
  the summary output path from preserved `out_dir_override`.

**Why**:
- The high-SNR ISO perfect/full BER point has too few bit errors to justify a
  large claim. A timing smoke is needed before selecting a larger frame budget.

**Expected effect**:
- MATLAB Online writes `TIMING_SUMMARY.txt` under
  `results/online_runs/<run_id>/iso_perfect_full_timing_smoke/`, including
  elapsed time, seconds per frame/SNR, BER, and estimated bit errors.

**Result**:
- Pushed to GitHub `main` at `92d233f`. Runtime smoke produced the core mat;
  final summary generation should pass after the `92d233f` fix.

### [online-20260629-03] Resumable Master Runner

**Commit**: `86d90a1`

**Changed**:
- Added `run_online_all_v4.m`.
- The master runner keeps the active run id in
  `results/online_runs/_ACTIVE_RUN_ID.txt`.
- Each completed task writes `checkpoints/<task_id>.done` and appends
  `TASK_STATUS.tsv`.
- The queue is split into six tasks: ISO full BER, vMF cv=0.10 full BER,
  vMF cv=0.30 full BER, vMF cv=0.10 adaptive BER, vMF cv=0.30 adaptive BER,
  and full capacity.

**Why**:
- MATLAB Online sessions can disconnect or be reclaimed during long serial
  runs. A single all-in-one script would lose too much work if interrupted.

**Expected effect**:
- Re-running `run('run_online_all_v4.m')` skips completed tasks and resumes at
  the next unfinished task.

**Result**:
- Pushed to GitHub `main` at `86d90a1`. MATLAB Online runtime validation is
  pending from the next run.

### [online-20260629-02] Serial-Safe MATLAB Online Path

**Commit**: `53650d0`

**Changed**:
- `run_online_*` paths force serial execution.
- `run_phase_e_3scheme_csi_grid.m` uses a normal `for` loop when
  `online_run_id` is present.
- `run_online_full_v4.m` sets capacity `USE_PARFOR=false`.
- Removed old Win-oriented `run_atlas_refresh_*` runners from the online repo.

**Why**:
- MATLAB Online default sessions do not support the local/processes parallel
  pools used by the old Win runners.

**Expected effect**:
- Online smoke/full/adaptive scripts no longer call `parpool('local')` or
  `parpool('Processes')` on the supported path.

**Result**:
- Pushed to GitHub `main` at `53650d0`. The old `parpool('local')` error is
  avoided on the `run_online_*` path.

### [online-20260629-01] Initial Minimal Online Repository

**Commit**: `9de7274`

**Changed**:
- Created standalone `matlab_online_repo/`.
- Included only the v4 MATLAB dependency closure, helper tools, manifests, and
  six latest v4 seed `.mat` files.
- Added `run_online_smoke_v4.m`, `run_online_full_v4.m`, and
  `run_online_adaptive_v4.m`.

**Why**:
- The GitHub repository is only for MATLAB Online execution, not for pushing
  the full research project and historical data.

**Expected effect**:
- MATLAB Online can clone a compact repository and run the current v4 workflow
  without legacy project clutter.

**Result**:
- Pushed to GitHub `main` at `9de7274`; later superseded by serial-safe and
  resumable updates.
