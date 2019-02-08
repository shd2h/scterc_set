#!/bin/bash
# sctercset.sh - checks for the availability of scterc on each drive, and records their serial numbers into a csv file.
# When run a second time against a drive contained within its csv file, will set scterc/scsi timeout appropriately for RAID arrays, 
# allowing "consumer" drives to perform normally. Script is set to default 7s for scterc supporting drives, and 180s for drives that
# dont support scterc (consumer drives can take 120s+ to timeout, so this prevents the raid controller from kicking them).
#
# NB: if you're using some form of ZFS software RAID you don't need to run this against your drives.
#
#
## USAGE:
# This is a fairly simple program that performs two different functions when run. Firstly, it will populate a csv file with serial 
# numbers of detected drives, and if these support scterc. Secondly, when run against a drive with a serial already present in the 
# csv file, it will check the is_raid_disk variable inside the csv file, which is user configurable. If this is set to yes, scterc 
# timeout or the linux scsi timeout will be set appropriately for using the drive in RAID if necessary. If this variable is set to 
# anything else (eg no), then no action is taken.
#
# example csv file, where the first disk supports scterc and is set as part of a raid array, and the second disk supports scterc but
# is not part of a raid array:
#
# >root@linux:~# cat /root/scterc_set/scterc_conf.csv
# >drive_serial,sctert_support,is_raid_disk
# >ABC123DE,yes,yes
# >FGH4I567,yes,no
#
# In this example, the script will act on the first drive and update the timings on it, but not the second.
#
## REQUIRES:
# smartctl, awk, grep.
#
## Version History:
#v0.1 - baseline
#v0.2 - added scterc value parsing


## USER CONFIGURABLE SETTINGS BLOCK

outputdir=~/scterc_set

## END USER CONFIGURABLE SETTINGS BLOCK

newdrives=0

# test + create our work directory in the users home dir.
if [[ ! -e $outputdir ]]; then
   mkdir -p $outputdir
fi


# loop through all drives individually
for drive in /dev/sd[a-z] /dev/sd[a-z][a-z]; do

   # first check if there actually is a drive there, if not then skip everything else
   if [[ ! -e $drive ]]; then continue ; fi

   # record the smart info from each drive that responded, then do a quick check to see if they offer smart reporting
   smartinfo=$(smartctl -a $drive)
   smartenabled=$(echo "$smartinfo" | grep 'SMART overall' | awk '{print $6}')

   # skip the ones that don't offer smart reporting.
   if [[ -z $smartenabled ]]; then continue; fi
   
   # gather serial + sct support status if smart is enabled
   driveserial=$(echo "$smartinfo" | grep 'Serial Number: ' | awk '{print $3}')
   sctercval=$(smartctl -l scterc $drive | grep "Read:" | awk '{print $2}')
   
   # write out scterc support to a variable
   if [[ -z $sctercval ]]; then
   supports_sctert="no"
   sctercval_nice=" "
   else
   supports_sctert="yes"
   fi
   
   #check if we got a numeric value in centiseconds for sct timeout, and convert it to seconds (+add "s" suffix) if we did
   if [[ $sctercval =~ ^[0-9]+$ ]]; then
      sctercval_nice=$(( sctercval / 10 ))s   
   else
      sctercval_nice=$sctercval
   fi
   
   
 
    # test + create our csv with the drive smart values if needed
    if [[ ! -e $outputdir/scterc_conf.csv ]]; then
       # do the initial creation
       echo "drive_serial,sctert_support,is_raid_disk" > $outputdir/scterc_conf.csv
    fi
 
    # check for current drive serial, if found read its info in as an array
    IFS=","
    driveinfoarray=$(grep $driveserial $outputdir/scterc_conf.csv)
    # if array exists, proceed
    if [[ -n $driveinfoarray  ]]; then
       # check if we need to do anything by reading the israiddisk var
 	   if [[ "${driveinfoarray[2]}" = 'yes' ]]; then
 	       # check if we're able to set scterc, or if we're failing over and amending the scsi timeout, and take the necessary action
 		   if [[ "$supports_sctert" = 'yes' ]]; then
 		   $(smartctl -l scterc,70,70 $drive)
 		   echo "Set scterc to 7 seconds on $drive (Serial: $driveserial)"
 		   else
 		   shortdrive=$(echo $drive | awk '{print substr($1,6); }')
 		   echo "$shortdrive"
 		   $(echo 180 > /sys/block/$shortdrive/device/timeout)
		   echo "Set linux scsi timeout to 180 seconds on $drive (Serial: $driveserial)"
 		   fi	   
 	   else
           echo "Making no changes to $drive (Serial: $driveserial), it is not marked as forming part of a RAID array."
	   fi
    # if array doesn't exist, we've never seen this drive before, so write its serial, scterc support status, to the array, so the user can decide what to do with it on next run.
    else
       echo "$driveserial,$supports_sctert,unknown" >> $outputdir/scterc_conf.csv
	   echo "-----New drive detected -----"
	   echo "                    Serial         : $driveserial"
	   echo "                    Scterc support : $supports_sctert"
	   echo "                    Scterc timeout : $sctercval_nice"
	   newdrives=1
    fi
   

done   
   
if [[ $newdrives -gt 0 ]]; then
   {
   echo "!!!!!!!!!!!!!!!!!!!!!!!!!!"
   echo "New drives were detected."
   echo "Please change the is_raid_disk variable in the csv database $outputdir/scterc_conf.csv to yes if these drives form part of a RAID array, and then re-run this program to set scterc/scsi timeouts for them."
   echo "!!!!!!!!!!!!!!!!!!!!!!!!!!"
   }
fi
