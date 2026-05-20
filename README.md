# ToF Final — 3D Face Anti-Spoofing

A MATLAB system that uses the LIPSEdge DL 3D ToF camera to tell a real human
face apart from a flat printed photo. A 2D face detector finds a face in the
RGB stream; the depth channel is then used to check whether the surface
actually has 3D structure (a nose protrusion, recessed eyes) or is flat like
a printout.

The system runs live from the camera and also re-plays prerecorded sequences,
and ships with a characterization routine that sweeps distance, yaw angle,
lighting, and orientation.


## Folder layout

```
ToF Final/
└── mxNI/
    ├── TOF_Final.m            (new)      Main workbook - the only script to run
    ├── detect_and_track.m     (new)      Face detection + KLT tracking
    ├── score_face.m           (new)      Plane-fit RMS classifier
    ├── mxNI.mexw64            (reused)   Compiled OpenNI2 wrapper, from ToF Lab 1
    ├── modify_config.m        (reused)   Near/far lens-mode switch, from ToF Lab 1
    ├── histroi.m              (reused)   ROI depth-stats helper, from ToF Lab 1
    ├── recordings/                       Saved .mat sequences (Section 4 output)
    └── figures/                          Saved plots (Section 5 output)
```

### What's new vs. what's reused

The three files marked `(new)` are written specifically for this project.

The three files marked `(reused)` are copied verbatim from my earlier ToF Lab 1
work in `~/Desktop/ToF Lab 1/mxNI/`:

| File              | Source                          | Why reused                                                  |
| ----------------- | ------------------------------- | ----------------------------------------------------------- |
| `mxNI.mexw64`     | `ToF Lab 1/mxNI/mxNI.mexw64`    | Compiled MATLAB wrapper around the OpenNI2 SDK. Rebuilding requires NiTE-Windows + OpenNI2 paths and adds nothing here — the binary is identical. |
| `modify_config.m` | `ToF Lab 1/mxNI/modify_config.m`| Writes the `lens_mode` field of `C:\Program Files\LIPSToF\ModuleConfig.json`. Called before `mxNI(0)` to switch between near (0) and far (1) mode. |
| `histroi.m`       | `ToF Lab 1/mxNI/histroi.m`      | Quick ROI mean/std/histogram plotting. Not on the critical path; kept around for debugging an ROI by hand. |


## What each new file does

### `TOF_Final.m`

Sectioned workbook, in the same `%%`-section style as Lab 1. Run section by
section the first time; once initialized, Sections 2/3/5 can be re-run alone.

| Section | Purpose                                                           |
| ------- | ----------------------------------------------------------------- |
| 0       | Camera init: `modify_config`, `mxNI(0)`, `mxNI(5)` registration, depth/RGB/IR streams |
| 1       | Threshold calibration: 15 real + 15 fake frames at ~50 cm, save `threshold.mat` |
| 2       | Live demo loop: RGB window with REAL/FAKE bbox overlay; close window to stop |
| 3       | Offline replay: walks `recordings/*.mat` and prints prediction vs ground truth |
| 4       | Record a sequence: edit metadata block, captures 60 frames with metadata |
| 5       | Characterization: accuracy vs distance / angle / lighting / orientation + confusion matrix |
| 6       | Camera close: `mxNI(1)`                                           |

### `detect_and_track.m`

Single function that wraps the standard MATLAB KLT face-tracking recipe:

1. On the first call (or after the tracker loses too many points), runs
   `vision.CascadeObjectDetector` (Viola-Jones) on the grayscale RGB frame
   to find a frontal face bounding box.
2. Seeds a `vision.PointTracker` with corners from `detectMinEigenFeatures`
   inside that bounding box.
3. On subsequent calls, steps the tracker on the new frame and translates
   the bbox by the **median displacement** of the valid tracked points.
   Translation-only is intentional — it's robust, predictable, and plenty
   for the head-on demo geometry.
4. If fewer than 10 points remain valid, signals "lost" by returning an
   empty tracker so the next call re-detects.

### `score_face.m`

Computes the spoof score and returns the real/fake decision.

