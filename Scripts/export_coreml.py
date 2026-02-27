#!/usr/bin/env python3
"""
Export YOLO26 to CoreML format using ultralytics.

Setup:
    pip install ultralytics

Usage:
    python3 Scripts/export_coreml.py

    Or directly via CLI:
    yolo export model=yolo26n.pt format=coreml imgsz=640

Output:
    yolo26n.mlpackage  — drag this into your Xcode project
"""

from ultralytics import YOLO

model = YOLO("yolo26n.pt")
model.export(format="coreml", imgsz=640)
