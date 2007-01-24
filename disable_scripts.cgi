#!/usr/local/bin/perl
# Change the enabled status of multiple scripts

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newscripts_ecannot'});
&ReadParse();
%d = map { $_, 1 } split(/\0/, $in{'d'});

# Get the script objects, and update available and min version flags
foreach $s (&list_scripts()) {
	$script = &get_script($s);
	$script->{'avail'} = $d{$script->{'name'}};
	$script->{'minversion'} = $in{$script->{'name'}."_minversion"};
	push(@scripts, $script);
	}

# Save it
&save_scripts_available(\@scripts);
&webmin_log("enable", "scripts");
&redirect("edit_newscripts.cgi");

