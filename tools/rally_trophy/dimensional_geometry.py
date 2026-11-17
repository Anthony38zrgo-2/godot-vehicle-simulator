"""Dimensional fitting for vehicle meshes in +Y up, -Z forward coordinates."""

from bisect import bisect_right
from dataclasses import dataclass
from math import isfinite


@dataclass(frozen=True)
class Dimensions:
    """Body envelope and axle centres in one coordinate system, in metres."""

    nose_z: float
    front_axle_z: float
    rear_axle_z: float
    tail_z: float
    width: float
    roof_y: float
    ground_y: float
    front_track: float
    rear_track: float

    @property
    def longitudinal_landmarks(self):
        return (self.nose_z, self.front_axle_z, self.rear_axle_z, self.tail_z)

    def __post_init__(self):
        if not all(isfinite(value) for value in vars(self).values()):
            raise ValueError("Dimensions must be finite")
        landmarks = self.longitudinal_landmarks
        if any(left >= right for left, right in zip(landmarks, landmarks[1:])):
            raise ValueError("Nose, front axle, rear axle and tail must be ordered")
        if min(self.width, self.front_track, self.rear_track) <= 0:
            raise ValueError("Body width and axle tracks must be positive")
        if self.roof_y <= self.ground_y:
            raise ValueError("Roof must be above ground")


@dataclass(frozen=True)
class DimensionalFit:
    source: Dimensions
    target: Dimensions

    def body_point(self, point):
        """Map a point on the centreline-symmetric body or an attached anchor."""
        x, y, z = point
        source = self.source.longitudinal_landmarks
        target = self.target.longitudinal_landmarks
        segment = bisect_right(source[1:-1], z)
        fraction = (z - source[segment]) / (source[segment + 1] - source[segment])
        return (
            x * self.target.width / self.source.width,
            self.target.ground_y
            + (y - self.source.ground_y)
            * (self.target.roof_y - self.target.ground_y)
            / (self.source.roof_y - self.source.ground_y),
            target[segment] + fraction * (target[segment + 1] - target[segment]),
        )

    def wheel_center(self, *, axle, side, radius):
        """Place a wheel at its target track and radius above the ground plane."""
        if axle not in ("front", "rear") or side not in ("left", "right"):
            raise ValueError("Expected front/rear axle and left/right side")
        if not isfinite(radius) or radius <= 0:
            raise ValueError("Wheel radius must be positive and finite")
        track, z = (
            (self.target.front_track, self.target.front_axle_z)
            if axle == "front"
            else (self.target.rear_track, self.target.rear_axle_z)
        )
        sign = -1 if side == "left" else 1
        return (sign * track / 2, self.target.ground_y + radius, z)
