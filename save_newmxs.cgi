#!/usr/local/bin/perl
# Save secondary MX servers

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newmxs_ecannot'});
&ReadParse();
&licence_status();
&error_setup($text{'newmxs_err'});

&ui_print_header(undef, $text{'newmxs_title'}, "");

# Get old MX servers and all servers
&foreign_require("servers");
@oldmxs = &list_mx_servers();
%oldmxids = map { $_->{'id'}, $_ } @oldmxs;
@servers = grep { $_->{'user'} } &servers::list_servers();

foreach $id (split(/\0/, $in{'servers'})) {
	($server) = grep { $_->{'id'} eq $id } @servers;
	if ($server) {
		# Make sure the system actually has Virtualmin 2.98+
		&$first_print(&text('newmxs_doing', $server->{'host'}));
		&remote_foreign_require($server, "webmin", "webmin-lib.pl");
		%minfo = &remote_foreign_call($server, "webmin",
				"get_module_info", "virtual-server");
		if (!$minfo{'version'}) {
			# Virtualmin not installed
			&$second_print(&text('newmxs_evirtualmin',
					     $server->{'host'}));
			goto failed;
			}
		else {
			# Ask the remote server if it is OK
			&remote_foreign_require($server, "virtual-server",
						"virtual-server-lib.pl");
			$mxerr = &remote_foreign_call($server, "virtual-server",
						      "check_secondary_mx");
			if ($mxerr) {
				&$second_print(&text('newmxs_eprob',
					$server->{'host'}, $mxerr));
				goto failed;
				}

			# Make sure we're not somehow adding this system!
			$rhost = &remote_foreign_call($server, "virtual-server",
						      "get_system_hostname");
			$myhost = &get_system_hostname();
			if ($rhost eq $myhost) {
				&$second_print(&text('newmxs_esame',
					$server->{'host'}, $myhost));
				goto failed;
				}

			# Save the MX name to use for this server
			if ($in{"mxname_".$server->{'id'}."_def"}) {
				delete($server->{'mxname'});
				}
			else {
				$in{"mxname_".$server->{'id'}} =~
				    /^[a-z0-9\.\-\_]+$/ ||
					&text('newmxs_emxname',
					      $server->{'host'});
				$server->{'mxname'} =
					$in{"mxname_".$server->{'id'}};
				}
			push(@mxs, $server);
			$newmxids{$server->{'id'}} = $server;
			}
		&$second_print($text{'setup_done'});
		}
	}
&save_mx_servers(\@mxs);

# Update all existing email domains on new MX servers
my $anychanged = 0;
foreach my $d (&list_domains()) {
	next if (!$d->{'mail'});
	my $oldd = { %$d };
	my $changed = 0;

	my @ids = split(/\s+/, $d->{'mx_servers'});
	my (@added, @deleted);
	if ($in{'addexisting'}) {
		# Add to new secondaries
		if (!$changed++) {
			&$first_print(&text('newmxs_dom', $d->{'dom'}));
			&$indent_print();
			}
		foreach $server (@mxs) {
			if (!$oldmxids{$server->{'id'}}) {
				&$first_print(&text('newmxs_adding',
						    $server->{'host'}));
				$err = &setup_one_secondary($d, $server);
				if (!$err) {
					push(@ids, $server->{'id'});
					&$second_print($text{'setup_done'});
					}
				else {
					&$second_print(&text('newmxs_failed',
							     $err));
					}
				push(@added, $server);
				}
			}
		}

	# Remove from old secondaries
	foreach $server (@oldmxs) {
		if (!$newmxids{$server->{'id'}} &&
		    &indexof($server->{'id'}, @ids) >= 0) {
			if (!$changed++) {
				&$first_print(&text('newmxs_dom', $d->{'dom'}));
				&$indent_print();
				}
			&$first_print(&text('newmxs_removing',
					    $server->{'host'}));
			$err = &delete_one_secondary($d, $server);
			if (!$err) {
				&$second_print($text{'setup_done'});
				}
			else {
				&$second_print(&text('newmxs_failed', $err));
				}
			@ids = grep { $_ != $server->{'id'} } @ids;
			push(@deleted, $server);
			}
		}
	if ($changed) {
		$d->{'mx_servers'} = join(" ", @ids);

		if ($d->{'dns'}) {
			# Add or remove DNS MX records
			&modify_dns($d, $oldd);
			}
		}

	# Re-sync virtusers for domain to secondaries, if any were added or
	# removed
	if (@added || @deleted) {
		&$first_print($text{'newmxs_syncing'});
		@rv = ( );
		push(@rv, &sync_secondary_virtusers($d, \@added, 0))
			if (@added);
		push(@rv, &sync_secondary_virtusers($d, \@deleted, 1))
			if (@deleted);
		@errs = grep { $_->[1] } @rv;
		if (@errs) {
			&$second_print(&text('newmxs_esynced',
				join(", ", map { $_->[0]->{'host'}." - ".
						 ($_->[1] || "OK") } @rv)));
			}
		else {
			&$second_print(&text('newmxs_synced',
				join(", ", map { $_->[0]->{'host'} } @rv)));
			}
		}

	&save_domain($d);
	if ($changed) {
		&$outdent_print();
		&$second_print($text{'setup_done'});
		$anychanged++;
		}
	}
if (!$anychanged) {
	&$first_print($text{'newmxs_nothing'});
	}

&run_post_actions();
&webmin_log("mxs");
failed:			# Goto here if one server fails
&ui_print_footer("edit_newmxs.cgi", $text{'newmxs_return'},
                 "", $text{'index_return'});

