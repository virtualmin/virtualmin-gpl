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
	$suffix = $in{'web'} ? 'web' : '';
	&ui_print_header($din, $text{'user_create'.$suffix}, "");
	$user = &create_initial_user($d, undef, $in{'web'});
	}
else {
	@users = &list_domain_users($d);
	($user) = grep { ($_->{'user'} eq $in{'user'} ||
			  &remove_userdom($_->{'user'}, $d) eq $in{'user'}) &&
			 $_->{'unix'} == $in{'unix'} } @users;
	$mailbox = $d && $d->{'user'} eq $user->{'user'} && $user->{'unix'};
	$suffix = $user->{'webowner'} ? 'web' : '';
	&ui_print_header($din, $text{'user_edit'.$suffix}, "");
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
	# Domain owner
	print &ui_table_row($ulabel, "<tt>$user->{'user'}</tt>", 2, \@tds);
	$pop3 = $user->{'user'};
	}
else {
	# Regular user
	$pop3 = $d && !$user->{'noappend'} ?
		&remove_userdom($user->{'user'}, $d) : $user->{'user'};
	print &ui_table_row($ulabel,
		&ui_textbox("mailuser", $pop3, 13).
		($d ? "\@".&show_domain_name($d) : ""),
		2, \@tds);
	print &ui_hidden("oldpop3", $pop3),"\n";

	# Full username differs
	if ($pop3 ne $user->{'user'}) {
		print &ui_table_row(
			$d->{'mail'} ? &hlink($text{'user_imap'}, 'user_imap')
				     : &hlink($text{'user_imapf'},'user_imapf'),
			"<tt>$user->{'user'}</tt>");
		}

	# MySQL username differs
	if ($user->{'mysql_user'} &&
             $user->{'mysql_user'} ne $user->{'user'}) {
		print &ui_table_row(
			&hlink($text{'user_mysqluser2'}, 'user_mysqluser2'),
			"<tt>$user->{'mysql_user'}</tt>");
		}
	}

