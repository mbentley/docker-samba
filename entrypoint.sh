#!/bin/sh

# set default values
SET_PERMISSIONS="${SET_PERMISSIONS:-false}"
SHARE_NAME="${SHARE_NAME:-samba}"
NTLM_AUTH="${NTLM_AUTH:-no}"
CUSTOM_SMB_CONF="${CUSTOM_SMB_CONF:-false}"
SMB_PROTO="${SMB_PROTO:-SMB2}"
SMB_PORT="${SMB_PORT:-445}"
USERNAME="${USERNAME:-samba}"
PASSWORD="${PASSWORD:-samba}"
GROUPNAME="${GROUPNAME:-samba}"
WORKGROUP="${WORKGROUP:-WORKGROUP}"
HIDE_SHARES="${HIDE_SHARES:-no}"
SMB_INHERIT_PERMISSIONS="${SMB_INHERIT_PERMISSIONS:-no}"
SHARE_PATH="${SHARE_PATH:-/opt/${USERNAME}}"
IGNORE_DOS_ATTRIBUTES="${IGNORE_DOS_ATTRIBUTES:-false}"
PUID="${PUID:-1000}"
PGID="${PGID:-${PUID}}"
PUBLIC_ACCESS="${PUBLIC_ACCESS:-false}"
READ_ONLY="${READ_ONLY:-yes}"


# common functions
set_password() {
  # check to see what the password should be set to
  if [ "${PASSWORD}" = "samba" ]
  then
      echo "INFO: Using default password: samba"
  else
      echo "INFO: Setting password from environment variable"
  fi

  # set the password
  printf "INFO: "
  echo "${USERNAME}":"${PASSWORD}" | chpasswd
}

samba_user_setup() {
  # set up user in Samba
  printf "INFO: Samba - Created "
  smbpasswd -L -a -n "${USERNAME}"
  printf "INFO: Samba - "
  smbpasswd -L -e -n "${USERNAME}"
  printf "INFO: Samba - setting password\n"
  printf "%s\n%s\n" "${PASSWORD}" "${PASSWORD}" | smbpasswd -L -s "${USERNAME}"
}

