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

### [online-20260717-02] Widen the Fractional-GaBP Grid and Tail Budget

**Changed**:
- Expanded `time_diversity_fractional_gabp_exploration` from
  `[-4 -2 0 1 2] dB` to `[-8 -6 -4 -2 0 1 2 4] dB` and raised only its
  per-point maximum from 300 to 500 frames. The 10-frame minimum, 100-error
  target, four physical stages, paired seeds, fractional WDM scope, GaBP
  40-iteration contract, and supplemental per-stream detector remain fixed.
- Advanced the immutable runner identity to `time-diversity-20260717.9` and
  assigned a new v9 run id. v8 checkpoints remain historical and incompatible.

**Why**:
- The completed v8 curves cover only -4 through 2 dB and visually compress the
  waterfall into a narrow interval. The added -8/-6 dB points expose the left
  transition, while 4 dB extends the tail for a preliminary slope check.

**Expected result and boundary**:
- This is still candidate exploration. At the observed decay rate, 4 dB may
  remain noise-limited even at 500 frames; it must be reported with raw
  bit/error counts and cannot by itself establish a diversity-order change.

---

### [online-20260717-01] Add a Pre-Registered Fractional-GaBP Exploration

**Changed**:
- Added `time_diversity_fractional_gabp_exploration`, using
  `[-4 -2 0 1 2] dB`, WDM, fractional Doppler, a 10--300-frame/100-error
  adaptive stop, and a shared 40-iteration GaBP contract.
- The public runner executes four fixed stages in order: the comparable
  `Lch=6, kmax=2, tau=32 us` anchor, then `Lch=8`, then `kmax=3` at about
  1100 km/h, then `tau=48 us`. Each transition changes one physical group.
- GaBP and per-stream LMMSE are both reported at every stage. Per-stream
  LMMSE is supplemental and cannot be selected after observing the gap.
- Added shared dimension auditing, explicit completion metadata, generalized
  available-detector tables/plots, and stage-per-SNR resume coverage. Advanced
  the immutable runner identity to `time-diversity-20260717.8`.

**Why**:
- The v6/v7 evidence makes fractional GaBP the most promising mechanism
  anchor, but a high-SNR tail separation alone does not establish additional
  diversity order. The fixed sequence isolates richer paths, larger Doppler
  support, and a longer delay window without post-hoc stage or detector
  selection.

**Result**:
- MATLAB R2025a time-diversity tests pass 44/44; an integration fixture
  consumes all 20 compatible stage-by-SNR checkpoints through the public
  runner and preserves a `candidate_exploration` label. Changed-file
  `checkcode` reports zero issues.
- A one-frame numerical wiring smoke completed all four physical stages. It
  verifies dimensions and detector execution only; no 300-frame Online run
  was started, no diversity-gain conclusion was promoted, and the final
  Online result remains a human-reviewed candidate.

---

### [online-20260716-01] Add a Comparable 4 dB Follow-up and Iteration Audit Range

**Changed**:
- Added `time_diversity_4db_followup`, restricted to 4 dB, WDM, `Lch=6`, both
  Doppler modes/detectors, the existing 10--150-frame/100-error stop, and no
  conditional escalation.
- Kept the follow-up GaBP contract at 20 iterations so it remains directly
  comparable with the v6 low-SNR pilot.
- Widened only the detector's accepted diagnostic iteration range from 20 to
  60; every shipped Online profile still defaults to 20 iterations.
- Advanced the immutable runner identity to `time-diversity-20260716.7`.

**Why**:
- The v6 result located GaBP's transition between 0 and 2 dB but showed severe
  non-convergence at -2/0 dB. A same-seed 20/40/60-iteration audit requires the
  detector to accept diagnostic caps above 20, while the user-requested 4 dB
  point must preserve the original detector contract.

**Result**:
- Contract tests lock the one-point scope, default 20-iteration setting,
  no-escalation behavior, diagnostic maximum, and new runner identity. The 4 dB
  output remains supplemental pilot evidence, not a production result.
- MATLAB R2025a time-diversity tests pass 38/38 and changed-file `checkcode`
  reports no issues. A one-frame 4 dB wiring smoke completes all four WDM runs;
  its GaBP arms observe zero errors, consistent with the point being diagnostic
  and likely noise-limited under the 150-frame cap.

---

