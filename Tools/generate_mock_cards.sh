#!/bin/zsh
# Generates a suite of mock camera cards to support "Lab Simulation" testing
# without requiring physical cameras or large video files.

set -euo pipefail

ROOT_DIR="${0:A:h}/.."
MOCK_DIR="$ROOT_DIR/MockCards"

echo "🧹 Cleaning old mock cards..."
rm -rf "$MOCK_DIR"
mkdir -p "$MOCK_DIR"

echo "📷 Generating ARRI Alexa Mini LF Mock Card (A_CAM)"
ARRI_DIR="$MOCK_DIR/A001_ARRI"
mkdir -p "$ARRI_DIR"
touch "$ARRI_DIR/A001C001_240509_R2QA.mxf"
touch "$ARRI_DIR/A001C002_240509_R2QA.mxf"

echo "📷 Generating RED V-Raptor Mock Card (B_CAM)"
RED_DIR="$MOCK_DIR/B001_RED"
RDC1="$RED_DIR/B001_C001_0509X1.RDC"
RDC2="$RED_DIR/B001_C002_0509X1.RDC"
mkdir -p "$RDC1" "$RDC2"
touch "$RDC1/B001_C001_0509X1_001.R3D"
touch "$RDC2/B001_C002_0509X1_001.R3D"

echo "📷 Generating Sony FX3 / A7S3 Mock Card (Untitled / Generic)"
SONY_DIR="$MOCK_DIR/Untitled_Sony"
mkdir -p "$SONY_DIR/PRIVATE/M4ROOT/CLIP"
touch "$SONY_DIR/PRIVATE/M4ROOT/CLIP/C0001.MP4"
touch "$SONY_DIR/PRIVATE/M4ROOT/CLIP/C0001M01.XML"
touch "$SONY_DIR/PRIVATE/M4ROOT/CLIP/C0002.MP4"
touch "$SONY_DIR/PRIVATE/M4ROOT/CLIP/C0002M01.XML"

echo "📷 Generating Canon EOS R5 Mock Card (NO NAME / Generic)"
CANON_DIR="$MOCK_DIR/NO_NAME_Canon"
mkdir -p "$CANON_DIR/DCIM/100EOSR5"
touch "$CANON_DIR/DCIM/100EOSR5/8A9A0001.MP4"
touch "$CANON_DIR/DCIM/100EOSR5/8A9A0002.MP4"

echo "✅ Mock cards generated in: $MOCK_DIR"
echo "You can now drag and drop these folders into 321Doit as source drives for lab simulation testing."
