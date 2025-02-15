#!/bin/bash

# --- Configuration clavier et partitionnement ---
loadkeys fr-latin1

# Nettoyage des partitions existantes
wipefs -a /dev/sda

# Partitionnement GPT avec fdisk (EFI, boot, LUKS)
echo -e "g\nn\n\n\n+512M\nt\n1\nn\n\n\n+1G\nn\n\n\n\nt\n3\n8e\nw" | fdisk /dev/sda

# --- Formatage des partitions ---
mkfs.fat -F32 /dev/sda1        # Partition EFI
mkfs.ext4 /dev/sda2            # Partition Boot

# --- Chiffrement LUKS ---
echo -n "azerty123" | cryptsetup luksFormat /dev/sda3 -
echo -n "azerty123" | cryptsetup open /dev/sda3 cryptlvm -

# --- Configuration LVM ---
pvcreate /dev/mapper/cryptlvm
vgcreate vg0 /dev/mapper/cryptlvm

# Création des volumes logiques avec taille totale de 80G
lvcreate -L 30G vg0 -n root
lvcreate -L 20G vg0 -n home
lvcreate -L 8G  vg0 -n swap
lvcreate -L 6G  vg0 -n virtualbox
lvcreate -L 5G  vg0 -n shared
lvcreate -L 10G vg0 -n encrypted

# --- Formatage des systèmes de fichiers ---
mkfs.ext4 /dev/vg0/root
mkfs.ext4 /dev/vg0/home
mkswap /dev/vg0/swap
mkfs.ext4 /dev/vg0/virtualbox
mkfs.ext4 /dev/vg0/shared

# Chiffrement supplémentaire pour le volume dédié
echo -n "azerty123" | cryptsetup luksFormat /dev/vg0/encrypted -
echo -n "azerty123" | cryptsetup open /dev/vg0/encrypted secret_volume
mkfs.ext4 /dev/mapper/secret_volume

# --- Montage des partitions ---
mount /dev/vg0/root /mnt
mkdir -p /mnt/boot
mount /dev/sda2 /mnt/boot
mkdir -p /mnt/home
mount /dev/vg0/home /mnt/home
swapon /dev/vg0/swap

# Création des points de montage spéciaux
mkdir -p /mnt/var/lib/virtualbox
mount /dev/vg0/virtualbox /mnt/var/lib/virtualbox
mkdir -p /mnt/mnt/shared
mount /dev/vg0/shared /mnt/mnt/shared

# --- Installation de base ---
pacstrap /mnt base base-devel linux linux-firmware lvm2 nano

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
echo "arch-pc" > /etc/hostname

# Configuration utilisateurs
echo "root:azerty123" | chpasswd
useradd -m -G wheel -s /bin/bash jean
echo "jean:azerty123" | chpasswd
useradd -m -G users -s /bin/bash philipe
echo "philipe:azerty123" | chpasswd

# Installation des paquets supplémentaires
pacman -Syu --noconfirm \
    sudo grub efibootmgr networkmanager \
    openssh virtualbox virtualbox-guest-utils \
    hyprland xorg-xwayland firefox gcc git htop \
    neofetch code feh dunst rofi kitty

# Configuration sudo
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Configuration Hyprland (WM moderne)
mkdir -p /home/jean/.config/hypr
cat > /home/jean/.config/hypr/hyprland.conf <<HYPRCONF
exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
exec = waybar
exec = nm-applet --indicator

monitor = ,preferred,auto,1

input {
    kb_layout = fr
}

general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
}

decoration {
    rounding = 5
    blur = yes
}

animation {
    bezier = myBezier, 0.05, 0.9, 0.1, 1.05
    animation = windows, 1, 7, myBezier
}

HYPRCONF

# Configuration du dossier partagé
chmod 2775 /mnt/shared
chown jean:users /mnt/shared

# Configuration GRUB
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard keymap modconf block encrypt lvm2 filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Activer les services
systemctl enable NetworkManager
systemctl enable sshd
systemctl enable vboxservice

EOF

# --- Nettoyage final ---
umount -R /mnt
swapoff -a

echo "Installation terminée !"
echo "Conseils post-installation :"
echo "1. Pour monter le volume chiffré manuellement :"
echo "   cryptsetup open /dev/vg0/encrypted secret_volume && mount /dev/mapper/secret_volume /mnt/secret"
echo "2. Le dossier partagé est disponible dans /mnt/shared"
echo "3. Hyprland est préconfiguré dans le profil de jean"