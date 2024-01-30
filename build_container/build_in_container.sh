#!/bin/sh


usage()
{
	cat << EOF
Usage:
$0 -b DIST -t DIR [ -k DIR ] 
$0 -h

Options:
-h       	Print this help
-d DIST 	Base operating system distro as a base for the docker container
-k DIR  	Path to ti-linux-kernel git workspace
-b BRANCH	kernel distro branch to use
-t DIR		Target installation directory
-f			Ignore cache when building the docker container

EOF
}

while getopts "hfd:k:b:t:" opt; do
	case "$opt" in
	h) usage; exit 0;;
	d) docker_base_distro=$OPTARG ;;
	k) kernel_workspace=$(realpath $OPTARG) ;;
	b) kernel_branch=$OPTARG ;;
	t) target=$(realpath $OPTARG) ;;
	f) force_build=1 ;;
	?) usage; exit 1;;
	esac
done

if [ -z ${docker_base_distro} ]; then
	usage
	echo "" >&2
	echo "ERROR: '-d' is a required parameter" >&2
	echo "" >&2
	exit 0
fi

if [ -z ${target} ]; then
	usage
	echo "" >&2
	echo "ERROR: '-t' is a required parameter" >&2
	echo "" >&2
	exit 0
fi

kernel_workspace_mount=""
if [ ! -z ${kernel_workspace} ]; then
	kernel_workspace_mount="-v ${kernel_workspace}:/dependencies/ti-linux-kernel "
fi

kernel_branch_env=''
if [ ! -z ${kernel_branch} ]; then
	kernel_branch_env="-e TI_LINUX_KERNEL_BRANCH=${kernel_branch}"
fi


src_workspace=$(realpath $(dirname "$0")/..)

force_build_option=""
if [ ! -z ${force_build} ]; then
	force_build_option="--no-cache"
fi

#Build the container
docker build ${force_build_option} \
	--build-arg="BASE_DISTRO=${docker_base_distro}" \
	--build-arg="KERNEL_BRANCH=${kernel_branch}" \
	--tag ltp-ddt-builder:latest .

#Build
docker container run \
	-v ${src_workspace}:/workspace \
	-v ${target}:/target \
	${kernel_workspace_mount} \
	${kernel_branch_env} \
	ltp-ddt-builder:latest

status=$?
if [ ${status} -eq 0 ]; then
	echo "INFO: Build completed successfully"
else
	echo "ERROR: Build failed -- please examine the log for errors"
fi

exit ${status}