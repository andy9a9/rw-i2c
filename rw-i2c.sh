#!/bin/sh

# I2C read-write script made by Peter Fabian for Peter Janis
# Full disclaimer: I DON'T DO MICROELECTRONICS.
# Use at your own risk
# Complaints send to: edizontn@gmail.com
# Questions about shell part you can send to: peter.fabian@papaphi.com (response not guaranteed)

# based on following write-edid script:
#
# Created by Dr. Ace Jeangle (support@chalk-elec.com) 
# based on script from Tom Kazimiers (https://github.com/tomka/write-edid)
#
# Writes EDID information over a given I2C-Bus to a monitor.
# The scripts expects root permissions.
#
# You can find out the bus number with ic2detect -l. Address 0x50
# should be available as the EDID data goes there.

#exit codes:
# 1: Argument parsing error
# 2: Neither R not W option was specified
# 3: Communication bus missing
# 4: In-out file handling error
# 5: Chip address format error
# 6: Length format error
# 7: Byte offset format error
# 8: Start address format error


# function to print help
print_help() {
  echo "Usage: $(basename $0) [mode] [options]"
  echo "Modes:"
  echo "  -h | --help  ... print this help message"
  echo "  -r | --read  ... read data from addr"
  echo "  -w | --write ... write data to addr"
  echo "Options:"
  echo "  -b | --bus <bus_number>       ... i2c communication bus"
  echo " [-c | --chip_addr <hex_addr>]  ... chip address (default value is 0x50)"
  echo " [-l | --length <size>]         ... length in bytes (default valur is 128)"
  echo " [-o | --offset <bytes>]        ... offset in bytes for writing (default value is 0)"
  echo "Options (valid only for 'write' mode)"
  echo " [-s | --start_addr <hex_addr>] ... start address (default value is 0x00)"
  echo " [-f | --file <filename>]       ... file to be written (default value is stdin)"
  echo "Options (valid only for 'read' mode)"
  echo "  -f | --file <filename>        ... file to be read"
  exit $1
}

# function to check decimal format
#  returns: 0 if format is correct, otherwise 1
check_dec_format() {
  if echo $1 | grep -q -E "^[0-9]+$"; then return 0; fi
  return 1
}

# function to check hex format
#  returns: 0 if format is correct, otherwise 1
check_hex_format() {
  if echo $1 | grep -q -E "^0x[0-9a-fA-F]+$"; then return 0; fi
  return 1
}

# initialize options variables
READ_MODE=-1
BUS=""
CHIP_ADDR=0x50
START_ADDR=0x00
WRITE_OFFSET=0
MAX_BYTES_CNT=128
FILENAME=""

# check options
[ $# -lt 1 ] && print_help 0

# check mode
case "$1" in
  -h|--help)
    if [ $# -gt 1 ]; then
      echo "ERR: mode 'HELP' does not support options"
      print_help 1
    else
      print_help 0
    fi
    ;;
  -r|--read)
    READ_MODE=1
    shift
    ;;
  -w|--write)
    READ_MODE=0
    shift
    ;;
   *)
    echo "ERR: unknown mode '$1'"
    print_help 1
    ;;
esac

if [ $# -lt 1 ]; then
  echo "ERR: working mode needs options"
  exit 2
fi

# process options
while [ $# -ge 1 ]; do
  case "$1" in
    -b|--bus)
      shift
      BUS="$1"
      ;;
    -c|--chip_addr)
      shift
      CHIP_ADDR=$1
      ;;
    -l|--length)
      shift
      MAX_BYTES_CNT=$1
      ;;
    -o|--offset)
      shift
      WRITE_OFFSET=$1
      ;;
    -s|--start_addr)
      shift
      if [ $READ_MODE -eq 0 ]; then
        START_ADDR=$1
      else
        echo "ERR: mode 'READ' does not support start addressing"
        print_help 1
      fi
      ;;
    -f|--file)
      shift
      FILENAME="$1"
      ;;
    *)
      echo "ERR: unrecognized mode option '$1'"
      print_help 1
      ;;
  esac
  shift
done

# check if bus is used
if [ -z "$BUS" ]; then
  echo "ERR: i2c bus has to be specified"
  exit 3
fi

# check if i2c bus is available
if ! i2cdetect -l | grep -q "i2c-$BUS"$(printf '\t'); then
  echo "ERR: i2c bus 'i2c-$BUS' was not found"
  exit 3
fi

# check if chip address is in hex format
if ! check_hex_format $CHIP_ADDR; then
  echo "ERR: chip address '$CHIP_ADDR' has to be in hex format"
  exit 5
fi

# check if max byte count is in dec format
if ! check_dec_format $MAX_BYTES_CNT; then
  echo "ERR: bytes count '$MAX_BYTES_CNT' has to be in decimal format"
  exit 6
fi

# check if offset is in dec format
if ! check_dec_format $WRITE_OFFSET; then
  echo "ERR: byte offset '$WRITE_OFFSET' has to be in decimal format"
  exit 7
fi

# check if start address is in hex format
if ! check_hex_format $START_ADDR ; then
  echo "ERR: start address '$START_ADDR' has to be in hex format"
  exit 8
fi

# write mode
if [ $READ_MODE -eq 0 ]; then
  # check if filename was specified, otherswise stdin will be used
  if [ -z "$FILENAME" ]; then
    FILENAME="/dev/stdin"
  else
    if [ ! -r "$FILENAME" ]; then
      echo "ERR: Can not read $FILENAME"
      exit 4
    fi
  fi

  # process MAX_BYTES_CNT bytes from input file
  count=$START_ADDR
  xxd -p -g 0 -u -c 1 -s $WRITE_OFFSET -l $MAX_BYTES_CNT "$FILENAME" | while read -r byte; do
    # convert counter to hex numbers of lentgh two, padded with zeros
    address=$(printf "0x%02X" $count)
    value=0x${byte}
    # give some feedback
    echo "Writing byte '$value' to bus $BUS, chip-adress '$CHIP_ADDR', data-adress '$address'"
    # write date to bus (with interactive mode disabled)
    i2cset -y "$BUS" $CHIP_ADDR $address $value
    # increment counter
    count=$((count+1))
    # sleep a moment
    sleep 0.1s
  done

  echo "Writing done, here is the output of i2cdump -y $BUS $CHIP_ADDR:"
  i2cdump -y "$BUS" $CHIP_ADDR
else
  if [ -z "$FILENAME" ]; then
    echo "ERR: Output file missing"
    exit 4
  fi

  outpath="$(dirname $FILENAME)"
  if [ ! -d "$outpath" ] || [ ! -w "$outpath" ]; then
    echo "ERR: Output directory is not existing or is not writable"
    exit 4
  fi

  echo "Here is the HEX output of i2cdump -y $BUS $CHIP_ADDR"
  i2cdump -y "$BUS" $CHIP_ADDR
  echo "Now we write it to '$FILENAME' in binary format including offset and max bytes count".
  i2cdump -y "$BUS" $CHIP_ADDR | xxd -r -p -s $WRITE_OFFSET -l $MAX_BYTES_CNT > "$FILENAME"
fi

exit 0