The score is the **RMS residual of a least-squares plane fit** to the depth
pixels inside the face bbox (in mm). The idea: a flat printout is well
approximated by a plane, so the residual is just sensor noise (typically a
few mm). A real face has a protruding nose and recessed eyes, so the
residual is much larger (typically 12–25 mm at arm's length).

The function also masks out background pixels (anything more than ±15 cm
from the bbox's median depth) and zero-return pixels before fitting, so
that the bbox edges don't contaminate the score with whatever's behind the
face.


## Dependencies

- MATLAB R2018b or later (`xline` is used in the calibration plot)
- **Computer Vision Toolbox** — provides `vision.CascadeObjectDetector`,
  `detectMinEigenFeatures`, `vision.PointTracker`
- LIPSEdge DL 3D ToF camera with the LIPS ToF SDK installed at
  `C:\Program Files\LIPSToF\`
- Write permission on `C:\Program Files\LIPSToF\ModuleConfig.json`
  (`modify_config.m` rewrites this file at the start of each session)
- OpenNI2 + NiTE-Windows runtime on the host (required by `mxNI.mexw64`)

The system is Windows-only because of `mxNI.mexw64` and the hard-coded JSON
config path. The MATLAB source itself is platform-neutral.


## How to run

From the lab Windows machine:

```matlab
>> cd 'C:\Users\<you>\Desktop\ToF Final\mxNI'
>> edit TOF_Final.m
```

Then run sections in order:

1. **Section 0** — camera comes up, all three streams open.
2. **Section 1** — stand ~50 cm from the camera and press Enter; the script
   captures 15 frames of your face. Then hold a printed photo at ~50 cm and
   press Enter to capture 15 fake frames. The threshold is set halfway
   between the two means and saved to `threshold.mat`. A histogram is saved
   to `figures/calibration.png`.
3. **Section 2** — live demo. An RGB window opens with a colored bounding
   box and text label that flips between `REAL  rms=18.4 mm` (green) and
   `FAKE  rms=4.1 mm` (red) depending on what's in front of the camera.
   Close the figure window to exit.
4. **Section 4** — open the file and edit the metadata block at the top:

   ```matlab
   meta.distance_cm  = 50;
   meta.angle_deg    = 0;
   meta.lighting     = 'on';
   meta.orientation  = 'upright';
   meta.lens_mode    = 0;
   meta.label        = 'real';
   record_name       = 'real_50cm_0deg_lighton_upright';
   ```

   then run the section. Repeat across the conditions you want to
   characterize (a representative subset of ~15 recordings is enough).
5. **Section 5** — produces `figures/accuracy_vs_distance.png`,
   `accuracy_vs_angle.png`, `accuracy_vs_lighting.png`,
   `accuracy_vs_orientation.png`, and prints a confusion matrix.
6. **Section 6** — `mxNI(1)` to release the camera before unplugging.


## Algorithm in one paragraph

For each RGB+depth frame: detect a face with Viola-Jones, track it across
subsequent frames with KLT so detection doesn't have to run on every frame,
crop the depth image to the face bounding box, drop pixels that are zero or
more than 15 cm away from the bbox's median depth, fit a plane `z = ax + by + c`
to the surviving pixels, and compute the RMS residual in millimeters. If
that residual exceeds a threshold learned during calibration, classify the
face as real; otherwise classify it as a printout. The depth-to-RGB pixel
alignment comes for free from the LIPSEdge SDK's registration mode (enabled
by the `mxNI(5)` call in Section 0).


## Known limitations

- **Strong yaw breaks the score**: at ±45° or more the face starts to look
  planar to the camera because much of the depth variation lies along the
  optical axis. Section 5's accuracy-vs-angle plot quantifies this.
- **Single biggest face only**: `detect_and_track` keeps only the first hit
  from the cascade detector. Multi-face scenes are out of scope.
- **Near mode is assumed**: Section 0 calls `modify_config(0)`. For targets
  beyond ~1 m, switch to `modify_config(1)` and recalibrate the threshold
  (the noise floor changes, so the printout RMS distribution shifts).
- **`mxNI(5)` must succeed**: if the SDK call errors on this particular
  module, comment it out — the score is still computed but RGB-to-depth
  alignment becomes approximate, which inflates the printout RMS slightly.
  An affine-calibration fallback is sketched in the project plan but is
  not included in the shipped code because it has not been needed in
  testing.


## Quick troubleshooting

| Symptom                                          | Likely cause                                                                 |
| ------------------------------------------------ | ---------------------------------------------------------------------------- |
| `modify_config.m` errors on `fopen` / `fwrite`   | `ModuleConfig.json` not writable — chown / set permissions on it once       |
| `mxNI(0)` fails immediately                      | OpenNI2/NiTE runtime not installed, or another process is holding the camera |
| `Section 0` fails on `mxNI(5)`                   | Registration not supported by this firmware — comment that line out          |
| Always classifies as FAKE                        | Threshold set too high; rerun Section 1 with the camera at the demo distance |
| Always classifies as REAL                        | Threshold set too low; same fix                                              |
| `vision.CascadeObjectDetector` undefined         | Computer Vision Toolbox not licensed on this machine                         |