### [online-20260715-17] Add a Bounded Low-SNR Detector Diagnostic

**Changed**:
- Added `time_diversity_low_snr_pilot` with
  `[-10 -6 -2 0 2 8 10 12] dB`, WDM only, `Lch=6`, both Doppler modes, and
  both co-primary detectors.
- Kept the 10--150-frame, 100-error adaptive stop, reduced the internal SISO
  anchor to one frame at 0 dB, and disabled conditional escalation for this
  diagnostic profile.
- Advanced the immutable runner identity to `time-diversity-20260715.6`.

**Why**:
- The completed 8--23 dB pilot bracketed Block-LMMSE near 12 dB but sat above
  GaBP's observable transition. Two local three-frame probes at 0 dB produced
  nonzero GaBP BER near `1e-3`, so the follow-up needs low points without
  repeating DFT/SVD or expanding into Lch/kmax escalation stages.

**Result**:
- The configuration contract locks the diagnostic grid, primary WDM scope,
  frame/error budget, one-frame SISO anchor, and no-escalation behavior. Output
  remains diagnostic evidence and cannot be promoted as a production result.

---

### [online-20260715-16] Add an Adaptive Six-Hour Pilot Profile

**Changed**:
- Added `time_diversity_pilot`, using the production seven-point SNR grid and
  the same paired 100-error adaptive stop, but with `max_frames=150` instead
  of 1500.
- `run_online_time_diversity` accepts the pilot profile without introducing a
  second runner or a separate simulation implementation.
- The immutable runner identity advances to `time-diversity-20260715.5`.

**Why**:
- MATLAB Online sessions can disconnect during a long run. A bounded pilot
  lets low-SNR points stop quickly while allocating more frames to high-SNR
  points, with the existing per-SNR checkpoints still providing recovery.

**Result**:
- The public configuration contract locks the pilot to the production SNR,
  detector, spatial-pair, Doppler, target-error, and minimum-frame settings;
  only the maximum frame budget differs. Pilot output remains preliminary and
  cannot be promoted as a production claim.

---

### [online-20260715-15] Focus the Production SNR Grid

**Changed**:
- The production MIMO and internal SISO grids now use
  `[8 10 12 14 17 20 23] dB` instead of `12:2:28 dB`.
- The immutable runner identity advances to `time-diversity-20260715.4`, so
  checkpoints created with the former grid cannot be reused silently.

**Why**:
- The calibrated smoke already produced zero observed errors at 12 dB in one
  frame. Starting at 12 dB risked spending most of the adaptive frame budget
  on noise-limited points while never bracketing the BER transition.
- The focused grid retains 2 dB resolution around the target region, uses a
  coarser 3 dB high-SNR tail, and removes the especially expensive 26/28 dB
  points. This changes measurement placement, not detector fairness or the
  stopping rule.

**Result**:
- TDD locks the same seven-point grid for production MIMO and the SISO anchor.
  The smoke profile remains the one-frame 12 dB execution check.

---

### [online-20260715-14] Calibrate GaBP Convergence for Production

**Changed**:
- The shared AFWDM/OFWDM GaBP contract now uses 20 maximum iterations and a
  `1e-3` relative-message tolerance, with damping 0.4 unchanged for both arms.
- Each BER point persists the per-frame final GaBP residuals and their mean in
  addition to iterations and non-convergence rates.
- The immutable runner identity advances to `time-diversity-20260715.3`, so
  old smoke or production checkpoints cannot be reused silently.

**Why**:
- The MATLAB Online one-frame smoke and a local fixed-seed five-frame probe
  showed 100% non-convergence at the former 15-iteration/`1e-4` limit despite
  stable zero-error hard decisions. The messages normally crossed `1e-3` near
  iteration 16, so the old cap and threshold mislabeled slow relaxation as a
  detector failure.

**Result**:
- TDD locks the public profile and residual evidence fields. A paired local
  sensitivity probe at 12/20/28 dB used identical channels, bits, and noise:
  all 36 new-setting detector calls converged, final residual means were below
  `1e-3`, and every hard decision was bit-identical to the former setting.
  This is convergence-calibration evidence, not a production BER claim.

---

### [online-20260715-13] Fingerprint the Recursive MATLAB Dependency Closure

**Changed**:
- Run manifests now recursively hash every `.m` file under the existing
  configured MATLAB path directories, with deduplicated stable paths.
