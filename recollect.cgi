#!/usr/local/bin/perl
# Update collected info

require './virtual-server-lib.pl';

# Refresh Webmin info
if (&foreign_check("system-status")) {
	&foreign_require("system-status");
	&system_status::scheduled_collect_system_info();
	}

# Refresh Virtualmin-specific info
$info = &collect_system_info();
if ($info) {
	&save_collected_info($info);
	}

&redirect($ENV{'HTTP_REFERER'});

