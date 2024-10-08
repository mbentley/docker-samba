#!/bin/bash

set -e

add_group() {
  GROUPNAME="${1}"
  GROUP_ID="${2}"

  # check to see if group exists; if not, create it
  if grep -q -E "^${GROUPNAME}:" /etc/group > /dev/null 2>&1
  then
    echo "INFO: group ${GROUPNAME} exists; skipping creation"
  else
    # make sure the group doesn't already exist with a different name
    if awk -F ':' '{print $3}' /etc/group | grep -q "^${GROUP_ID}$"
    then
      # group exists; need to rename it
      EXISTING_GROUP="$(grep ":${GROUP_ID}:" /etc/group | awk -F ':' '{print $1}')"
      echo "INFO: group already exists with a different name; renaming '${EXISTING_GROUP}' to '${GROUPNAME}'..."
      sed -i "s/^${EXISTING_GROUP}:/${GROUPNAME}:/g" /etc/group
    else
      # create the group
      echo "INFO: group ${GROUPNAME} doesn't exist; creating..."
      addgroup -g "${GROUP_ID}" "${GROUPNAME}"
    fi
  fi
}

add_user() {
  USERNAME="${1}"
  GROUP="${USERNAME}"
  USER_ID="${2}"

  # check to see if user exists; if not, create it
  if id -u "${USERNAME}" > /dev/null 2>&1
  then
    echo "INFO: user ${USERNAME} exists; skipping creation"
  else
    echo "INFO: user ${USERNAME} doesn't exist; creating..."
    # create the user
    adduser -u "${USER_ID}" -G "${GROUP}" -H -s /bin/false -D "${USERNAME}"

    # set password in samba
    printf "%s\n%s\n" "${PASSWORD}" "${PASSWORD}" | smbpasswd -L -a -s "${USERNAME}"
  fi
}

add_user_to_group() {
  USERNAME="${1}"
  GROUP="${2}"

  # add user to the group
  # TODO: make sure that the user exists first
  echo "INFO: adding ${USERNAME} to ${GROUP}"
  addgroup "${USERNAME}" "${GROUP}"
}

createdir() {
  # create directory, if needed
  if [ ! -d "${1}" ]
  then
    echo "INFO: Creating ${1}"
    mkdir -p "${1}"
  fi

  # set permissions, if needed
  if [ -n "${2}" ]
  then
    chmod "${2}" "${1}"
  fi
}


# check to see if a secret source was set
if [ -n "${SECRET_FILE}" ] && [ -f "${SECRET_FILE}" ]
then
  echo "INFO: loading secrets from ${SECRET_FILE}..."
  . "${SECRET_FILE}"
fi

# make sure a samba config file exists
if [ -f /etc/samba/smb.conf ]
then
  # file exists
  echo "INFO: running testparm against /etc/samba/smb.conf to validate the config..."

  # run testparm to make sure we have a valid config
  testparm -s /etc/samba/smb.conf > /dev/null
  echo "INFO: testparm complete!"
else
  echo "ERROR: unable to find a samba configuraton file at /etc/samba/smb.conf!"
  exit 1
fi

# get a list of variables that start with ACCOUNT_
ACCOUNT_ENV_VARS="$(env | awk -F '=' '{print $1}' | grep ^ACCOUNT_ | sort)"

# process user accounts, if needed
if [ -n "${ACCOUNT_ENV_VARS}" ]
then
  # process accounts
  echo -e "\nINFO: processing user accounts..."

  # loop through variables to output the contents
  for VAR in ${ACCOUNT_ENV_VARS}
  do
    # extract get username from the key
    USERNAME="$(echo "${VAR}" | awk -F '^ACCOUNT_' '{print $2}')"

    # assume we want the user's group name to match the username
    GROUP="${USERNAME}"

    # set VAR to varname then use substitution to get the UID & password from the value
    VARNAME="${VAR}"
    UID_PASSWORD="${!VARNAME}"

    # get UID from the variable
    USER_UID="$(echo "${UID_PASSWORD}" | awk -F ':' '{print $1}')"

    # get the password from the rest of the variable
    PASSWORD="${UID_PASSWORD/${USER_UID}:/}"

    # TODO: make sure none of these are empty before adding

    # create group, if needed
    add_group "${USERNAME}" "${USER_UID}"

    # create user account & set samba password
    add_user "${USERNAME}" "${USER_UID}"
  done

  # done with accounts
  echo -e "INFO: user account processing complete!\n"
