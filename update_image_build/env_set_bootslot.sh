#!/bin/sh

echo "Set upgrade_available to 1"
hub_setenv --upgrade_available 1

echo "Switch boot_slot to... " 
cur_boot_slot=$(hub_printenv -f boot_slot)
if [ x$cur_boot_slot == x"A" ]; then
	echo "SlotB"
	hub_setenv --boot_slot 2
else
	echo "SlotA"
	hub_setenv --boot_slot 1
fi

