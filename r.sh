#!/bin/bash

# Activer le clavier FR
loadkeys fr-latin1

# Création de la table de partition GPT + partitions EFI, Boot et LUKS
echo -e "g
n


+512M
t
1
n


+1G
n



t
3
8e
w" | fdisk /dev/sda

# Formatage des partitions
mkfs.fat -F32 /dev/sda1   # EFI
mkfs.ext4 /dev/sda2       # Boot

# Chiffrement LUKS de la partition principale
echo -n "azerty123" | cryptsetup luksFormat /dev/sda3 -
echo -n "azerty123" | cryptsetup open /dev/sda3 lvm -

# Création du groupe de volumes LVM
pvcreate /dev/mapper/lvm
vgcreate volgroup0 /dev/mapper/lvm
lvcreate -L 30G volgroup0 -n lv_root
lvcreate -L 25G volgroup0 -n lv_home
lvcreate -L 4G volgroup0 -n lv_swap
lvcreate -L 6G volgroup0 -n lv_virtualbox
lvcreate -L 5G volgroup0 -n lv_shared
lvcreate -L 10G volgroup0 -n lv_encrypted

# Formatage des volumes logiques
mkfs.ext4 /dev/volgroup0/lv_root
mkfs.ext4 /dev/volgroup0/lv_home
mkswap /dev/volgroup0/lv_swap
mkfs.ext4 /dev/volgroup0/lv_virtualbox
mkfs.ext4 /dev/volgroup0/lv_shared
mkfs.ext4 /dev/volgroup0/lv_encrypted

# Montage des partitions
mount /dev/volgroup0/lv_root /mnt
mkdir -p /mnt/boot
mount /dev/sda2 /mnt/boot
mkdir -p /mnt/home
mount /dev/volgroup0/lv_home /mnt/home
swapon /dev/volgroup0/lv_swap

# Installation du système de base
pacstrap /mnt base linux linux-lts linux-firmware base-devel nano lvm2

# Génération de fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Configuration du système
arch-chroot /mnt /bin/bash <<EOF

# Définir le mot de passe root
echo root:azerty123 | chpasswd

# Création des utilisateurs
useradd -m -G wheel -s /bin/bash jean
echo jean:azerty123 | chpasswd

useradd -m -G users -s /bin/bash philipe
echo philipe:azerty123 | chpasswd

# Installer les outils de base
pacman -S --noconfirm sudo grub efibootmgr networkmanager openssh \
  virtualbox-guest-utils mesa hyprland xdg-utils xdg-user-dirs firefox gcc

# Activer les services essentiels
systemctl enable NetworkManager
systemctl enable sshd

# Configurer GRUB avec support LUKS + LVM
sed -i 's/HOOKS=(.*)/HOOKS=(base udev autodetect modconf block encrypt lvm2 filesystems keyboard fsck)/' /etc/mkinitcpio.conf
mkinitcpio -p linux
mkinitcpio -p linux-lts

mkdir -p /boot/EFI
mount /dev/sda1 /boot/EFI
grub-install --target=x86_64-efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

exit
EOF

# Démontage et reboot
umount -R /mnt
swapoff -a
echo "Installation terminée"
