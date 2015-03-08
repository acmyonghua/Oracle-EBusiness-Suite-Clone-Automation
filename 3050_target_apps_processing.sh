#!/usr/bin/ksh
#
#####################################################################################################
#                S T A G I N G    O V E R L A Y - target Apps Tasks                            		#
#                           3050_target_apps_processing.sh											#
#####################################################################################################
#
# Import properties file
#
. clone_environment.properties
#################################################
# Default Configuration							#
#################################################
trgbasepath="${basepath}targets/"
logfilepath="${basepath}logs/"
functionbasepath="${basepath}function_lib/"
custfunctionbasepath="${basepath}custom_lib/"
custsqlbasepath="${custfunctionbasepath}sql/"
sqlbasepath="${functionbasepath}sql/"
rmanbasepath="${functionbasepath}rman/"
abendfile="$trgbasepath""$trgappname"/"$trgappname"_3050_abend_step


####################################################################################################
#      add functions library                                                                       #
####################################################################################################
    
. ${functionbasepath}/syncpoint.sh   
. ${functionbasepath}/send_notification.sh
. ${functionbasepath}/os_tar_gz_file.sh
. ${functionbasepath}/os_delete_move_file.sh
. ${functionbasepath}/os_user_check.sh
. ${functionbasepath}/os_verify_or_make_directory.sh
. ${functionbasepath}/os_verify_or_make_file.sh
. ${functionbasepath}/is_os_file_exist.sh
. ${functionbasepath}/is_os_process_running.sh
. ${custfunctionbasepath}/error_notification_exit.sh
#
########################################
#       VALIDATIONS                    #
########################################
#
if [ $# -lt 1 ]
then
	echo " ====> Abort!!!. Invalid apps name for overlay"
        usage $0 :1000_overlay_staging  "[APPS NAME]"
        ########################################################################
        #   send notification  and exit                                        #
        ########################################################################
        send_notification "$trgappname"_Overlay_abend "Invalid apps name for replication" ${TOADDR} ${RTNADDR} ${CCADDR}
        exit 3
fi
#

#
# Check user  
#
os_user_check ${appsosuser}
	rcode=$?
	if [ "$rcode" -gt 0 ]
	then
		error_notification_exit $rcode "Wrong os user, user should be ${appsosuser}!!" $trgappname 0 $LINENO
	fi
#
# Validate Directory
#
os_verify_or_make_directory ${logfilepath}
os_verify_or_make_directory ${trgbasepath}
os_verify_or_make_directory ${trgbasepath}${srcappname}
os_verify_or_make_file ${abendfile} 0

#
# Verify Apps environment
#
if [[ -n "${TWO_TASK+1}" && $TWO_TASK == $trgappname ]]
then
	echo "Environment is correct!"
else 
	echo "Environment is not set or wrong environment to clone."
	error_notification_exit $rcode "Wrong Enviornment to clone $trgappname !!" $trgappname 0 $LINENO
fi
############################################################
restart=false
while read val1 val2
do
        stepnum=$val1
        linenum=$val2
        if [[ "$stepnum" !=  "0" ]]
        then
                restart=true
		echo ""
                echo "  RESTART LOCATION: "$stepnum" ,around line: "$linenum"" 
		echo "   SCRIPT LOCATION: ${basepath}$0"
                echo "TASK LOG  LOCATION: ${trgbasepath}${trgdbname}/"
                echo " RUN LOG  LOCATION: ${logfilepath}"
		echo ""
	else
		echo ""
                echo "   NORMAL LOCATION: "$stepnum" ,line: "$linenum""
		echo "   SCRIPT LOCATION: ${basepath}$0"
                echo "TASK LOG  LOCATION: ${trgbasepath}${trgdbname}/"
                echo " RUN LOG  LOCATION: ${logfilepath}"
		echo ""
		stepnum=`expr $stepnum + 50`
        fi
done < "$abendfile"
#
now=$(date "+%m/%d/%y %H:%M:%S")
echo $now >>$logfilepath$logfilename
#
now=$(date "+%m/%d/%y %H:%M:%S")" ====>  ########    $srcappname to $trgappname overlay has been started - PART3    ########"
echo $now >>$logfilepath$logfilename
#
for step in $(seq "$stepnum" 50 250)
do
        case $step in
        "50")
			#####################################################################################
			#  send notification that APPS overlay started                                      #
			#  													                                #
			#####################################################################################
			echo "START TASK: $step send_notification"
			send_notification "$srcappname"_backup_started  "$srcappname backup started" ${TOADDR} ${RTNADDR} ${CCADDR}
			#
			########################################
			#  write an audit record in the log    #
			########################################
			now=$(date "+%m/%d/%y %H:%M:%S")" ====> Send start $srcappname apps backup Notification"
			echo $now >>$logfilepath$logfilename
			#
			echo "END   TASK: $step send_notification"
		;;
		"100")
			########################################
			#  check source apps status            #
			########################################
			echo "START TASK: $step apps status check"
			if is_os_process_running FNDLIBR 
			then
				echo "Concurrent process is running.."
				os_killall_process FNDLIBR
			else 
				echo "Concurrent process is not running.."
			fi
			echo "END   TASK: $step apps status check"
		;;
		"150")
			########################################
			#  restore apps from  backup		   #
			########################################
			echo "START TASK: $step os_untar_gz_file"
			now=$(date "+%m/%d/%y %H:%M:%S")" ====> Delete $srcappname old backups"
			echo $now >>$logfilepath$logfilename
			#
			if is_os_file_exist ${appsourcebkupdir}${srcappname}.tar.gz 
			then
			    echo "Moving previous backup file ${appsourcebkupdir}${srcappname}.tar.gz ${appsourcebkupdir}${srcappname}.tar.gz.$appender"
				os_untar_gz_file ${appsourcebkupdir}${srcappname}.tar.gz ${apptargethomepath}
			else 
			    error_notification_exit $rcode "Apps Backup not found." $trgappname $step $LINENO
			fi
			#
	        rcode=$?
            if [ "$rcode" -gt 0 ]
            then
				error_notification_exit $rcode "Restore apps files FAILED!!" $trgappname $step $LINENO
			fi
			echo "END   TASK: $step os_untar_gz_file"
		;; 
		"200")
			#########################################
			#  Run adcfgclone 					    #
			#########################################
			echo "START TASK: $step start_rman_prod_backups"
			now=$(date "+%m/%d/%y %H:%M:%S")" ====> Start $srcappname new backups"
			echo $now >>$logfilepath$logfilename
			#
			echo taring ${appsourcehomepath} to ${appsourcebkupdir}${srcappname}.tar.gz
			apps_run_adcfgclone 
			rcode=$?
			if [ $? -ne 0 ] # if RMAN connection fails
			then
				error_notification_exit $rcode "Apps clone for $trgappname FAILED!!" $trgappname $step $LINENO
			fi
			echo "END   TASK: $step os_tar_gz_file"
		;;
#		"250")
			########################################
			#  Source database backups completed   #
			########################################
			#
			########################################
			#  check source apps after backups #
			########################################
		"300")
            echo "START TASK: $step end-of $srcappname app backup"
            syncpoint $srcappname "0 " "$LINENO"
            echo "END   TASK: $step end-of $srcappname app backup"
		;;
        *)
            echo "step not found - step: $step around Line ===> "  "$LINENO"
        ;;
        esac
done