create_user_directory() {
  # create user directory if needed
  if [ ! -d "${SHARE_PATH}" ]
  then
    mkdir "${SHARE_PATH}"
  fi
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

create_smb_user() {
  # validate that none of the required environment variables are empty
  if [ -z "${USERNAME}" ] || [ -z "${GROUPNAME}" ] || [ -z "${PASSWORD}" ] || [ -z "${SHARE_NAME}" ] || [ -z "${PUID}" ] || [ -z "${PGID}" ]
  then
    echo "ERROR: Missing one or more of the following variables; unable to create user"
    echo "  USERNAME=${USERNAME}"
    echo "  GROUPNAME=${GROUPNAME}"
    echo "  PASSWORD=$(if [ -n "${PASSWORD}" ]; then printf "<value reddacted but present>";fi)"
    echo "  SHARE_NAME=${SHARE_NAME}"
    echo "  PUID=${PUID}"
    echo "  PGID=${PGID}"
    exit 1
  fi

  # create custom user, group, and directories
  # check to see if group exists; if not, create it
  if grep -q -E "^${GROUPNAME}:" /etc/group > /dev/null 2>&1
  then
    echo "INFO: Group ${GROUPNAME} exists; skipping creation"
  else
    # make sure the group doesn't already exist with a different name
    if awk -F ':' '{print $3}' /etc/group | grep -q "^${PGID}$"
    then
      EXISTING_GROUP="$(grep ":${PGID}:" /etc/group | awk -F ':' '{print $1}')"
      echo "INFO: Group already exists with a different name; renaming '${EXISTING_GROUP}' to '${GROUPNAME}'..."
      sed -i "s/^${EXISTING_GROUP}:/${GROUPNAME}:/g" /etc/group
    else
      echo "INFO: Group ${GROUPNAME} doesn't exist; creating..."
      # create the group
      addgroup -g "${PGID}" "${GROUPNAME}"
    fi
  fi

  # check to see if user exists; if not, create it
  if id -u "${USERNAME}" > /dev/null 2>&1
  then
    echo "INFO: User ${USERNAME} exists; skipping creation"
  else
    echo "INFO: User ${USERNAME} doesn't exist; creating..."
    # create the user
    adduser -u "${PUID}" -G "${GROUPNAME}" -h "${SHARE_PATH}" -s /bin/false -D "${USERNAME}"

    # set the user's password if necessary
    set_password
  fi

  # create user directory if necessary
  create_user_directory

  # write smb.conf if CUSTOM_SMB_CONF is not true
  if [ "${CUSTOM_SMB_CONF}" != "true" ]
  then
    echo "INFO: CUSTOM_SMB_CONF=false; generating [${SHARE_NAME}] section of /etc/samba/smb.conf..."
    echo "
[${SHARE_NAME}]
   path = ${SHARE_PATH}
   inherit permissions = ${SMB_INHERIT_PERMISSIONS}
   read only = ${READ_ONLY}
   #valid users = ${USERNAME}" >> /etc/samba/smb.conf
   if [ "${PUBLIC_ACCESS}" = "true" ]
   then
     # public access
     echo "   force user = ${USERNAME}
   guest ok = yes
   browsable = yes" >> /etc/samba/smb.conf
   fi
  else
    # CUSTOM_SMB_CONF was specified; make sure the file exists
    if [ -f "/etc/samba/smb.conf" ]
    then
      echo "INFO: CUSTOM_SMB_CONF=true; skipping generating smb.conf and using provided /etc/samba/smb.conf"
    else
      # there is no /etc/samba/smb.conf; exit
      echo "ERROR: CUSTOM_SMB_CONF=true but you did not bind mount a config to /etc/samba/smb.conf; exiting."
      exit 1
    fi
  fi

  # set up user in Samba
  samba_user_setup

  # set user permissions
  set_permissions
}

set_permissions() {
  # set ownership and permissions, if requested
  if [ "${SET_PERMISSIONS}" = "true" ]
  then
    # set the ownership of the directory time machine will use
    printf "INFO: "
    chown -v "${USERNAME}":"${GROUPNAME}" "${SHARE_PATH}"

    # change the permissions of the directory time machine will use
    printf "INFO: "
    chmod -v 770 "${SHARE_PATH}"
  else
    echo "INFO: SET_PERMISSIONS=false; not setting ownership and permissions for ${SHARE_PATH}"
  fi
}


# write global smb.conf if CUSTOM_SMB_CONF is not true
if [ "${CUSTOM_SMB_CONF}" != "true" ]
then
  echo "INFO: CUSTOM_SMB_CONF=false; generating [global] section of /etc/samba/smb.conf..."
  echo "[global]
 log level = 3 passdb:5 auth:5
 access based share enum = ${HIDE_SHARES}
 hide unreadable = ${HIDE_SHARES}
 inherit permissions = ${SMB_INHERIT_PERMISSIONS}
 load printers = no
 log file = /var/log/samba/log.%m
 logging = file
 max log size = 1000
 security = user
 server min protocol = ${SMB_PROTO}
 ntlm auth = ${NTLM_AUTH}
 server role = standalone server
 smb ports = ${SMB_PORT}
 workgroup = ${WORKGROUP}" > /etc/samba/smb.conf
fi
if [ "${IGNORE_DOS_ATTRIBUTES}" = "true" ]
then
  echo "   store dos attributes = no
 map hidden = no
 map system = no
 map archive = no
 map readonly = no" >> /etc/samba/smb.conf
fi

# create user & user share
create_smb_user

# mkdir if needed
createdir /var/lib/samba/private 700
createdir /var/log/samba/cores 700

# write avahi config file (smbd.service) to customize services advertised
echo "INFO: Avahi - generating base configuration in /etc/avahi/services/smbd.service..."
SERVICE_NAME="%h"
HOSTNAME_XML=""
if [ -n "${ADVERTISED_HOSTNAME}" ]
then
  echo "INFO: Avahi - using ${ADVERTISED_HOSTNAME} as hostname."
  SERVICE_NAME="${ADVERTISED_HOSTNAME}"
  HOSTNAME_XML="<host-name>${ADVERTISED_HOSTNAME}.local</host-name>"
fi
echo "<?xml version=\"1.0\" standalone='no'?><!--*-nxml-*-->
<!DOCTYPE service-group SYSTEM \"avahi-service.dtd\">

<service-group>
<name replace-wildcards=\"yes\">${SERVICE_NAME}</name>
<service>
  <type>_smb._tcp</type>
  <port>${SMB_PORT}</port>
  ${HOSTNAME_XML}
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

# output filesystem types detected
for DIR in /opt/*
do
  DETECTED_FS="$(df -TP "${DIR}" | grep -v ^Filesystem | awk '{print $2}')"

  # output based on detected fs
  case ${DETECTED_FS} in
    overlay)
      echo "WARN: Detected filesystem for ${DIR} is ${DETECTED_FS}! This likely means that your shared data is being stored inside the container, not in a volume or bind mount!"
      ;;
    *)
      echo "INFO: Detected filesystem for ${DIR} is ${DETECTED_FS}"
      ;;
  esac
done

# run CMD
echo "INFO: entrypoint complete; executing '${*}'"
exec "${@}"