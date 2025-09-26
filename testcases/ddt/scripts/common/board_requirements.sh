# Single place to define test requirements associated with
# different platforms.

source "common.sh"

# Return names of power domain and its corresponding state that
# must be hit during system suspend.
# $1: platform
get_power_domain_states_on_suspend()
{
  platform=$1

  case $platform in
    dra7xx*|dra72x*|am57xx*)
      rtn="cam_pwrdm:OFF,mpu_pwrdm:RET,vpe_pwrdm:OFF,cpu0_pwrdm:RET,gpu_pwrdm:OFF,dss_pwrdm:OFF,iva_pwrdm:OFF,dsp1_pwrdm:OFF,dsp2_pwrdm:OFF" ;;
    am335x*|beagle*|am43*)
      rtn="mpu_pwrdm:OFF,per_pwrdm:RET,gfx_pwrdm:OFF" ;;
  esac

  if [ -z "$rtn" ]; then
    die "Could not get power domain states requirements on suspend for $platform"
  fi

  echo "$rtn"
}

# Return max latency accepted for given use case and SoC
# $1: use case
get_acceptable_latency()
{
  local usecase=$1
  local max_latency
  case $usecase in
  *)
      case $SOC in
      *)
          max_latency=50 ;;
      esac
  esac
  echo "$max_latency"
}

# Return expected memory size (in kB) for running platform
get_acceptable_memory_size()
{
  expected_memory=''

  case $MACHINE in
    omapl138-lcdk)
      expected_memory=123100  ;;
    k2g-ice)
      expected_memory=383992  ;;
    beaglebone-black)
      expected_memory=495788  ;;
    am335x-evm)
      #TODO: AM335x EVM seems to have 256MB of mem in DT
      expected_memory=1015116 ;;
    k2hk-evm|k2l-evm)
      expected_memory=1415144 ;;
    am43xx-gpevm|am57*|dra71x*|dra72x*|k2g-evm)
      expected_memory=2065756 ;;
    k2e-evm)
      expected_memory=3494192 ;;
    am65*|dra7xx*|dra76x*)
      expected_memory=4123488 ;;
    beaglebone_green_eco-gp)
      # BeagleBone Green Eco has 512MB RAM but DT only shows 256MB
      expected_memory=256000 ;;
  esac

  if [ -z "$expected_memory" ]; then
    die "Could not get expected memory value from board_requirements.sh"
  fi

  export expected_memory
}

# Return expected r5f lockstep cores
get_num_r5f_lockstep_cores()
{
  local expected_r5f_lockstep=''

  case $MACHINE in
    am65*)
      expected_r5f_lockstep=1 ;;
  esac

  if [ -z "$expected_r5f_lockstep" ]; then
    die "No value is defined for $MACHINE in get_num_r5f_lockstep_cores() at board_requirements.sh"
  fi

  echo $expected_r5f_lockstep
}

# Return expected r5f cores in split mode
get_num_r5f_splitmode_cores()
{
  local expected_r5f_splitmode=''

  case $MACHINE in
    am65*)
      expected_r5f_splitmode=2 ;;
  esac

  if [ -z "$expected_r5f_splitmode" ]; then
    die "No value is defined for $MACHINE in get_num_r5f_splitmode_cores() at board_requirements.sh"
  fi

  echo $expected_r5f_splitmode
}