#!/usr/local/bin/perl
# Create, update or delete an extra administrator

require './virtual-server-lib.pl';
&ReadParse();
$d = &get_domain($in{'dom'});
&can_edit_domain($d) || &error($text{'edit_ecannot'});
&can_edit_admins($d) || &error($text{'admins_ecannot'});

&obtain_lock_webmin() if (!$in{'switch'});
@admins = &list_extra_admins($d);
&require_acl();

if (!$in{'new'}) {
	($admin) = grep { $_->{'name'} eq $in{'old'} } @admins;
	$admin || &error($text{'admin_egone'});
	$oldadmin = { %$admin };
	}
else {
	$admin = { };
	}

if ($in{'switch'}) {
	# Special case - switch to this Webmin user
	&ui_print_header(&domain_in($d), $text{'admin_title2'}, "");
	print &text('admin_switching', "<tt>$in{'old'}</tt>"),"<p>\n";
	print "<script>\n";
	print "var w = window;\n";
	print "while(w.parent && w.parent != w) { w = w.parent; }\n";
	print "w.location = \"switch_user.cgi?dom=$in{'dom'}&admin=$in{'old'}\";\n";
	print "</script>\n";
	&ui_print_footer();
	exit;
	}
elsif ($in{'delete'}) {
	# Just delete him
	&delete_extra_admin($admin, $d);
	}
else {
	# Validate inputs
	&error_setup($text{'admin_err'});
	$tmpl = &get_template($d->{'template'});
	$in{'name'} =~ /^[a-z0-9\.\_\-]+$/ || &error($text{'admin_ename'});
	$in{'name'} eq 'webmin' && &error($text{'resel_ewebmin'});
	if ($tmpl->{'extra_prefix'} ne "none") {
		# Force-prepend prefix
		$pfx = &substitute_domain_template($tmpl->{'extra_prefix'}, $d);
		if ($in{'new'} || $admin->{'name'} =~ /^\Q$pfx\E(.*)/) {
			$admin->{'name'} = $pfx.$in{'name'};
			}
		elsif (&master_admin()) {
			$admin->{'name'} = $in{'name'};
			}
		}
	else {
		$admin->{'name'} = $in{'name'};
		}
	if ($in{'new'} || $in{'name'} ne $in{'old'}) {
		($clash) = grep { $_->{'name'} eq $in{'name'} }
				&acl::list_users();
		$clash && &error($text{'admin_eclash'});
		}
	if (!$in{'pass_def'}) {
		$admin->{'pass'} = $in{'pass'};
		}
	$admin->{'desc'} = $in{'desc'};
	if ($in{'email_def'}) {
		delete($admin->{'email'});
		}
	else {
		$in{'email'} =~ /^\S+\@\S+$/ ||
			&error($text{'admin_eemail'});
		$admin->{'email'} = $in{'email'};
		}

	# Save edit options
	$admin->{'create'} = $in{'create'};
	$admin->{'norename'} = $in{'norename'};
	$admin->{'features'} = $in{'features'};
	$admin->{'modules'} = $in{'modules'};
	%sel_edits = map { $_, 1 } split(/\0/, $in{'edit'});
	foreach $ed (@edit_limits) {
		if ($d->{'edit_'.$ed}) {
			$admin->{"edit_".$ed} = $sel_edits{$ed};
			}
		}

	# Save allowed domains
	if ($in{'doms_def'}) {
		delete($admin->{'doms'});
		}
	else {
		$in{'doms'} || &error($text{'admin_edoms'});
		$admin->{'doms'} = join(" ", split(/\0/, $in{'doms'}));
		}

	# Save or create the admin
	if ($in{'new'}) {
		&create_extra_admin($admin, $d);
		}
	else {
		&modify_extra_admin($admin, $oldadmin, $d);
		}
	}
&release_lock_webmin();

&run_post_actions_silently();
&webmin_log($in{'new'} ? "create" : $in{'delete'} ? "delete" : "modify",
	    "admin", $oldadmin ? $oldadmin->{'name'} : $admin->{'name'});
&redirect("list_admins.cgi?dom=$d->{'id'}");

