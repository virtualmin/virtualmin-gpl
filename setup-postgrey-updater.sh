#!/usr/bin/env bash
# We are going to setup a newer whitelist for postgrey, the version included in the distribution is old
cat > /etc/cron.daily/virtualmin-postgrey-whitelist << EOF;
#!/usr/bin/env bash

# Virtualmin

# check we have a postgrey_whitelist_clients file and that it is not older than 28 days
if [ ! -f /etc/postgrey/whitelist_clients ] || find /etc/postgrey/whitelist_clients -mtime +28 > /dev/null ; then
    # ok we need to update the file, so lets try to fetch it
    if curl https://postgrey.schweikert.ch/pub/postgrey_whitelist_clients --output /tmp/postgrey_whitelist_clients -sS --fail > /dev/null 2>&1 ; then
        # if fetching hasn't failed yet then check it is a plain text file
        # curl manual states that --fail sometimes still produces output
        # this final check will at least check the output is not html
        # before moving it into place
        if [ "\$(file -b --mime-type /tmp/postgrey_whitelist_clients)" == "text/plain" ]; then
            mv /tmp/postgrey_whitelist_clients /etc/postgrey/whitelist_clients
            service postgrey restart
	else
            rm /tmp/postgrey_whitelist_clients
        fi
    fi
fi
EOF
chmod +x /etc/cron.daily/virtualmin-postgrey-whitelist
/etc/cron.daily/virtualmin-postgrey-whitelist
