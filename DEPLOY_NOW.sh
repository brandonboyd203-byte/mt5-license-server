#!/bin/bash

# License Server - Quick Deploy Script
# This script helps you deploy to Railway

echo "=========================================="
echo "License Server - Railway Deployment"
echo "=========================================="
echo ""

# Check if Railway CLI is installed
if ! command -v railway &> /dev/null; then
    echo "Installing Railway CLI..."
    npm install -g @railway/cli
    echo ""
fi

echo "Step 1: Login to Railway"
echo "This will open your browser..."
railway login

echo ""
echo "Step 2: Initializing Railway project..."
railway init

echo ""
echo "Step 3: Setting up environment variables..."
echo "Generating SECRET_KEY..."
SECRET_KEY=$(openssl rand -hex 32)
railway variables set SECRET_KEY=$SECRET_KEY
echo "SECRET_KEY set: $SECRET_KEY"
echo ""

echo "Step 4: Deploying to Railway..."
railway up

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo "Getting your server URL..."
railway domain

echo ""
echo "Next steps:"
echo "1. Copy the URL above"
echo "2. Update your EAs: LicenseServerURL = 'your-url'"
echo "3. Add licenses using admin panel or API"
echo ""