- Resume validation also compares the saved Git commit and MATLAB release.

**Why**:
- Direct-only scans omitted `variance/` and `variance_aniso/`; changing a
  physical-model dependency could otherwise reuse an incompatible checkpoint.

**Result**:
- TDD modifies a nested dependency fixture and confirms its code fingerprint
  changes and resume validation raises `manifestMismatch`; an unchanged tree
  produces an identical fingerprint. Manifest files pass checkcode.

---

### [online-20260715-12] Compose Final Results per Subscenario

**Changed**:
- Canonical final results now start from the complete Lch=6 baseline and
  replace only matching Doppler/detector/WDM records with the newest
  conditional-stage evidence.
- Untriggered Doppler modes, DFT robustness, and the SVD appendix remain in
  the final package and figures. Summary rows report each record's actual Lch.

**Why**:
- Conditional stages are intentionally Doppler-specific and WDM-only. Taking
  the last stage wholesale dropped the other Doppler plus both robustness
  comparisons from the most visible final artifacts.

**Result**:
- TDD reproduces a one-Doppler Lch=8 upgrade and verifies 12 final paired
  records, Lch=8 only for upgraded integer WDM, Lch=6 fractional WDM, retained
  DFT/SVD records, and a complete four-row summary. Changed files are clean.

---

### [online-20260715-11] Preserve Independent Doppler Outcomes

**Changed**:
- Added a persistent integer/fractional state ledger with independent
  `complete`, `inconclusive`, `escalating`, and `fail_closed` outcomes.
- Global completion now requires every Doppler mode in the current decision
  scope to be eligible, and the package records per-Doppler plus aggregate
  outcome (`partial` for mixed complete/fail-closed boundaries).

**Why**:
- One significant Doppler result must not hide a noise-limited peer, and an
  escalated subset must not erase the terminal state of an untriggered mode.

**Result**:
- TDD reproduced the mixed eligible/ineligible false completion. Ten
  escalation tests now pass, including mixed inconclusive and explicit
  complete/fail-closed partial-outcome contracts.

---

### [online-20260715-10] Make the Last Evidence Stage Canonical

**Changed**:
- The final package now exposes `final_stage`, `final_results`, and a
  machine-readable outcome with terminal status and stage parameters.
- Fixed-name final plots/table are built from the last evidence-producing
  stage. Baseline artifacts are retained under an explicit `_baseline_`
  prefix, so conditional results cannot be confused with Lch=6 evidence.
- Plot labels now use the Spec names AFWDM/OFWDM, AFDM-DFT/OFDM-DFT, and
  AFDM-SVD/OFDM-SVD. Fixed-BER interpolation rejects and diagnoses
  non-monotonic eligible curves.

**Why**:
- A fail-closed or escalated result must point to the actual stopping stage,
  while the baseline remains auditable. Sorting a non-monotonic BER curve by
  BER before interpolation could otherwise hide a production anomaly.

**Result**:
- TDD covers last-stage selection, non-monotonic rejection, locked labels,
  and the no-escalation end-to-end smoke. All seven delivery tests pass and
  the smoke writes both baseline and canonical final artifacts.

---

### [online-20260715-09] Fail Closed on Resume Identity Mismatch

**Changed**:
- Added immutable run/stage manifests with schema and runner versions, profile,
  physical/time-diversity config fingerprint, code-content fingerprint, Git
  commit, MATLAB release, seed contract, Doppler/detector/spatial sets, Lch,
  and the SNR grid.
- Final MAT and per-SNR checkpoints are validated before reuse. Missing or
  mismatched manifests now raise an explicit error requiring a new run id.

**Why**:
- A stage/SNR filename alone cannot prove that an old artifact belongs to the
  current scientific configuration or code. Silent cross-config reuse would
  invalidate a resumed production result.

**Result**:
- TDD first reproduced silent reuse of a smoke final MAT by the production
  profile. The end-to-end smoke now resumes an identical run without rewriting
  its checkpoint and rejects the changed profile with `manifestMismatch`.

---

### [online-20260715-08] Gate Scientific Completion on Paired Significance

**Changed**:
- Added a decision record that requires both co-primary detectors to have a
  finite fixed-BER gain, sufficient errors, BER-ratio CI wholly above one,
  and McNemar `p<0.05` before a Doppler result is claim-eligible.
