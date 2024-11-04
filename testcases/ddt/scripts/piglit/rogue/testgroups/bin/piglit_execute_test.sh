#! /bin/bash

source "common.sh"

OPTSTRING=":x:y:z:i:a:"s

while getopts ${OPTSTRING} opt; do
  case ${opt} in
    x)
      TESTCASE=${OPTARG};;
    y)
      TESTPROFILE=${OPTARG};;
    z) 
      TEXTURE=${OPTARG};;
    i)
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

swapfile_create

piglit run ${TESTPROFILE} results --test-list ${LTPROOT}/testcases/ddt/scripts/piglit/${ARCHITECTURE}/testgroups/${TEXTURE}/${API}/${TESTCASE}

piglit_exit=$?

output=$(piglit summary console results -p)

if [ $piglit_exit != 0 ] || echo "${output}" | grep -q 'failed$' 
then 
    die "${output}"
fi