# Real name - only for true Unix users or LDAP persons
if ($user->{'person'}) {
	print &ui_table_row(&hlink($text{'user_real'}, "realname"),
		$mailbox ? $user->{'real'} :
			   &ui_textbox("real", $user->{'real'}, 40),
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
			(defined($user->{'plainpass'}) ?
			  &show_password_popup($d, $user) : ""),
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

$showmailquota = !$mailbox && $user->{'mailquota'};
$showquota = !$mailbox && $user->{'unix'} && !$user->{'noquota'};
$showhome = &can_mailbox_home($user) && $d && $d->{'home'} &&
	    !$mailbox && !$user->{'fixedhome'};

if ($showmailquota || $showquota || $showhome) {
	# Start quota and home table
	print &ui_hidden_table_start($text{'user_header2'}, "width=100%", 2,
				     "table2", 0);
	}

if ($showmailquota) {
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

if ($showquota) {
	# Show quotas field(s)
	if (&has_home_quotas()) {
		print &ui_table_row(
			&hlink($qsame ? $text{'user_umquota'}
				      : $text{'user_uquota'}, "diskquota"),
			&quota_field("quota", $user->{'quota'},
			     $user->{'uquota'}, "home", $user),
			2, \@tds);
		}
	if (&has_mail_quotas()) {
		print &ui_table_row(&hlink($text{'user_mquota'}, "diskmquota"),
				    &quota_field("mquota", $user->{'mquota'},
					 $user->{'umquota'}, "mail", $user),
				    2, \@tds);
		}
	}

if ($showhome) {
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

if ($showmailquota || $showquota || $showhome) {
	print &ui_hidden_table_end("table2");
	}

# Start third table, for email settings
$hasprimary = $d && !$user->{'noprimary'} && $d->{'mail'};
$hasmailfile = !$in{'new'} && ($user->{'email'} || @{$user->{'extraemail'}}) &&
	       !$user->{'nomailfile'};
$hasextra = !$user->{'noextra'};
$hassend = $in{'new'} && &will_send_user_email($d) || !$in{'new'};
$hasspam = $config{'spam'} && $hasprimary;
$hasemail = $hasprimary || $hasmailfile || $hasextra || $hassend || $hasspam;
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
if ($hasspam) {
	$awl_link = undef;
	if (!$in{'new'} && &foreign_available("spam")) {
		# Create AWL link
		&foreign_require("spam", "spam-lib.pl");
		if (defined(&spam::can_edit_awl) &&
		    &spam::supports_auto_whitelist() == 2 &&
		    &spam::get_auto_whitelist_file($user->{'user'}) &&
		    &spam::can_edit_awl($user->{'user'})) {
			$awl_link = "&nbsp;( <a href='../spam/edit_awl.cgi?".
				    "user=".&urlize($user->{'user'}).
				    "'>$text{'user_awl'}</a> )";
			}
		}
	print &ui_table_row(&hlink($text{'user_nospam'}, "nospam"),
		!$d->{'spam'} ? $text{'user_spamdis'} :
			&ui_radio("nospam", int($user->{'nospam'}),
				  [ [ 0, $text{'yes'} ], [ 1, $text{'no'} ] ]).
			$awl_link,
		2, \@tds);
	}

# Show most recent logins
if ($hasemail && !$in{'new'}) {
	$ll = &get_last_login_time($user->{'user'});
	@grid = ( );
	foreach $k (keys %$ll) {
		push(@grid, $text{'user_lastlogin_'.$k},
			    &make_date($ll->{$k}));
		}
	print &ui_table_row(&hlink($text{'user_lastlogin'}, "lastlogin"),
		@grid ? &ui_grid_table(\@grid, 2, 50)
		      : $text{'user_lastlogin_never'});
	}

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
		$simple = &get_simple_alias($d, $user);
		}
	if ($simple && ($simple->{'local'} || $simple->{'bounce'})) {
		# Local and bounce delivery are not allowed on the simple form
		$simple = undef;
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

# Show user-level mail filters, if he has any
@filters = ( );
$procmailrc = "$user->{'home'}/.procmailrc" if (!$in{'new'});
if (!$in{'new'} && $user->{'email'} && $user->{'unix'} && -r $procmailrc &&
    &foreign_check("filter")) {
	&foreign_require("filter", "filter-lib.pl");
	@filters = &filter::list_filters($procmailrc);
	}
if (@filters) {
	print &ui_hidden_table_start($text{'user_header5'}, "width=100%", 2,
				     "table5", 0);
	$lastalways = 0;
	@folders = &mailboxes::list_user_folders($user->{'user'});
	@table = ( );
	foreach $filter (@filters) {
		($cdesc, $lastalways) = &filter::describe_condition($filter);
		$adesc = &filter::describe_action($filter, \@folders,
						  $user->{'home'});
		push(@table, [ $cdesc, $adesc ]);
		}
	if (!$lastalways) {
		push(@table, [ $filter::text{'index_calways'},
			       $filter::text{'index_adefault'} ]);
		}
	$ftable = &ui_columns_table(
		[ $text{'user_fcondition'}, $text{'user_faction'} ],
		100,
		\@table);
	print &ui_table_row(undef, $ftable, 2);
	print &ui_hidden_table_end("table5");
	}

# Work out if the other permissions section has anything to display
if ($d && !$mailbox) {
	@dbs = grep { $_->{'users'} } &domain_databases($d);
	}
@sgroups = &allowed_secondary_groups($d);
foreach $f (&list_mail_plugins()) {
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
		&available_shells_menu("shell", $user->{'shell'}, "mailbox",
				       0, $user->{'webowner'}),
		2, \@tds);
	}

# Find and show all plugin features
foreach $f (&list_mail_plugins()) {
	$input = &plugin_call($f, "mailbox_inputs", $user, $in{'new'}, $d);
	print $input;
	}

# Show allowed databases
if (@dbs) {
	@userdbs = map { [ $_->{'type'}."_".$_->{'name'},
			   $_->{'name'}." ($_->{'desc'})" ] } @{$user->{'dbs'}};
	@alldbs = map { [ $_->{'type'}."_".$_->{'name'},
			  $_->{'name'}." ($_->{'desc'})" ] } @dbs;
	print &ui_table_row(&hlink($text{'user_dbs'},"userdbs"),
	  &ui_multi_select("dbs", \@userdbs, \@alldbs, 5, 1, 0,
			   $text{'user_dbsall'}, $text{'user_dbssel'}),
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

# Work out if switching to Usermin is allowed
$usermin = 0;
if (&can_switch_usermin($d, $user) &&
    $user->{'unix'} && &foreign_installed("usermin", 1)) {
	&foreign_require("usermin", "usermin-lib.pl");
	local %uminiserv;
	&usermin::get_usermin_miniserv_config(\%uminiserv);
	if (defined(&usermin::switch_to_usermin_user) &&
	    $uminiserv{'session'}) {
		$usermin = 1;
		}
	}

# Form create/delete buttons
if ($in{'new'}) {
	print &ui_form_end(
	   [ [ "create", $text{'create'} ] ]);
	}
else {
	print &ui_form_end(
	   [ [ "save", $text{'save'} ],
	     $usermin ? ( [ "switch", $text{'user_switch'}, undef, undef,
			    "onClick='form.target = \"_new\"'" ] ) : ( ),
	     &will_send_user_email($d) && $user->{'email'} ?
	     	( [ "remailbut", $text{'user_remailbut'} ] ) : ( ),
	     $mailbox ? ( ) : ( [ "delete", $text{'delete'} ] ) ]);
	}

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

# quota_field(name, value, used, filesystem, &user)
sub quota_field
{
my ($name, $value, $used, $fs, $u) = @_;
my $rv;
my $color = $u->{'over_quota'} ? "#ff0000" :
	    $u->{'warn_quota'} ? "#ff8800" :
	    $u->{'spam_quota'} ? "#aaaaaa" : undef;
if (&can_mailbox_quota()) {
	# Show inputs for editing quotas
	local $quota = $_[1];
	$quota = undef if ($quota eq "none");
	$rv .= &opt_quota_input($_[0], $quota, $_[3]);
	$rv .= "\n";
	}
else {
	# Just show current settings, or default
	local $q = $in{'new'} ? $defmquota[0] : $_[1];
	$rv .= ($q ? &quota_show($q, $_[3]) : $text{'form_unlimit'})."\n";
	}
if (!$in{'new'}) {
	my $umsg = $used ? &text('user_used', &quota_show($used, $fs))
		         : &text('user_noneused');
	if ($color) {
		$umsg = "<font color=$color>$umsg</font>";
		}
	$rv .= $umsg."\n";
	}
return $rv;
}

