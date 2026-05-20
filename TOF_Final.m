%% ToF Final - 3D Face Anti-Spoofing
% Detect a face in the RGB frame, then use the depth channel to decide
% whether it is a real 3D face or a flat printout.  Same mxNI plumbing as
% Lab 1; the new logic lives in detect_and_track.m and score_face.m.
%
% Run each section in order the first time.  Sections 2/3/5 can be re-run
% standalone after Section 0 has initialized the camera.

clear; clc; close all;
if ~exist('recordings', 'dir'), mkdir('recordings'); end
if ~exist('figures',    'dir'), mkdir('figures');    end


%% Section 0 - Init
% Near mode (lens_mode = 0) gives best precision for ~30-90 cm, which is the
% demo range.  Switch to 1 for >1 m work.  modify_config must run BEFORE
% mxNI(0) because the SDK reads the JSON at open time.

modify_config(0);

mxNI(0);          % open camera
mxNI(5);          % depth <-> RGB image registration ON (so bbox in RGB == bbox in depth)
mxNI(13, 0);      % depth stream, mode 0
mxNI(14, 0);      % color stream, mode 0
mxNI(15, 0);      % IR stream, mode 0

disp('Camera initialized.  Run Section 1 to calibrate the threshold.');


%% Section 1 - Calibrate threshold
% Capture N_CAL frames of a real face, then N_CAL frames of a printed photo,
% both at about 50 cm.  Compute the plane-fit RMS for each frame and pick a
% threshold halfway between the two means.

N_CAL = 15;
real_rms = nan(N_CAL, 1);
fake_rms = nan(N_CAL, 1);

input('Position a REAL face ~50 cm from the camera, then press Enter...', 's');
for i = 1:N_CAL
    [depth_raw, ~] = mxNI(2);
    [rgb,       ~] = mxNI(3);
    depth_cm = double(fliplr(depth_raw)) / 10;
    rgb      = fliplr(rgb);

    [bbox, ~, ~] = detect_and_track(rgb, [], [], []);    % single-shot detect
    if isempty(bbox), continue; end
    [~, rms_mm] = score_face(depth_cm, bbox, 0);
    real_rms(i) = rms_mm;
    fprintf('  real frame %2d:  rms = %.2f mm\n', i, rms_mm);
end

input('Now hold a PRINTED PHOTO ~50 cm from the camera, then press Enter...', 's');
for i = 1:N_CAL
    [depth_raw, ~] = mxNI(2);
    [rgb,       ~] = mxNI(3);
    depth_cm = double(fliplr(depth_raw)) / 10;
    rgb      = fliplr(rgb);

    [bbox, ~, ~] = detect_and_track(rgb, [], [], []);
    if isempty(bbox), continue; end
    [~, rms_mm] = score_face(depth_cm, bbox, 0);
    fake_rms(i) = rms_mm;
    fprintf('  fake frame %2d:  rms = %.2f mm\n', i, rms_mm);
end

real_rms = real_rms(~isnan(real_rms));
fake_rms = fake_rms(~isnan(fake_rms));

mean_real = mean(real_rms);
mean_fake = mean(fake_rms);
THRESH    = (mean_real + mean_fake) / 2;

fprintf('\n  mean real-face plane RMS = %.2f mm\n', mean_real);
fprintf('  mean printout  plane RMS = %.2f mm\n',   mean_fake);
fprintf('  THRESHOLD (saved)        = %.2f mm\n\n', THRESH);

save('threshold.mat', 'THRESH', 'real_rms', 'fake_rms');

figure('Name', 'Calibration RMS distribution');
histogram(real_rms, 'BinWidth', 1, 'FaceColor', 'g'); hold on;
histogram(fake_rms, 'BinWidth', 1, 'FaceColor', 'r');
xline(THRESH, 'k--', sprintf('THRESH = %.1f mm', THRESH), 'LineWidth', 2);
xlabel('Plane RMS residual (mm)'); ylabel('# frames');
legend('Real face', 'Printout', 'Location', 'best');
title('Section 1 - Threshold calibration');
saveas(gcf, 'figures/calibration.png');


%% Section 2 - Live demo loop
% Real-time loop.  Close the figure window to exit.

load('threshold.mat', 'THRESH');

% Grab one frame to size the figure correctly
[depth_raw, ~] = mxNI(2);
[rgb,       ~] = mxNI(3);
rgb            = fliplr(rgb);

hf = figure('Name', 'ToF Final - Live demo  (close window to stop)', ...
            'NumberTitle', 'off');
