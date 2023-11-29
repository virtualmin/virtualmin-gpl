#!/usr/local/bin/perl
# edit_user_mail.cgi
# Display a form for adding a mail user.

require './virtual-server-lib.pl';
&ReadParse();
if ($in{'dom'}) {
	$d = &get_domain($in{'dom'});
	&can_edit_domain($d) || &error($text{'users_ecannot'});
	}
else {
	&can_edit_local() || &error($text{'users_ecannot2'});
	}
&can_edit_users() || &error($text{'users_ecannot'});
$d->{'mail'} || &error($text{'users_ecannot3'});

$din = $d ? &domain_in($d) : undef;
$tmpl = $d ? &get_template($d->{'template'}) : &get_template(0);
&ui_print_header($din, $text{'user_createmail'}, "");
$user = &create_initial_user($d);

@tds = ( "width=30%", "width=70%" );
print &ui_form_start("save_user.cgi", "post");
print &ui_hidden("new", 1);
print &ui_hidden("dom", $in{'dom'});
print &ui_hidden("home_def", 1);
print &ui_hidden("shell", '/dev/null');

# Print quota hidden defaults as
# it has to be always considered
my $showmailquota = $user->{'mailquota'};
my $showquota = $user->{'unix'} && !$user->{'noquota'};
my $showhome = &can_mailbox_home($user) && $d && $d->{'home'} && !$user->{'fixedhome'};
if ($showmailquota) {
        my $qquota_default = $user->{'qquota'} ne "none" && $user->{'qquota'} ? 0 : 1;
        my $qquota = &ui_hidden("qquota_def", $qquota_default);
        $qquota .= &ui_hidden("qquota", $user->{'qquota'})
                if (!$qquota_default);
        print $qquota;
	}
if ($showquota) {
        if (&has_home_quotas()) {
                my $quota_data =
                        &quota_field("quota", $user->{'quota'},
                          $user->{'uquota'}, $user->{'ufquota'}, "home", $user);
                print &vui_hidden($quota_data);
                }
        if (&has_mail_quotas()) {
                my $mquota_data =
                        &quota_field("mquota", $user->{'mquota'},
                          $user->{'umquota'},$user->{'umfquota'}, "mail", $user);
                print &vui_hidden($mquota_data);
                }
	}

# Show accordions
print &ui_hidden_table_start($d ? $text{'user_header_mail'} : $text{'user_lheader'},
		             "width=100%", 2, "table1", 1);

# Edit mail username
print &ui_table_row(&hlink($text{'user_user'}, "username"),
        &ui_textbox("mailuser", undef, 13, 0, undef,
                &vui_ui_input_noauto_attrs()).
        ($d ? "\@".&show_domain_name($d) : ""),
        2, \@tds);

# Password field
$pwfield = &new_password_input("mailpass");
if (!$user->{'alwaysplain'}) {
        # Option to disable
        $pwfield .= "<br>" if ($pwfield !~ /\/table>/);
        $pwfield .=
                &ui_checkbox("disable", 1, $text{'user_disabled'},
                                $user->{'pass'} =~ /^\!/ ? 1 : 0);
        }
print &ui_table_row(&hlink($text{'user_pass'}, "password"),
                        $pwfield,
                        2, \@tds);

# Real name - only for true Unix users or LDAP persons
if ($user->{'person'}) {
	print &ui_table_row(&hlink($text{'user_real'}, "realname"),
			&ui_textbox("real", $user->{'real'}, 40, 0, undef,
				&vui_ui_input_noauto_attrs()), 2, \@tds);
	}

# Password recovery field
print &ui_table_row(&hlink($text{'user_recovery'}, "recovery"),
        &ui_opt_textbox("recovery", $user->{'recovery'}, 40,
                        $text{'user_norecovery'},
                        $text{'user_gotrecovery'}));

print &ui_hidden_table_end();

# Start third table, for email settings
$hasprimary = $d && !$user->{'noprimary'} && $d->{'mail'};
$hasmailfile = 0;
$hasextra = !$user->{'noextra'};
$hassend = &will_send_user_email($d, 1);
$hasspam = $config{'spam'} && $hasprimary;
$hasemail = $hasprimary || $hasmailfile || $hasextra || $hassend || $hasspam;
if ($hasemail) {
	my $style_display_none = $d->{'mail'} ? "" : " style='display:none' ";
	print &ui_hidden_table_start($text{'user_header2a'}, "${style_display_none}width=100%", 2,
				     "table2a", 0);
	}

if ($hasprimary) {
	# Show primary email address field
	print &ui_table_row(&hlink($text{'user_mailbox'}, "mailbox"),
		    &ui_yesno_radio("mailbox", 1),
		    2, \@tds, $d->{'mail'} ? undef : ['style="display: none"']);
	}

