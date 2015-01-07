#!/usr/local/bin/perl
# delete_domain.cgi
# Delete a domain, after asking first

require './virtual-server-lib.pl';
&require_bind() if ($config{'dns'});
&require_useradmin();
&require_mail() if ($config{'mail'});
&ReadParse();
$d = &get_domain($in{'dom'});
$d || &error($text{'edit_egone'});
$d->{'dom'} || &error("Domain $in{'dom'} is not valid!");
&can_delete_domain($d) || &error($text{'delete_ecannot'});

if ($in{'confirm'}) {
	$main::force_bottom_scroll = 1;
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
	if ($d->{'unix'}) {
		$sz = &disk_usage_kb($d->{'home'});
		print &text('delete_rusure2',
			    "<tt>".&show_domain_name($d)."</tt>",
			    &nice_size($sz*1024)),"<p>\n";
		}
	else {
		print &text('delete_rusure3',
			    "<tt>".&show_domain_name($d)."</tt>"),"<p>\n";
		}

	print "<ul>\n";
	foreach $f (@features) {
		if ($d->{$f} && ($config{$f} || $f eq 'unix')) {
			my $msg = $d->{'parent'} ? $text{"sublosing_$f"}
						 : undef;
			$msg ||= $text{"losing_$f"};
			print "<li>",$text{'feature_'.$f}," - ",$msg,"<br>\n";
			}
		}
	foreach $f (&list_feature_plugins()) {
		if ($d->{$f}) {
			print "<li>",&plugin_call($f, "feature_name")," - ",
			     &plugin_call($f, "feature_losing"),"<br>\n";
			}
		}
	if (@users && @aliases) {
		print "<li>",&text('delete_mailboxes',
				   scalar(@users), scalar(@aliases)),"<br>\n";
		}
	elsif (@users) {
		print "<li>",&text('delete_mailboxes2',
				   scalar(@users)),"<br>\n";
		}
	elsif (@aliases) {
		print "<li>",&text('delete_mailboxes3',
				   scalar(@aliases)),"<br>\n";
		}
	print "</ul>\n";

	if (@subs) {
		print "<p><font size=+1>",&text('delete_subs',
			join(", ", map { "<tt>".&show_domain_name($_)."</tt>" }
				       @subs)),
			"</font><p>\n";
		}
	if (@aliasdoms) {
		print "<p><font size=+1>",&text('delete_aliasdoms',
			join(", ", map { "<tt>".&show_domain_name($_)."</tt>" }
				       @aliasdoms)),
			"</font><p>\n";
		}

	# Show the OK button
	print "<center>\n";
	print &ui_form_start("delete_domain.cgi");
	print &ui_hidden("dom", $in{'dom'});
	print &ui_form_end([ [ "confirm", $text{'delete_ok'} ] ]);
	print "</center>\n";

	&ui_print_footer(&domain_footer_link($d),
		"", $text{'index_return'});
	}
else {
	# Go ahead and delete this domain and all sub-domains ..
	$in{'only'} = 0 if (!&can_import_servers());
	$err = &delete_virtual_server($d, $in{'only'});
	&error($err) if ($err);

	# Call any theme post command
	if (defined(&theme_post_save_domain)) {
		&theme_post_save_domain(\%dom, 'delete');
		}

	&run_post_actions();
	&webmin_log("delete", "domain", $d->{'dom'}, $d);
	&ui_print_footer("", $text{'index_return'});
	}

