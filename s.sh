#!/bin/bash

# Configuration du clavier français
loadkeys fr-latin1

# Vérification de l'espace disque disponible
if [ $(lsblk -b /dev/sda | awk 'NR==2 {print $4}') -lt 85899345920 ]; then
    echo "Erreur: Le disque doit faire au moins 80GB"
    exit 1
fi

# Création de la table de partition GPT + partitions EFI, Boot et LUKS
echo -e "g\n  # Nouvelle table GPT
n\n  # Nouvelle partition EFI
1\n  # Partition number
\n   # Premier secteur (défaut)
+512M\n # Taille EFI
t\n  # Changer type
1\n  # Type EFI
n\n  # Nouvelle partition Boot
2\n  # Partition number
\n   # Premier secteur (défaut)
+1G\n # Taille Boot
n\n  # Nouvelle partition LUKS
3\n  # Partition number
\n   # Premier secteur (défaut)
\n   # Dernier secteur (défaut - utilise l'espace restant)
t\n  # Changer type
3\n  # Partition number
8e\n # Type LVM
w\n" | fdisk /dev/sda

# Formatage des partitions
mkfs.fat -F32 /dev/sda1   # EFI
mkfs.ext4 /dev/sda2       # Boot

# Chiffrement LUKS de la partition principale
echo -n "azerty123" | cryptsetup luksFormat /dev/sda3 -
echo -n "azerty123" | cryptsetup open /dev/sda3 lvm -

# Création du groupe de volumes LVM avec allocation optimisée pour 80GB
pvcreate /dev/mapper/lvm
vgcreate volgroup0 /dev/mapper/lvm

# Création des volumes logiques avec tailles optimisées
lvcreate -L 25G volgroup0 -n lv_root    # Système
lvcreate -L 20G volgroup0 -n lv_home    # /home
lvcreate -L 4G volgroup0 -n lv_swap     # Swap (50% de la RAM)
lvcreate -L 6G volgroup0 -n lv_vbox     # VirtualBox
lvcreate -L 5G volgroup0 -n lv_shared   # Dossier partagé père/fils
lvcreate -L 10G volgroup0 -n lv_secret  # Volume chiffré supplémentaire

# Formatage des volumes logiques
mkfs.ext4 /dev/volgroup0/lv_root
mkfs.ext4 /dev/volgroup0/lv_home
mkswap /dev/volgroup0/lv_swap
mkfs.ext4 /dev/volgroup0/lv_vbox
mkfs.ext4 /dev/volgroup0/lv_shared
echo -n "azerty123" | cryptsetup luksFormat /dev/volgroup0/lv_secret -  # Chiffrement du volume secret

# Montage des partitions
mount /dev/volgroup0/lv_root /mnt
mkdir -p /mnt/boot
mount /dev/sda2 /mnt/boot
mkdir -p /mnt/boot/EFI
mount /dev/sda1 /mnt/boot/EFI
mkdir -p /mnt/home
mount /dev/volgroup0/lv_home /mnt/home
mkdir -p /mnt/vbox
mount /dev/volgroup0/lv_vbox /mnt/vbox
mkdir -p /mnt/shared
mount /dev/volgroup0/lv_shared /mnt/shared
chmod 770 /mnt/shared  # Permissions pour le dossier partagé
swapon /dev/volgroup0/lv_swap

# Installation du système de base avec les outils nécessaires
pacstrap /mnt \
    base linux linux-lts linux-firmware base-devel \
    nano vim lvm2 networkmanager \
    grub efibootmgr os-prober \
    sudo git gcc gdb make \
    man-db man-pages texinfo \
    firefox hyprland kitty waybar \
    virtualbox virtualbox-host-modules-arch \
    xdg-desktop-portal-hyprland \
    openssh htop neofetch \
    pulseaudio pavucontrol \
    mesa vulkan-intel

# Génération de fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Configuration du système
arch-chroot /mnt /bin/bash <<EOF
# Configuration locale et clavier
echo "fr_FR.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=fr_FR.UTF-8" > /etc/locale.conf
echo "KEYMAP=fr-latin1" > /etc/vconsole.conf

# Configuration du fuseau horaire
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
hwclock --systohc

