#!/usr/local/bin/perl
# edit_user.cgi
# Display a form for editing or adding a user. This can be a local user,
# or a domain mailbox user

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
$din = $d ? &domain_in($d) : undef;
$tmpl = $d ? &get_template($d->{'template'}) : &get_template(0);
if ($in{'new'}) {
	&ui_print_header($din, $text{'user_create'}, "");
	$user = &create_initial_user($d, undef, $in{'web'});
	}
else {
	&ui_print_header($din, $text{'user_edit'}, "");
	@users = &list_domain_users($d);
	($user) = grep { $_->{'user'} eq $in{'user'} &&
			 $_->{'unix'} == $in{'unix'} } @users;
	$mailbox = $d && $d->{'user'} eq $user->{'user'} && $user->{'unix'};
	}

@tds = ( "width=30%", "width=70%" );
print &ui_form_start("save_user.cgi", "post");
print &ui_hidden("new", $in{'new'});
print &ui_hidden("dom", $in{'dom'});
print &ui_hidden("old", $in{'user'});
print &ui_hidden("unix", $in{'unix'});
print &ui_hidden("web", $in{'web'});

print &ui_hidden_table_start($mailbox ? $text{'user_mheader'} :
			     $user->{'webowner'} ? $text{'user_wheader'} :
			     $d ? $text{'user_header'} : $text{'user_lheader'},
		             "width=100%", 2, "table1", 1);

# Show username, editable if this is not the domain owner
$ulabel = $d->{'mail'} ? &hlink($text{'user_user'}, "username")
		       : &hlink($text{'user_user2'}, "username2");
if ($mailbox) {
	print &ui_table_row($ulabel, "<tt>$user->{'user'}</tt>", 2, \@tds);
	$pop3 = $user->{'user'};
	}
else {
	$pop3 = $d && !$user->{'noappend'} ?
		&remove_userdom($user->{'user'}, $d) : $user->{'user'};
	print &ui_table_row($ulabel,
		&ui_textbox("mailuser", $pop3, 13).
		($d ? "\@$d->{'dom'}" : "")."\n".
		($pop3 ne $user->{'user'} ?
			" ".&text($d->{'mail'} ? 'user_pop3' : 'user_pop3f',
				  "<tt>$user->{'user'}</tt>") :
			""),
		2, \@tds);
	print &ui_hidden("oldpop3", $pop3),"\n";
	}

# Real name - only for true Unix users or LDAP persons
if ($user->{'person'}) {
	print &ui_table_row(&hlink($text{'user_real'}, "realname"),
		$mailbox ? $user->{'real'} :
			   &ui_textbox("real", $user->{'real'}, 25),
		2, \@tds);
	}

# Password cannot be edited for domain owners (because it is the domain pass)
if (!$mailbox) {
	$pwfield = "";
	if ($in{'new'}) {
		$pwfield = &new_password_input("mailpass");
		}
	else {
		# For an existing user, offer to change password
		$pwfield = &ui_opt_textbox("mailpass", undef, 13,
			$text{'user_passdef'}."\n".
			(!&can_show_pass() ? "" :
			 $user->{'plainpass'} ? "($user->{'plainpass'})" :
			 defined($user->{'plainpass'}) ?
			   "(<i>$text{'user_none'}</i>)" : ""),
			$text{'user_passset'});
		if ($user->{'unix'} && $user->{'change'}) {
			local $tm = timelocal(gmtime($user->{'change'} *
						     60*60*24));
			$pwfield .= &text('user_lastch', &make_date($tm, 1));
			}
		}
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
	}

print &ui_hidden_table_end();

if (!$mailbox) {
	# Start quota and home table
	print &ui_hidden_table_start($text{'user_header2'}, "width=100%", 2,
				     "table2", 0);
	}

if (!$mailbox && $user->{'mailquota'}) {
	# Show Qmail/VPOPMail quota field
	$user->{'qquota'} = "" if ($user->{'qquota'} eq "none");
	print &ui_table_row(&hlink($text{'user_qquota'},"qmailquota"),
		&ui_radio("qquota_def", $user->{'qquota'} ? 0 : 1,
			       [ [ 1, $text{'form_unlimit'} ],
				 [ 0, " " ] ])." ".
		&ui_textbox("qquota", $user->{'qquota'} || "", 10)." ".
			$text{'form_bytes'},
		2, \@tds);
	}

