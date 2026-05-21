# Strategy

## Problem statement

A face authentication system that uses only a 2D RGB image is trivially
fooled by holding up a printed photo of the target's face. Modern phones
(Face ID, Pixel face unlock) defeat this by also looking at the **3D shape**
of the face: a real face has a protruding nose, recessed eyes, and curved
cheeks, while a printout is flat. The goal of this project is to build the
same kind of liveness check from scratch using the LIPSEdge DL ToF camera,
which gives a co-registered RGB image and depth map at ~30 fps.

The system has to:

1. Find a face in the 2D RGB stream.
2. Look at the depth pixels under that face.
3. Decide real vs. printout from the depth shape alone.
4. Run live and also off prerecorded captures.
5. Be characterized across distance, yaw angle, lighting, and orientation.


## Why use depth at all

A printed photo and a real face look essentially identical in the RGB
channel — that's the whole point of the spoof. They differ in two physical
ways the ToF camera *can* see:

| Property                 | Real face                          | Flat printout                |
| ------------------------ | ---------------------------------- | ---------------------------- |
| 3D surface shape         | Nose protrudes ~20 mm, eyes recess | Planar to within ~1 mm        |
| IR reflectance pattern   | Skin-specific                      | Paper / glossy print          |

I chose to key on the **shape** signal rather than the reflectance signal,
for three reasons:

- Reflectance is sensitive to ambient IR, distance, and skin tone, which
  makes a fixed threshold fragile across conditions.
- The shape signal has a much larger separation than the noise floor at the
  ranges we care about (~30–90 cm), so a single scalar feature suffices.
- Shape is what's actually being *spoofed*, so the writeup is cleaner: the
  attacker has to physically build a 3D mask to defeat the system.


## Pipeline

```
   ┌──────────┐   ┌──────────────┐   ┌────────────┐   ┌────────────┐   ┌────────────┐
   │  RGB +   │──▶│ Face detect  │──▶│ KLT track  │──▶│ Crop depth │──▶│ Plane fit  │
   │  depth   │   │ (Viola-Jones)│   │ across     │   │ to face    │   │ RMS in mm  │
   │  frame   │   │              │   │ frames     │   │ bbox       │   │            │
   └──────────┘   └──────────────┘   └────────────┘   └────────────┘   └─────┬──────┘
                                                                              │
                                                              ┌───────────────┴───────────────┐
                                                              │  RMS > threshold  →  REAL     │
                                                              │  RMS ≤ threshold  →  FAKE     │
                                                              └───────────────────────────────┘
```

Each stage is one of the cheapest options that gets the job done — that
choice is deliberate, because the system has to run live during the demo
and the report has to defend every step.


## Stage-by-stage rationale

### 1. Capture (mxNI wrapper, reused from Lab 1)

I'm reusing the OpenNI2 MATLAB wrapper from my ToF Lab 1 work because it
already gives me everything I need: `mxNI(2)` returns the depth image in
millimeters, `mxNI(3)` returns the RGB image, and `mxNI(5)` turns on
**depth↔RGB registration** inside the SDK. With registration enabled, RGB
pixel `(y, x)` corresponds to depth pixel `(y, x)`, which means I don't
have to calibrate or apply a homography between the two sensors. That is
the single most useful simplification in the whole project; without it the
ROI cropping in Stage 4 would need its own calibration step.

The depth values are cast to `double` and divided by 10 so I'm working in
centimeters, matching the convention used in Lab 1.

### 2. Face detection — `vision.CascadeObjectDetector` (Viola-Jones)

I picked the built-in Viola-Jones frontal-face detector for two reasons:

- It is the same detector the official MATLAB KLT face-tracking tutorial
  uses, which means I can borrow that tutorial's known-good initialization
  code without modification.
- It runs in ~5–10 ms per frame on a normal lab laptop, which is fast
  enough to re-detect at any time if the tracker drifts off.

A deep-learning detector (RetinaFace, MTCNN) would be more accurate at
extreme poses but adds GPU dependency, model weights, and inference time —
none of which buy me anything at the demo's near-frontal geometry.

### 3. Tracking — `vision.PointTracker` (KLT)

I don't actually need a tracker to compute the spoof score — the detector
could run on every frame. I track for two reasons:

- It makes the live demo look smooth. Re-running Viola-Jones every frame
  produces a slightly jittery box because the detector rounds to a fixed
  grid and occasionally misses; KLT gives a sub-pixel-stable bbox between
  re-detects.
- It demonstrates a standard CV pipeline (detect-then-track) instead of
  just calling a black-box detector in a loop.

I simplified the textbook KLT recipe in one way: I only use the **median
2-D translation** of the valid tracked points to update the bbox, rather
than the full affine/similarity transform from
`estimateGeometricTransform2D`. At our viewing geometry the face barely
rotates, so translation-only is more robust to point outliers and easier
to explain on a whiteboard. When more than 90% of points are lost (face
turns away, hand crosses face, etc.) the tracker resets and the next call
re-detects.

### 4. ROI cropping and segmentation

Once I have a face bbox in RGB, I crop the **registered depth image** to
the same bbox. The bbox is rectangular, so it also contains some
background pixels along the edges. I drop two kinds of pixels before the
plane fit:

- Zero-depth pixels (the ToF camera writes 0 where it has no valid range
  return — usually edges, hair, dark surfaces).
