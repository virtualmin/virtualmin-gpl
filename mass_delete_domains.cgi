#!/usr/local/bin/perl
# Delete a bunch of virtual servers, after asking first

require './virtual-server-lib.pl';
&ReadParse();
&error_setup($text{'massdelete_err'});

# Validate inputs
@d = split(/\0/, $in{'d'});
@d || &error($text{'massdelete_enone'});
foreach $did (@d) {
	$d = &get_domain($did);
	$d && $d->{'uid'} && ($d->{'gid'} || $d->{'ugid'}) ||
		&error("Domain $did does not exist!");
	&can_delete_domain($d) || &error($text{'delete_ecannot'});
	push(@doms, $d);
	}

if ($in{'confirm'}) {
	&ui_print_unbuffered_header(undef, $text{'massdelete_title'}, "");
	}
else {
	&ui_print_header(undef, $text{'massdelete_title'}, "");
	}

foreach $d (@doms) {
	$idmap{$d->{'id'}} = $d;
	}
if (!$in{'confirm'}) {
	# Ask the user if he is sure
	print &check_clicks_function();

	# Work out size of all domains
	$size = 0;
	$users = 0;
	$aliases = 0;
	$subs = 0;
	$dbs = $dbssize = 0;
	foreach $d (@doms) {
		if ($d->{'dir'} &&
		    (!$d->{'parent'} || !$idmap{$d->{'parent'}})) {
			# Don't count sub-domains when doing parent
			$size += &disk_usage_kb($d->{'home'})*1024;
			}
		@users = &list_domain_users($d, 1);
		@aliases = &list_domain_aliases($d);
		@subs = &get_domain_by("parent", $d->{'id'});
		@dbs = &domain_databases($d);
		$users += scalar(@users);
		$aliases += scalar(@aliases);
		$subs += scalar(@subs);
		$dbs += scalar(@dbs);
		$dbssize += &get_database_usage($d);
		push(@alldel, $d, @subs);
		}
	@alldel = &unique(@alldel);

	print &text('massdelete_rusure', scalar(@alldel),
					 &nice_size($size)),"<br>\n";
	if ($subs) {
		print &text('massdelete_subs', $subs),"<br>\n";
		}
	if ($users) {
		print &text('massdelete_users', $users),"<br>\n";
		}
	if ($dbs) {
		print &text('massdelete_dbs',
			    $dbs, &nice_size($dbssize)),"<br>\n";
		}
	print "<p>\n";
	@dnames = sort @dnames;
	print &text('massdelete_doms', &nice_domains_list(\@alldel)),"<br>\n";

	print "<center>\n";
	print &ui_form_start("mass_delete_domains.cgi", "post");
	foreach $d (@doms) {
		print &ui_hidden("d", $d->{'id'}),"\n";
		}
	print &ui_submit($text{'massdelete_ok'}, "confirm");
	print &ui_form_end();
	print "</center>\n";

	&ui_print_footer("", $text{'index_return'});
	}
else {
	# Strip out all sub-domains of domains to be deleted
	@doms = grep { !$_->{'parent'} || !$idmap{$_->{'parent'}} } @doms;
	@das = ( );

	foreach $d (@doms) {
		# Go ahead and delete this domain and all sub-domains ..
		&$first_print(&text('massdelete_doing', &show_domain_name($d)));
		&$indent_print();
		$err = &delete_virtual_server($d, 0, 1);
		&error($err) if ($err);
		&$outdent_print();
		&$second_print($text{'setup_done'});

		# Call any theme post command
		if (defined(&theme_post_save_domain) &&
		    !defined(&theme_post_save_domains)) {
			&theme_post_save_domain($d, 'delete');
			}
		else {
			push(@das, $d, 'delete');
			}
		}
	&run_post_actions();
	if (defined(&theme_post_save_domains)) {
		&theme_post_save_domains(@das);
		}

	&webmin_log("delete", "domains", scalar(@doms));
	&ui_print_footer("", $text{'index_return'});
	}