if (!$mailbox && $user->{'unix'} && !$user->{'noquota'}) {
	# Show quotas field(s)
	if (&has_home_quotas()) {
		print &ui_table_row(
			&hlink($qsame ? $text{'user_umquota'}
				      : $text{'user_uquota'}, "diskquota"),
			&quota_field("quota", $user->{'quota'},
				     $user->{'uquota'}, "home"),
			2, \@tds);
		}
	if (&has_mail_quotas()) {
		print &ui_table_row(&hlink($text{'user_mquota'}, "diskmquota"),
				    &quota_field("mquota", $user->{'mquota'},
						 $user->{'umquota'}, "mail"),
				    2, \@tds);
		}
	}

if (&can_mailbox_home() && $d && $d->{'home'} &&
    !$mailbox && !$user->{'fixedhome'}) {
	# Show home directory editing field
	local $reshome = &resolve_links($user->{'home'});
	local $helppage = "userhome";
	if ($user->{'brokenhome'}) {
		# Home directory is in odd location, and so cannot be edited
		$homefield = "<tt>$user->{'home'}</tt>";
		print &ui_hidden("brokenhome", 1),"\n";
		}
	elsif ($user->{'webowner'}) {
		# Home can be public_html or a sub-dir
		local $phd = &public_html_dir($d);
		local $auto = $in{'new'} || $reshome eq &resolve_links($phd);
		$homefield = &ui_radio("home_def", $auto ? 1 : 0,
				       [ [ 1, $text{'user_home2'} ],
					 [ 0, $text{'user_homeunder2'} ] ])." ".
			     &ui_textbox("home", $auto ? "" :
				substr($user->{'home'}, length($phd)+1), 20);
		$helppage = "userhomeftp";
		}
	else {
		# Home is under server root, and so can be edited
		local $auto = $in{'new'} ||
		    $reshome eq
		    &resolve_links("$d->{'home'}/$config{'homes_dir'}/$pop3");
		$homefield = &ui_radio("home_def", $auto ? 1 : 0,
				[ [ 1, $text{'user_home1'} ],
				  [ 0, &text('user_homeunder') ] ])." ".
			     &ui_textbox("home", $auto ? "" :
			substr($user->{'home'}, length($d->{'home'})+1), 20);
		}
	print &ui_table_row(&hlink($text{'user_home'}, $helppage),
			    $homefield,
			    2, \@tds);
	}

if (!$mailbox) {
	print &ui_hidden_table_end("table2");
	}

# Start third table, for email settings
$hasprimary = $d && !$user->{'noprimary'} && $d->{'mail'};
$hasmailfile = !$in{'new'} && ($user->{'email'} || @{$user->{'extraemail'}}) &&
	       !$user->{'nomailfile'};
$hasextra = !$user->{'noextra'};
$hassend = $in{'new'} && &will_send_user_email($d) || !$in{'new'};
$hasemail = $hasprimary || $hasmailfile || $hasextra || $hassend ||
	    $config{'spam'};
if ($hasemail) {
	print &ui_hidden_table_start($text{'user_header2a'}, "width=100%", 2,
				     "table2a", 0);
	}

if ($hasprimary) {
	# Show primary email address field
	print &ui_table_row(&hlink($text{'user_mailbox'}, "mailbox"),
		    &ui_yesno_radio("mailbox",
				    $user->{'email'} || $in{'new'} ? 1 : 0),
		    2, \@tds);
	}

if ($hasmailfile) {
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
			    2, \@tds);
	}

if ($hasextra) {
	# Show extra email addresses
	print &ui_table_row(&hlink($text{'user_extra'}, "extraemail"),
			    &ui_textarea("extra",
				join("\n", @{$user->{'extraemail'}}), 5, 50),
			    2, \@tds);
	}

