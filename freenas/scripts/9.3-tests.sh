#!/usr/local/bin/bash
# Author: Kris Moore
# License: BSD
# Location for tests into REST API of FreeNAS 9.3
# Resty Docs: https://github.com/micha/resty
# jsawk: https://github.com/micha/jsawk

# Where is the pcbsd-build program installed
PROGDIR="`realpath | sed 's|/scripts||g'`" ; export PROGDIR

# IP of client we are testing
if [ -n "$1" ] ; then
  ip="$1"
  manualip="YES"
else
  ip="192.168.56.100"
  manualip="NO"
fi

# Set the username / pass of FreeNAS for REST calls
if [ -n "$2" ] ; then
  fuser="$2"
else
  fuser="root"
fi
if [ -n "$3" ] ; then
  fpass="$3"
else
  fpass="testing"
fi

# Source our resty / jsawk functions
. ${PROGDIR}/../utils/resty -W "http://${ip}:80/api/v1.0" -H "Accept: application/json" -H "Content-Type: application/json" -u ${fuser}:${fpass}

# Set variable to call jsawk utility
JSAWK="${PROGDIR}/../utils/jsawk -j js24"

# Log files
RESTYOUT=/tmp/resty.out
RESTYERR=/tmp/resty.err

TOTALCOUNT="0"

#################################################################
# Run the tests now!
#################################################################

echo_ok()
{
  echo -e " - OK"
}

# Check for $1 REST response, error out if not found
check_rest_response()
{
  grep -q "$1" ${RESTYERR}
  if [ $? -ne 0 ] ; then
    cat ${RESTYERR}
    cat ${RESTYOUT}
    exit 1
  fi
}

check_rest_response_continue()
{
  grep -q "$1" ${RESTYERR}
  return $?
}

# $1 = Command to run
# $2 = Command to run if $1 fails
rc_halt()
{
  ${1} >/tmp/.cmdTest.$$ 2>/.cmdTest.$$
  if [ $? -ne 0 ] ; then
     echo -e " - FAILED"
     ${2}
     echo "Failed running: $1"
     cat /tmp/.cmdTest.$$
     rm /tmp/.cmdTest.$$
     exit 1
  fi
  rm /tmp/.cmdTest.$$
}

set_test_group_text()
{
  GROUPTEXT="$1"
  TOTALTESTS="$2"
  TCOUNT=0
}

echo_test_title()
{
  TCOUNT=`expr $TCOUNT + 1`
  TOTALCOUNT=`expr $TOTALCOUNT + 1`
  sync
  echo -e "Running $GROUPTEXT ($TCOUNT/$TOTALTESTS) - $1\c"
}

storage_tests()
{
  # Set the group text and number of tests
  set_test_group_text "Storage tests" "6"

  # Check getting disks
  echo_test_title "Disks / API functionality"
  GET /storage/disk/ -v 2>${RESTYERR} >${RESTYOUT}
  check_rest_response "200 OK"
  echo_ok

  # Check creating a zpool
  echo_test_title "Creating volume"
  POST /storage/volume/ '{ "volume_name" : "tank", "layout" : [ { "vdevtype" : "stripe", "disks" : [ "ada1", "ada2" ] } ] }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "201 CREATED"
  echo_ok

  # Check creating a dataset /share
  echo_test_title "Creating dataset tank/share"
  POST /storage/volume/tank/datasets/ '{ "name": "share" }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "201 CREATED"
  echo_ok

  # Check creating a dataset /jails
  echo_test_title "Creating dataset tank/jails"
  POST /storage/volume/tank/datasets/ '{ "name": "jails" }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "201 CREATED"
  echo_ok

  # Set the permissions of the dataset
  echo_test_title "Changing permissions on /mnt/tank"
  PUT /storage/permission/ '{ "mp_path": "/mnt/tank", "mp_acl": "unix", "mp_mode": "777", "mp_user": "root", "mp_group": "wheel" }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "201 CREATED"
  echo_ok

  # Set the permissions of the dataset
  echo_test_title "Changing permissions on /mnt/tank/share"
  PUT /storage/permission/ '{ "mp_path": "/mnt/tank/share", "mp_acl": "unix", "mp_mode": "777", "mp_user": "root", "mp_group": "wheel" }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "201 CREATED"
  echo_ok
}

