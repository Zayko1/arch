#!/bin/bash

# Configuration du clavier en AZERTY
loadkeys fr-latin1

# Partitionnement du disque
echo -e "g\nn\n\n\n+1G\nn\n\n\n+1G\nn\n\n\n\nt\n3\n44\nw" | fdisk /dev/sda

# Formatage des partitions
mkfs.fat -F32 /dev/sda1
mkfs.ext4 /dev/sda2

# Configuration du chiffrement LUKS
echo -n "arch" | cryptsetup luksFormat /dev/sda3
echo -n "arch" | cryptsetup open --type luks /dev/sda3 lvm

# Création de LVM
pvcreate /dev/mapper/lvm
vgcreate volgroup0 /dev/mapper/lvm
lvcreate -L 30GB volgroup0 -n lv_root
lvcreate -L 25GB volgroup0 -n lv_home
lvcreate -L 4GB volgroup0 -n lv_swap
lvcreate -L 6GB volgroup0 -n lv_virtualbox
lvcreate -L 5GB volgroup0 -n lv_shared
lvcreate -L 10GB volgroup0 -n lv_encrypted

# Activation LVM
modprobe dm_mod
vgscan
vgchange -ay

# Formatage des volumes logiques
mkfs.ext4 /dev/volgroup0/lv_root
mkfs.ext4 /dev/volgroup0/lv_home
mkfs.ext4 /dev/volgroup0/lv_virtualbox
mkfs.ext4 /dev/volgroup0/lv_shared
mkfs.ext4 /dev/volgroup0/lv_encrypted
mkswap /dev/volgroup0/lv_swap

# Montage des partitions
mount /dev/volgroup0/lv_root /mnt
mkdir /mnt/boot
mount /dev/sda2 /mnt/boot
mkdir /mnt/home
mount /dev/volgroup0/lv_home /mnt/home
mkdir /mnt/var/lib/virtualbox
mount /dev/volgroup0/lv_virtualbox /mnt/var/lib/virtualbox
mkdir /mnt/mnt/shared
mount /dev/volgroup0/lv_shared /mnt/mnt/shared
swapon /dev/volgroup0/lv_swap

# Installation des paquets de base
pacstrap -i /mnt base linux linux-firmware linux-headers linux-lts linux-lts-headers

# Configuration fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot dans le système installé
arch-chroot /mnt <<EOF

# Configuration du mot de passe root
echo "root:root" | chpasswd

# Création des utilisateurs
useradd -m -g users -G wheel son
echo "son:son" | chpasswd

useradd -m -g users -G wheel,storage,video collegue
echo "collegue:azerty123" | chpasswd

# Installation des paquets supplémentaires
pacman -S --noconfirm base-devel dosfstools grub efibootmgr \
lvm2 mtools nano networkmanager openssh os-prober sudo \
mesa intel-media-driver \
firefox neovim git htop neofetch btop virtualbox qemu libvirt

# Activer les services
systemctl enable sshd
systemctl enable gdm
systemctl enable NetworkManager

# Configuration du chiffrement et LVM dans mkinitcpio
sed -i 's/^HOOKS.*/HOOKS=(base udev autodetect modconf block encrypt lvm2 filesystems keyboard fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Configuration de la locale
sed -i 's/#fr_FR.UTF-8 UTF-8/fr_FR.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=fr_FR.UTF-8" > /etc/locale.conf
export LANG=fr_FR.UTF-8

# Configuration du réseau
echo "archlinux" > /etc/hostname

# Configuration de GRUB
mkdir /boot/EFI
mount /dev/sda1 /boot/EFI
grub-install --target=x86_64-efi --bootloader-id=grub_uefi --recheck
grub-mkconfig -o /boot/grub/grub.cfg

EOF

# Démontage et redémarrage
umount -R /mnt
swapoff -a
echo "Installation terminée. Redémarrage dans 5 secondes..."
sleep 5
reboot
