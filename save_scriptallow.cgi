#!/usr/local/bin/perl
# Update the master admin's allowed scripts flags

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newscripts_ecannot'});
&ReadParse();

&save_script_master_permissions($in{'allowmaster'}, $in{'allowvers'},
				$in{'denydefault'});
&run_post_actions_silently();
&webmin_log("allow", "scripts");
&redirect("edit_newscripts.cgi?mode=enable");