nfs_tests()
{
  # Set the group text and number of tests
  set_test_group_text "NFS tests" "9"

  # Enable NFS server
  echo_test_title "Creating the NFS server"
  PUT /services/nfs/ '{ "nfs_srv_bindip": "'"${ip}"'", "nfs_srv_mountd_port": 618, "nfs_srv_allow_nonroot": false, "nfs_srv_servers": 10, "nfs_srv_udp": false, "nfs_srv_rpcstatd_port": 871, "nfs_srv_rpclockd_port": 32803, "nfs_srv_v4": true, "nfs_srv_v4_krb": true, "id": 1 }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "200 OK"
  echo_ok

  # Check creating a NFS share
  echo_test_title "Creating a NFS share on /mnt/tank/share"
  POST /sharing/nfs/ '{ "nfs_comment": "My Test Share", "nfs_paths": ["/mnt/tank/share"], "nfs_security": "sys" }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "201 CREATED"
  echo_ok

  # Now start the service
  echo_test_title "Starting NFS service"
  PUT /services/services/nfs/ '{ "srv_enable": true }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "200 OK"
  echo_ok

  # Now check if we can mount NFS / create / rename / copy / delete / umount
  echo_test_title "Mounting NFS"
  rc_halt "mkdir /tmp/nfs-mnt.$$"
  rc_halt "mount_nfs ${ip}:/mnt/tank/share /tmp/nfs-mnt.$$" "umount /tmp/nfs-mnt.$$ ; rmdir /tmp/nfs-mnt.$$"
  echo_ok

  echo_test_title "Creating NFS file"
  rc_halt "touch /tmp/nfs-mnt.$$/testfile" "umount /tmp/nfs-mnt.$$ ; rmdir /tmp/nfs-mnt.$$"
  echo_ok

  echo_test_title "Moving NFS file"
  rc_halt "mv /tmp/nfs-mnt.$$/testfile /tmp/nfs-mnt.$$/testfile2"
  echo_ok

  echo_test_title "Copying NFS file"
  rc_halt "cp /tmp/nfs-mnt.$$/testfile2 /tmp/nfs-mnt.$$/testfile"
  echo_ok

  echo_test_title "Deleting NFS file"
  rc_halt "rm /tmp/nfs-mnt.$$/testfile2"
  echo_ok

  echo_test_title "Unmounting NFS"
  rc_halt "umount /tmp/nfs-mnt.$$"
  rc_halt "rmdir /tmp/nfs-mnt.$$"
  echo_ok
}

iscsi_tests()
{
  # Set the group text and number of tests
  set_test_group_text "iSCSI tests" "1"

  # Enable iSCSI server
  echo_test_title "Creating iSCSI extent"
  POST /services/iscsi/extent/ '{ "iscsi_target_extent_type": "File", "iscsi_target_extent_name": "extent", "iscsi_target_extent_filesize": "50MB", "iscsi_target_extent_path": "/mnt/tank/iscsi" }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "201 CREATED"
  echo_ok

}

cifs_tests()
{
  # Set the group text and number of tests
  set_test_group_text "CIFS tests" "9"

  echo_test_title "Enabling CIFS service"
  PUT /services/cifs/ '{ "cifs_srv_description": "Test FreeNAS Server", "cifs_srv_guest": "nobody", "cifs_hostname_lookup": false, "cifs_srv_aio_enable": false, "cifs_srv_netbiosname": "testnas" }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "200 OK"
  echo_ok

  echo_test_title "Creating a CIFS share on /mnt/tank/share"
  POST /sharing/cifs/ '{ "cfs_comment": "My Test CIFS Share", "cifs_path": "/mnt/tank/share", "cifs_name": "TestShare", "cifs_guestok": true, "cifs_vfsobjects": "streams_xattr" }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "201 CREATED"
  echo_ok

  # Now start the service
  echo_test_title "Starting CIFS service"
  PUT /services/services/cifs/ '{ "srv_enable": true }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "200 OK"
  echo_ok

  sleep 3

  # Now check if we can mount NFS / create / rename / copy / delete / umount
  echo_test_title "Mounting CIFS"
  rc_halt "mkdir /tmp/cifs-mnt.$$"
  sync
  rc_halt "mount_smbfs -N -I ${ip} //guest@testnas/TestShare /tmp/cifs-mnt.$$" "rmdir /tmp/cifs-mnt.$$"
  echo_ok

  echo_test_title "Creating CIFS file"
  rc_halt "touch /tmp/cifs-mnt.$$/testfile" "umount /tmp/cifs-mnt.$$ ; rmdir /tmp/cifs-mnt.$$"
  echo_ok

  echo_test_title "Moving CIFS file"
  rc_halt "mv /tmp/cifs-mnt.$$/testfile /tmp/cifs-mnt.$$/testfile2"
  echo_ok

  echo_test_title "Copying CIFS file"
  rc_halt "cp /tmp/cifs-mnt.$$/testfile2 /tmp/cifs-mnt.$$/testfile"
  echo_ok

  echo_test_title "Deleting CIFS file"
  rc_halt "rm /tmp/cifs-mnt.$$/testfile2"
  echo_ok

  echo_test_title "Unmounting CIFS"
  rc_halt "umount /tmp/cifs-mnt.$$"
  rc_halt "rmdir /tmp/cifs-mnt.$$"
  echo_ok
}

