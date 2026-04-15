#!/bin/bash
# Train MTG Card Detector model from collected training data
#
# Usage:
#   ./scripts/train_model.sh [training_data_path]
#
# If no path provided, looks for training_data in common locations:
#   1. Current directory
#   2. ~/Desktop/training_data
#   3. Downloads

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MODEL_NAME="MTGCardDetector"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  MTG Card Detector — Model Trainer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Find training data
TRAINING_DATA=""
if [ -n "$1" ]; then
    TRAINING_DATA="$1"
elif [ -d "./training_data" ]; then
    TRAINING_DATA="./training_data"
elif [ -d "$HOME/Desktop/training_data" ]; then
    TRAINING_DATA="$HOME/Desktop/training_data"
elif [ -d "$HOME/Downloads/training_data" ]; then
    TRAINING_DATA="$HOME/Downloads/training_data"
fi

if [ -z "$TRAINING_DATA" ] || [ ! -f "$TRAINING_DATA/annotations.json" ]; then
    echo "Training data not found!"
    echo ""
    echo "To get training data from your iPhone:"
    echo "  1. Connect iPhone to Mac"
    echo "  2. Open Finder → iPhone → Files"
    echo "  3. Expand MTG Keyan → training_data"
    echo "  4. Drag the folder to your Desktop"
    echo "  5. Run: ./scripts/train_model.sh ~/Desktop/training_data"
    echo ""
    echo "Or provide the path directly:"
    echo "  ./scripts/train_model.sh /path/to/training_data"
    exit 1
fi

# Count annotations
COUNT=$(python3 -c "import json; print(len(json.load(open('$TRAINING_DATA/annotations.json'))))" 2>/dev/null || echo "0")
echo "Found $COUNT annotated images in: $TRAINING_DATA"

if [ "$COUNT" -lt 10 ]; then
    echo ""
    echo "Need at least 10 annotated images."
    echo "Collect more using Split Cards in the app."
    exit 1
fi

echo ""
echo "Training model with $COUNT images..."
echo "This will take 5-15 minutes."
echo ""

# Train using the Swift script
swift "$SCRIPT_DIR/train_card_detector.swift" "$TRAINING_DATA"

# Check if model was created
MODEL_PATH="$PROJECT_DIR/Resources/$MODEL_NAME.mlmodel"
if [ -f "$MODEL_PATH" ]; then
    echo ""
    echo "✓ Model trained successfully!"
    echo "  Location: $MODEL_PATH"
    echo ""
    echo "To deploy:"
    echo "  ./scripts/deploy.sh 00008130-0014508C3C8A001C"
    echo ""
else
    echo "Model file not found at expected location."
    exit 1
fi
