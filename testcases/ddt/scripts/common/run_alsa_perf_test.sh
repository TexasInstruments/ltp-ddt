source "common.sh"

############################# Functions #######################################
usage()
{
	cat <<-EOF >&2
	usage: ./${0##*/}  <test type: playback/record>
	EOF
	exit 0
}

################################ CLI Params ####################################
# Please use getopts
while getopts  :h arg
do case $arg in
        h)      usage;;
        :)      die "$0: Must supply an argument to -$OPTARG.";;
        \?)     die "Invalid Option -$OPTARG ";;
esac
done

############################ USER-DEFINED Params ##############################
# Try to avoid defining values here, instead see if possible
# to determine the value dynamically
test_type=$1

case $SOC in
am6*|j722s*)
	PERIODSIZE=256
;;
j784s4*|j721*)
	PERIODSIZE=64
;;
esac

########################### REUSABLE TEST LOGIC ###############################

RATES=(11025 16000 22050 24000 32000 44100 48000 88200 96000)

for i in "${RATES[@]}"
do
        do_cmd run_alsa_perf.sh -${test_type} 0 -rate $i -periodsize ${PERIODSIZE} -performance
        sleep 2  # allow codec hardware to settle before next rate change
done
