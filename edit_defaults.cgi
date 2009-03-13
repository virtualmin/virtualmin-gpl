#!/usr/local/bin/perl
# Show a form for editing defaults for new users in this virtual server

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'users_ecannot'});
&can_edit_users() || &error($text{'users_ecannot'});
$user = &create_initial_user($d, 1);

&ui_print_header(&domain_in($d), $text{'defaults_title'}, "");

print &ui_form_start("save_defaults.cgi");
print &ui_hidden("dom", $in{'dom'}),"\n";
print &ui_table_start($text{'defaults_header'}, "width=100%", 2);

# Disk quotas
if (&has_home_quotas()) {
	print &ui_table_row($text{'defaults_quota'},
		&opt_quota_input("quota", $user->{'quota'}, "home",
				 $text{'defaults_tmpl'}));
	}
if (&has_mail_quotas()) {
	print &ui_table_row($text{'defaults_mquota'},
		&opt_quota_input("mquota", $user->{'mquota'}, "mail",
				 $text{'defaults_tmpl'}));
	}

# Mail server quota
if (&has_server_quotas()) {
	$qquota = $user->{'qquota'};
	local $dis1 = &js_disable_inputs([ "qquota" ], [ ]);
	local $dis2 = &js_disable_inputs([ ], [ "qquota" ]);
	print &ui_table_row($text{'defaults_qquota'},
		&ui_radio("qquota_def", 
			$qquota eq "" || $qquota eq "none" ? 1 : 0,
			[ [ 1, $text{'form_unlimit'}, "onClick='$dis1'" ],
			  [ 0, " ", "onClick='$dis2'" ] ])."\n".
		&ui_textbox("qquota", $qquota eq "none" ? "" : $qquota, 10,
			    $qquota eq "" || $qquota eq "none"), 1);
	}

# Default shell
if (&can_mailbox_ftp()) {
        print &ui_table_row($text{'user_ushell'},
	    &available_shells_menu("shell", $user->{'shell'}, "mailbox"));
        }

# Mail forwarding
print &ui_table_row($text{'user_aliases'},
	&ui_radio("aliases_def", $user->{'to'} ? 0 : 1,
		  [ [ 1, $text{'defaults_tmpl'} ],
		    [ 0, $text{'defaults_below'} ] ]), 1);
&alias_form($user->{'to'}, " ", $d, "user", "NEWUSER");

# Databases
@dbs = grep { $_->{'type'} eq 'mysql' } &domain_databases($d);
if (@dbs) {
	@userdbs = map { [ $_->{'type'}."_".$_->{'name'},
			   $_->{'name'}." ($_->{'desc'})" ] } @{$user->{'dbs'}};
	@alldbs = map { [ $_->{'type'}."_".$_->{'name'},
			  $_->{'name'}." ($_->{'desc'})" ] } @dbs;
	print &ui_table_row($text{'user_dbs'},
	  &ui_multi_select("dbs", \@userdbs, \@alldbs, 5, 1, 0,
			   $text{'user_dbsall'}, $text{'user_dbssel'}), 1);
	}

# Secondary groups
@sgroups = &allowed_secondary_groups($d);
if (@sgroups) {
	print &ui_table_row($text{'user_groups'},
		&ui_select("groups", $user->{'secs'},
                        [ map { [ $_ ] } @sgroups ], 5, 1, 1), 1);
	}

# Plugin defaults
foreach $f (&list_mail_plugins()) {
	$pi = &plugin_call($f, "mailbox_defaults_inputs", $user, $d);
	if ($pi) {
		print &ui_table_hr() if (!$donehr++);
		print $pi;
		}
	}

print &ui_table_end();
print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer("list_users.cgi?dom=$in{'dom'}", $text{'users_return'},
		 "", $text{'index_return2'});
