#!/bin/bash

# Clavier FR
loadkeys fr-latin1

# Partition simple (MBR)
echo -e "o\nn\np\n1\n\n+512M\na\nn\np\n2\n\n+1G\nn\np\n3\n\n\nw" | fdisk /dev/sda

# Formatage
mkfs.fat -F32 /dev/sda1
mkfs.ext4 /dev/sda2
cryptsetup luksFormat /dev/sda3 <<< "azerty123"
cryptsetup open /dev/sda3 lvm <<< "azerty123"

# LVM setup
pvcreate /dev/mapper/lvm
vgcreate volgroup0 /dev/mapper/lvm

# Volumes logiques
lvcreate -L 25G volgroup0 -n lv_root
lvcreate -L 20G volgroup0 -n lv_home
lvcreate -L 4G volgroup0 -n lv_swap
lvcreate -L 6G volgroup0 -n lv_vbox
lvcreate -L 5G volgroup0 -n lv_shared
lvcreate -L 10G volgroup0 -n lv_secret

# Formatage des volumes
mkfs.ext4 /dev/volgroup0/lv_root
mkfs.ext4 /dev/volgroup0/lv_home
mkswap /dev/volgroup0/lv_swap
mkfs.ext4 /dev/volgroup0/lv_vbox
mkfs.ext4 /dev/volgroup0/lv_shared
cryptsetup luksFormat /dev/volgroup0/lv_secret <<< "azerty123"

# Montage
mount /dev/volgroup0/lv_root /mnt
mkdir -p /mnt/{boot,home,vbox,shared}
mount /dev/sda2 /mnt/boot
mount /dev/volgroup0/lv_home /mnt/home
mount /dev/volgroup0/lv_vbox /mnt/vbox
mount /dev/volgroup0/lv_shared /mnt/shared
swapon /dev/volgroup0/lv_swap

# Installation base
pacstrap /mnt base linux linux-firmware lvm2 grub sudo networkmanager hyprland firefox virtualbox gcc

# fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Configuration système
arch-chroot /mnt /bin/bash <<EOF
# Root password
echo root:azerty123 | chpasswd

# Users
useradd -m -G wheel,vboxusers pere
echo pere:azerty123 | chpasswd
useradd -m -G users fils
echo fils:azerty123 | chpasswd

# Sudo
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers.d/wheel

# Services
systemctl enable NetworkManager

# Grub
sed -i 's/HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)/HOOKS=(base udev autodetect keyboard modconf block encrypt lvm2 filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -p linux
grub-install /dev/sda
CRYPTUUID=\$(blkid -s UUID -o value /dev/sda3)
sed -i "s/GRUB_CMDLINE_LINUX=\"\"/GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=\$CRYPTUUID:lvm root=/dev/volgroup0/lv_root\"/" /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
EOF

# Fin
umount -R /mnt
swapoff -a
echo "Installation terminée! Redémarrez avec 'reboot'"