- Pixels more than ±15 cm away from the bbox's **median depth**. The
  median is a robust estimator of "the distance to the face", so anything
  much closer or much farther is either background (the wall behind the
  person) or foreground clutter (a hand). 15 cm is loose enough to keep
  the entire face (forehead to chin in profile is at most ~25 cm, and
  we're looking at it nearly frontal) and tight enough to drop the wall.

This is intentionally not a real segmentation model. A proper face mask
(skin segmentation, GrabCut, a learned mask) would help at strong yaw, but
on flat-vs-3D classification the simple depth-median gate is already very
discriminative because the printout is at one depth and the wall behind it
is at a different depth.

### 5. The spoof score: RMS plane-fit residual

This is the key idea. Let the masked face depth pixels be points
`(xᵢ, yᵢ, zᵢ)` in millimeters, where `xᵢ` and `yᵢ` are pixel coordinates
and `zᵢ` is the depth value. I fit the plane

```
    z̃(x, y) = a·x + b·y + c
```

by least squares (in MATLAB: `coef = [x y 1] \ z`), and compute

```
    plane_rms_mm = sqrt( mean( (zᵢ − z̃(xᵢ, yᵢ))² ) )
```

This number has a clean physical meaning: it is the root-mean-square
deviation of the face surface from the best-fit plane, in millimeters.
For a printout that's actually a plane, the residual is just the camera's
depth noise — typically 3–6 mm in near mode at 50 cm. For a real face,
the nose alone protrudes ~15–25 mm, and the eyes recess by a similar
amount, so the residual is much larger.

I deliberately did not stack multiple features (depth std, depth range,
center-vs-ring depth, surface normals, point-cloud descriptors). One
scalar feature with a clear interpretation is much easier to defend in a
live demo than a 5-feature logistic regression that adds 1–2% accuracy on
the held-out data.

### 6. Decision: a single learned threshold

Rather than hard-coding a threshold like "10 mm", I learn it from a short
calibration capture taken at the start of every session (Section 1 in the
workbook):

1. Capture 15 frames of a real face at ~50 cm.
2. Capture 15 frames of a printed photo at ~50 cm.
3. Compute `plane_rms_mm` for each frame.
4. Set `THRESH = (mean(real_rms) + mean(fake_rms)) / 2` and save it to
   `threshold.mat`.

The midpoint-of-means rule is a textbook one-feature Bayes-optimal
threshold under the (very loose) assumption that the two classes are
roughly Gaussian with similar variance. In practice the real and fake
distributions are so well separated (gap ≈ 10 mm, sd ≈ 2 mm each) that
the exact rule doesn't matter — any threshold inside the gap works. The
calibration step is mostly there to absorb session-to-session drift:
ambient IR, lens-mode, camera warm-up time.


## Why this design demos well

A few specific decisions that came from "this has to run live for the
professor" rather than from pure accuracy:

- **One feature, one threshold.** I can write the decision rule on a
  whiteboard in two lines, and the score number on screen lines up with
  intuition (bigger = more 3D = more real).
- **No state across the demo.** Sections 0 and 1 set everything up; from
  then on, each frame is processed independently except for the KLT
  tracker, which auto-resets when it fails.
- **Visible failure modes.** When the system gets it wrong (e.g. at strong
  yaw) the on-screen RMS number tells you why: the score crashed because
  the face is now mostly planar to the camera. The professor can see the
  failure and immediately know the cause.
- **No deep learning, no GPU.** Everything runs on CPU in the MATLAB
  Computer Vision Toolbox, so the demo machine doesn't need any
  per-installation setup beyond what Lab 1 already required.


## Characterization plan

The assignment asks for accuracy across distance, angle, lighting, and
orientation. Section 4 of the workbook captures one labeled `.mat` file
per condition, and Section 5 walks all recordings and produces:

- Accuracy vs. distance bar chart (30, 45, 60, 75, 90 cm)
- Accuracy vs. yaw angle bar chart (−30°, 0°, +30°)
- Accuracy vs. lighting bar chart (room light on / off)
- Accuracy vs. orientation bar chart (upright / tilted)
- A 2×2 confusion matrix printed to the console

What I expect to see:

- **Distance**: best around 50–60 cm where the ToF camera's near-mode
  noise floor is lowest. At 30 cm the face is so close that parts may
  fall outside the bbox; at 90 cm the noise floor rises and the gap
  between real and fake RMS shrinks.
- **Angle**: best at 0° yaw, degrading toward ±30°. At extreme yaw the
  side of the face is more planar to the camera, so a real face starts
  to look more like a printout.
- **Lighting**: roughly invariant. The ToF range measurement uses an
  active IR modulation that is largely decoupled from visible ambient
  light. This is one of the advantages of ToF over passive stereo.
- **Orientation**: minimal effect. Rotating the face in-plane changes
  the bbox aspect ratio but not the depth shape under it, so the
  plane-fit residual barely moves.


## Limitations and honest caveats

- **Yaw is the main failure mode.** A real face at ≥45° yaw can score
  below threshold. A more sophisticated system would use surface
  curvature instead of plane RMS, or learn a small classifier on top of
  several features.
- **A curved photo would defeat me.** If an attacker wraps the printed
  photo around a cylinder, the residual goes up and my detector says
  "real". The literature solution is to also check IR reflectance or
  use a structured-light pattern, neither of which I'm doing.
- **Single biggest face.** I take only the first detection result and
  ignore multi-face scenes. Fine for one-on-one authentication; not
  fine for surveillance.
- **The threshold is per-session.** That's the price of the very simple
  classifier. A more elaborate system would calibrate once and rely on
  the camera's repeatability. In practice the session-to-session drift
  is small enough that the same threshold often works for a whole day.
