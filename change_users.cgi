#!/usr/local/bin/perl
# Just redirect to either delete_users.cgi or mass_form.cgi

require './virtual-server-lib.pl';
&ReadParse();
&licence_status();

if ($in{'mass'}) {
	&redirect("mass_form.cgi?$in");
	}
else {
	&redirect("delete_users.cgi?$in");
	}