- Statistically inconclusive evidence now returns `await_evidence`; significant
  sub-dB evidence alone can trigger the approved escalation sequence.

**Why**:
- Error-count sufficiency and a finite interpolated gain do not establish a
  paired scientific result. The production state machine must not declare
  completion when the confidence interval crosses one or McNemar is not
  significant.

**Result**:
- TDD reproduced the significance-blind completion path, then seven escalation
  tests passed, including insignificant gain, significant completion, and
  significant sub-dB escalation contracts. Changed-file checkcode is clean.

---

### [online-20260715-07] Add Resumable Time-Diversity Delivery Entry

**Changed**:
- Added `run_online_time_diversity.m`, which checkpoints each stage/SNR,
  reconstructs the multi-SNR paired result, and resumes from a stable run id.
- Added WDM/DFT/SVD paired spatial routes, a four-row fixed-BER gain table,
  separate MIMO main/SVD appendix figures, and an internal-only SISO anchor.
- Wired the evidence-gated `Lch=8 -> kmax=3 -> per-stream LMMSE` sequence into
  the production runner. Conditional runs are Doppler-specific and WDM-only.

**Why**:
- MATLAB Online sessions can disconnect during the 9-point, adaptive-frame
  sweep. Scientific escalation must use combined claim-eligible evidence,
  never a one-point smoke or a noise-limited zero-error observation.

**Result**:
- MATLAB R2025a: the delivery contract first failed on the missing public
  entry, then its full smoke executed and resumed successfully. The smoke
  produced one baseline checkpoint, final MAT, MIMO/SVD figures, table, and
  an `await_evidence` outcome; it is workflow evidence, not a production BER
  claim. The complete local suite passes 19 tests before commit.

---

### [online-20260715-06] Add Evidence-Gated Fail-Closed Escalation

**Changed**:
- Added the per-Doppler escalation sequence `Lch=6 -> Lch=8 -> kmax=3 at
  1100 km/h -> supplemental per-stream LMMSE -> fail-closed`.
- Noise-limited points cannot trigger escalation. The kmax=3 stage computes the
  unique velocity mapping and verifies `2*3*(5+1)+5=41<64`.
- Added a runnable config applicator and a per-stream LMMSE detector that is
  appended beside, never substituted for, block-LMMSE and GaBP.

**Why**:
- Conditional stages must change one variable at a time and must not use an
  unmeasured high-SNR point as evidence for a sub-1 dB gap.

**Result**:
- MATLAB R2025a: 15/15 tests passed. Real one-frame smokes completed the
  kmax=3/Lch=8 stage (2 detectors) and the supplemental per-stream stage
  (3 detectors). No conditional stage was claimed as scientifically triggered;
  those smokes used synthetic gain records solely to exercise the code paths.

---

### [online-20260715-05] Add Controlled Lch=4-to-6 DD-Crowding Sweep

**Changed**:
- The paired runner now executes `Lch=[4,6]` while preserving every other
  physical, spatial, waveform, detector, seed, and stopping parameter.
- Added a contract helper that rejects per-path-Sigma scenarios, proves only
  `cfg.Lch` changed, and rechecks the AFDM diversity inequality.
- Added a net-gap summary comparing `BER_OFWDM/BER_AFWDM` at Lch 4 and 6 for
  each Doppler/detector/SNR combination; noise-limited points remain ineligible.

**Why**:
- Moderate DD crowding is the approved mechanism probe, but increasing paths
  can also add shared spatial diversity. A single-variable audit prevents that
  effect from being mislabeled as a temporal waveform gain.

**Result**:
- MATLAB R2025a: 11/11 tests passed. A one-frame full-`N_s=11` smoke completed
  all eight Lch x Doppler x detector runs and produced four Lch comparisons;
  all were correctly marked noise-limited, so no scientific trend is claimed.

---

### [online-20260715-04] Run GaBP Beside LMMSE on the Same Paired Frames

**Changed**:
- The time-diversity profiles now schedule `block_lmmse` and `gabp` together
  for both integer and fractional Doppler.
- Both waveform arms and both detectors reuse the same deterministic frame
  seeds, shared bits, and shared unit noise. GaBP uses one locked contract:
  damping 0.4, 15 iterations, tolerance `1e-4`, no edge truncation.

