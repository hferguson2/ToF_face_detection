function [is_real, plane_rms_mm, depth_face_mm] = score_face(depth_cm, bbox, thresh_mm)
% SCORE_FACE  Decide real face vs flat printout from the depth pixels inside a bbox.
%
%   The score is the RMS residual (in mm) of a least-squares plane fit to the
%   depth pixels inside the face bbox.  A flat printout looks like a plane and
%   gives a small residual (just sensor noise, a few mm).  A real face has a
%   protruding nose / receding eyes and gives a much larger residual.
%
%   Inputs
%     depth_cm   HxW double   depth image in cm (as produced by mxNI(2)/10)
%     bbox       1x4          [x y w h] in pixels (RGB == depth after mxNI(5))
%     thresh_mm  scalar       decision threshold on plane_rms_mm
%
%   Outputs
%     is_real         logical          plane_rms_mm > thresh_mm
%     plane_rms_mm    double           RMS plane-fit residual in mm
%     depth_face_mm   HfxWf double     cropped depth ROI in mm (for plotting)

    H = size(depth_cm, 1);
    W = size(depth_cm, 2);

    x1 = max(1, round(bbox(1)));
    y1 = max(1, round(bbox(2)));
    x2 = min(W, x1 + round(bbox(3)) - 1);
    y2 = min(H, y1 + round(bbox(4)) - 1);

    roi_mm = depth_cm(y1:y2, x1:x2) * 10;   % cm -> mm
    depth_face_mm = roi_mm;

    [Y, X] = ndgrid(y1:y2, x1:x2);

    % Drop zero pixels (no return) and background pixels more than 15 cm away
    % from the bbox median depth.  This is the simple, robust segmentation.
    valid_mm = roi_mm(roi_mm > 0);
    if numel(valid_mm) < 50
        is_real = false; plane_rms_mm = 0;
        return
    end
    med_mm = median(valid_mm);
    mask = roi_mm > 0 & abs(roi_mm - med_mm) < 150;   % +/- 15 cm

    z = roi_mm(mask);
    x = X(mask);
    y = Y(mask);

    if numel(z) < 50
        is_real = false; plane_rms_mm = 0;
        return
    end

    % Plane fit:  z ~= a*x + b*y + c
    A = [x(:), y(:), ones(numel(z), 1)];
    coef = A \ z(:);
    resid = z(:) - A * coef;
    plane_rms_mm = sqrt(mean(resid .^ 2));

    is_real = plane_rms_mm > thresh_mm;
end
