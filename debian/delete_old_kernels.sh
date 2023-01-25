# Get kernel version #
v="$(uname -r | awk -F '-virtual' '{ print $1}')"
 
# Create ignore list to avoid deleting the running kernel #
i="linux-headers-virtual|linux-image-virtual|linux-headers-${v}|linux-image-$(uname -r)"
 
# Display the list #
echo dpkg --list | egrep -i  'linux-image|linux-headers' | awk '/ii/{ print $2}' | egrep -v "$i"

# Run apt script to remove listed old kernels #
apt-get --purge remove $(dpkg --list | egrep -i  'linux-image|linux-headers' | awk '/ii/{ print $2}' | egrep -v "$i")