# Set the IP address of REST
set_ip()
{
  set_test_group_text "Networking Configuration" "4"

  echo_test_title "Setting IP address: ${ip} on em0"
  if [ "$manualip" = "NO" ] ; then
    POST /network/interface/ '{ "int_ipv4address": "'"${ip}"'", "int_name": "internal", "int_v4netmaskbit": "24", "int_interface": "em0" }' -v >${RESTYOUT} 2>${RESTYERR}
    check_rest_response "201 CREATED"
  fi
  echo_ok

  echo_test_title "Setting DHCP on em1"
  POST /network/interface/ '{ "int_dhcp": true, "int_name": "ext", "int_interface": "em1" }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "201 CREATED"
  echo_ok

  echo_test_title "Rebooting VM"
  POST /system/reboot/ '' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "202 ACCEPTED"
  echo_ok

  echo_test_title "Waiting for reboot"
  sleep 20
  wait_for_avail
  echo_ok
}

# Run a series of tests on the boot-environments
bootenv_tests() {
  set_test_group_text "Boot-Environment Tests" "3"

  echo_test_title "Creating a new boot-environment: newbe1"
  POST /system/bootenv/ '{ "name": "newbe1", "source": "default" }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "201 CREATED"
  echo_ok

  echo_test_title "Creating a new boot-environment: newbe2"
  POST /system/bootenv/ '{ "name": "newbe2", "source": "newbe1" }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "201 CREATED"
  echo_ok

  echo_test_title "Removing a boot-environment: newbe2"
  DELETE /system/bootenv/newbe2 '' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "204 NO CONTENT"
  echo_ok
}

# Run a series of tests on the ssh settings
# We also leave it enabled, so we have access to VM if something hangs / goes wrong
ssh_tests() {
  set_test_group_text "SSH Tests" "2"

  echo_test_title "Configuring SSH settings"
  PUT /services/ssh/ '{ "ssh_rootlogin": true }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "200 OK"
  echo_ok

  echo_test_title "Enabling SSH Service"
  PUT /services/services/ssh/ '{ "srv_enable": true }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "200 OK"
  echo_ok

}

# Run a series of tests on the email settings
email_tests() {
  set_test_group_text "E-Mail Tests" "1"

  echo_test_title "Configuring e-mail settings"
  PUT /system/email/ '{ "em_fromemail": "william.spam@ixsystems.com", "em_outgoingserver": "mail.ixsystems.com", "em_pass": "changeme", "em_port": 25, "em_security": "plain", "em_smtp": true, "em_user": "william.spam@ixsystems.com" }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "200 OK"
  echo_ok
}

# Run a series of tests on jail creation
jail_tests() {
  set_test_group_text "Jail Tests" "6"

  echo_test_title "Configuring jails"
  PUT /jails/configuration/ '{ "jc_ipv4_network_start": "192.168.56.150", "jc_path": "/mnt/tank/jails" }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "201 CREATED"
  echo_ok

  echo_test_title "Creating jail - VNET OFF"
  POST /jails/jails/ '{ "jail_host": "testjail", "jail_defaultrouter_ipv4": "192.168.56.1", "jail_ipv4": "192.168.56.155", "jail_ipv4_netmask": "24", "jail_vnet": false }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "201 CREATED"
  echo_ok

  echo_test_title "Mount tank/share into jail"
  POST /jails/mountpoints/ '{ "destination": "/mnt", "jail": "testjail", "mounted": true, "readonly": false, "source": "/mnt/tank/share" }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "201 CREATED"
  echo_ok

  echo_test_title "Starting jail"
  POST /jails/jails/1/start/ '' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "202 ACCEPTED"
  echo_ok

  echo_test_title "Restarting jail"
  POST /jails/jails/1/restart/ '' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "202 ACCEPTED"
  echo_ok

  echo_test_title "Stopping jail"
  POST /jails/jails/1/stop/ '' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "202 ACCEPTED"
  echo_ok
}