**Why**:
- The approved comparison makes GaBP co-primary, not a fallback, and forbids
  waveform-specific detector tuning or hiding the LMMSE result.

**Result**:
- MATLAB R2025a: 9/9 tests passed. A full-`N_s=11` one-frame smoke completed
  all four integer/fractional x LMMSE/GaBP runs with finite iteration metrics
  and printed `TIME_DIVERSITY_COPRIMARY_SMOKE_OK`. Production curves remain an
  external MATLAB Online run.

---

### [online-20260715-03] Add Damped Gaussian MP for MIMO-DD Blocks

**Changed**:
- Added `detect_gmp.m`, a vectorized rectangular Gaussian BP detector using
  observation/variable extrinsic messages, a finite QPSK denoiser, locked
  damping `0.3..0.5`, 10--20 iterations, convergence reporting, and an
  explicit shared edge-threshold setting.
- The detector consumes the same equivalent block `H` used by block-LMMSE and
  exposes iteration count, non-convergence, residual, and edge density.

**Why**:
- Block-LMMSE can absorb DD path separation into a global spatial-time solve.
  The Spec therefore requires GaBP as a co-primary detector, with identical
  hyperparameters for AFWDM and OFWDM.

**Result**:
- MATLAB R2025a TDD: three detector tests failed before implementation and then
  passed. A fixed-seed SISO reduction matched the referenced `MP_MUD_SISO`
  error count (`0` vs `0`) and converged in 14 iterations. This is algorithmic
  smoke evidence, not a production BER claim.

---

### [online-20260715-02] Add Full-Stream AFWDM/OFWDM Time-Diversity Baseline

**Changed**:
- Added `time_diversity_smoke` and `time_diversity_online` profiles with the
  locked `4x4`, `N_s=m_s=11`, `Nblk=64`, 4 GHz, 2 kHz configuration.
- Added a pure waveform pair builder: AFWDM and OFWDM share the selected WDM
  spatial basis and differ only in `c1/c2`.
- Added the strictly paired integer/fractional block-LMMSE runner. Both Doppler
  modes reuse the same frame seeds; the production grid is `12:2:28 dB` with
  error-target stopping up to 1500 frames.

**Why**:
- The prior low-MIMO screen mixed six independently randomized scheme calls,
  which obscured the temporal waveform effect and starved the high-SNR points.

**Result**:
- MATLAB R2025a: two configuration/isolation contracts passed. A real one-frame
  full-`N_s=11` smoke completed both integer and fractional runs and printed
  `TIME_DIVERSITY_BASELINE_SMOKE_OK`. Production Online curves were not run.

---

### [online-20260715-01] Add Strictly Paired BER Statistics Harness

**Changed**:
- Added a paired-frame simulator that accepts one shared bit vector and one
  shared unit-noise vector for two equal-dimension MIMO-DD block channels.
- Added adaptive stopping on the better arm's error count, paired frame
  bootstrap confidence intervals for `BER_B/BER_A`, exact McNemar testing,
  and explicit `noise_limited` / `claim_eligible` fields.

**Why**:
- The previous six-scheme runner generated bits and noise independently inside
  each arm, so it could not support paired significance tests or distinguish a
  true high-SNR waveform gap from finite-bit starvation.

**Result**:
- MATLAB R2025a test-first cycle: the three harness contracts first failed on
  missing functions, then passed after implementation. This is a local unit
  test only; no MATLAB Online production Monte Carlo result is claimed.

---

### [online-20260714-01] Adaptive BER Decade Axes and Imported Follow-up Results

**Changed**:
- BER figures now derive their y limits from the actual plotted positive values,
  round outward to complete log decades, and place one tick per decade.
- `cfg_run.ber_y_limits=[]` is the new default; an explicit two-element value
  remains a supported override for reproducible legacy plots.
- Added the shared `delivery_ber_axis_scale.m` helper to the Online dependency
  closure.

**Why**:
- The vMF cv=0.30 figure used a hard-coded `1e-6..1` range even though its
  plotted values only required `1e-3..1`, leaving three empty decades.
- Complete-decade bounds keep logarithmic tick spacing visually uniform while
  adapting to each result.

**Result**:
- MATLAB R2025a unit tests: 5/5 passed. Runtime plot smoke regenerated the
  archived vMF and full-stream MAT outputs; vMF selected `1e-3..1` with ticks
  at `1e-3,1e-2,1e-1,1`.
