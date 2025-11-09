#!/bin/bash

# Copy project to WSL home directory
echo "Setting up xray-wsl-bootstrap in WSL..."

# Create project directory
mkdir -p ~/project/xray-wsl-bootstrap

# Copy all files to WSL
rsync -av --exclude='.git' /mnt/z/home/fixplizz/project/xray-wsl-bootstrap/ ~/project/xray-wsl-bootstrap/ 2>/dev/null || {
    echo "Rsync failed, trying cp..."
    cp -r /mnt/z/home/fixplizz/project/xray-wsl-bootstrap/* ~/project/xray-wsl-bootstrap/ 2>/dev/null || {
        echo "Direct copy from current directory..."
        # If we're already in WSL, copy from current directory
        cp -r ./* ~/project/xray-wsl-bootstrap/
    }
}

# Go to project directory
cd ~/project/xray-wsl-bootstrap

echo "Project copied to: $(pwd)"
echo "Contents:"
ls -la

# Make scripts executable
chmod +x scripts/*.sh
chmod +x lib/*.sh

echo "Starting setup..."
bash scripts/setup-config.sh