ax  = axes('Parent', hf);
him = imshow(rgb, 'Parent', ax);
hr  = rectangle(ax, 'Position', [1 1 1 1], 'EdgeColor', 'g', 'LineWidth', 3, ...
                'Visible', 'off');
ht  = text(ax, 10, 25, '', 'Color', 'g', 'FontSize', 18, 'FontWeight', 'bold', ...
           'BackgroundColor', [0 0 0], 'Margin', 2);

tracker = []; pts = []; bbox = [];

while isvalid(hf)
    [depth_raw, ~] = mxNI(2);
    [rgb,       ~] = mxNI(3);
    depth_cm = double(fliplr(depth_raw)) / 10;
    rgb      = fliplr(rgb);

    [bbox, tracker, pts] = detect_and_track(rgb, tracker, pts, bbox);

    set(him, 'CData', rgb);
    if ~isempty(bbox)
        [is_real, rms_mm] = score_face(depth_cm, bbox, THRESH);
        if is_real
            col = [0 1 0];  label = sprintf('REAL  rms=%.1f mm', rms_mm);
        else
            col = [1 0 0];  label = sprintf('FAKE  rms=%.1f mm', rms_mm);
        end
        set(hr, 'Position', bbox, 'EdgeColor', col, 'Visible', 'on');
        set(ht, 'String', label, 'Color', col, ...
                'Position', [bbox(1), max(20, bbox(2) - 10)]);
    else
        set(hr, 'Visible', 'off');
        set(ht, 'String', 'no face');
    end

    drawnow limitrate;
end

disp('Live demo ended.');


