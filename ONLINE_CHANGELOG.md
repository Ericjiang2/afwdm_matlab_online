# MATLAB Online Repo Log

This document is the lightweight change/provenance log for the standalone
`afwdm_matlab_online` repository. It records what changed, why it changed,
the expected effect, and the observed result. The source of truth is this file
in the main project; `tools/prepare_matlab_online_bundle.py` copies it to the
online repo root as `ONLINE_CHANGELOG.md`.

## Current Workflow

- Main research repo remains local and is not pushed to the online GitHub repo.
- `tools/prepare_matlab_online_bundle.py` refreshes `matlab_online_repo/`.
- `matlab_online_repo/` is the only repository pushed to GitHub.
- MATLAB Online users should run `run_online_smoke_v4.m` first, then
  `run_online_all_v4.m` for a resumable full queue.
- Results are downloaded as `results/online_runs/<run_id>/` and imported into
  the main project with `tools/import_online_results.py`.

## Entries

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
