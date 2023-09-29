#!/bin/bash

# Initialize log file
logfile="/tmp/osprep.log"
echo "OS Preparation Log - $(date)" > $logfile

# Function to install packages
install_packages() {
    local distro=$1
    shift
    local packages=$@

    for package in $packages; do
        echo "Installing $package..."
        if [[ $distro == "debian" ]]; then
            apt-get install -y $package && echo "Successfully installed $package" >> $logfile || echo "Failed to install $package" >> $logfile
        elif [[ $distro == "fedora" ]]; then
            yum install -y $package && echo "Successfully installed $package" >> $logfile || echo "Failed to install $package" >> $logfile
        fi
    done
}

# Check the distro type and install curl and wget first
echo "Determining distribution type..."
distro=$(awk -F= '/^NAME/{print tolower($2)}' /etc/os-release)

echo "Installing curl and wget..."
if [[ $distro == *"debian"* ]]; then
    apt-get update && apt-get install -y curl wget && echo "Successfully installed curl and wget" >> $logfile || echo "Failed to install curl and wget" >> $logfile
elif [[ $distro == *"fedora"* ]]; then
    yum update && yum install -y curl wget && echo "Successfully installed curl and wget" >> $logfile || echo "Failed to install curl and wget" >> $logfile
fi

# Check if the OS is a VM guest and install open-vm-tools
echo "Checking if the OS is a VM guest..."
if [[ $(systemd-detect-virt) == "vmware" ]]; then
    echo "OS is a VM guest. Installing open-vm-tools..."
    install_packages "$distro" open-vm-tools
fi

# Install appropriate packages based on distro type
echo "Installing packages based on distribution type..."
if [[ $distro == *"debian"* ]]; then
    install_packages "$distro" vim nano wget axel curl rsync htop bmon iotop net-tools mtr bind9utils traceroute mc p7zip* zip unzip
elif [[ $distro == *"fedora"* ]]; then
    install_packages "$distro" vi vim nano tmux wget axel curl htop bmon iotop yum-utils bind-utils traceroute net-tools mtr mc ftp rsync lftp mlocate policycoreutils-python p7zip* unzip zip
fi

# Add ssh keys by downloading them from GitHub
echo "Adding ssh keys from GitHub..."
mkdir -p ~/.ssh && curl -s https://github.com/bhaukaalbaba.keys >> ~/.ssh/authorized_keys && echo "Successfully added ssh keys" >> $logfile || echo "Failed to add ssh keys" >> $logfile

# Find out sshd_config file relevant for the distro and disable password based SSH access.
echo "Disabling password based SSH access..."
sshd_file=$(find /etc/ssh -name sshd_config)
if grep -q "^PasswordAuthentication" $sshd_file; then
    sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' $sshd_file && echo "Successfully disabled password based SSH access" >> $logfile || echo "Failed to disable password based SSH access" >> $logfile
else
    echo "PasswordAuthentication no" >> $sshd_file && echo "Successfully disabled password based SSH access" >> $logfile || echo "Failed to disable password based SSH access" >> $logfile
fi

# If the distro type is Debian then edit all entries in /etc/network/interfaces from allow-hotplug to auto
if [[ $distro == *"debian"* ]]; then
    echo "Editing /etc/network/interfaces..."
    sed -i 's/allow-hotplug/auto/g' /etc/network/interfaces && echo "Successfully edited /etc/network/interfaces" >> $logfile || echo "Failed to edit /etc/network/interfaces" >> $logfile
fi

# Append timesyncd config to use time.google.com as failover server. Enable timesyncd service and start it.
echo "Configuring timesyncd..."
echo -e "\n[Time]\nFallbackNTP=time.google.com" >> /etc/systemd/timesyncd.conf && echo "Successfully configured timesyncd" >> $logfile || echo "Failed to configure timesyncd" >> $logfile

echo "Enabling and starting timesyncd service..."
systemctl enable systemd-timesyncd && systemctl start systemd-timesyncd && echo "Successfully enabled and started timesyncd service" >> $logfile || echo "Failed to enable and start timesyncd service" >> $logfile

echo "OS preparation completed. Please check the log file for any errors."
