#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
LANG=en_US.UTF-8
setup_path=/data

# 1. 检测服务器上是否存在第二块磁盘
# 通过/proc/partitions查找磁盘设备名，排除了主盘（sda, vda, xvda）和内存分区。
sysDisk=$(cat /proc/partitions | grep -v name | grep -v ram | awk '{print $4}' | grep -v '^$' | grep -v '[0-9]$' | grep -v 'vda' | grep -v 'xvda' | grep -v 'sda' | grep -e 'vd' -e 'sd' -e 'xvd')
if [ "${sysDisk}" == "" ]; then
	echo "ERROR: This server has only one disk, cannot perform mounting."
	echo "错误：此服务器只有一块磁盘，无法挂载。"
	exit;
fi

# 2. 检测目标目录是否已经被挂载
mountDisk=$(df -h | awk '{print $6}' | grep "^${setup_path}$")
if [ "${mountDisk}" != "" ]; then
	echo "ERROR: The ${setup_path} directory has already been mounted."
	echo "错误：${setup_path} 目录已被挂载，脚本退出。"
	exit;
fi

# 3. 检测是否存在Windows分区，避免操作不当导致数据丢失
winDisk=$(fdisk -l | grep "NTFS\|FAT32")
if [ "${winDisk}" != "" ]; then
	echo 'Warning: A Windows partition (NTFS/FAT32) was detected.'
	echo "警告：检测到Windows分区，为保证数据安全，请手动挂载。"
	exit;
fi

echo "
+----------------------------------------------------------------------
| Automatic disk partitioning and mounting tool
+----------------------------------------------------------------------
| The script will automatically partition and mount the data disk to ${setup_path}
+----------------------------------------------------------------------
"

# 4. 核心功能：自动分区并挂载
fdisk_mount() {
	# 遍历所有符合条件的磁盘设备
	for i in $(cat /proc/partitions | grep -v name | grep -v ram | awk '{print $4}' | grep -v '^$' | grep -v '[0-9]$' | grep -v 'vda' | grep -v 'xvda' | grep -v 'sda' | grep -e 'vd' -e 'sd' -e 'xvd'); do
		
		# 再次确认目标目录未被挂载
		is_mounted=$(df -P | grep $setup_path)
		if [ "$is_mounted" != "" ]; then
			echo "Error: The $setup_path directory has been mounted during the process."
			return;
		fi

		# 检查磁盘是否已经有分区
		has_partition=$(fdisk -l /dev/$i | grep -v 'bytes' | grep "$i[1-9]*")
		
		if [ "$has_partition" = "" ]; then
			# 如果磁盘未分区，则开始自动分区
			echo "Partitioning /dev/${i} ..."
			fdisk -S 56 /dev/$i <<EOF
n
p
1


wq
EOF
			sleep 3
			# 检查分区是否成功创建
			check_partition=$(fdisk -l /dev/$i | grep "/dev/${i}1")
			if [ "$check_partition" != "" ]; then
				echo "Formatting /dev/${i}1 ..."
				# 格式化新分区为 ext4
				mkfs.ext4 /dev/${i}1
				
				echo "Mounting /dev/${i}1 to ${setup_path} ..."
				# 创建挂载点目录
				mkdir -p $setup_path
				
				# 将挂载信息写入 /etc/fstab 以实现开机自动挂载
				# 为防止重复写入，先删除旧的记录
				sed -i "/\/dev\/${i}1/d" /etc/fstab
				echo "/dev/${i}1    $setup_path    ext4    defaults    0 0" >>/etc/fstab
				
				# 执行挂载
				mount -a
				
				echo "Mount successful."
				df -h
				return; # 成功后退出循环
			fi
		else
			# 如果磁盘已有分区但未挂载，则尝试直接挂载第一个分区
			is_partition_mounted=$(df -P | grep "/dev/${i}1")
			if [ "$is_partition_mounted" = "" ]; then
				echo "Detected existing partition /dev/${i}1, attempting to mount..."
				mkdir -p $setup_path
				sed -i "/\/dev\/${i}1/d" /etc/fstab
				echo "/dev/${i}1    $setup_path    ext4    defaults    0 0" >>/etc/fstab
				mount -a
				
				# 检查是否挂载成功且可写
				echo 'test' >$setup_path/test.pl
				if [ -f $setup_path/test.pl ]; then
					rm -f $setup_path/test.pl
					echo "Mount successful."
					df -h
					return; # 成功后退出循环
				else
					# 如果不可写，则撤销挂载配置
					sed -i "/\/dev\/${i}1/d" /etc/fstab
					mount -a
					echo "Mount failed: Partition is read-only or has other issues."
				fi
			fi
		fi
	done
	
	echo "No suitable unmounted disk found to operate on."
}

# 执行分区和挂载
fdisk_mount

echo ""
echo "Done."