if ($hasmailfile && $config{'show_mailuser'}) {
	# Show the user's mail file
	local ($sz, $umf, $lastmod) = &mail_file_size($user);
	local $link = &read_mail_link($user, $d);
	if ($link) {
		$mffield = "<a href='$link'><tt>$umf</tt></a>\n";
		}
	else {
		$mffield = "<tt>$umf</tt>\n";
		}
	if ($lastmod) {
		$mffield .= "(".&text('user_lastmod', &make_date($lastmod)).")";
		}
	if ($user->{'spam_quota'}) {
		$mffield .= "<br><font color=#ff0000>".
		      &text($user->{'spam_quota_diff'} ? 'user_spamquota'
						       : 'user_soamquota2',
			    &nice_size($user->{'spam_quota_diff'})).
		      "</font>\n";
		}
	print &ui_table_row(&hlink($text{'user_mail'}, "mailfile"),
			    $mffield,
			    2, \@tds, $d->{'mail'} ? undef : ['style="display: none"']);
	}

if ($hasextra) {
	# Show extra email addresses
	@extra = @{$user->{'extraemail'}};
	foreach $e (@extra) {
		if ($e =~ /^(\S*)\@(\S+)$/) {
			local ($eu, $ed) = ($1, $2);
			$ed = &show_domain_name($ed);
			$e = $eu."\@".$ed;
			}
		}
	print &ui_table_row(&hlink($text{'user_extra'}, "extraemail"),
			    &ui_textarea("extra", join("\n", @extra), 5, 50),
			    2, \@tds, $d->{'mail'} ? undef : ['style="display: none"']);
	}

if ($in{'new'} && &will_send_user_email($d, 1)) {
	# Show address for confirmation email (for the mailbox itself)
	print &ui_table_row(&hlink($text{'user_newmail'},"newmail"),
		&ui_opt_textbox("newmail", undef, 40,
				$user->{'email'} ? $text{'user_newmail1'}
						 : $text{'user_newmail2'},
				$text{'user_newmail0'}),
		2, \@tds, $d->{'mail'} ? undef : ['style="display: none"']);
	}

# Show spam check flag
if ($hasspam) {
	$awl_link = undef;
	print &ui_table_row(
		&hlink($d->{'virus'} ? $text{'user_nospam'}
				     : $text{'user_nospam2'}, "nospam"),
		!$d->{'spam'} ? $text{'user_spamdis'} :
			&ui_radio("nospam", int($user->{'nospam'}),
				  [ [ 0, $text{'yes'} ], [ 1, $text{'no'} ] ]).
			$awl_link,
		2, \@tds, $d->{'mail'} ? undef : ['style="display: none"']);
	}

# Show most recent logins
if ($hasemail) {
	print &ui_hidden_table_end("table2a");
	}

# Show forwarding setup for this user, using simple form if possible
if (($user->{'email'} || $user->{'noprimary'}) && !$user->{'noalias'}) {
	print &ui_hidden_table_start($text{'user_header3'}, "width=100%", 2,
				     "table3", 0);

	# Work out if simple mode is supported
	if (!@{$user->{'to'}}) {
		# If no forwarding, just check delivery to me as this is
		# the default.
		$simple = { 'tome' => 1 };
		}
	else {
		$simple = &get_simple_alias($d, $user, 1);
		}
	if ($simple && ($simple->{'local'} || $simple->{'bounce'})) {
		# Local and bounce delivery are not allowed on the simple form,
		# unless we can merge some (@) local users with forward users, 
		# which will be handled automatically on save to prevent showing
		# advanced form for no reason
		$simple = undef
			if (!$simple->{'local-all'} || $simple->{'bounce'});
		}

	if ($simple) {
		# Show simple form
		print &ui_hidden("simplemode", "simple");
		&show_simple_form($simple, 1, 1, 1, 1, \@tds, "user");
		}
	else {
		# Show complex form
		print &ui_hidden("simplemode", "complex");
		&alias_form($user->{'to'},
			    &hlink($text{'user_aliases'}, "userdest"),
			    $d, "user", $in{'user'}, \@tds);
		}

	print &ui_hidden_table_end("table3");
	}

# Form create/delete buttons
print &ui_form_end(
        [ [ "create", $text{'create'} ] ]);

# Link back to user list and/or main menu
if ($d) {
	if ($single_domain_mode) {
		&ui_print_footer(
			"list_users.cgi?dom=$in{'dom'}", $text{'users_return'},
			"", $text{'index_return2'});
		}
	else {
		&ui_print_footer(
			"list_users.cgi?dom=$in{'dom'}", $text{'users_return'},
			&domain_footer_link($d),
			"", $text{'index_return'});
		}
	}
else {
	&ui_print_footer("", $text{'index_return'});
	}