%% Section 3 - Offline replay
% Load every recordings/*.mat captured by Section 4 and print one row per
% file showing the predicted label vs the ground-truth label.

load('threshold.mat', 'THRESH');

files = dir('recordings/*.mat');
if isempty(files)
    disp('No recordings found.  Run Section 4 to capture some.');
else
    fprintf('\n  %-30s  %-6s  %-7s  %-7s  rms(mm)\n', ...
            'file', 'truth', 'pred', 'match');
    fprintf('  %s\n', repmat('-', 1, 70));
    for k = 1:length(files)
        S = load(fullfile('recordings', files(k).name));
        % S has fields: rgb_seq (HxWx3xN), depth_cm_seq (HxWxN), meta
        N      = size(S.rgb_seq, 4);
        votes  = false(N, 1);
        rmsbuf = nan(N, 1);
        for f = 1:N
            rgb     = S.rgb_seq(:, :, :, f);
            depth_cm = S.depth_cm_seq(:, :, f);
            bbox = detect_and_track(rgb, [], [], []);
            if isempty(bbox), continue; end
            [votes(f), rmsbuf(f)] = score_face(depth_cm, bbox, THRESH);
        end
        % Majority vote across frames where a face was found
        good = ~isnan(rmsbuf);
        if any(good)
            pred = mode(double(votes(good))) == 1;
            mean_rms = mean(rmsbuf(good));
        else
            pred = false; mean_rms = NaN;
        end
        truth = strcmpi(S.meta.label, 'real');
        match = ternary_str(pred == truth, 'OK', 'MISS');
        fprintf('  %-30s  %-6s  %-7s  %-7s  %5.1f\n', ...
                files(k).name, S.meta.label, ternary_str(pred,'real','fake'), ...
                match, mean_rms);
    end
end


%% Section 4 - Record a sequence
% Set the metadata variables for the condition you are recording, then run
% this section.  Captures N_REC frames of RGB + depth and saves them to
% recordings/<name>.mat together with the metadata struct.

% --- EDIT THESE BEFORE EACH RECORDING --------------------------------------
meta.distance_cm  = 50;          % 30, 45, 60, 75, 90
meta.angle_deg    = 0;           % -30, 0, +30  (yaw)
meta.lighting     = 'on';        % 'on' or 'off'
meta.orientation  = 'upright';   % 'upright' or 'tilted'
meta.lens_mode    = 0;           % 0 = near, 1 = far  (matches modify_config)
meta.label        = 'real';      % 'real' or 'fake'
record_name       = 'real_50cm_0deg_lighton_upright';
N_REC             = 60;
% ---------------------------------------------------------------------------

% Pre-size the buffers using one frame
[depth_raw, ~] = mxNI(2);
[rgb,       ~] = mxNI(3);
depth_cm = double(fliplr(depth_raw)) / 10;
rgb      = fliplr(rgb);
[H, W, C] = size(rgb);

rgb_seq      = zeros(H, W, C, N_REC, 'uint8');
depth_cm_seq = zeros(H, W, N_REC);

fprintf('Recording %d frames as "%s"...\n', N_REC, record_name);
for f = 1:N_REC
    [depth_raw, ~] = mxNI(2);
    [rgb,       ~] = mxNI(3);
    depth_cm_seq(:, :, f)    = double(fliplr(depth_raw)) / 10;
    rgb_seq(:, :, :, f)      = fliplr(rgb);
end

save(fullfile('recordings', [record_name '.mat']), ...
     'rgb_seq', 'depth_cm_seq', 'meta', '-v7.3');
fprintf('Saved recordings/%s.mat\n', record_name);


%% Section 5 - Characterization
% Walk all recordings and report accuracy broken down by each metadata
% dimension.  Produces one figure per dimension and a confusion matrix.

load('threshold.mat', 'THRESH');

files = dir('recordings/*.mat');
if isempty(files)
    error('No recordings found.  Run Section 4 several times first.');
end

distance = nan(length(files), 1);
angle    = nan(length(files), 1);
lighting = strings(length(files), 1);
orient   = strings(length(files), 1);
lensmode = nan(length(files), 1);
truth    = false(length(files), 1);
pred     = false(length(files), 1);
mean_rms = nan(length(files), 1);

for k = 1:length(files)
    S = load(fullfile('recordings', files(k).name));
    N = size(S.rgb_seq, 4);
    votes  = false(N, 1);
    rmsbuf = nan(N, 1);
    for f = 1:N
        rgb     = S.rgb_seq(:, :, :, f);
        depth_cm = S.depth_cm_seq(:, :, f);
        bbox = detect_and_track(rgb, [], [], []);
        if isempty(bbox), continue; end
        [votes(f), rmsbuf(f)] = score_face(depth_cm, bbox, THRESH);
    end
    good = ~isnan(rmsbuf);
    if any(good)
        pred(k)     = mode(double(votes(good))) == 1;
        mean_rms(k) = mean(rmsbuf(good));
    end
    distance(k) = S.meta.distance_cm;
    angle(k)    = S.meta.angle_deg;
    lighting(k) = string(S.meta.lighting);
    orient(k)   = string(S.meta.orientation);
    lensmode(k) = S.meta.lens_mode;
    truth(k)    = strcmpi(S.meta.label, 'real');
end

correct = pred == truth;
fprintf('\n  Overall accuracy: %d / %d = %.1f%%\n\n', ...
        sum(correct), length(correct), 100 * mean(correct));

% --- Accuracy vs distance ---
plot_acc_by(distance, correct, 'Distance (cm)', 'figures/accuracy_vs_distance.png');
plot_acc_by(angle,    correct, 'Yaw angle (deg)', 'figures/accuracy_vs_angle.png');
plot_acc_by_cat(lighting, correct, 'Lighting', 'figures/accuracy_vs_lighting.png');
plot_acc_by_cat(orient,   correct, 'Orientation', 'figures/accuracy_vs_orientation.png');

% --- Confusion matrix ---
TP = sum( truth &  pred);  FN = sum( truth & ~pred);
FP = sum(~truth &  pred);  TN = sum(~truth & ~pred);
fprintf('  Confusion matrix:\n');
fprintf('              pred real   pred fake\n');
fprintf('  truth real   %5d        %5d\n', TP, FN);
fprintf('  truth fake   %5d        %5d\n', FP, TN);

save('figures/results.mat', 'distance', 'angle', 'lighting', 'orient', ...
     'lensmode', 'truth', 'pred', 'mean_rms', 'THRESH');


%% Section 6 - Close
mxNI(1);
disp('Camera closed.  Done.');


%% --- Local helpers -------------------------------------------------------
function s = ternary_str(cond, a, b)
    if cond, s = a; else, s = b; end
end

function plot_acc_by(values, correct, xlabel_str, outfile)
    u = unique(values(~isnan(values)));
    acc = zeros(size(u));
    for i = 1:numel(u)
        m = values == u(i);
        acc(i) = mean(correct(m));
    end
    figure;
    bar(u, 100 * acc);
    ylim([0 100]); grid on; box on;
    xlabel(xlabel_str); ylabel('Accuracy (%)');
    title(['Accuracy vs ', xlabel_str]);
    saveas(gcf, outfile);
end

function plot_acc_by_cat(values, correct, xlabel_str, outfile)
    u = unique(values(values ~= ""));
    acc = zeros(size(u));
    for i = 1:numel(u)
        m = values == u(i);
        acc(i) = mean(correct(m));
    end
    figure;
    bar(categorical(u), 100 * acc);
    ylim([0 100]); grid on; box on;
    xlabel(xlabel_str); ylabel('Accuracy (%)');
    title(['Accuracy vs ', xlabel_str]);
    saveas(gcf, outfile);
end
