#!/bin/bash
# ============================================
# سكربت تثبيت Arch Linux على HP ProBook 650 G1
# ============================================

set -e  # إيقاف التنفيذ عند أي خطأ

# الألوان للعرض
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================
# التحقق من التشغيل كـ root
# ============================================
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}هذا السكربت يجب تشغيله كـ root${NC}"
   exit 1
fi

# ============================================
# إعدادات الجهاز
# ============================================
DISK="/dev/sda"           # القرص الرئيسي (تأكد منه!)
HOSTNAME="probook-arch"   # اسم الجهاز
USERNAME="user"           # اسم المستخدم (غيره)
TIMEZONE="Asia/Riyadh"    # المنطقة الزمنية

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  تثبيت Arch Linux على HP ProBook 650 G1${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# ============================================
# التحقق من UEFI
# ============================================
echo -e "${YELLOW}[1/10] التحقق من وضع UEFI...${NC}"
if [[ ! -d /sys/firmware/efi/efivars ]]; then
    echo -e "${RED}خطأ: لم يتم التمهيد في وضع UEFI!${NC}"
    echo -e "أعد التشغيل واضبط BIOS على UEFI Mode"
    exit 1
fi
echo -e "${GREEN}✓ UEFI متوفر${NC}"

# ============================================
# الاتصال بالشبكة
# ============================================
echo -e "${YELLOW}[2/10] التحقق من الاتصال بالشبكة...${NC}"
if ! ping -c 1 archlinux.org &> /dev/null; then
    echo -e "${RED}لا يوجد اتصال بالشبكة!${NC}"
    echo "اضبط الشبكة يدوياً باستخدام: iwctl أو dhcpcd"
    exit 1
fi
echo -e "${GREEN}✓ متصل بالشبكة${NC}"

# ============================================
# تحديث الساعة
# ============================================
echo -e "${YELLOW}[3/10] تحديث الساعة...${NC}"
timedatectl set-ntp true
timedatectl status
echo -e "${GREEN}✓ تم تحديث الساعة${NC}"

# ============================================
# تقسيم القرص (GPT/UEFI)
# ============================================
echo -e "${YELLOW}[4/10] تقسيم القرص...${NC}"
echo -e "${RED}تحذير: سيتم مسح جميع البيانات على $DISK!${NC}"
read -p "هل أنت متأكد؟ اكتب YES للمتابعة: " confirm
if [[ $confirm != "YES" ]]; then
    echo "تم إلغاء التثبيت"
    exit 1
fi

# مسح القرص وإنشاء تقسيم جديد
wipefs -af "$DISK"
sgdisk -Z "$DISK"

# إنشاء الأقسام
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI System" "$DISK"      # EFI
sgdisk -n 2:0:+8G -t 2:8200 -c 2:"Linux Swap" "$DISK"        # Swap
sgdisk -n 3:0:+100G -t 3:8300 -c 3:"Arch Linux" "$DISK"      # Root
sgdisk -n 4:0:0 -t 4:8300 -c 4:"Home" "$DISK"                # Home

# تحديث جدول الأقسام
partprobe "$DISK"
sleep 2

# تحديد أسماء الأقسام
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

echo -e "${GREEN}✓ تم إنشاء الأقسام:${NC}"
lsblk "$DISK"

# ============================================
# تهيئة الأقسام
# ============================================
echo -e "${YELLOW}[5/10] تهيئة الأقسام...${NC}"

mkfs.fat -F32 -n EFI "$EFI"
mkswap -L Swap "$SWAP"
mkfs.ext4 -L ArchRoot "$ROOT"
mkfs.ext4 -L ArchHome "$HOME"

swapon "$SWAP"

echo -e "${GREEN}✓ تم تهيئة الأقسام${NC}"

# ============================================
# تركيب الأقسام
# ============================================
echo -e "${YELLOW}[6/10] تركيب الأقسام...${NC}"

mount "$ROOT" /mnt
mkdir -p /mnt/boot/efi
mkdir -p /mnt/home
mount "$EFI" /mnt/boot/efi
mount "$HOME" /mnt/home

echo -e "${GREEN}✓ تم تركيب الأقسام${NC}"
df -h

# ============================================
# تثبيت النظام الأساسي
# ============================================
echo -e "${YELLOW}[7/10] تثبيت النظام الأساسي...${NC}"

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

echo -e "${GREEN}✓ تم تثبيت النظام الأساسي${NC}"

# ============================================
# إعداد fstab
# ============================================
echo -e "${YELLOW}[8/10] إعداد fstab...${NC}"
genfstab -U /mnt >> /mnt/etc/fstab
cat /mnt/etc/fstab
echo -e "${GREEN}✓ تم إعداد fstab${NC}"

# ============================================
# إعدادات النظام داخل chroot
# ============================================
echo -e "${YELLOW}[9/10] إعدادات النظام...${NC}"

arch-chroot /mnt /bin/bash <<CHROOT_EOF

# المنطقة الزمنية
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# اللغة
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "ar_SA.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# لوحة المفاتيح
echo "KEYMAP=us" > /etc/vconsole.conf

# اسم الجهاز
echo "$HOSTNAME" > /etc/hostname

# hosts
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

# كلمة مرور root
echo "root:123456" | chpasswd

# إنشاء المستخدم
useradd -m -G wheel,audio,video,storage,network,power -s /bin/bash "$USERNAME"
echo "$USERNAME:123456" | chpasswd

# sudo
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# تفعيل الخدمات
systemctl enable NetworkManager
systemctl enable tlp
systemctl enable dhcpcd

CHROOT_EOF

echo -e "${GREEN}✓ تم إعداد النظام${NC}"

# ============================================
# تثبيت GRUB مع حل مشكلة HP
# ============================================
echo -e "${YELLOW}[10/10] تثبيت GRUB...${NC}"

arch-chroot /mnt /bin/bash <<CHROOT_EOF

# تثبيت GRUB
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB

# الحل السحري لمشكلة HP: نسخ GRUB إلى مسار Windows
mkdir -p /boot/efi/EFI/Microsoft/Boot
cp /boot/efi/EFI/grub/grubx64.efi /boot/efi/EFI/Microsoft/Boot/bootmgfw.efi

# إنشاء إعداد GRUB
grub-mkconfig -o /boot/grub/grub.cfg

CHROOT_EOF

echo -e "${GREEN}✓ تم تثبيت GRUB${NC}"

# ============================================
# نسخ سكربت ما بعد التثبيت
# ============================================
echo -e "${YELLOW}نسخ سكربت ما بعد التثبيت...${NC}"

cat > /mnt/home/$USERNAME/post-install.sh <<'POSTEOF'
#!/bin/bash
# ============================================
# سكربت ما بعد التثبيت - HP ProBook 650 G1
# ============================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  إعدادات ما بعد التثبيت${NC}"
echo -e "${GREEN}========================================${NC}"

# ============================================
# إعدادات Intel Graphics
# ============================================
echo -e "${YELLOW}[1/6] إعدادات Intel Graphics...${NC}"

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

echo -e "${GREEN}✓ تم إعداد Intel Graphics${NC}"

# ============================================
# إصلاح مشكلة الإغلاق/الاستيقاظ
# ============================================
echo -e "${YELLOW}[2/6] إصلاح مشكلة الإغلاق...${NC}"

sudo tee /etc/modprobe.d/blacklist.conf > /dev/null <<EOF
# إصلاح مشكلة استيقاظ HP ProBook 650 G1 فوراً بعد الإغلاق
blacklist hp-wmi
EOF

echo -e "${GREEN}✓ تم إصلاح مشكلة الإغلاق${NC}"

# ============================================
# إعدادات Kernel لـ Suspend/Hibernate
# ============================================
echo -e "${YELLOW}[3/6] إعدادات Kernel...${NC}"

sudo sed -i 's/^MODULES=(/MODULES=(intel_agp i915 /' /etc/mkinitcpio.conf
sudo mkinitcpio -P

echo -e "${GREEN}✓ تم تحديث Kernel modules${NC}"

# ============================================
# إعدادات النظام
# ============================================
echo -e "${YELLOW}[4/6] إعدادات النظام...${NC}"

sudo tee /etc/sysctl.d/99-sysctl.conf > /dev/null <<EOF
# تحسين الأداء
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF

echo -e "${GREEN}✓ تم إعدادات النظام${NC}"

# ============================================
# تثبيت بيئة سطح المكتب (اختياري)
# ============================================
echo -e "${YELLOW}[5/6] اختيار بيئة سطح المكتب...${NC}"

echo "اختر بيئة سطح المكتب:"
echo "1) XFCE (خفيفة وسريعة)"
echo "2) KDE Plasma (جميلة وكاملة)"
echo "3) GNOME (حديثة وبسيطة)"
echo "4) i3 (للمستخدمين المتقدمين)"
echo "5) لا شيء (سطر أوامر فقط)"

read -p "اختر رقم (1-5): " choice

case $choice in
    1)
        echo "تثبيت XFCE..."
        sudo pacman -S --noconfirm xfce4 xfce4-goodies lightdm lightdm-gtk-greeter
        sudo systemctl enable lightdm
        ;;
    2)
        echo "تثبيت KDE Plasma..."
        sudo pacman -S --noconfirm plasma-meta kde-applications sddm
        sudo systemctl enable sddm
        ;;
    3)
        echo "تثبيت GNOME..."
        sudo pacman -S --noconfirm gnome gnome-tweaks gdm
        sudo systemctl enable gdm
        ;;
    4)
        echo "تثبيت i3..."
        sudo pacman -S --noconfirm i3 dmenu rxvt-unicode lightdm lightdm-gtk-greeter
        sudo systemctl enable lightdm
        ;;
    5)
        echo "تم تخطي بيئة سطح المكتب"
        ;;
    *)
        echo "اختيار غير صحيح، تخطي"
        ;;
