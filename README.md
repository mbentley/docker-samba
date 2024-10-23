# mbentley/samba

docker image based on alpine:latest to run a generic Samba container where you bring your own samba config.

## Tags

* `latest` - multi-arch for `amd64` and `arm64`

## Usage

Example usage - see further below for additional information about the `ACCOUNT_*`, and `GROUP_*` environment variables.

```
docker run -d \
  --name samba \
  --hostname samba \
  -p 445:445 \
  -p 137:137/udp \
  -p 138:138/udp \
  -p 5353:5353/udp \
  -e DEBUG_LEVEL="1" \
  -e ACCOUNT_user1="1000:mysecret" \
  -e ACCOUNT_user2="1001:mysecret" \
  -e ACCOUNT_user3="1002:mysecret" \
  -e GROUP_home="2000:user1 user2 user3" \
  -v /path/to/my/smb.conf":/etc/samba/smb.conf \
  -v /path/to/my/data:/data \
  --tmpfs /run/samba \
  mbentley/samba
```

## Required Volumes

### Samba Config

This image requires you to bring your own samba config which needs to be mounted into the container. The following command will output the default, sample configuration to start a samba config:

```bash
docker run -it --rm --entrypoint cat mbentley/samba /etc/samba/smb.sample.conf
```

The configuration needs to be bind mounted to `/etc/samba/smb.conf` inside the container as that is where samba will look for it.

The [`smb.conf` man page](https://www.samba.org/samba/docs/current/man-html/smb.conf.5.html) is a great resource for details on the settings and their options.

### Shares

You need to bind mount any shares into the container at the appropriate path. For example, if you have data on your host at `/path/to/my/data`, you could bind mount it to `/data`, assuming that your `smb.conf` refers to `/data` as the path. The `smb.conf` should reference all paths as they exist inside the container, not on the host!

## User Accounts

Replace `<username>`, `<uid>`, and `<password>` with the username, user id #, and password you wish the user to have, repeating as necessary for all users.

```
-e ACCOUNT_<username>="<uid>:<password>"
```

Example to create the user `user1` with the user id `1000` and the samba password `mysecret`:

```
-e ACCOUNT_user1="1000:mysecret"
```

## Groups

Replace `<group_name>`, `<group_id>`, and `<space_separated_user_list>` with the group name, group id, and a space separated list of users to add to the group.

```
-e GROUP_<group_name>="<group_id>:<space_separated_user_list>"
```

Example to create the group `mygroup` with GID of `2000` and add the users `user1`, `user2`, and `user3` to the group:

```
-e GROUP_mygroup="2000:user1 user2 user3"
```

## Secret file

If you do not want to set env vars at the container level, you can bind mount them into the container and have the entrypoint load them. Set the env var `SECRET_FILE` to the path where it is bind mounted in the container. The file format is:

```bash
export ACCOUNT_user1="1000:mysecret"
export ACCOUNT_user2="1001:mysecret"
export ACCOUNT_user3="1002:mysecret"
export GROUP_mygroup="2000:user1 user2 user3"
```
