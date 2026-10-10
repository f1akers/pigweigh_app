#!/usr/bin/env python3
"""
Quick comparison: best.pt vs best_executorch_model via Ultralytics.
"""

from ultralytics import YOLO
import sys

if len(sys.argv) < 2:
    print("Usage: python compare_models.py <path/to/image.jpg>")
    sys.exit(1)

image_path = sys.argv[1]

# 1. Original PyTorch model
print("=" * 60)
print("1. Original PyTorch model (best.pt)")
print("=" * 60)
pt_model = YOLO(r"D:\pigweigh_train_2\runs\detect\pigweigh_2\yolo26n_v1_6402\weights\best.pt")
pt_results = pt_model(image_path, verbose=False)
for r in pt_results:
    for box in r.boxes:
        cls_id = int(box.cls)
        conf = float(box.conf)
        print(f"  class={cls_id}  conf={conf:.4f}")

# 2. ExecuTorch exported model
print("\n" + "=" * 60)
print("2. ExecuTorch exported model (best_executorch_model)")
print("=" * 60)
et_model = YOLO(r"D:\pigweigh_train_2\runs\detect\pigweigh_2\yolo26n_v1_6402\weights\best_executorch_model")
et_results = et_model(image_path, verbose=False)
for r in et_results:
    for box in r.boxes:
        cls_id = int(box.cls)
        conf = float(box.conf)
        print(f"  class={cls_id}  conf={conf:.4f}")
