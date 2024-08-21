# rebased/repackaged base image that only updates existing packages
FROM mbentley/alpine:latest
LABEL maintainer="Matt Bentley <mbentley@mbentley.net>"

# install samba and s6
RUN apk add --no-cache s6 samba-common-tools samba-server &&\
  touch /etc/samba/lmhosts &&\
  rm /etc/samba/smb.conf

# copy in necessary supporting config files
COPY s6 /etc/s6
COPY entrypoint.sh /

ENTRYPOINT ["/entrypoint.sh"]
CMD ["s6-svscan","/etc/s6"]
