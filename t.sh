#!/bin/bash

# --- Configuration clavier ---
loadkeys fr-latin1

# --- Partitionnement ---
# Efface la table de partition et crée une nouvelle table GPT
echo -e "g\nn\n\n\n+512M\nn\n\n\n\nw" | fdisk /dev/sda

# --- Formatage des partitions ---
mkfs.fat -F32 /dev/sda1        # Partition EFI (512M)
mkfs.ext4 /dev/sda2            # Partition racine (reste du disque)

# --- Montage des partitions ---
mount /dev/sda2 /mnt           # Monte la partition racine
mkdir -p /mnt/boot/EFI         # Crée le point de montage pour l'EFI
mount /dev/sda1 /mnt/boot/EFI  # Monte la partition EFI

# --- Installation de base ---
pacstrap /mnt base linux linux-firmware nano sudo grub efibootmgr networkmanager

# --- Génération du fstab ---
genfstab -U /mnt >> /mnt/etc/fstab

# --- Configuration système ---
arch-chroot /mnt /bin/bash <<EOF

# Configuration de base
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
hwclock --systohc
echo "fr_FR.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=fr_FR.UTF-8" > /etc/locale.conf
echo "KEYMAP=fr-latin1" > /etc/vconsole.conf
echo "arch-test" > /etc/hostname

# Configuration utilisateur
echo "root:azerty123" | chpasswd
useradd -m -G wheel -s /bin/bash testuser
echo "testuser:azerty123" | chpasswd

# Configuration sudo
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Configuration GRUB
grub-install --target=x86_64-efi --efi-directory=/boot/EFI --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Activation des services
systemctl enable NetworkManager

EOF

# --- Nettoyage final ---
umount -R /mnt

echo "Installation terminée ! Redémarrez la machine."