# Configuration des mots de passe et utilisateurs
echo root:azerty123 | chpasswd
useradd -m -G wheel,vboxusers -s /bin/bash pere
echo pere:azerty123 | chpasswd
useradd -m -G users,vboxusers -s /bin/bash fils
echo fils:azerty123 | chpasswd

# Configuration du groupe pour le dossier partagé
groupadd famille
usermod -a -G famille pere
usermod -a -G famille fils
chown -R root:famille /shared
chmod 2770 /shared  # SGID pour que les nouveaux fichiers héritent du groupe

# Configuration sudo
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers.d/wheel

# Activation des services
systemctl enable NetworkManager
systemctl enable sshd
systemctl enable vboxservice

# Configuration GRUB avec support LUKS + LVM
sed -i 's/HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)/HOOKS=(base udev autodetect keyboard keymap modconf block encrypt lvm2 filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -p linux
mkinitcpio -p linux-lts

# Installation de GRUB
grub-install --target=x86_64-efi --efi-directory=/boot/EFI --bootloader-id=GRUB
# Ajout du support pour le chiffrement dans GRUB
CRYPTUUID=\$(blkid -s UUID -o value /dev/sda3)
sed -i "s/GRUB_CMDLINE_LINUX=\"\"/GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=\$CRYPTUUID:lvm root=/dev/volgroup0/lv_root\"/" /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# Configuration Hyprland de base pour le père
mkdir -p /home/pere/.config/hypr
cat > /home/pere/.config/hypr/hyprland.conf <<'HYPRCONF'
# Configuration Hyprland basique
monitor=,preferred,auto,1

# Autostart
exec-once = waybar & firefox

# Quelques règles de base
input {
    kb_layout = fr
    follow_mouse = 1
    sensitivity = 0
}

general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(33ccffee)
}

decoration {
    rounding = 10
    blur = true
    blur_size = 3
    blur_passes = 1
}

animations {
    enabled = true
    bezier = myBezier, 0.05, 0.9, 0.1, 1.05
    animation = windows, 1, 7, myBezier
    animation = windowsOut, 1, 7, default, popin 80%
    animation = fade, 1, 7, default
}

dwindle {
    pseudotile = true
    preserve_split = true
}

# Règles de base pour les fenêtres
windowrulev2 = float,class:^(firefox)$
windowrulev2 = workspace 1,class:^(firefox)$
windowrulev2 = workspace 2,class:^(code)$

# Quelques bindings de base
bind = SUPER, Return, exec, kitty
bind = SUPER, Q, killactive,
bind = SUPER, M, exit,
bind = SUPER, E, exec, dolphin
bind = SUPER, V, togglefloating,
bind = SUPER, R, exec, wofi --show drun
bind = SUPER, P, pseudo,
bind = SUPER, J, togglesplit,

# Workspaces
bind = SUPER, 1, workspace, 1
bind = SUPER, 2, workspace, 2
bind = SUPER, 3, workspace, 3
bind = SUPER, 4, workspace, 4
bind = SUPER, 5, workspace, 5
bind = SUPER, 6, workspace, 6
bind = SUPER, 7, workspace, 7
bind = SUPER, 8, workspace, 8
bind = SUPER, 9, workspace, 9
bind = SUPER, 0, workspace, 10

bind = ALT, 1, movetoworkspace, 1
bind = ALT, 2, movetoworkspace, 2
bind = ALT, 3, movetoworkspace, 3
bind = ALT, 4, movetoworkspace, 4
bind = ALT, 5, movetoworkspace, 5
bind = ALT, 6, movetoworkspace, 6
bind = ALT, 7, movetoworkspace, 7
bind = ALT, 8, movetoworkspace, 8
bind = ALT, 9, movetoworkspace, 9
bind = ALT, 0, movetoworkspace, 10
HYPRCONF

chown -R pere:pere /home/pere/.config

# Instructions pour le volume secret
echo "Pour monter le volume secret:"
echo "cryptsetup open /dev/volgroup0/lv_secret secret"
echo "mount /dev/mapper/secret /mnt/secret"
EOF

# Démontage et reboot
umount -R /mnt
swapoff -a
echo "Installation terminée ! Redémarre la VM avec 'reboot'"