function [bbox, tracker, pts] = detect_and_track(rgb, tracker, pts, prev_bbox)
% DETECT_AND_TRACK  Find a face in the RGB frame and track it with KLT.
%
%   First call:    pass tracker=[], pts=[], prev_bbox=[].  The Viola-Jones
%                  detector runs and seeds a vision.PointTracker.
%   Later calls:   pass back the tracker/pts/bbox returned from the previous
%                  frame.  The tracker is stepped and the bbox is translated
%                  by the median point displacement.  When too few points
%                  remain valid, the tracker is reset to empty so the next
%                  call re-detects.
%
%   Inputs
%     rgb       HxWx3 uint8     current RGB frame
%     tracker   PointTracker|[] previous tracker state, [] to (re)detect
%     pts       Nx2 single|[]   previous point positions (matches tracker)
%     prev_bbox 1x4|[]          previous bbox [x y w h], [] to (re)detect
%
%   Outputs
%     bbox      1x4 or []       updated face bbox, [] if no face detected
%     tracker   PointTracker|[] tracker state for next call ([] forces redetect)
%     pts       Nx2 single|[]   updated point positions

    persistent detector
    if isempty(detector)
        detector = vision.CascadeObjectDetector();   % default frontal-face model
        detector.MinSize = [60 60];                  % skip tiny false positives
    end

    gray = rgb2gray(rgb);

    % --- (Re)detect path ------------------------------------------------
    needs_detect = isempty(tracker) || isempty(pts) || size(pts,1) < 10;
    if needs_detect
        b = step(detector, gray);
        if isempty(b)
            bbox = []; tracker = []; pts = [];
            return
        end
        bbox = b(1, :);                              % first hit is fine for demo
        feat = detectMinEigenFeatures(gray, 'ROI', bbox);
        pts  = feat.Location;
        if size(pts,1) < 10
            % not enough texture in this bbox to track; bail this frame
            bbox = []; tracker = []; pts = [];
            return
        end
        tracker = vision.PointTracker('MaxBidirectionalError', 2);
        initialize(tracker, pts, gray);
        return
    end

    % --- KLT track path -------------------------------------------------
    [new_pts, valid] = step(tracker, gray);
    if nnz(valid) < 10
        % lost the face; signal a redetect on the next call
        bbox = prev_bbox; tracker = []; pts = [];
        return
    end

    % displacement of valid points (old -> new), then shift the bbox by the median
    old_valid = pts(valid, :);
    new_valid = new_pts(valid, :);
    d = median(new_valid - old_valid, 1);            % 1x2 [dx dy]
    bbox = prev_bbox + [d(1), d(2), 0, 0];

    pts = new_valid;
    setPoints(tracker, pts);
end