esac

echo -e "${GREEN}✓ تم تثبيت بيئة سطح المكتب${NC}"

# ============================================
# تثبيت برامج إضافية
# ============================================
echo -e "${YELLOW}[6/6] تثبيت برامج إضافية...${NC}"

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

# إنشاء مجلدات المستخدم
xdg-user-dirs-update

echo -e "${GREEN}✓ تم تثبيت البرامج الإضافية${NC}"

# ============================================
# اختبار النظام
# ============================================
echo -e "${YELLOW}اختبار النظام...${NC}"

echo "معلومات الرسوميات:"
glxinfo | grep "OpenGL renderer" || echo "غير متوفر (قم بتثبيت mesa-utils)"

echo ""
echo "حالة الشبكة:"
ip link show

echo ""
echo "حالة البطارية:"
cat /sys/class/power_supply/BAT*/status 2>/dev/null || echo "لا توجد بطارية"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  تم الانتهاء!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "ملاحظات مهمة:"
echo "1. كلمة المرور الافتراضية: 123456"
echo "2. قم بتغيير كلمة المرور فوراً: passwd"
echo "3. أعد التشغيل للدخول للنظام الجديد"
echo ""
echo "للتحديث المستقبلي استخدم: sudo pacman -Syu"

POSTEOF

chmod +x /mnt/home/$USERNAME/post-install.sh
chown $USERNAME:$USERNAME /mnt/home/$USERNAME/post-install.sh

echo -e "${GREEN}✓ تم نسخ سكربت ما بعد التثبيت إلى /home/$USERNAME/${NC}"

# ============================================
# الانتهاء
# ============================================
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  تم التثبيت بنجاح!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "الخطوات التالية:"
echo "1. اخرج من chroot: exit"
echo "2. افصل الأقسام: umount -R /mnt"
echo "3. أعد التشغيل: reboot"
echo ""
echo "بعد الدخول للنظام الجديد:"
echo "1. سجل الدخول باسم المستخدم: $USERNAME"
echo "2. شغل سكربت ما بعد التثبيت: ./post-install.sh"
echo "3. اتبع التعليمات لإكمال الإعداد"
echo ""
echo "ملاحظة: كلمة المرور الافتراضية هي '123456'"
echo -e "${YELLOW}تغيير كلمة المرور موصى به فوراً!${NC}"
