from itertools import count
import math
import os
import random
import time
import cv2
import numpy as np


# videoName = "yuuki_mbp_16.mov"
# videoName = "project_test_footage.avi"

# cap = cv2.VideoCapture(os.path.join(os.path.dirname(__file__), videoName))
cap = cv2.VideoCapture(0)

# image = cv2.imread("/Users/rioog/Downloads/iu.png")


windowName = "windowname"
cv2.namedWindow(windowName)

while cap.isOpened():
# modification_angle = 5
# while True:
#   modification_angle += 0.1
#   if modification_angle > 7:
#     modification_angle = -7
#   image_center = tuple((np.array(image.shape[1::-1]) / 2).astype(np.int16))
#   rotation_matrix = cv2.getRotationMatrix2D(image_center, modification_angle, 1.0)
#   cap = cv2.warpAffine(image, rotation_matrix, image.shape[1::-1], flags=cv2.INTER_LINEAR)
#   frame = cap

  ret, frame = cap.read()
  viewport_image = frame
  frame_center = tuple((np.array(frame.shape[1::-1]) / 2).astype(np.int16))

  edge_cutoff = 100
  left = frame[0:frame.shape[0], edge_cutoff:frame_center[0]]
  left_avged = cv2.reduce(left, 1, cv2.REDUCE_AVG)

  right = frame[0:frame.shape[0], frame_center[0]:(frame.shape[1] - edge_cutoff)]
  right_avged = cv2.reduce(right, 1, cv2.REDUCE_AVG)

  centerXDelta = frame_center[0] - edge_cutoff

  offsets = []
  # if True:
  for i in range(-10, 10):
    # i = 1
    total = 0
    jMin = max(0, i)
    jMax = min(720, 720 + i)
    for j in range(jMin, jMax):
      # can only find delta for intersection
      delta = left_avged[j].astype(np.float32) - right_avged[j - i].astype(np.float32)
      delta = np.dot(delta[0], delta[0])
      total += math.sqrt(delta)
    offsets.append((i, total / (jMax - jMin)))

  for x in [(x[0], round(((np.arctan(x[0]/centerXDelta) * 180/math.pi) if x[0] != 0 else 0), ndigits=1), x[1]) for x in offsets]:
    print(x)

  offsets.sort(key = lambda x: x[1])

  yDelta = offsets[0][0]
  if yDelta != 0:
    angle = np.arctan(-yDelta/centerXDelta) * 180 / math.pi
    # print("Actual angle: " + str(modification_angle))
    print("Angle: " + str(round(angle, ndigits=1)))
    # print("ERROR: " + str(round(abs(angle + modification_angle), ndigits=2)))
    rotation_matrix = cv2.getRotationMatrix2D(frame_center, angle, 1.0)
    viewport_image = cv2.warpAffine(frame, rotation_matrix, frame.shape[1::-1], flags=cv2.INTER_LINEAR)

  original_averaged = cv2.reduce(frame, 1, cv2.REDUCE_AVG)
  rotated_averaged = cv2.reduce(viewport_image, 1, cv2.REDUCE_AVG)
  viewport_image = np.concatenate((
      cv2.resize(original_averaged,  (left.shape[1], left.shape[0])),
      cv2.resize(rotated_averaged, (left.shape[1], left.shape[0])),
    ),
    axis = 1
  )

  # right_avged = np.roll(right_avged, offsets[0][0], axis=0)
  # viewport_image = np.concatenate((
  #     cv2.resize(left_avged,  (left.shape[1], left.shape[0])),
  #     cv2.resize(right_avged, (left.shape[1], left.shape[0])),
  #   ),
  #   axis = 1
  # )

  # viewport_image = right



  cv2.imshow(windowName, viewport_image)
  key = cv2.waitKey(100) & 0xFF
  if key == ord('q'):  # Close the script when q is pressed.
    break

# Release the camera device and close the GUI.
cap.release()
cv2.destroyAllWindows()
