#!/usr/local/bin/perl
# Update collected info

require './virtual-server-lib.pl';

# Refresh Webmin info, but only if scheduled collection is enabled in that
# module .. otherwise when Virtualmin's collect_system_info is called below
# it will trigger Webmin collection again!
if (&foreign_check("system-status")) {
	&foreign_require("system-status");
	if ($system_status::config{'collect_interval'} ne 'none') {
		&system_status::scheduled_collect_system_info();
		}
	}

# Refresh Virtualmin-specific info
$info = &collect_system_info();
if ($info) {
	&save_collected_info($info);
	}

&redirect($ENV{'HTTP_REFERER'});

