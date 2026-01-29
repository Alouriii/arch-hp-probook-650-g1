#!/bin/bash
# ============================================
# Arch Linux Installation Script for HP ProBook 650 G1
# ============================================

set -e  # Stop execution on any error

# Display Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================
# Check for root execution
# ============================================
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

# ============================================
# Device Settings
# ============================================
DISK="/dev/sda"           # Main Disk (Verify this!)
HOSTNAME="probook-arch"   # Hostname
USERNAME="user"           # Username (Change it)
TIMEZONE="Asia/Riyadh"    # Timezone

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Installing Arch Linux on HP ProBook 650 G1${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# ============================================
# Check UEFI
# ============================================
echo -e "${YELLOW}[1/10] Checking UEFI mode...${NC}"
if [[ ! -d /sys/firmware/efi/efivars ]]; then
    echo -e "${RED}Error: Not booted in UEFI mode!${NC}"
    echo -e "Reboot and set BIOS to UEFI Mode"
    exit 1
fi
echo -e "${GREEN}✓ UEFI available${NC}"

# ============================================
# Network Connection
# ============================================
echo -e "${YELLOW}[2/10] Checking network connection...${NC}"
if ! ping -c 1 archlinux.org &> /dev/null; then
    echo -e "${RED}No network connection!${NC}"
    echo "Set up network manually using: iwctl or dhcpcd"
    exit 1
fi
echo -e "${GREEN}✓ Connected to network${NC}"

# ============================================
# Update Clock
# ============================================
echo -e "${YELLOW}[3/10] Updating clock...${NC}"
timedatectl set-ntp true
timedatectl status
echo -e "${GREEN}✓ Clock updated${NC}"

# ============================================
# Disk Partitioning (GPT/UEFI)
# ============================================
echo -e "${YELLOW}[4/10] Partitioning disk...${NC}"
echo -e "${RED}Warning: All data on $DISK will be erased!${NC}"
read -p "Are you sure? Type YES to continue: " confirm
if [[ $confirm != "YES" ]]; then
    echo "Installation cancelled"
    exit 1
fi

# Erase disk and create new partition table
wipefs -af "$DISK"
sgdisk -Z "$DISK"

# Create partitions
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI System" "$DISK"      # EFI
sgdisk -n 2:0:+8G -t 2:8200 -c 2:"Linux Swap" "$DISK"        # Swap
sgdisk -n 3:0:+100G -t 3:8300 -c 3:"Arch Linux" "$DISK"      # Root
sgdisk -n 4:0:0 -t 4:8300 -c 4:"Home" "$DISK"                # Home

# Update partition table
partprobe "$DISK"
sleep 2

# Determine partition names
if [[ "$DISK" == *"nvme"* ]]; then
    EFI="${DISK}p1"
    SWAP="${DISK}p2"
    ROOT="${DISK}p3"
    HOME="${DISK}p4"
else
    EFI="${DISK}1"
    SWAP="${DISK}2"
    ROOT="${DISK}3"
    HOME="${DISK}4"
fi

echo -e "${GREEN}✓ Partitions created:${NC}"
lsblk "$DISK"

# ============================================
# Format Partitions
# ============================================
echo -e "${YELLOW}[5/10] Formatting partitions...${NC}"

mkfs.fat -F32 -n EFI "$EFI"
mkswap -L Swap "$SWAP"
mkfs.ext4 -L ArchRoot "$ROOT"
mkfs.ext4 -L ArchHome "$HOME"

swapon "$SWAP"

echo -e "${GREEN}✓ Partitions formatted${NC}"

# ============================================
# Mount Partitions
# ============================================
echo -e "${YELLOW}[6/10] Mounting partitions...${NC}"

mount "$ROOT" /mnt
mkdir -p /mnt/boot/efi
mkdir -p /mnt/home
mount "$EFI" /mnt/boot/efi
mount "$HOME" /mnt/home

echo -e "${GREEN}✓ Partitions mounted${NC}"
df -h

# ============================================
# Install Base System
# ============================================
echo -e "${YELLOW}[7/10] Installing base system...${NC}"

pacstrap -K /mnt base base-devel linux linux-firmware \
    intel-ucode vim nano networkmanager sudo grub efibootmgr \
    os-prober dosfstools mtools git wget curl \
    mesa lib32-mesa vulkan-intel lib32-vulkan-intel \
    intel-media-driver libva-intel-driver \
    xf86-video-intel \
    tlp tlp-rdw powertop \
    acpi_call \
    fprintd libfprint \
    broadcom-wl-dkms linux-headers \
    dhcpcd iwd

echo -e "${GREEN}✓ Base system installed${NC}"

# ============================================
# Setup fstab
# ============================================
echo -e "${YELLOW}[8/10] Setting up fstab...${NC}"
genfstab -U /mnt >> /mnt/etc/fstab
cat /mnt/etc/fstab
echo -e "${GREEN}✓ fstab configured${NC}"

# ============================================
# System Configuration inside chroot
# ============================================
echo -e "${YELLOW}[9/10] System configuration...${NC}"

arch-chroot /mnt /bin/bash <<CHROOT_EOF

# Timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Language
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "ar_SA.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Keyboard
echo "KEYMAP=us" > /etc/vconsole.conf

# Hostname
echo "$HOSTNAME" > /etc/hostname

# hosts
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

# root password
echo "root:123456" | chpasswd

# Create user
useradd -m -G wheel,audio,video,storage,network,power -s /bin/bash "$USERNAME"
echo "$USERNAME:123456" | chpasswd

# sudo
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# Enable services
systemctl enable NetworkManager
systemctl enable tlp
systemctl enable dhcpcd

CHROOT_EOF

echo -e "${GREEN}✓ System configured${NC}"

# ============================================
# Install GRUB with HP Fix
# ============================================
echo -e "${YELLOW}[10/10] Installing GRUB...${NC}"

arch-chroot /mnt /bin/bash <<CHROOT_EOF

# Install GRUB
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB

# Magic fix for HP problem: copy GRUB to Windows path
mkdir -p /boot/efi/EFI/Microsoft/Boot
cp /boot/efi/EFI/grub/grubx64.efi /boot/efi/EFI/Microsoft/Boot/bootmgfw.efi

# Create GRUB config
grub-mkconfig -o /boot/grub/grub.cfg

CHROOT_EOF

echo -e "${GREEN}✓ GRUB installed${NC}"

# ============================================
# Copy Post-Install Script
# ============================================
echo -e "${YELLOW}Copying post-install script...${NC}"

cat > /mnt/home/$USERNAME/post-install.sh <<'POSTEOF'
#!/bin/bash
# ============================================
# Post-Install Script - HP ProBook 650 G1
# ============================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Post-Installation Settings${NC}"
echo -e "${GREEN}========================================${NC}"

# ============================================
# Intel Graphics Settings
# ============================================
echo -e "${YELLOW}[1/6] Intel Graphics settings...${NC}"

sudo mkdir -p /etc/X11/xorg.conf.d/

sudo tee /etc/X11/xorg.conf.d/20-intel.conf > /dev/null <<EOF
Section "Device"
    Identifier  "Intel Graphics"
    Driver      "intel"
    Option      "TearFree"    "true"
    Option      "AccelMethod" "sna"
    Option      "DRI"         "3"
EndSection
EOF

echo -e "${GREEN}✓ Intel Graphics configured${NC}"

# ============================================
# Fix Shutdown/Wakeup Problem
# ============================================
echo -e "${YELLOW}[2/6] Fixing shutdown problem...${NC}"

sudo tee /etc/modprobe.d/blacklist.conf > /dev/null <<EOF
# Fix HP ProBook 650 G1 wakeup immediately after shutdown
blacklist hp-wmi
EOF

echo -e "${GREEN}✓ Shutdown problem fixed${NC}"

# ============================================
# Kernel Settings for Suspend/Hibernate
# ============================================
echo -e "${YELLOW}[3/6] Kernel settings...${NC}"

sudo sed -i 's/^MODULES=(/MODULES=(intel_agp i915 /' /etc/mkinitcpio.conf
sudo mkinitcpio -P

echo -e "${GREEN}✓ Kernel modules updated${NC}"

# ============================================
# System Settings
# ============================================
echo -e "${YELLOW}[4/6] System settings...${NC}"

sudo tee /etc/sysctl.d/99-sysctl.conf > /dev/null <<EOF
# Performance optimization
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF

echo -e "${GREEN}✓ System settings configured${NC}"

# ============================================
# Install Desktop Environment (Optional)
# ============================================
echo -e "${YELLOW}[5/6] Choosing Desktop Environment...${NC}"

echo "Choose Desktop Environment:"
echo "1) XFCE (Light and fast)"
echo "2) KDE Plasma (Beautiful and complete)"
echo "3) GNOME (Modern and simple)"
echo "4) i3 (For advanced users)"
echo "5) None (Command line only)"

read -p "Choose a number (1-5): " choice

case $choice in
    1)
        echo "Installing XFCE..."
        sudo pacman -S --noconfirm xfce4 xfce4-goodies lightdm lightdm-gtk-greeter
        sudo systemctl enable lightdm
        ;;
    2)
        echo "Installing KDE Plasma..."
        sudo pacman -S --noconfirm plasma-meta kde-applications sddm
        sudo systemctl enable sddm
        ;;
    3)
        echo "Installing GNOME..."
        sudo pacman -S --noconfirm gnome gnome-tweaks gdm
        sudo systemctl enable gdm
        ;;
    4)
        echo "Installing i3..."
        sudo pacman -S --noconfirm i3 dmenu rxvt-unicode lightdm lightdm-gtk-greeter
        sudo systemctl enable lightdm
        ;;
    5)
        echo "Desktop Environment skipped"
        ;;
    *)
        echo "Invalid choice, skipping"
        ;;
