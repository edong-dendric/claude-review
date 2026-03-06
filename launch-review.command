#!/bin/bash
# This .command file opens in Terminal.app when double-clicked or launched as a Login Item
cd "$(dirname "$0")"
exec ./review-projects.sh
