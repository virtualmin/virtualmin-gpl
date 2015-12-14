#!/usr/local/bin/perl
# Save secondary MX servers

require './virtual-server-lib.pl';
&can_edit_templates() || &error($text{'newmxs_ecannot'});
&ReadParse();
&error_setup($text{'newmxs_err'});

&ui_print_header(undef, $text{'newmxs_title'}, "");

# Get old MX servers and all servers
&foreign_require("servers";
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
		elsif ($minfo{'version'} < 2.98) {
			# Old Virtualmin version
			&$second_print(&text('newmxs_eversion',
					     $server->{'host'},
				     	     $minfo{'version'}, 2.98));
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
			else {
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
				}
			$newmxids{$server->{'id'}} = $server;
			}
		&$second_print($text{'setup_done'});
		}
	}
&save_mx_servers(\@mxs);

# Update all existing email domains on new MX servers
foreach my $d (&list_domains()) {
	next if (!$d->{'mail'});
	local $oldd = { %$d };
	&$first_print(&text('newmxs_dom', $d->{'dom'}));
	&$indent_print();

	local @ids = split(/\s+/, $d->{'mx_servers'});
	local @added;
	if ($in{'addexisting'}) {
		# Add to new secondaries
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
			}
		}
	$d->{'mx_servers'} = join(" ", @ids);

	if ($d->{'dns'}) {
		# Add or remove DNS MX records
		&modify_dns($d, $oldd);
		}

	# Re-sync virtusers for domain to secondaries, if any were added
	if (@added) {
		&$first_print($text{'newmxs_syncing'});
		@rv = &sync_secondary_virtusers($d, \@added);
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
	&$outdent_print();
	&$second_print($text{'setup_done'});
	}

&run_post_actions();
&webmin_log("mxs");
failed:			# Goto here if one server fails
&ui_print_footer("", $text{'index_return'});