esac

echo -e "${GREEN}✓ Desktop Environment installed${NC}"

# ============================================
# Install Additional Software
# ============================================
echo -e "${YELLOW}[6/6] Installing additional software...${NC}"

sudo pacman -S --noconfirm \
    firefox \
    vlc \
    libreoffice-still \
    htop \
    neofetch \
    pavucontrol \
    pulseaudio \
    pulseaudio-alsa \
    alsa-utils \
    xdg-utils \
    xdg-user-dirs \
    gvfs \
    ntfs-3g \
    exfat-utils

# Create user directories
xdg-user-dirs-update

echo -e "${GREEN}✓ Additional software installed${NC}"

# ============================================
# System Test
# ============================================
echo -e "${YELLOW}Testing system...${NC}"

echo "Graphics Information:"
glxinfo | grep "OpenGL renderer" || echo "Not available (install mesa-utils)"

echo ""
echo "Network Status:"
ip link show

echo ""
echo "Battery Status:"
cat /sys/class/power_supply/BAT*/status 2>/dev/null || echo "No battery found"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Finished!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Important Notes:"
echo "1. Default password: 123456"
echo "2. Change password immediately: passwd"
echo "3. Reboot to enter the new system"
echo ""
echo "For future updates use: sudo pacman -Syu"

POSTEOF

chmod +x /mnt/home/$USERNAME/post-install.sh
chown $USERNAME:$USERNAME /mnt/home/$USERNAME/post-install.sh

echo -e "${GREEN}✓ Post-install script copied to /home/$USERNAME/${NC}"

# ============================================
# Finish
# ============================================
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Installation Successful!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Next Steps:"
echo "1. Exit chroot: exit"
echo "2. Unmount partitions: umount -R /mnt"
echo "3. Reboot: reboot"
echo ""
echo "After entering the new system:"
echo "1. Login with username: $USERNAME"
echo "2. Run post-install script: ./post-install.sh"
echo "3. Follow instructions to complete setup"
echo ""
echo "Note: Default password is '123456'"
echo -e "${YELLOW}Password change recommended immediately!${NC}"