if ($in{'new'} && &will_send_user_email($d)) {
	# Show address for confirmation email (for the mailbox itself)
	print &ui_table_row(&hlink($text{'user_newmail'},"newmail"),
		&ui_opt_textbox("newmail", undef, 40,
				$user->{'email'} ? $text{'user_newmail1'}
						 : $text{'user_newmail2'},
				$text{'user_newmail0'}),
		2, \@tds);
	}
elsif (!$in{'new'}) {
	# Show option to re-send info email
	print &ui_table_row(&hlink($text{'user_remail'},"remail"),
		    &ui_radio("remail_def", 1,
			  [ [ 1, $text{'user_remail1'} ],
			    [ 0, $text{'user_remail0'} ] ])." ".
		    &ui_textbox("remail", $user->{'email'}, 40),
		    2, \@tds);
	}

# Show spam check flag
if ($config{'spam'}) {
	print &ui_table_row(&hlink($text{'user_nospam'}, "nospam"),
		!$d->{'spam'} ? $text{'user_spamdis'} :
			&ui_radio("nospam", int($user->{'nospam'}),
				  [ [ 0, $text{'yes'} ], [ 1, $text{'no'} ] ]));
	}

if ($hasemail) {
	print &ui_hidden_table_end("table2a");
	}

# Show forwarding setup for this user (can use the simple or complex forms)
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
		$simple = &get_simple_alias($d, $user);
		}
	if ($simple && ($simple->{'local'} || $simple->{'bounce'})) {
		# Local and bounce delivery are not allowed on the simple form
		$simple = undef;
		}
	if ($simple) {
		# Show simple / advanced tabs
		$prog = "edit_user.cgi?dom=$in{'dom'}&new=$in{'new'}&".
			"user=$in{'user'}&unix=$in{'unix'}&web=$in{'web'}";
		@tabs = ( [ "simple", $text{'alias_simplemode'},
			    "$prog&simplemode=simple" ],
			  [ "complex", $text{'alias_complexmode'},
			    "$prog&simplemode=complex" ] );
		print &ui_table_row(
			undef, &ui_tabs_start(\@tabs, "simplemode",
				$in{'simplemode'} || "simple"), 2);
		}
	else {
		print &ui_hidden("simplemode", "complex"),"\n";
		}

	if ($simple) {
		# Show simple form
		print &ui_tabs_start_tabletab("simplemode", "simple");
		&show_simple_form($simple, 1, 1, 1, \@tds, "user");
		print &ui_tabs_end_tabletab();
		}

	# Show complex form
	if ($simple) {
		print &ui_tabs_start_tabletab("simplemode", "complex");
		}
	&alias_form($user->{'to'},
		    &hlink($text{'user_aliases'}, "userdest"),
		    $d, "user", $in{'user'}, \@tds);
	if ($simple) {
		print &ui_tabs_end_tabletab();
		print &ui_tabs_end(0);
		}

	print &ui_hidden_table_end("table3");
	}

# Show user-level mail filters, if he has any
@filters = ( );
$procmailrc = "$user->{'home'}/.procmailrc" if (!$in{'new'});
if (!$in{'new'} && $user->{'email'} && $user->{'unix'} && -r $procmailrc &&
    &foreign_check("filter") && &get_webmin_version() >= 1.333) {
	&foreign_require("filter", "filter-lib.pl");
	@filters = &filter::list_filters($procmailrc);
	}
if (@filters) {
	print &ui_hidden_table_start($text{'user_header5'}, "width=100%", 2,
				     "table5", 0);
	$ftable = &ui_columns_start([ $text{'user_fcondition'},
				      $text{'user_faction'} ], 100);
	$lastalways = 0;
	@folders = &mailboxes::list_user_folders($user->{'user'});
	foreach $filter (@filters) {
		($cdesc, $lastalways) = &filter::describe_condition($filter);
		$adesc = &filter::describe_action($filter, \@folders,
						  $user->{'home'});
		$ftable .= &ui_columns_row([ $cdesc, $adesc ]);
		}
	if (!$lastalways) {
		$ftable .= &ui_columns_row([
			$filter::text{'index_calways'},
			$filter::text{'index_adefault'} ]);
		}
	$ftable .= &ui_columns_end();
	print &ui_table_row(undef, $ftable, 2);
	print &ui_hidden_table_end("table5");
	}

