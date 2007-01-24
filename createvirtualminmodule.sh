#!/bin/sh
# Create a .wbm file for the current version of this module, save it in the
# the virtualmin directory, and update the updates.txt file.

if [ "$1" = "--noupdate" ]; then
	noupdate=1
	shift
fi
if [ "$2" != "" ]; then
	echo "usage: createvirtualminmodule.sh [--noupdate] [version]"
	exit 1
fi

# Work out the version
cd /usr/local/webadmin
if [ "$1" != "" ]; then
	version=$1
else
	version=`grep version= virtual-server/module.info | sed -e 's/version=//'`
fi

# Create .wbm.gz and .rpm files
./create-module.pl virtualmin/virtual-server-$version.wbm.gz virtual-server/$version
./makemodulerpm.pl --target-dir virtualmin/rpm virtual-server $version

if [ "$noupdate" = "" ]; then
	# Add to updates.txt for .wbm
	grep virtual-server-$version.wbm.gz virtualmin/updates.txt >/dev/null
	if [ "$?" != 0 ]; then
		echo "virtual-server	$version	virtual-server-$version.wbm.gz	0	Latest version of Virtualmin Pro" >/tmp/updates.txt.$$
		cat virtualmin/updates.txt >>/tmp/updates.txt.$$
		mv /tmp/updates.txt.$$ virtualmin/updates.txt
	fi

	# Add to updates.txt for .rpm
	grep wbm-virtual-server-$version-1.noarch.rpm virtualmin/rpm/updates.txt >/dev/null
	if [ "$?" != 0 ]; then
		echo "virtual-server	$version	wbm-virtual-server-$version-1.noarch.rpm	0	Latest version of Virtualmin Pro" >/tmp/updates.txt.$$
		cat virtualmin/rpm/updates.txt >>/tmp/updates.txt.$$
		mv /tmp/updates.txt.$$ virtualmin/rpm/updates.txt
	fi
fi

