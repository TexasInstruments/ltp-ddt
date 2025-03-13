#! /bin/sh

source "common.sh"

############################# Functions #######################################
usage()
{
	cat <<-EOF >&2
	usage: ./${0##*/} -t TEST_TYPE
	-t TEST_TYPE		Test Type. Possible Values are:
	      1 : weston is running
	      2 : weston is using DRM
	      3 : weston can run a simple EGL app
	      4 : weston can run it's ivi shell interface
	EOF
	exit 0
}

simple_egl_test()
{
	if which simple-egl-readpixels ; then
		simple-egl-readpixels -n 10
		return $?
	fi

	if which weston-simple-egl ; then
		weston-simple-egl  &
		PID=$!
		sleep 3
		kill $PID
		return $?
	fi
}

weston_ivi_test()
{
	stop_daemon emptty
	ini_files=$(find /etc -type f -name 'weston.ini')

	# tweak ini files for test
	for weston_ini in $ini_files; do
		cp "${weston_ini}" "${weston_ini}.orig"
		if [ -f /usr/lib/weston/hmi-controller.so ] ; then
			sed -i 's/^\[core\]$/\[core\]\nshell=ivi-shell.so\nmodules=hmi-controller.so/' "${weston_ini}"
			cat >> "${weston_ini}" << EOF
[ivi-shell]
ivi-shell-user-interface=weston-ivi-shell-user-interface
cursor-theme=default
cursor-size=32
base-layer-id=1000
base-layer-id-offset=10000
workspace-background-layer-id=2000
workspace-layer-id=3000
application-layer-id=4000
transition-duration=300
background-id=1001
panel-id=1002
surface-id-offset=10
tiling-id=1003
sidebyside-id=1004
fullscreen-id=1005
random-id=1006
home-id=1007
workspace-background-color=0x99000000
workspace-background-id=2001
EOF
		else
			sed -i 's/^\[core\]$/\[core\]\nshell=ivi-shell.so/' "${weston_ini}"
		fi
	done

	unset WAYLAND_DISPLAY
	weston &
	weston_pid=$!

	sleep 15 && kill $weston_pid
	wait $weston_pid
	ret=$?

	# replace origional ini
	for weston_ini in $ini_files; do
		mv "${weston_ini}.orig" "${weston_ini}" 
	done

	return $ret
}

################################ CLI Params ####################################
# Please use getopts
while getopts  :t:h arg
do case $arg in
        t)      TYPE="$OPTARG";;
        h)      usage;;
        :)      die "$0: Must supply an argument to -$OPTARG.";;
        \?)     die "Invalid Option -$OPTARG ";;
esac
done

[ -z "$TYPE" ] && die "you must provide a test type"

case "$TYPE" in
	1)
		wayland-info
		;;
	2)
		wayland-info | grep -w "interface: 'wl_drm',\s*version:"
		;;
	3)
		simple_egl_test
		;;
	4)
		weston_ivi_test
		;;
	*) die "$TYPE is not a valid test type"
esac
