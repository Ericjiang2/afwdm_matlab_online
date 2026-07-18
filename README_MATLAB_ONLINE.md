# MATLAB Online Bundle

Generated: 2026-07-14T05:35:45Z
Commit marker: `94cdbaa18aad43e468ababf8497c68c976789073`

## Recommended Path: Git First

1. Create or use a private Git remote for this project.
2. On the local Mac, commit code changes and push the branch.
3. In MATLAB Online, clone or pull the same branch.
4. Open the cloned repository root in MATLAB Online.
5. Run `run('run_online_smoke_v4.m')` first.
6. If smoke passes, run `run('run_online_all_v4.m')` for a resumable full queue.

## Fallback Path: Zip Upload

Upload `afwdm_v4_online_20260714_133545.zip` to MATLAB Online or MATLAB Drive, unzip it, open the `src/`
folder, then run the same online runner scripts from there.

## Results

All online outputs go under:

```text
results/online_runs/<online_run_id>/
```

Download that single run folder as a zip. Back on the Mac, import it with:

```bash
python3 tools/import_online_results.py --run-id <online_run_id> --zip /path/to/downloaded.zip
```

The `results_seed/latest_v4/` folder contains only the current v4 reference
mat files, not the full historical `results/` tree.

## Tau48 Six-Line Time-Diversity Run

From the cloned repository root in MATLAB Online, run:

```matlab
addpath(fullfile(pwd, 'delivery', 'atlas_v4_matlab'));
package = run_time_diversity_tau48_sixline();
```

This fixed v11 entry uses `Lch=6`, `v_max=860 km/h` (`kmax=2`),
`tau_max=48 us`, fractional Doppler, QPSK, full `N_s=11`, common 40-iteration
GaBP, and the SNR grid `[-8 -6 -4 -2 0 2 4] dB`. At each point it runs the
WDM, DFT, and SVD spatial pairs, producing six AFDM/OFDM BER curves under
shared channel, bits/noise, detector, and adaptive stopping settings.

The fixed run id is `time_diversity_tau48_sixline_v11_20260718`. Rerun the
same command after a disconnect to resume compatible per-SNR checkpoints.
Outputs are written under
`delivery/atlas_v4_matlab/outputs/online_runs/<run_id>/`; do not copy v10
checkpoints into this run.

## MATLAB Online Parallel Note

MATLAB Online default sessions do not support the local/processes pools used by
the old Win runners. Use only the `run_online_*.m` runners in this repository.
Those runners force serial execution for Online safety.

`run_online_all_v4.m` is resumable. It stores the active run id in
`results/online_runs/_ACTIVE_RUN_ID.txt` and writes per-task checkpoints under
`results/online_runs/<run_id>/checkpoints/`. If MATLAB Online disconnects, run
the same command again and completed tasks will be skipped.

## Provenance

Each result should be traceable by:

```text
git commit + cc entry + runner + online_run_id + MAT metadata + manifest hash
```

The root-level untracked shadow files `build_G_paper_eq31.m`,
`svd_precoder_from_G.m`, and `build_precoder.m` are intentionally excluded.
The bundle uses the tracked `src/tools/` versions to avoid MATLAB path shadowing.
