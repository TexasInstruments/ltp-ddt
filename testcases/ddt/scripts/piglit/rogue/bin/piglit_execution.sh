#! /bin/bash
source "common.sh"

OPTSTRING=":x:y:z:i:a:"s

while getopts ${OPTSTRING} opt; do
  case ${opt} in
    x)
      TESTFILE=${OPTARG};;
    y)
      TESTPROFILE=${OPTARG};;
    i)
      TEXTURE=${OPTARG};;
    z)
      API=${OPTARG};;
    a)
      ARCHITECTURE=${OPTARG};;
    :)
      echo "Option -${OPTARG} requires an argument."
      exit 1
      ;;
    ?)
      echo "Invalid option: -${OPTARG}."
      exit 1
      ;;
  esac
done

echo "Kmsprint output:"
kmsprint

if systemctl is-active -q weston; then
	echo "Weston service is running"
else
	sleep 5
	if systemctl is-failed weston.service -q; then
		echo "Failure with weston service"
		journalctl -b | grep weston
		die "Weston not running"
	else 
		echo "Weston service is running"
	fi
fi

if [ -z "${TEXTURE}" ]; then
    TESTFILEPATH=/opt/ltp/testcases/ddt/scripts/piglit/${ARCHITECTURE}/extensions/${API}/${TESTFILE}
else
    TESTFILEPATH=/opt/ltp/testcases/ddt/scripts/piglit/${ARCHITECTURE}/testgroups/${TEXTURE}/${API}/${TESTFILE}
fi

swapfile_create

piglit run ${TESTPROFILE} results/ --test-list ${TESTFILEPATH}

piglit_exit=$?

output=$(piglit summary console results -p)

if [ $piglit_exit != 0 ] || echo "${output}" | grep -qE 'fail|crash|skip|timeout'
then
    die "${output}"
fi