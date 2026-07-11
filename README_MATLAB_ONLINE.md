# MATLAB Online Bundle

Generated: 2026-07-11T13:54:19Z
Commit marker: `0d9607184cc17a440a6c54ef58f15f9dd66f49cc`

## Recommended Path: Git First

1. Create or use a private Git remote for this project.
2. On the local Mac, commit code changes and push the branch.
3. In MATLAB Online, clone or pull the same branch.
4. Open the cloned repository root in MATLAB Online.
5. Run `run('run_online_smoke_v4.m')` first.
6. If smoke passes, run `run('run_online_all_v4.m')` for a resumable full queue.

## Fallback Path: Zip Upload

Upload `afwdm_v4_online_20260711_215419.zip` to MATLAB Online or MATLAB Drive, unzip it, open the `src/`
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
