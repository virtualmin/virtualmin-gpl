#!/usr/local/bin/perl
# delete_domain.cgi
# Delete a domain, after asking first

require './virtual-server-lib.pl';
&require_bind() if ($config{'dns'});
&require_useradmin();
&require_mail() if ($config{'mail'});
&ReadParse();
$d = &get_domain($in{'dom'});
$d && $d->{'uid'} && ($d->{'gid'} || $d->{'ugid'}) ||
	&error("Domain $in{'dom'} does not exist!");
&can_delete_domain($d) || &error($text{'edit_ecannot'});

if ($in{'confirm'}) {
	&ui_print_unbuffered_header(&domain_in($d), $text{'delete_title'}, "");
	}
else {
	&ui_print_header(&domain_in($d), $text{'delete_title'}, "");
	}

@users = &list_domain_users($d, 1);
@aliases = &list_domain_aliases($d, 1);
@subs = &get_domain_by("parent", $d->{'id'});
@aliasdoms = &get_domain_by("alias", $d->{'id'});
@aliasdoms = grep { $_->{'parent'} != $d->{'id'} } @aliasdoms;
if (!$in{'confirm'}) {
	# Ask the user if he is sure
	print &check_clicks_function();
	if ($d->{'unix'}) {
		$sz = &disk_usage_kb($d->{'home'});
		print "<p>",&text('delete_rusure2', "<tt>$d->{'dom'}</tt>",
				  &nice_size($sz*1024)),"<p>\n";
		}
	else {
		print "<p>",&text('delete_rusure3', "<tt>$d->{'dom'}</tt>"),"<p>\n";
		}

	$pfx = $d->{'parent'} ? "sublosing_" : "losing_";
	print "<ul>\n";
	foreach $f (@features) {
		if ($d->{$f} && ($config{$f} || $f eq 'unix')) {
			print "<li>",$text{'feature_'.$f}," - ",
				     $text{$pfx.$f},"<br>\n";
			}
		}
	foreach $f (@feature_plugins) {
		if ($d->{$f}) {
			print "<li>",&plugin_call($f, "feature_name")," - ",
			     &plugin_call($f, "feature_losing"),"<br>\n";
			}
		}
	if (@users || @aliases) {
		print "<li>",&text('delete_mailboxes', scalar(@users), scalar(@aliases)),"<br>\n";
		}
	print "</ul>\n";

	if (@subs) {
		print "<p><font size=+1>",&text('delete_subs',
			join(", ", map { "<tt>$_->{'dom'}</tt>" } @subs)),
			"</font><p>\n";
		}
	if (@aliasdoms) {
		print "<p><font size=+1>",&text('delete_aliasdoms',
			join(", ", map { "<tt>$_->{'dom'}</tt>" } @aliasdoms)),
			"</font><p>\n";
		}

	print "<center><form action=delete_domain.cgi>\n";
	print "<input type=hidden name=dom value='$in{'dom'}'>\n";
	print "<input type=submit name=confirm ",
	      "value='$text{'delete_ok'}' onClick='check_clicks(form)'>\n";
	if (&can_import_servers()) {
		print "<p><input type=checkbox name=only value=1> ",
		      "$text{'delete_only'}<br>\n";
		}
	print "</form></center>\n";

	&ui_print_footer(&domain_footer_link($d),
		"", $text{'index_return'});
	}
else {
	# Go ahead and delete this domain and all sub-domains ..
	$in{'only'} = 0 if (!&can_import_servers());
	$err = &delete_virtual_server($d, $in{'only'});
	&error($err) if ($err);

	# Call any theme post command
	if (defined(&theme_post_save_domain, 'delete')) {
		&theme_post_save_domain(\%dom);
		}

	&webmin_log("delete", "domain", $d->{'dom'}, $d);
	&ui_print_footer("", $text{'index_return'});
	}

