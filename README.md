# Arch Linux Installer for HP ProBook 650 G1

A comprehensive script to automate the installation of Arch Linux specifically tailored for the HP ProBook 650 G1 laptop.

## Features
- Automated disk partitioning (GPT/UEFI)
- Base system installation and configuration
- Specific hardware fixes for HP BIOS/UEFI
- Intel Graphics optimization
- Power management setup (TLP, Powertop)
- Post-installation script for Desktop Environments (XFCE, KDE, GNOME, i3)

## Usage
1. Boot from Arch Linux installation media.
2. Ensure internet connection.
3. Download and run the script:
   ```bash
   curl -O https://raw.githubusercontent.com/Alouriii/arch-hp-probook-650-g1/main/install.sh
   chmod +x install.sh
   ./install.sh
   ```

## Disclaimer
**Warning:** This script will erase all data on the specified disk (default `/dev/sda`). Use at your own risk.