- The imported MATLAB Online follow-up establishes `delivery_20260710_222618`
  as the current 200-frame/SNR, `4x4`, `N_s=m_s=11` six-line OFDM-inclusive
  result. The strict-iso AFWDM perfect-CSI 15 dB pooled count is
  `1/12288000 = 8.138020833e-8`.

---

### [online-20260711-02] Fix Phase-G Scenario Prep: Restore nomask/per-path Baseline (v1 Results Void)

**Changed**:
- `run_phase_g_channel_estimation.m` scenario prep now sets
  `disable_prop_mask = true; use_perpath_sigma = true;` (paper-faithful v4
  baseline flags, same as `run_online_full_v4.m`).
- Default `online_run_id` bumped to `phase_g_v2` so a plain rerun cannot
  silently resume the void `phase_g_v1` checkpoints.

**Why**:
- Eric caught it from the smoke BER table: without the flag the legacy
  centre-ellipse mask zeroed the 13 edge-cell modes of the 60-mode iso pool,
  fabricating dead streams and a fake perfect-CSI floor of `13/(2*60)=0.108`.
  Under the adjudicated nomask baseline those edge modes carry 0.73-2.15x the
  median energy (bowl-spectrum edge enrichment), so no dead streams exist.
- vMF generation (per-path de-masked `Sigma2_p`) was never affected.

**Result**:
- Local regression 20/20; corrected 1-frame iso probe: perfect-CSI AFWDM
  `8.9e-3 / 0 / 0` at data SNR `0/15/25 dB` (fake floor gone, AFWDM again
  uniformly at or below MIMO-AFDM, consistent with Phase-E); estimated
  threshold/SOMP at 25 dB: AFWDM `3.3e-3` vs MIMO-AFDM `3.9e-2`.
- ALL `phase_g_v1` results (both tasks, both scenarios) are void; rerun
  everything under `phase_g_v2` after pulling this commit.

### [online-20260711-01] Add Phase-G Channel-Estimation Production Runner (NMSE + Paired BER)

**Changed**:
- New public entry `run_online_phase_g_v1.m`: resumable Phase-G production run
  for AFWDM vs MIMO-AFDM integer-DD embedded-pilot channel estimation.
  - `nmse` task: pilot-SNR sweep `0:5:40` at fixed data SNR 15 dB, default
    200 frames, all five estimators (full-grid/threshold LS/threshold
    LMMSE/SOMP/oracle).
  - `ber` task: paired operator-PCG BER for perfect_csi / full_grid_lmmse /
    threshold_lmmse / somp_ls, data SNR `0:5:25`, both `SNR_p=SNR_d+10 dB`
    (linked) and fixed `SNR_p=25 dB` floor diagnostic, default 50 frames.
  - Per-(task, scenario, chunk) checkpoints under
    `results/online_runs/<run_id>/checkpoints/`; re-running the same
    `online_run_id` skips finished chunks and re-combines.
  - `phase_g_smoke = true` gives a 1-frame local/Online sanity preset.
- Bundled the eleven Phase-G dependency files (`run_phase_g_channel_estimation.m`,
  `build_modal_dd_truth.m`, `build_modal_block_operator.m`, estimators, CFAR,
  paired-BER helper, smoke gate) so the online repo stays self-contained.

**Why**:
- Stage-B/C production Monte Carlo runs on MATLAB Online per the main-repo
  Phase-G design spec (cc-0711-01/02); local Mac only runs smokes.
- Detection uses the matrix-free modal block operator with PCG on the normal
  equations, so no branch materializes the `3840x3840` dense block matrix;
  Mac cross-validation against dense-direct agreed within 10/7680 error bits
  and all PCG solves converged (`tol 1e-6`, max iter 5000).

**Result**:
- Local Mac smoke from this repository copy: `PHASE_G_ONLINE_SMOKE_OK`
  (1 frame, both tasks, checkpoints + combined MATs written, PCG flags all 0).
- Expected Online cost at defaults: NMSE ~1.5 h, BER ~2.5-3.5 h, both
  chunk-resumable. Not yet run in MATLAB Online; Eric runs
  `run('run_online_phase_g_v1.m')` (optionally `phase_g_smoke = true` first).

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
