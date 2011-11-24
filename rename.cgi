#!/usr/local/bin/perl
# rename.cgi
# Actually rename a server

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'rename_err'});
$d = &get_domain($in{'dom'});
$d || &error($text{'edit_egone'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_rename_domains() || &error($text{'rename_ecannot'});

# Validate inputs
$in{'new'} = lc(&parse_domain_name($in{'new'}));
$err = &valid_domain_name($in{'new'});
&error($err) if ($err);
$newdom = $in{'new'} ne $d->{'dom'} ? 1 : 0;
if (!$d->{'parent'} && &can_rename_domains() == 2 &&
    ($in{'user_mode'} == 2 || $newdom)) {
	if ($in{'user_mode'} == 1) {
		# Make up a new username
		($user, $try1, $try2) = &unixuser_name($in{'new'});
		$user || &error(&text('setup_eauto', $try1, $try2));
		}
	elsif ($in{'user_mode'} == 2) {
		# Use the entered username
		$in{'user'} || &error($text{'rename_euser'});
		$user = $in{'user'};
		&valid_mailbox_name($user) && &error($text{'setup_euser2'});
		}
	}
$parentdom = $d->{'parent'} ? &get_domain($d->{'parent'}) : undef;

# Work out new group name and prefix
if ($in{'prefix_mode'}) {
	$group = $user || $d->{'user'};
	}
if ($in{'prefix_mode'} == 0) {
	# Don't change
	$prefix = undef;
	}
elsif ($in{'prefix_mode'} == 1) {
	# Automatically compute
	$prefix = &compute_prefix($in{'new'}, $group, $parentdom);
	}
elsif ($in{'prefix_mode'} == 2) {
	# Entered value
	$in{'prefix'} =~ /^[a-z0-9\.\-]+$/i || &error($text{'setup_eprefix'});
	$pclash = &get_domain_by("prefix", $in{'prefix'});
	$pclash && &error(&text('setup_eprefix3',
				$in{'prefix'}, $pclash->{'dom'}));
	$prefix = $in{'prefix'};
	}

# Make sure new domain is valid
local $derr = &allowed_domain_name($parentdom, $in{'new'});
&error($derr) if ($derr);

# Make sure no domain with the same name already exists
if ($newdom) {
	@doms = &list_domains();
	($clash) = grep { $_->{'dom'} eq $in{'new'} } @doms;
	$clash && &error($text{'rename_eclash'});
	}

# Update the domain object, where appropriate
%oldd = %$d;
if ($newdom) {
	$d->{'email'} =~ s/\@$d->{'dom'}$/\@$in{'new'}/gi;
	$d->{'emailto'} =~ s/\@$d->{'dom'}$/\@$in{'new'}/gi;
	$d->{'dom'} = $in{'new'};
	}
if ($user) {
	$d->{'email'} =~ s/^\Q$d->{'user'}\E\@/$user\@/g;
	$d->{'emailto'} =~ s/^\Q$d->{'user'}\E\@/$user\@/g;
	$d->{'user'} = $user;
	}
if ($in{'home_mode'} == 1) {
	# Automatic home
	&can_rehome_domains() || &error($text{'rename_ehome'});
	&change_home_directory($d, &server_home_directory($d, $parentdom));
	}
elsif ($in{'home_mode'} == 2) {
	# User-selected home
	&can_rehome_domains() == 2 || &error($text{'rename_ehome'});
	$in{'home'} || &error($text{'rename_ehome2'});
	-e $in{'home'} && &error($text{'rename_ehome3'});
	$in{'home'} =~ /^(.*)\// && -d $1 || &error($text{'rename_ehome4'});
	&change_home_directory($d, $in{'home'});
	}
if ($oldd{'home'} ne $d->{'home'}) {
	$newhome = $d->{'home'};
	}
if ($group) {
	$d->{'group'} = $group;
	$d->{'prefix'} = $prefix;
	}

# Find any sub-domain objects and update them
if (!$d->{'parent'}) {
	@subs = &get_domain_by("parent", $d->{'id'});
	foreach $sd (@subs) {
		local %oldsd = %$sd;
		push(@oldsubs, \%oldsd);
		if ($user) {
			$sd->{'email'} =~ s/^\Q$sd->{'user'}\E\@/$user\@/g;
			$sd->{'emailto'} =~ s/^\Q$sd->{'user'}\E\@/$user\@/g;
			$sd->{'user'} = $user;
			}
		if ($newdom) {
			$sd->{'email'} =~ s/\@$d->{'dom'}$/\@$in{'new'}/gi;
			$sd->{'emailto'} =~ s/\@$d->{'dom'}$/\@$in{'new'}/gi;
			}
		if ($in{'home_mode'}) {
			&change_home_directory($sd,
					       &server_home_directory($sd, $d));
			}
		if ($group) {
			$sd->{'group'} = $group;
			}
		}
	}

# Find any domains aliases to this one, excluding child domains
@aliases = &get_domain_by("alias", $d->{'id'});
@aliases = grep { $_->{'parent'} != $d->{'id'} } @aliases;
foreach $ad (@aliases) {
	local %oldad = %$ad;
	push(@oldaliases, \%oldad);
	}

# Check for domain name clash, where the domain, user or group have changed
foreach my $f (@features) {
	local $cfunc = "check_${f}_clash";
	if (defined(&$cfunc) && $dom{$f}) {
		if ($newdom && &$cfunc($d, 'dom')) {
			&error(&text('setup_e'.$f, $in{'dom'}, $dom{'db'},
				     $user, $d->{'group'} || $group));
			}
		if ($user && &$cfunc($d, 'user')) {
			&error(&text('setup_e'.$f, $in{'dom'}, $dom{'db'},
				     $user, $d->{'group'} || $group));
			}
		if ($group && &$cfunc($d, 'group')) {
			&error(&text('setup_e'.$f, $in{'dom'}, $dom{'db'},
				     $user, $group));
			}
		}
	}

&ui_print_unbuffered_header(&domain_in(\%oldd), $text{'rename_title'}, "");

# Run the before command
&set_domain_envs(\%oldd, "MODIFY_DOMAIN", $d);
$merr = &making_changes();
&reset_domain_envs(\%oldd);
&error(&text('rename_emaking', "<tt>$merr</tt>")) if (defined($merr));

if ($newdom) {
	print "<b>",&text('rename_doingdom',
			  "<tt>$in{'new'}</tt>"),"</b><br>\n";
	}
if ($user) {
	print "<b>",&text('rename_doinguser', "<tt>$user</tt>"),"</b><br>\n";
	}
if ($newhome) {
	print "<b>",&text('rename_doinghome', "<tt>$newhome</tt>"),"</b><br>\n";
	}
print "<p>\n";

# Build the list of domains being changed
@doms = ( $d );
@olddoms = ( \%oldd );
push(@doms, @subs, @aliases);
push(@olddoms, @oldsubs, @oldaliases);

# Setup print function to include domain name
sub first_html_withdom
{
print &text('rename_dd', $doing_dom->{'dom'})," : ",@_,"<br>\n";
}
if (@doms > 1) {
	$first_print = \&first_html_withdom;
	}

# Update all features in all domains. Include the mail feature always, as this
# covers FTP users
foreach my $f (&unique(@features, 'mail')) {
	local $mfunc = "modify_$f";
	my $i;
	for($i=0; $i<@doms; $i++) {
		local $p = &domain_has_website($doms[$i]);
		if ($f eq "web" && $p && $p ne "web") {
			# Web feature is provided by a plugin .. call it now
			$doing_dom = $doms[$i];
			&try_plugin_call($f, "feature_modify",
					 $doms[$i], $olddoms[$i]);
			}
		elsif ($doms[$i]->{$f} && $config{$f} ||
	               $f eq "unix" || $f eq "mail") {
			$doing_dom = $doms[$i];
			local $main::error_must_die = 1;
			eval {
				if ($doms[$i]->{'alias'}) {
					# Is an alias domain, so pass in old
					# and new target domain objects
					local $aliasdom = &get_domain(
						$doms[$i]->{'alias'});
					local $idx = &indexof($aliasdom, @doms);
					if ($idx >= 0) {
						&try_function($f, $mfunc,
						   $doms[$i], $olddoms[$i],
						   $doms[$idx], $olddoms[$idx]);
						}
					else {
						&try_function($f, $mfunc,
						   $doms[$i], $olddoms[$i],
						   $aliasdom, $aliasdom);
						}
					}
				else {
					# Not an alias domain
					&try_function($f, $mfunc,
						      $doms[$i], $olddoms[$i]);
					}
				};
			if ($@) {
				&$second_print(&text('setup_failure',
					$text{'feature_'.$f}, "$@"));
				}
			}
		}
	}

# Update plugins in all domains
foreach $f (&list_feature_plugins()) {
	for($i=0; $i<@doms; $i++) {
		local $p = &domain_has_website($doms[$i]);
		if ($doms[$i]->{$f} && $f ne $p) {
			$doing_dom = $doms[$i];
			&try_plugin_call($f, "feature_modify",
					 $doms[$i], $olddoms[$i]);
			}
		}
	}

# Fix script installer paths in all domains
if (defined(&list_domain_scripts)) {
	&$first_print($text{'rename_scripts'});
	for($i=0; $i<@doms; $i++) {
		($olddir, $newdir) =
		    ($olddoms[$i]->{'home'}, $doms[$i]->{'home'});
		($olddname, $newdname) =
		    ($olddoms[$i]->{'dom'}, $doms[$i]->{'dom'});
		foreach $sinfo (&list_domain_scripts($doms[$i])) {
			$changed = 0;
			if ($olddir ne $newdir) {
				# Fix directory
				$changed++ if ($sinfo->{'opts'}->{'dir'} =~
				       	       s/^\Q$olddir\E\//$newdir\//);
				}
			if ($olddname ne $newdname) {
				# Fix domain in URL
				$changed++ if ($sinfo->{'url'} =~
					       s/\Q$olddname\E/$newdname/);
				}
			if (!$info{'opts'}->{'dir'} ||
			    -d $info{'opts'}->{'dir'}) {
				# list_domain_scripts will set deleted flag
				# due to home directory move, so fix it now that
				# script dir has been corrected
				$sinfo->{'deleted'} = 0;
				}
			&save_domain_script($doms[$i], $sinfo) if ($changed);
			}
		}
	&$second_print($text{'setup_done'});
	}

&refresh_webmin_user($d);
&run_post_actions();

# Save all new domain details
print $text{'save_domain'},"<br>\n";
for($i=0; $i<@doms; $i++) {
	&save_domain($doms[$i]);
	}
print $text{'setup_done'},"<p>\n";

# Run the after command
&set_domain_envs($d, "MODIFY_DOMAIN", undef, \%oldd);
local $merr = &made_changes();
&$second_print(&text('rename_emade', "<tt>$merr</tt>")) if (defined($merr));
&reset_domain_envs($d);

# Clear all left-frame links caches, as links to Apache may no longer be valid
&clear_links_cache();

&webmin_log("rename", "domain", $oldd{'dom'}, $d);

# Call any theme post command
if (defined(&theme_post_save_domain)) {
	&theme_post_save_domain($d, 'modify');
	}

&ui_print_footer(&domain_footer_link($d),
	"", $text{'index_return'});