# Work out if the other permissions section has anything to display
if ($d && !$mailbox) {
	@dbs = grep { $_->{'users'} } &domain_databases($d);
	}
@sgroups = &allowed_secondary_groups($d);
foreach $f (@mail_plugins) {
	$anyplugins++ if (&plugin_defined($f, "mailbox_inputs"));
	}
$anyother = &can_mailbox_ftp() && !$mailbox && $user->{'unix'} ||
	    $anyplugins ||
	    @dbs ||
	    @sgroups && $user->{'unix'};

if ($anyother) {
	print &ui_hidden_table_start($text{'user_header4'}, "width=100%", 2,
				     "table4", 0, \@tds);
	}

if (&can_mailbox_ftp() && !$mailbox && $user->{'unix'}) {
	# Show FTP shell field
	print &ui_table_row(&hlink($text{'user_ushell'}, "ushell"),
		&available_shells_menu("shell", $user->{'shell'}, "mailbox"),
		2, \@tds);
	}

# Find and show all plugin features
foreach $f (@mail_plugins) {
	$input = &plugin_call($f, "mailbox_inputs", $user, $in{'new'}, $d);
	print $input;
	}

# Show allowed databases
if (@dbs) {
	@userdbs = map { $_->{'type'}."_".$_->{'name'} } @{$user->{'dbs'}};
	print &ui_table_row(&hlink($text{'user_dbs'},"userdbs"),
	  &ui_select("dbs", \@userdbs,
	    [ map { [ $_->{'type'}."_".$_->{'name'},
		      $_->{'name'}." ($_->{'desc'})" ] }
		  @dbs ], 5, 1).
	    ($user->{'mysql_user'} &&
	     $user->{'mysql_user'} ne $user->{'user'} ?
		"<br>".&text('user_mysqluser',
			     "<tt>$user->{'mysql_user'}</tt>") : ""),
	  2, \@tds);
	}

# Show secondary groups
if (@sgroups && $user->{'unix'}) {
	print &ui_table_row(&hlink($text{'user_groups'},"usergroups"),
			    &ui_select("groups", $user->{'secs'},
				[ map { [ $_ ] } @sgroups ], 5, 1, 1),
			    2, \@tds);
	}

if ($anyother) {
	print &ui_hidden_table_end("table4");
	}

if ($in{'new'}) {
	print &ui_form_end([ [ "create", $text{'create'} ] ]);
	}
else {
	print &ui_form_end([ [ "save", $text{'save'} ],
		     $mailbox ? ( ) : ( [ "delete", $text{'delete'} ] ) ]);
	}

if ($d) {
	if ($single_domain_mode) {
		&ui_print_footer("list_users.cgi?dom=$in{'dom'}", $text{'users_return'},
			"", $text{'index_return2'});
		}
	else {
		&ui_print_footer("list_users.cgi?dom=$in{'dom'}", $text{'users_return'},
			&domain_footer_link($d),
			"", $text{'index_return'});
		}
	}
else {
	&ui_print_footer("", $text{'index_return'});
	}

# quota_field(name, value, used, filesystem)
sub quota_field
{
local $rv;
if (&can_mailbox_quota()) {
	# Show inputs for editing quotas
	local $quota = $_[1];
	$quota = undef if ($quota eq "none");
	$rv .= &opt_quota_input($_[0], $quota, $_[3]);
	$rv .= "\n";
	if (!$in{'new'}) {
		$rv .= &text('user_used', &quota_show($_[2], $_[3])),"\n";
		}
	}
else {
	# Just show current settings, or default
	local $q = $in{'new'} ? $defmquota[0] : $_[1];
	$rv .= ($q ? &quota_show($q, $_[3]) : $text{'form_unlimit'})."\n";
	$rv .= &text('user_used', &quota_show($_[2], $_[3])) if (!$in{'new'});
	}
return $rv;
}

