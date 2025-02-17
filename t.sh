#!/bin/bash

# Envs
disk="/dev/sda"
device_mapper="/dev/mapper/cryptlvm"
hostname="archlinux"
user_collegue="collegue"
user_fils="fils"
default_password="azerty123"

# NTP
timedatectl set-ntp true

# Partitionnement avec fdisk
echo -e "g\nn\n1\n\n+512M\nt\n1\n1\nn\n2\n\n+1G\nn\n3\n\n\nw" | fdisk "$disk"

# Activer le drapeau boot sur la partition EFI
parted "$disk" set 1 boot on

# Formatage et chiffrement du disque principal
mkfs.fat -F32 "${disk}1"  # EFI
mkfs.ext4 "${disk}2"  # /boot
echo -n "$default_password" | cryptsetup luksFormat --batch-mode "${disk}3"
echo -n "$default_password" | cryptsetup open "${disk}3" cryptlvm

# Configuration de LVM
pvcreate "$device_mapper"
vgcreate vg_arch "$device_mapper"
lvcreate -L 10G vg_arch -n root
lvcreate -L 20G vg_arch -n home
lvcreate -L 4G vg_arch -n swap
lvcreate -L 10G vg_arch -n encrypted
lvcreate -L 10G vg_arch -n virtualbox
lvcreate -L 20G vg_arch -n partage

# Formatage des partitions
mkfs.ext4 /dev/vg_arch/root
mkfs.ext4 /dev/vg_arch/home
mkfs.ext4 /dev/vg_arch/virtualbox
mkfs.ext4 /dev/vg_arch/partage
mkswap /dev/vg_arch/swap

# Montage des partitions
mount /dev/vg_arch/root /mnt
mkdir -p /mnt/{home,mnt/virtualbox,mnt/partage}
mkdir -p /mnt/boot/
mkdir -p /mnt/boot/efi
mount "${disk}1" /mnt/boot/efi  # Monte EFI
mount "${disk}2" /mnt/boot  # Monte /boot
mount /dev/vg_arch/home /mnt/home
mount /dev/vg_arch/virtualbox /mnt/mnt/virtualbox
mount /dev/vg_arch/partage /mnt/mnt/partage
swapon /dev/vg_arch/swap

# Installation de base
pacstrap /mnt base linux linux-firmware vim linux-headers grub efibootmgr lvm2

# Configuration du système
genfstab -U /mnt >> /mnt/etc/fstab
echo "$hostname" > /mnt/etc/hostname

# POST-INSTALLATION
echo "Configuration post-installation..."
arch-chroot /mnt /bin/bash <<EOF
# Configuration de l'heure
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
hwclock --systohc

# Configuration de la langue
echo "fr_FR.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=fr_FR.UTF-8" > /etc/locale.conf
echo "KEYMAP=fr" > /etc/vconsole.conf

# Création des utilisateurs
useradd -m -G wheel -s /bin/bash $user_collegue
echo "$user_collegue:$default_password" | chpasswd
useradd -m -G wheel -s /bin/bash $user_fils
echo "$user_fils:$default_password" | chpasswd

# Ajout des droits sudo aux utilisateurs
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Modifier mkinitcpio > LUSK et LVM
sed -i 's/^HOOKS=.*/HOOKS="base udev autodetect modconf block keyboard keymap encrypt lvm2 filesystems fsck"/' /etc/mkinitcpio.conf
mkinitcpio -p linux

# Configuration de GRUB
echo 'GRUB_ENABLE_CRYPTODISK=y' >> /etc/default/grub
sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="cryptdevice=UUID=$(blkid -s UUID -o value ${disk}3):cryptlvm root=\/dev\/vg_arch\/root"/' /etc/default/grub
s
echo "insmod luks2" >> /etc/grub.d/40_custom

grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# === INSTALLATION ENVIRONNEMENT GRAPHIQUE ===
echo "Installation de l'environnement graphique..."
pacman -S --noconfirm xorg xorg-xinit xterm xorg-apps i3 dmenu alacritty picom feh rofi firefox thunar virtualbox virtualbox-host-dkms --needed

# Configuration des modules VirtualBox
modprobe vboxdrv
systemctl enable vboxservice

# === CONFIGURATION DE L'INTERFACE GRAPHIQUE ===
echo "Configuration de l'interface graphique..."
echo "exec i3" > /home/$user_collegue/.xinitrc
echo "exec i3" > /home/$user_fils/.xinitrc
chown $user_collegue:$user_collegue /home/$user_collegue/.xinitrc
chown $user_fils:$user_fils /home/$user_fils/.xinitrc

# Correction des permissions de .Xauthority
touch /home/$user_collegue/.Xauthority
touch /home/$user_fils/.Xauthority
chown $user_collegue:$user_collegue /home/$user_collegue/.Xauthority
chown $user_fils:$user_fils /home/$user_fils/.Xauthority
chmod 600 /home/$user_collegue/.Xauthority
chmod 600 /home/$user_fils/.Xauthority
EOF

# Ne marche pas dans le script actuellement donc je tente de les refaires après
mkdir -p /mnt/boot/efi
mount /dev/sda1 /mnt/boot/efi
arch-chroot /mnt /bin/bash <<EOF
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
EOF

echo "Installation terminé"