else
  # no accounts to process
  echo -e "\nINFO: no user accounts to process, skipping..."
fi

# get a list of variables that start with GROUP_
GROUP_ENV_VARS="$(env | awk -F '=' '{print $1}' | grep ^GROUP_ | sort)"

# process groups, if needed
if [ -n "${GROUP_ENV_VARS}" ]
then
  # process groups
  echo -e "INFO: processing groups..."

  # loop through variables to output the contents
  for VAR in ${GROUP_ENV_VARS}
  do
    # extract group name from the key
    GROUP="$(echo "${VAR}" | awk -F '^GROUP_' '{print $2}')"

    # set VAR to varname then use substitution to get the group id and username(s) from the value
    VARNAME="${VAR}"
    GROUP_GID_USERS="${!VARNAME}"

    # loop through groups, make sure they exist and then add the user
    GROUP_ID="$(echo "${GROUP_GID_USERS}" | awk -F ':' '{print $1}')"
    MEMBERS="$(echo "${GROUP_GID_USERS}" | awk -F ':' '{print $2}')"

    # create group, if needed
    add_group "${GROUP}" "${GROUP_ID}"

    # loop through the users; add each to the group
    for USERNAME in ${MEMBERS}
    do
      # add user to the group
      add_user_to_group "${USERNAME}" "${GROUP}"
    done
  done

  # done with groups
  echo -e "INFO: group processing complete!\n"
else
  # no groups to process
  echo -e "INFO: no groups to process, skipping...\n"
fi

# mkdirs if needed
createdir /var/lib/samba/private 700
createdir /var/log/samba/cores 700

# write avahi config file (smbd.service) to customize services advertised
echo "INFO: generating avahi configuration for /etc/avahi/services/smbd.service..."
SERVICE_NAME="%h"
HOSTNAME_XML=""

# try to read smb port from smb.conf; default to 445 if not set
SMB_PORT="$(grep "smb ports" /etc/samba/smb.conf 2>/dev/null | awk -F '=' '{print $2}' | awk '{print $1}')"
SMB_PORT="${SMB_PORT:-445}"

# see if an advertised hostname was set
if [ -n "${ADVERTISED_HOSTNAME}" ]
then
  echo "INFO: Avahi - using ${ADVERTISED_HOSTNAME} as hostname."
  SERVICE_NAME="${ADVERTISED_HOSTNAME}"
  HOSTNAME_XML="
    <host-name>${ADVERTISED_HOSTNAME}.local</host-name>"
fi
echo "<?xml version=\"1.0\" standalone='no'?>
<!DOCTYPE service-group SYSTEM \"avahi-service.dtd\">
<service-group>
  <name replace-wildcards=\"yes\">${SERVICE_NAME}</name>
  <service>
    <type>_smb._tcp</type>
    <port>${SMB_PORT}</port>${HOSTNAME_XML}
  </service>
</service-group>" > /etc/avahi/services/smbd.service

# cleanup PID files
for PIDFILE in nmbd samba-bgqd smbd
do
  if [ -f /run/samba/${PIDFILE}.pid ]
  then
    echo "INFO: ${PIDFILE} PID exists; removing..."
    rm -v /run/samba/${PIDFILE}.pid
  fi
done

# cleanup dbus PID file
if [ -f /run/dbus/dbus.pid ]
then
  echo "INFO: dbus PID exists; removing..."
  rm -v /run/dbus/dbus.pid
fi

# cleanup avahi PID file
if [ -f /run/avahi-daemon/pid ]
then
  echo "INFO: avahi PID exists; removing..."
  rm -v /run/avahi-daemon/pid
fi

# run CMD
echo "INFO: entrypoint complete; executing '${*}'"
exec "${@}"
