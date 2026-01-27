#!/bin/bash

# Script to push license server to GitHub

echo "=========================================="
echo "Pushing License Server to GitHub"
echo "=========================================="
echo ""

cd /Users/brandonboyd/Documents/discord-gpt-bot/license-server

# Initialize git if not already
if [ ! -d .git ]; then
    echo "Initializing git repository..."
    git init
fi

# Add all files
echo "Adding files..."
git add .

# Commit
echo "Committing..."
git commit -m "Initial commit - MT5 License Server"

# Add remote (user will need to replace with their actual repo URL)
echo ""
echo "=========================================="
echo "Next: Add your GitHub repository URL"
echo "=========================================="
echo ""
echo "After creating the repo on GitHub, copy the URL and run:"
echo ""
echo "git remote add origin https://github.com/brandonboyd203-byte/mt5-license-server.git"
echo "git branch -M main"
echo "git push -u origin main"
echo ""
