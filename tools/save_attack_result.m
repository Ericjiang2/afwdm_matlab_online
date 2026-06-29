function save_attack_result(combo_id, label_human, milestone, switches_struct, cfg_in, results_in, out_dir)
% save_attack_result  Save one combo's BER/cap data with full metadata trail.
%
% Inputs:
%   combo_id        char, e.g. 'B1'
%   label_human     char, e.g. 'iso/full_digital/unit/fully_digital/Ns=2'
%   milestone       char, e.g. 'M2'
%   switches_struct struct of injected/effective switch values
%   cfg_in          full cfg struct snapshot
%   results_in      struct with .SNR_dB, .ber_ofdm/.ber_afdm/.ber_afwdm, .cap_*, ...
%   out_dir         e.g. 'results/attack-0428-01/'
%
% Output: writes <out_dir>/<combo_id>_<safe_label>.mat
% Also appends one line to <out_dir>/_run_log.txt and <out_dir>/_index.csv.

if ~exist(out_dir, 'dir'); mkdir(out_dir); end

% ---- metadata ----
metadata = struct();
metadata.combo_id        = combo_id;
metadata.label_human     = label_human;
metadata.milestone       = milestone;
metadata.attack_id       = 'attack-0428-01';
metadata.timestamp_iso   = datestr(datetime('now','TimeZone','UTC'), 'yyyy-mm-ddTHH:MM:SSZ');
metadata.matlab_version  = version();
[~, host_raw] = system('hostname');
metadata.host            = strtrim(host_raw);

% Provenance commit (cc-0602-02): prefer the Mac-authoritative `.provenance_commit`
% marker (written by Mac post-commit hook, synced to Win via Syncthing). The Win
% `.git` is a stale Syncthing residue, so `git rev-parse HEAD` there returns a
% phantom hash absent from the real repo (e.g. 5056b7b). Marker -> git -> unknown.
metadata.git_commit = 'unknown';
pc_file = fullfile(pwd, '.provenance_commit');
if exist(pc_file, 'file')
    fid = fopen(pc_file, 'r');
    if fid > 0
        c = strtrim(fgetl(fid)); fclose(fid);
        if ischar(c) && ~isempty(c); metadata.git_commit = c; end
    end
end
if strcmp(metadata.git_commit, 'unknown')
    try
        [git_status, git_out] = system('git rev-parse HEAD 2>nul');
        if git_status == 0; metadata.git_commit = strtrim(git_out); end
    catch
    end
end

% Parpool worker count (if pool open)
try
    pool = gcp('nocreate');
    if ~isempty(pool); metadata.parpool_workers = pool.NumWorkers;
    else;              metadata.parpool_workers = 0; end
catch
    metadata.parpool_workers = NaN;
end

% Frame counts (pulled from caller via switches if present)
if isfield(switches_struct, 'numFrames');       metadata.numFrames       = switches_struct.numFrames;       end
if isfield(switches_struct, 'numFrames_block'); metadata.numFrames_block = switches_struct.numFrames_block; end

% ---- compose payload ----
switches = switches_struct;   %#ok<NASGU>
cfg      = cfg_in;            %#ok<NASGU>
results  = results_in;        %#ok<NASGU>

% ---- filename: B<ID>_<safe_label>.mat ----
safe_label = regexprep(label_human, '[^a-zA-Z0-9]+', '_');
safe_label = regexprep(safe_label, '_+$', '');
fname = sprintf('%s_%s.mat', combo_id, safe_label);
fpath = fullfile(out_dir, fname);

save(fpath, 'metadata', 'switches', 'cfg', 'results', '-v7.3');
fprintf('  [save_attack_result] wrote %s\n', fpath);

% ---- append run log ----
log_fid = fopen(fullfile(out_dir, '_run_log.txt'), 'a');
fprintf(log_fid, '%s  %s  %s  -> %s  (commit %s, workers=%d, nF=%d/%d)\n', ...
    metadata.timestamp_iso, combo_id, label_human, fname, ...
    metadata.git_commit, metadata.parpool_workers, ...
    metadata.numFrames, metadata.numFrames_block);
fclose(log_fid);

% ---- append index CSV (header on first run) ----
csv_path = fullfile(out_dir, '_index.csv');
need_header = ~exist(csv_path, 'file');
csv_fid = fopen(csv_path, 'a');
if need_header
    fprintf(csv_fid, 'combo_id,milestone,label,preset,profile,pas_model,pas_config,norm_mode,wbb_mode,Nstreams,numFrames,numFrames_block,timestamp,filename\n');
end
gv = @(s,f) get_or_dash(s,f);
fprintf(csv_fid, '%s,%s,"%s",%s,%s,%s,%s,%s,%s,%s,%d,%d,%s,%s\n', ...
    combo_id, milestone, label_human, ...
    gv(switches_struct,'simulation_preset'), ...
    gv(switches_struct,'experiment_profile'), ...
    gv(switches_struct,'pas_model'), ...
    gv(switches_struct,'pas_config'), ...
    gv(switches_struct,'channel_norm_mode'), ...
    gv(switches_struct,'wbb_mode'), ...
    gv(switches_struct,'Nstreams'), ...
    metadata.numFrames, metadata.numFrames_block, ...
    metadata.timestamp_iso, fname);
fclose(csv_fid);
end

function v = get_or_dash(s, f)
if isfield(s, f)
    val = s.(f);
    if isnumeric(val); v = num2str(val); else; v = char(string(val)); end
else
    v = '-';
end
end