rsyncd_tests() {
  set_test_group_text "RSYNC tests" "4"

  echo_test_title "Configuring rsyncd service"
  PUT /services/rsyncd/ '{ "rsyncd_port": 873 }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "200 OK"
  echo_ok

  echo_test_title "Starting rsyncd service"
  PUT /services/services/rsync/ '{ "srv_enable": true }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "200 OK"
  echo_ok

  echo_test_title "Creating rsync resource"
  POST /services/rsyncmod/ '{ "rsyncmod_name": "testmod", "rsyncmod_path": "/mnt/tank/share" }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "201 CREATED"
  echo_ok

  # Test rsync
  echo_test_title "Testing rsync access"
  rc_halt "rsync -avn ${ip}::testmod"
  echo_ok
}

ftp_tests() {
  set_test_group_text "FTP tests" "3"

  echo_test_title "Configuring ftp service"
  PUT /services/ftp/ '{ "ftp_clients": 10, "ftp_rootlogin": true }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "200 OK"
  echo_ok

  echo_test_title "Starting ftp service"
  PUT /services/services/ftp/ '{ "srv_enable": true }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "200 OK"
  echo_ok

  echo_test_title "Fetching file via FTP"
  rc_halt "ftp -o /tmp/ftpfile ftp://testuser:test@${ip}/.cshrc"
  echo_ok
}

user_tests() {
  set_test_group_text "User tests" "3"

  # Create dataset for the home directory
  echo_test_title "Creating home dataset tank/testuser"
  POST /storage/volume/tank/datasets/ '{ "name": "testuser" }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "201 CREATED"
  echo_ok

  # Create the testuser
  echo_test_title "Creating user: testuser"
  POST /account/users/ '{ "bsdusr_username": "testuser", "bsdusr_creategroup": true, "bsdusr_full_name": "Test User", "bsdusr_password": "test", "bsdusr_uid": 1111, "bsdusr_home": "/mnt/tank/testuser", "bsdusr_mode": "755", "bsdusr_shell": "/bin/csh" }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "201 CREATED"
  echo_ok

  # Get the ID of this user
  userid=$(cat ${RESTYOUT} | ${JSAWK} 'return this.id')

  # Set the user to part of the 'wheel' / 'ftp' groups
  echo_test_title "Setting user groups: wheel,ftp"
  POST /account/users/${userid}/groups/ '["wheel","ftp"]' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "202 OK"
  echo_ok

}

wait_for_avail()
{
  count=0
  while :
  do
    GET /storage/disk/ -v 2>${RESTYERR} >${RESTYOUT}
    check_rest_response_continue "200 OK"
    if [ $? -eq 0 ] ; then break; fi
    echo -e ".\c"
    sleep 60
    if [ $count -gt 10 ] ; then
       echo "FreeNAS API failed to respond!"
       exit 1
    fi
    count=`expr $count + 1`
  done
}

# When running via Jenkins / ATF mode, it may take a variable
# time to boot the system and be ready for REST calls. We run
# an initial test to determine when the interface is up
echo -e "Testing access to REST API\c"
wait_for_avail
echo_ok

# Reset the IP address via REST
set_ip

# Setup SSH access
ssh_tests

# Check e-mail configuration
email_tests

# Check boot environment support
bootenv_tests

# Run the storage tests
storage_tests

# Run the user tests
user_tests

# Run the rsyncd tests
rsyncd_tests

# Run the CIFS tests
cifs_tests

# Run the FTP tests
ftp_tests

# Run the NFS tests
nfs_tests

# Run the iSCSI tests
iscsi_tests

# Run the jail tests
jail_tests

# Made it to the end, exit with success!
echo "SUCCESS - $TOTALCOUNT tests run - REST API testing complete!"
exit 0
