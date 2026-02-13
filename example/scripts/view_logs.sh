#!/bin/bash

# Script to view Flutter app logs from a manually launched app

echo "Flutter Log Viewer"
echo "=================="
echo ""
echo "Select an option:"
echo "1. View Flutter logs (flutter logs)"
echo "2. View Flutter logs with clear (-c)"
echo "3. Attach to Flutter app (flutter attach)"
echo "4. View iOS Simulator logs"
echo "5. View logs for specific device"
echo ""
read -p "Enter option (1-5): " option

case $option in
  1)
    echo "Viewing Flutter logs..."
    flutter logs
    ;;
  2)
    echo "Clearing and viewing Flutter logs..."
    flutter logs -c
    ;;
  3)
    echo "Attaching to Flutter app..."
    flutter attach
    ;;
  4)
    echo "Viewing iOS Simulator logs..."
    xcrun simctl spawn booted log stream --predicate 'processImagePath contains "Runner"'
    ;;
  5)
    echo "Available devices:"
    flutter devices
    echo ""
    read -p "Enter device ID: " device_id
    flutter logs -d "$device_id"
    ;;
  *)
    echo "Invalid option"
    exit 1
    ;;
esac


