#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
LANG=en_US.UTF-8

# --- 配置 ---
# 目标挂载目录
setup_path=/data

# --- 脚本开始 ---

echo "
+----------------------------------------------------------------------
| 自动磁盘分区与挂载工具 (UUID 持久化版本)
+----------------------------------------------------------------------
| 脚本将自动分区、格式化并使用UUID将数据盘挂载到 ${setup_path}
+----------------------------------------------------------------------
"

# 1. 检查是否存在第二块数据盘
# 通过/proc/partitions查找磁盘设备名，排除了主盘（sda, vda, xvda）和内存分区。
sysDisk=$(cat /proc/partitions | grep -v name | grep -v ram | awk '{print $4}' | grep -v '^$' | grep -v '[0-9]$' | grep -v 'vda' | grep -v 'xvda' | grep -v 'sda' | grep -e 'vd' -e 'sd' -e 'xvd')
if [ -z "${sysDisk}" ]; then
	echo "错误：此服务器只有一块磁盘，无法执行挂载操作。"
	exit 1
fi

# 2. 检查目标挂载目录是否已被占用
mountDisk=$(df -h | awk '{print $6}' | grep "^${setup_path}$")
if [ -n "${mountDisk}" ]; then
	echo "错误：${setup_path} 目录已被挂载，脚本将退出。"
	exit 1
fi

# 3. 检查是否存在Windows分区，避免误操作导致数据丢失
winDisk=$(fdisk -l 2>/dev/null | grep "NTFS\|FAT32")
if [ -n "${winDisk}" ]; then
	echo "警告：检测到Windows分区 (NTFS/FAT32)，为保证数据安全，请手动挂载。"
	exit 1
fi

# 4. 核心功能：分区、格式化并挂载
fdisk_mount() {
	# 遍历所有符合条件的数据盘
	for device_name in ${sysDisk}; do
		local device_path="/dev/${device_name}"
		local partition_path="${device_path}1"

		# 检查磁盘是否已经有分区
		local has_partition=$(fdisk -l ${device_path} 2>/dev/null | grep "${partition_path}")
		
		if [ -z "$has_partition" ]; then
			# --- 场景A：磁盘是全新的，没有分区 ---
			echo "检测到未分区的磁盘: ${device_path}"
			echo "开始自动分区..."
			
			# 使用fdisk进行非交互式分区
			fdisk -S 56 ${device_path} <<EOF > /dev/null 2>&1
n
p
1


wq
EOF
			sleep 3 # 等待内核识别新分区

			# 检查分区是否成功创建
			if [ ! -b "${partition_path}" ]; then
				echo "错误：创建分区 ${partition_path} 失败。"
				continue # 尝试下一块磁盘
			fi

			echo "分区 ${partition_path} 创建成功。"
			echo "开始格式化为 ext4 文件系统..."
			mkfs.ext4 ${partition_path} > /dev/null 2>&1
			echo "格式化完成。"

		else
			# --- 场景B：磁盘已有分区但未挂载 ---
			# 检查该分区是否已被挂载到任何地方
			local is_partition_mounted=$(df -P | grep "${partition_path}")
			if [ -n "${is_partition_mounted}" ]; then
				echo "信息：分区 ${partition_path} 已被挂载，跳过。"
				continue # 尝试下一块磁盘
			fi
			echo "检测到未挂载的已有分区: ${partition_path}"
		fi

		# --- 统一挂载步骤 ---
		echo "开始挂载分区 ${partition_path} 到 ${setup_path}..."
		
		# 使用 blkid 命令获取分区的 UUID
		local DISK_UUID=$(blkid -s UUID -o value ${partition_path})
		if [ -z "${DISK_UUID}" ]; then
			echo "错误：无法获取分区 ${partition_path} 的 UUID。"
			continue # 尝试下一块磁盘
		fi
		echo "获取到 UUID: ${DISK_UUID}"

		# 创建挂载点目录
		mkdir -p ${setup_path}
		
		# 将 UUID 挂载信息写入 /etc/fstab，实现开机自动挂载
		# 为防止重复写入，先用 grep 检查是否已存在该 UUID 的条目
		if ! grep -q "${DISK_UUID}" /etc/fstab; then
			echo "UUID=${DISK_UUID}    ${setup_path}    ext4    defaults    0 0" >>/etc/fstab
			echo "已将挂载信息写入 /etc/fstab。"
		else
			echo "信息：/etc/fstab 中已存在该 UUID 的挂载配置。"
		fi
		
		# 执行挂载命令
		mount -a
		
		# 最终检查挂载是否成功
		if df -h | awk '{print $6}' | grep -q "^${setup_path}$"; then
			echo "成功！磁盘已挂载到 ${setup_path}。"
			df -h
			return 0 # 成功挂载一块后即可退出
		else
			echo "错误：挂载失败！请检查系统日志。"
			# 清理失败的 fstab 条目
			sed -i "/UUID=${DISK_UUID}/d" /etc/fstab
			exit 1
		fi
	done
	
	echo "未找到合适的可操作磁盘。"
	return 1
}

# 执行主函数
fdisk_mount

echo ""
echo "脚本执行完毕。"
