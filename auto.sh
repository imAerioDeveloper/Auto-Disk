#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
LANG=en_US.UTF-8

setup_path=/data

echo "
+----------------------------------------------------------------------
 Automatic Disk Partitioning and Mounting Tool (UUID Persistent Version)
+----------------------------------------------------------------------
 This script will automatically partition, format, and mount the data disk to ${setup_path} using UUID.
+----------------------------------------------------------------------
"

sysDisk=$(cat /proc/partitions | grep -v name | grep -v ram | awk '{print $4}' | grep -v '^$' | grep -v '[0-9]$' | grep -v 'vda' | grep -v 'xvda' | grep -v 'sda' | grep -e 'vd' -e 'sd' -e 'xvd')
if [ -z "${sysDisk}" ]; then
	echo "Error: This server has only one disk and the mount operation cannot be performed."
	exit 1
fi

mountDisk=$(df -h | awk '{print $6}' | grep "^${setup_path}$")
if [ -n "${mountDisk}" ]; then
	echo "Error: The ${setup_path} directory is already mounted, the script will exit."
	exit 1
fi

winDisk=$(fdisk -l 2>/dev/null | grep "NTFS\|FAT32")
if [ -n "${winDisk}" ]; then
	echo "Warning: Windows partition (NTFS/FAT32) detected. To ensure data security, please mount it manually."
	exit 1
fi

fdisk_mount() {
	for device_name in ${sysDisk}; do
		local device_path="/dev/${device_name}"
		local partition_path="${device_path}1"

		local has_partition=$(fdisk -l ${device_path} 2>/dev/null | grep "${partition_path}")
		
		if [ -z "$has_partition" ]; then
			echo "Unpartitioned disk detected: ${device_path}"
			echo "Starting automatic partitioning..."
			
			fdisk -S 56 ${device_path} <<EOF > /dev/null 2>&1
n
p
1


wq
EOF
			sleep 3

			if [ ! -b "${partition_path}" ]; then
				echo "Error: Failed to create partition ${partition_path}."
				continue
			fi

			echo "Partition ${partition_path} created successfully."
			echo "Formatting to ext4 file system..."
			mkfs.ext4 ${partition_path} > /dev/null 2>&1
			echo "Formatting complete."

		else
			local is_partition_mounted=$(df -P | grep "${partition_path}")
			if [ -n "${is_partition_mounted}" ]; then
				echo "Info: Partition ${partition_path} is already mounted, skipping."
				continue
			fi
			echo "Detected an existing unmounted partition: ${partition_path}"
		fi

		echo "Start mounting partition ${partition_path} to ${setup_path}..."
		
		local DISK_UUID=$(blkid -s UUID -o value ${partition_path})
		if [ -z "${DISK_UUID}" ]; then
			echo "Error: Unable to get the UUID of the partition ${partition_path}."
			continue
		fi
		echo "Get UUID: ${DISK_UUID}"

		mkdir -p ${setup_path}
		
		if ! grep -q "${DISK_UUID}" /etc/fstab; then
			echo "UUID=${DISK_UUID}    ${setup_path}    ext4    defaults    0 0" >>/etc/fstab
			echo "Mount information has been written to /etc/fstab."
		else
			echo "Info: The mount configuration for this UUID already exists in /etc/fstab."
		fi
		
		mount -a
		
		if df -h | awk '{print $6}' | grep -q "^${setup_path}$"; then
			echo "Success! The disk has been mounted to ${setup_path}."
			df -h
			return 0
		else
			echo "Error: Mount failed! Please check the system log."
			sed -i "/UUID=${DISK_UUID}/d" /etc/fstab
			exit 1
		fi
	done
	
	echo "No suitable disk for operation was found."
	return 1
}

fdisk_mount

echo ""
echo "Script execution is complete."
