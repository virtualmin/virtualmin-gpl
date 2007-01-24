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
	$quota = $user->{'quota'};
	print &ui_table_row($text{'defaults_quota'},
		&ui_radio("quota_def", 
			$quota eq "" ? 0 : $quota eq "none" ? 1 : 2,
			[ [ 0, $text{'defaults_tmpl'} ],
			  [ 1, $text{'form_unlimit'} ],
			  [ 2, " " ] ])."\n".
		&quota_input("quota", $quota, "home"), 1);
	}
if (&has_mail_quotas()) {
	$mquota = $user->{'mquota'};
	print &ui_table_row($text{'defaults_mquota'},
		&ui_radio("mquota_def", 
			$mquota eq "" ? 0 : $mquota eq "none" ? 1 : 2,
			[ [ 0, $text{'defaults_tmpl'} ],
			  [ 1, $text{'form_unlimit'} ],
			  [ 2, " " ] ])."\n".
		&quota_input("mquota", $mquota, "home"), 1);
	}

# Mail server quota
if (&has_server_quotas()) {
	$qquota = $user->{'qquota'};
	print &ui_table_row($text{'defaults_qquota'},
		&ui_radio("qquota_def", 
			$qquota eq "" || $qquota eq "none" ? 1 : 2,
			[ [ 1, $text{'form_unlimit'} ],
			  [ 2, " " ] ])."\n".
		&ui_textbox("qquota", $qquota eq "none" ? "" : $qquota, 10), 1);
	}

# FTP login
if (&can_mailbox_ftp()) {
	$ftp = $user->{'shell'} eq $config{'ftp_shell'} ? 1 :
	       $user->{'shell'} eq $config{'jail_shell'} ? 3 : 2;
        print &ui_table_row($text{'user_ftp'},
                    &ui_radio('ftp', $ftp,
                              [ [ 1, $text{'yes'} ],
                                ( $config{'jail_shell'} ?
                                        ( [ 3, $text{'user_jail'} ] ) : ( ) ),
                                [ 2, $text{'no'} ] ]), 1);
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
	@userdbs = map { $_->{'type'}."_".$_->{'name'} } @{$user->{'dbs'}};
	print &ui_table_row($text{'user_dbs'},
	  &ui_select("dbs", \@userdbs,
            [ map { [ $_->{'type'}."_".$_->{'name'},
                      $_->{'name'}." (".$text{'databases_'.$_->{'type'}}.")" ] }
                  @dbs ], 5, 1), 1);
	}

# Secondary groups
@sgroups = &allowed_secondary_groups($d);
if (@sgroups) {
	print &ui_table_row($text{'user_groups'},
		&ui_select("groups", $user->{'secs'},
                        [ map { [ $_ ] } @sgroups ], 5, 1, 1), 1);
	}

# Plugin defaults
foreach $f (@mail_plugins) {
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
