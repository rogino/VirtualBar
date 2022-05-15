#  VirtualBar

A Touch Bar, but worse, using computer vision and ML. Done as part of my COSC428 Computer Vision project.

Inspired by [Anish Athalye's MacBook touchscreen](https://www.anishathalye.com/2018/04/03/macbook-touchscreen/)

Using a mirror, the webcam sees the keyboard and uses this to detect two and three finger gestures
on the not-a-Touch Bar area above the keyboard to control system volume and brightness.

![three finger gesture gif](./img/three_finger.gif)

Brightness control is achieved using [nriley/brightness](https://github.com/nriley/brightness)

The gesture area is detected by taking the row mean to get a 1 px wide image, using the Sobel filter
to find the derivative, and using this to detect horizontal edges. Some heuristics are used to
determine the pair of edges that correspond to the gesture area above the keyboard.

Hands are detected using Apple's Vision framework. It doesn't work great, so the full hand needs to
be in the image. MediaPipe hands is better, but I could barely get it compiling and had no idea where
to start with porting it to macOS and integrating it with this system.

Works on my MacBook Air 2020. Will probably work on 13' MacBook Pros, 15' MacBook Pros with some
minor tweaking, and possibly on the 2021 MacBook Pros with some more tweaking.

Requires macOS Big Sur or later. Tested on an M1 Mac, so it might be very slow Intel ones.

## Code

- `MetalView` is responsible for setting up the camera. It outputs 720p video at 30 fps. If the
  `useLiveCamera` variable is set to false, input from a video file is used instead. The start
   and stop times, as well as the playback rate (`slowDown`) can be set in the `VideoFeed`
   constructor
- `Renderer` is resposible for the main render loop as well as processing. When a frame arrives,
   it is converted to a metal texture. Then:
   - `Straighten` straightens and corrects lens distortion, and the texture is given to `ImageMean`
   - `ImageMean` determines the active area and sets the static `activeArea` array to a list of
      candidate areas, the first being the top. Values are `[yMin, yMax]` where 0 is the bottom and
      1 is the top
      - `ActiveAreaDetector` is responsible for detecting possible active areas within a single frame 
      - `ActiveAreaSelector` keeps a record of active areas from previous frames
   - `FingerDetector` runs the hand pose detector on the original frame (not the straightened one)
      and sets the volume/brightness as required.
      - `GestureRecognizer` is responsible for determining gesture start/stop, and the type of gesture
      - When a gesture is detected, it tells `ActiveAreaSelector` to lock the current top candidate
