sub require_bind
{
return if ($require_bind++);
&foreign_require("bind8", "bind8-lib.pl");
%bconfig = &foreign_config("bind8");
}

# check_depends_dns(&domain)
# For a sub-domain that is being added to a parent DNS domain, make sure the
# parent zone actually exists
sub check_depends_dns
{
if ($_[0]->{'subdom'}) {
	local $tmpl = &get_template($_[0]->{'template'});
	local $parent = &get_domain($_[0]->{'subdom'});
	if ($tmpl->{'dns_sub'} && !$parent->{'dns'}) {
		return $text{'setup_edepdnssub'};
		}
	}
return undef;
}

# setup_dns(&domain)
# Set up a zone for a domain
sub setup_dns
{
&require_bind();
local $tmpl = &get_template($_[0]->{'template'});
if (!$_[0]->{'subdom'} || $tmpl->{'dns_sub'} ne 'yes') {
	# Creating a new real zone
	&$first_print($text{'setup_bind'});
	local $conf = &bind8::get_config();
	local $base = $bconfig{'master_dir'} ? $bconfig{'master_dir'} :
					       &bind8::base_directory($conf);
	local $file = &bind8::automatic_filename($_[0]->{'dom'}, 0, $base);
	local $dir = {
		 'name' => 'zone',
		 'values' => [ $_[0]->{'dom'} ],
		 'type' => 1,
		 'members' => [ { 'name' => 'type',
				  'values' => [ 'master' ] },
				{ 'name' => 'file',
				  'values' => [ $file ] } ]
		};
	if ($tmpl->{'namedconf'} &&
	    $tmpl->{'namedconf'} ne 'none') {
		push(@{$dir->{'members'}},
		     &text_to_named_conf($tmpl->{'namedconf'}));
		}
	local @slaves = &bind8::list_slave_servers();
	if (@slaves) {
		# Also notify slave servers, unless already added
		local ($also) = grep { $_->{'name'} eq 'also-notify' }
				     @{$dir->{'members'}};
		if (!$also) {
			$also = { 'name' => 'also-notify',
				  'type' => 1,
				  'members' => [ ] };
			foreach my $s (@slaves) {
				push(@{$also->{'members'}},
				     { 'name' => &to_ipaddress($s->{'host'}) });
				}
			push(@{$dir->{'members'}}, $also);
			push(@{$dir->{'members'}}, 
				{ 'name' => 'notify',
				  'values' => [ 'yes' ] });
			}
		}
	local $pconf;
	local $indent = 0;
	if ($tmpl->{'dns_view'}) {
		# Adding inside a view. This may use named.conf, or an include
		# file references inside the view, if any
		$pconf = &bind8::get_config_parent();
		local $view = &get_bind_view($conf, $tmpl->{'dns_view'});
		if ($view) {
			local $addfile = &bind8::add_to_file();
			local $addfileok;
			if ($bind8::config{'zones_file'}) {
				foreach my $vm (@{$view->{'members'}}) {
					if ($vm->{'file'} eq $addfile) {
						# Add file is OK
						$addfileok = 1;
						}
					}
				}

			if (!$addfileok) {
				# Add to named.conf
				$pconf = $view;
				$indent = 1;
				$dir->{'file'} = $view->{'file'};
				}
			else {
				# Add to the file
				$dir->{'file'} = $addfile;
				$pconf = &bind8::get_config_parent($addfile);
				}
			}
		else {
			&error(&text('setup_ednsview', $tmpl->{'dns_view'}));
			}
		}
	else {
		# Adding at top level .. but perhaps in a different file
		$dir->{'file'} = &bind8::add_to_file();
		$pconf = &bind8::get_config_parent($dir->{'file'});
		}
	&lock_file($dir->{'file'});
	&bind8::save_directive($pconf, undef, [ $dir ], $indent);
	&flush_file_lines();
	&unlock_file($dir->{'file'});
	unlink($bind8::zone_names_cache);
	undef(@bind8::list_zone_names_cache);

	# Create the records file
	local %zd;
	&bind8::get_zone_defaults(\%zd);
	local $rootfile = &bind8::make_chroot($file);
	local $ip = $_[0]->{'dns_ip'} || $_[0]->{'ip'};
	if (!-r $rootfile) {
		&lock_file($rootfile);
		&create_standard_records($file, $_[0], $ip);
		&bind8::set_ownership($rootfile);
		&unlock_file($rootfile);
		}
	&$second_print($text{'setup_done'});

	# Create on slave servers
	local $myip = $bconfig{'this_ip'} ||
		      &to_ipaddress(&get_system_hostname());
	if (@slaves) {
		local $slaves = join(" ", map { $_->{'host'} } @slaves);
		&$first_print(&text('setup_bindslave', $slaves));
		local @slaveerrs = &bind8::create_on_slaves($_[0]->{'dom'},
							    $myip);
		if (@slaveerrs) {
			&$second_print($text{'setup_eslaves'});
			foreach $sr (@slaveerrs) {
				&$second_print($sr->[0]->{'host'}." : ".
					       $sr->[1]);
				}
			}
		else {
			&$second_print($text{'setup_done'});
			}
		$_[0]->{'dns_slave'} = $slaves;
		}

	undef(@bind8::get_config_cache);
	}
else {
	# Creating a sub-domain - add to parent's DNS zone
	local $parent = &get_domain($_[0]->{'subdom'});
	&$first_print(&text('setup_bindsub', $parent->{'dom'}));
	local $z = &get_bind_zone($parent->{'dom'});
	if (!$z) {
		&error(&text('setup_ednssub', $parent->{'dom'}));
		}
	local $file = &bind8::find("file", $z->{'members'});
	local $fn = $file->{'values'}->[0];
	&lock_file(&bind8::make_chroot($fn));
	$_[0]->{'dns_submode'} = 1;	# So we know how this was done
	local $ipdom = $_[0]->{'virt'} ? $_[0] : $parent;
	local $ip = $ipdom->{'dns_ip'} || $ipdom->{'ip'};
	&create_standard_records($fn, $_[0], $ip);
	local @recs = &bind8::read_zone_file($fn, $parent->{'dom'});
        &bind8::bump_soa_record($nfn, \@recs);
	&unlock_file(&bind8::make_chroot($fn));

	&$second_print($text{'setup_done'});
	}
&register_post_action(\&restart_bind);
}

sub slave_error_handler
{
$slave_error = $_[0];
}

# delete_dns(&domain)
# Delete a domain from the BIND config
sub delete_dns
{
&require_bind();
if (!$_[0]->{'dns_submode'}) {
	&$first_print($text{'delete_bind'});
	local $z = &get_bind_zone($_[0]->{'dom'});
	if ($z) {
		# Delete the records file
		local $file = &bind8::find("file", $z->{'members'});
		if ($file) {
			local $zonefile =
			    &bind8::make_chroot($file->{'values'}->[0]);
			&unlink_logged($zonefile);
			local $logfile = $zonefile.".log";
			if (!-r $logfile) { $logfile = $zonefile.".jnl"; }
			if (-r $logfile) {
				&unlink_logged($logfile);
				}
			}

		# Delete from named.conf
		local $rootfile = &bind8::make_chroot($z->{'file'});
		&lock_file($rootfile);
		local $lref = &read_file_lines($rootfile);
		splice(@$lref, $z->{'line'}, $z->{'eline'} - $z->{'line'} + 1);
		&flush_file_lines();
		&unlock_file($rootfile);

		# Clear zone names caches
		unlink($bind8::zone_names_cache);
		undef(@bind8::list_zone_names_cache);
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'save_nobind'});
		}

	local @slaves = split(/\s+/, $_[0]->{'dns_slave'});
	if (@slaves) {
		# Delete from slave servers too
		&$first_print(&text('delete_bindslave', $_[0]->{'dns_slave'}));
		local @slaveerrs = &bind8::delete_on_slaves(
					$_[0]->{'dom'}, \@slaves);
		if (@slaveerrs) {
			&$second_print($text{'delete_bindeslave'});
			foreach $sr (@slaveerrs) {
				&$second_print($sr->[0]->{'host'}." : ".
					       $sr->[1]);
				}
			}
		else {
			&$second_print($text{'setup_done'});
			}
		delete($_[0]->{'dns_slave'});
		}
	}
else {
	# Delete records from parent zone
	local $parent = &get_domain($_[0]->{'subdom'});
	&$first_print(&text('delete_bindsub', $parent->{'dom'}));
	local $z = &get_bind_zone($parent->{'dom'});
	if (!$z) {
		&$second_print($text{'save_nobind'});
		return;
		}
	local $file = &bind8::find("file", $z->{'members'});
	local $fn = $file->{'values'}->[0];
	&lock_file(&bind8::make_chroot($fn));
	local @recs = &bind8::read_zone_file($fn, $parent->{'dom'});
	foreach $r (reverse(@recs)) {
		if ($r->{'name'} =~ /$_[0]->{'dom'}/) {
			&bind8::delete_record($fn, $r);
			}
		}
        &bind8::bump_soa_record($fn, \@recs);
	&unlock_file(&bind8::make_chroot($fn));
	&$second_print($text{'setup_done'});
	$_[0]->{'dns_submode'} = 0;
	}
&register_post_action(\&restart_bind);
}

# modify_dns(&domain, &olddomain)
# If the IP for this server has changed, update all records containing the old
# IP to the new.
sub modify_dns
{
&require_bind();
local $tmpl = &get_template($_[0]->{'template'});
local $z;
local ($oldzonename, $newzonename);
if ($_[0]->{'dns_submode'}) {
	# Get parent domain
	local $parent = &get_domain($_[0]->{'subdom'});
	$z = &get_bind_zone($parent->{'dom'});
	$oldzonename = $newzonename = $parent->{'dom'};
	}
else {
	# Get this domain
	$z = &get_bind_zone($_[1]->{'dom'});
	$newzonename = $_[1]->{'dom'};
	$oldzonename = $_[1]->{'dom'};
	}
return 0 if (!$z);	# No DNS zone!
local $oldip = $_[1]->{'dns_ip'} || $_[1]->{'ip'};
local $newip = $_[0]->{'dns_ip'} || $_[0]->{'ip'};
local $rv = 0;
if ($_[0]->{'dom'} ne $_[1]->{'dom'}) {
	local $nfn;
	local $file = &bind8::find("file", $z->{'members'});
	if (!$_[0]->{'dns_submode'}) {
		# Domain name has changed .. rename zone file
		&$first_print($text{'save_dns2'});
		&lock_file(&bind8::make_chroot($z->{'file'}));
		local $fn = $file->{'values'}->[0];
		$nfn = $fn;
		$nfn =~ s/$_[1]->{'dom'}/$_[0]->{'dom'}/;
		if ($fn ne $nfn) {
			&rename_logged(&bind8::make_chroot($fn),
				       &bind8::make_chroot($nfn))
			}
		$file->{'values'}->[0] = $nfn;
		$file->{'value'} = $nfn;

		# Change zone in .conf file
		$z->{'values'}->[0] = $_[0]->{'dom'};
		$z->{'value'} = $_[0]->{'dom'};
		&bind8::save_directive(&bind8::get_config_parent(),
				       [ $z ], [ $z ], 0);
		&flush_file_lines();
		&unlock_file(&bind8::make_chroot($z->{'file'}));
		}
	else {
		&$first_print($text{'save_dns6'});
		$nfn = $file->{'values'}->[0];
		}

	# Modify any records containing the old name
	&lock_file(&bind8::make_chroot($nfn));
        local @recs = &bind8::read_zone_file($nfn, $oldzonename);
        foreach my $r (@recs) {
                if ($r->{'name'} =~ /$_[1]->{'dom'}/i) {
                        $r->{'name'} =~ s/$_[1]->{'dom'}/$_[0]->{'dom'}/;
			if ($r->{'type'} eq 'SPF') {
				# Fix SPF TXT record
				$r->{'values'}->[0] =~
					s/$_[1]->{'dom'}/$_[0]->{'dom'}/;
				}
			if ($r->{'type'} eq 'MX') {
				# Fix mail server in MX record
				$r->{'values'}->[1] =~
					s/$_[1]->{'dom'}/$_[0]->{'dom'}/;
				}
                        &bind8::modify_record($nfn, $r, $r->{'name'},
                                              $r->{'ttl'}, $r->{'class'},
                                              $r->{'type'},
					      &join_record_values($r),
                                              $r->{'comment'});
                        }
                }

        # Update SOA record
        &bind8::bump_soa_record($nfn, \@recs);
	&unlock_file(&bind8::make_chroot($nfn));
	$rv++;

	# Clear zone names caches
	unlink($bind8::zone_names_cache);
	undef(@bind8::list_zone_names_cache);
	&$second_print($text{'setup_done'});

	if (!$_[0]->{'dns_submode'}) {
		local @slaves = split(/\s+/, $_[0]->{'dns_slave'});
		if (@slaves) {
			# Rename on slave servers too
			&$first_print(&text('save_dns3', $_[0]->{'dns_slave'}));
			local @slaveerrs = &bind8::rename_on_slaves(
				$_[1]->{'dom'}, $_[0]->{'dom'}, \@slaves);
			if (@slaveerrs) {
				&$second_print($text{'save_bindeslave'});
				foreach $sr (@slaveerrs) {
					&$second_print($sr->[0]->{'host'}." : ".
						       $sr->[1]);
					}
				}
			else {
				&$second_print($text{'setup_done'});
				}
			}
		}
	}

if ($oldip ne $newip) {
	# IP address has changed .. need to update any records that use
	# the old IP
	&$first_print($text{'save_dns'});
	local $file = &bind8::find("file", $z->{'members'});
	local $fn = $file->{'values'}->[0];
	local $zonefile = &bind8::make_chroot($fn);
	&lock_file($zonefile);
	local @recs = &bind8::read_zone_file($fn, $newzonename);
	foreach $r (@recs) {
		if ($r->{'values'}->[0] eq $oldip) {
			# Change IP in A record
			&bind8::modify_record($fn, $r, $r->{'name'},
					      $r->{'ttl'}, $r->{'class'},
					      $r->{'type'}, $newip,
					      $r->{'comment'});
			}
		elsif ($r->{'type'} eq 'SPF' &&
		       $r->{'values'}->[0] =~ /$oldip/) {
			# Fix IP within an SPF
			$r->{'values'}->[0] =~ s/$oldip/$newip/g;
			&bind8::modify_record($fn, $r, $r->{'name'},
					      $r->{'ttl'}, $r->{'class'},
					      $r->{'type'},
					      &join_record_values($r),
					      $r->{'comment'});
			}
		}

	# Update SOA record
	&bind8::bump_soa_record($fn, \@recs);
	&unlock_file($zonefile);
	$rv++;
	&$second_print($text{'setup_done'});
	}

if ($_[0]->{'mail'} && !$_[1]->{'mail'} && !$tmpl->{'dns_replace'}) {
	# Email was enabled .. add MX records
	local $file = &bind8::find("file", $z->{'members'});
	local $fn = $file->{'values'}->[0];
	local $zonefile = &bind8::make_chroot($fn);
	&lock_file($zonefile);
	local @recs = &bind8::read_zone_file($fn, $newzonename);
	local ($mx) = grep { $_->{'type'} eq 'MX' &&
			     $_->{'name'} eq $_[0]->{'dom'}."." ||
			     $_->{'type'} eq 'A' &&
			     $_->{'name'} eq "mail.".$_[0]->{'dom'}."." } @recs;
	if (!$mx) {
		&$first_print($text{'save_dns4'});
		local $ip = $_[0]->{'dns_ip'} || $_[0]->{'ip'};
		&create_mx_records($fn, $_[0], $ip);
		&bind8::bump_soa_record($fn, \@recs);
		&$second_print($text{'setup_done'});
		$rv++;
		}
	&unlock_file($zonefile);
	}
elsif (!$_[0]->{'mail'} && $_[1]->{'mail'} && !$tmpl->{'dns_replace'}) {
	# Email was disabled .. remove MX records
	local $file = &bind8::find("file", $z->{'members'});
	local $zonefile = &bind8::make_chroot($file);
	&lock_file($zonefile);
	local $fn = $file->{'values'}->[0];
	local @recs = &bind8::read_zone_file($fn, $newzonename);
	local @mx = grep { $_->{'type'} eq 'MX' &&
			   $_->{'name'} eq $_[0]->{'dom'}."." ||
			   $_->{'type'} eq 'A' &&
			   $_->{'name'} eq "mail.".$_[0]->{'dom'}."." } @recs;
	if (@mx) {
		&$first_print($text{'save_dns5'});
		foreach my $r (reverse(@mx)) {
			&bind8::delete_record($fn, $r);
			}
		&bind8::bump_soa_record($fn, \@recs);
		&$second_print($text{'setup_done'});
		$rv++;
		}
	&unlock_file($zonefile);
	}

if ($_[0]->{'mx_servers'} ne $_[1]->{'mx_servers'}) {
	# Secondary MX servers have been changed - add or remove MX records
	&$first_print($text{'save_dns7'});
	local @newmxs = split(/\s+/, $_[0]->{'mx_servers'});
	local @oldmxs = split(/\s+/, $_[1]->{'mx_servers'});
	local $file = &bind8::find("file", $z->{'members'});
	local $zonefile = &bind8::make_chroot($file);
	&lock_file($zonefile);
	local $fn = $file->{'values'}->[0];
	local @recs = &bind8::read_zone_file($fn, $newzonename);
	&foreign_require("servers", "servers-lib.pl");
	local %servers = map { $_->{'id'}, $_ } &servers::list_servers();
	local $withdot = $_[0]->{'dom'}.".";

	# Add missing MX records
	foreach my $id (@newmxs) {
		if (&indexof($id, @oldmxs) < 0) {
			# A new MX .. add a record for it
			local $s = $servers{$id};
			local $mxhost = $s->{'mxname'} || $s->{'host'};
			&bind8::create_record($fn, $withdot, undef,
				      "IN", "MX", "10 $mxhost.");
			}
		}

	# Remove those that are no longer needed
	local @mxs;
	foreach my $id (@oldmxs) {
		if (&indexof($id, @newmxs) < 0) {
			# An old MX .. remove it
			local $s = $servers{$id};
			local $mxhost = $s->{'mxname'} || $s->{'host'};
			foreach my $r (@recs) {
				if ($r->{'type'} eq 'MX' &&
				    $r->{'name'} eq $withdot &&
				    $r->{'values'}->[1] eq $mxhost.".") {
					push(@mxs, $r);
					}
				}
			}
		}
	foreach my $r (reverse(@mxs)) {
		&bind8::delete_record($fn, $r);
		}

	&bind8::bump_soa_record($fn, \@recs);
	&$second_print($text{'setup_done'});
	$rv++;
	}

&register_post_action(\&restart_bind) if ($rv);
return $rv;
}

# join_record_values(&record)
# Given the values for a record, joins them into a space-separated string
# with quoting if needed
sub join_record_values
{
local ($r) = @_;
local @rv;
foreach my $v (@{$r->{'values'}}) {
	push(@rv, $v =~ /\s/ ? "\"$v\"" : $v);
	}
return join(" ", @rv);
}

# create_mx_records(file, &domain, ip)
# Adds MX records to a DNS domain
sub create_mx_records
{
local ($file, $d, $ip) = @_;
local $withdot = $d->{'dom'}.".";
&bind8::create_record($file, "mail.$withdot", undef,
		      "IN", "A", $ip);
&bind8::create_record($file, $withdot, undef,
		      "IN", "MX", "5 mail.$withdot");

# Add MX records for slaves
local %ids = map { $_, 1 }
	split(/\s+/, $d->{'mx_servers'});
local @servers = grep { $ids{$_->{'id'}} } &list_mx_servers();
local $n = 10;
foreach my $s (@servers) {
	local $mxhost = $s->{'mxname'} || $s->{'host'};
	&bind8::create_record($file, $withdot, undef,
		      "IN", "MX", "$n $mxhost.");
	$n += 5;
	}
}

# create_standard_records(file, &domain, ip)
# Adds to a records file the needed records for some domain
sub create_standard_records
{
local ($file, $d, $ip) = @_;
local $rootfile = &bind8::make_chroot($file);
local $tmpl = &get_template($d->{'template'});
local $serial = $bconfig{'soa_style'} ?
	&bind8::date_serial().sprintf("%2.2d", $bconfig{'soa_start'}) :
	time();
if (!$tmpl->{'dns_replace'}) {
	# Create records that are appropriate for this domain
	if (!$d->{'dns_submode'}) {
		# Only add SOA if this is a new file, not a sub-domain
		&open_tempfile(RECS, ">$rootfile");
		if ($bconfig{'master_ttl'}) {
			&print_tempfile(RECS,
			    "\$ttl $zd{'minimum'}$zd{'minunit'}\n");
			}
		&close_tempfile(RECS);
		local $tmaster = $tmpl->{'dns_master'} eq 'none' ? undef :
					$tmpl->{'dns_master'};
		local $master = $tmaster ||
				$bconfig{'default_prins'} ||
				&get_system_hostname();
		$master .= "." if ($master !~ /\.$/);
		local $email = $bconfig{'tmpl_email'} ||
			       "root\@$master";
		$email = &bind8::email_to_dotted($email);
		local $soa = "$master $email (\n".
			     "\t\t\t$serial\n".
			     "\t\t\t$zd{'refresh'}$zd{'refunit'}\n".
			     "\t\t\t$zd{'retry'}$zd{'retunit'}\n".
			     "\t\t\t$zd{'expiry'}$zd{'expunit'}\n".
			     "\t\t\t$zd{'minimum'}$zd{'minunit'} )";
		&bind8::create_record($file, "@", undef, "IN",
				      "SOA", $soa);
		&bind8::create_record($file, "@", undef, "IN",
				      "NS", $master);
		local $slave;
		local @slaves = &bind8::list_slave_servers();
		foreach $slave (@slaves) {
			local @bn = $slave->{'nsname'} ||
				    gethostbyname($slave->{'host'});
			local $full = "$bn[0].";
			&bind8::create_record($file, "@", undef, "IN",
					      "NS", "$bn[0].");
			}
		}
	local $withdot = $d->{'dom'}.".";
	&bind8::create_record($file, $withdot, undef,
			      "IN", "A", $ip);
	&bind8::create_record($file, "www.$withdot", undef,
			      "IN", "A", $ip);
	&bind8::create_record($file, "ftp.$withdot", undef,
			      "IN", "A", $ip);
	&bind8::create_record($file, "m.$withdot", undef,
			      "IN", "A", $ip);
	if ($d->{'mail'}) {
		# For mail domains, add MX to this server
		&create_mx_records($file, $d, $ip);
		}
	if ($tmpl->{'dns_spf'} ne "none") {
		# Add SPF record for domain
		local $str = &bind8::join_spf(&default_domain_spf($d));
		&bind8::create_record($file, $withdot, undef,
				      "IN", "TXT", "\"$str\"");
		}
	}
if ($tmpl->{'dns'} && (!$d->{'dns_submode'} || !$tmpl->{'dns_replace'})) {
	# Add or use the user-defined template
	&open_tempfile(RECS, ">>$rootfile");
	local %subs = %$d;
	$subs{'serial'} = $serial;
	$subs{'dnsemail'} = $d->{'emailto'};
	$subs{'dnsemail'} =~ s/\@/./g;
	local $recs = &substitute_domain_template(
		join("\n", split(/\t+/, $tmpl->{'dns'}))."\n", \%subs);
	&print_tempfile(RECS, $recs);
	&close_tempfile(RECS);
	}
}

# validate_dns(&domain)
# Check for the DNS domain and records file
sub validate_dns
{
local ($d) = @_;
local $z;
if ($d->{'dns_submode'} && $d->{'subdom'}) {
	# Records are in parent domain's file
	local $parent = &get_domain($d->{'subdom'});
	$z = &get_bind_zone($parent->{'dom'});
	}
else {
	# Domain has its own records file
	$z = &get_bind_zone($d->{'dom'});
	}
return &text('validate_edns', "<tt>$d->{'dom'}</tt>") if (!$z);
local $file = &bind8::find("file", $z->{'members'});
return &text('validate_ednsfile', "<tt>$d->{'dom'}</tt>") if (!$file);
local $zonefile = &bind8::make_chroot(
			&bind8::absolute_path($file->{'values'}->[0]));
return &text('validate_ednsfile2', "<tt>$zonefile</tt>") if (!-r $zonefile);
local @recs = &bind8::read_zone_file($file->{'values'}->[0], $d->{'dom'});
local %got;
foreach my $r (@recs) {
	$got{lc($r->{'type'})}++;
	}
$got{'SOA'} || &text('validate_ednssoa', "<tt>$zonefile</tt>");
$got{'A'} || &text('validate_ednsa', "<tt>$zonefile</tt>");
return undef;
}

# disable_dns(&domain)
# Re-names this domain in named.conf with the .disabled suffix
sub disable_dns
{
&$first_print($text{'disable_bind'});
&require_bind();
local $z = &get_bind_zone($_[0]->{'dom'});
if ($z) {
	local $rootfile = &bind8::make_chroot($z->{'file'});
	&lock_file($rootfile);
	$z->{'values'}->[0] = $_[0]->{'dom'}.".disabled";
	&bind8::save_directive(&bind8::get_config_parent(), [ $z ], [ $z ], 0);
	&flush_file_lines();
	&unlock_file($rootfile);

	# Clear zone names caches
	unlink($bind8::zone_names_cache);
	undef(@bind8::list_zone_names_cache);
	&$second_print($text{'setup_done'});
	&register_post_action(\&restart_bind);
	}
else {
	&$second_print($text{'save_nobind'});
	}
}

# enable_dns(&domain)
# Re-names this domain in named.conf to remove the .disabled suffix
sub enable_dns
{
&$first_print($text{'enable_bind'});
&require_bind();
local $z = &get_bind_zone($_[0]->{'dom'});
if ($z) {
	local $rootfile = &bind8::make_chroot($z->{'file'});
	&lock_file($rootfile);
	$z->{'values'}->[0] = $_[0]->{'dom'};
	&bind8::save_directive(&bind8::get_config_parent(), [ $z ], [ $z ], 0);
	&flush_file_lines();
	&unlock_file($rootfile);

	# Clear zone names caches
	unlink($bind8::zone_names_cache);
	undef(@bind8::list_zone_names_cache);
	&$second_print($text{'setup_done'});
	&register_post_action(\&restart_bind);
	}
else {
	&$second_print($text{'save_nobind'});
	}
}

# get_bind_zone(name, [&config], [file])
# Returns the zone structure for the named domain, possibly with .disabled
sub get_bind_zone
{
&require_bind();
local $conf = $_[1] ? $_[1] :
	      $_[2] ? [ &bind8::read_config_file($_[2]) ] :
		      &bind8::get_config();
local @zones = &bind8::find("zone", $conf);
local ($v, $z);
foreach $v (&bind8::find("view", $conf)) {
	push(@zones, &bind8::find("zone", $v->{'members'}));
	}
local ($z) = grep { lc($_->{'value'}) eq lc($_[0]) ||
		    lc($_->{'value'}) eq lc("$_[0].disabled") } @zones;
return $z;
}

# restart_bind(&domain)
# Signal BIND to re-load its configuration
sub restart_bind
{
&$first_print($text{'setup_bindpid'});
local $pid = &get_bind_pid();
if ($pid) {
	if ($bconfig{'restart_cmd'}) {
		&system_logged("$bconfig{'restart_cmd'} >/dev/null 2>&1 </dev/null");
		}
	else {
		&kill_logged('HUP', $pid);
		}
	&$second_print($text{'setup_done'});
	$rv = 1;
	}
else {
	&$second_print($text{'setup_notrun'});
	$rv = 0;
	}
if (&bind8::list_slave_servers()) {
	# Re-start on slaves too
	&$first_print(&text('setup_bindslavepids'));
	local @slaveerrs = &bind8::restart_on_slaves();
	if (@slaveerrs) {
		&$second_print($text{'setup_bindeslave'});
		foreach $sr (@slaveerrs) {
			&$second_print($sr->[0]->{'host'}." : ".$sr->[1]);
			}
		}
	else {
		&$second_print($text{'setup_done'});
		}
	}
return $rv;
}

# check_dns_clash(&domain, [changing])
# Returns 1 if a domain already exists in BIND
sub check_dns_clash
{
if (!$_[1] || $_[1] eq 'dom') {
	local ($czone) = &get_bind_zone($_[0]->{'dom'});
	return $czone ? 1 : 0;
	}
return 0;
}

# get_bind_pid()
# Returns the BIND PID, if it is running
sub get_bind_pid
{
&require_bind();
local $pidfile = &bind8::get_pid_file();
return &check_pid_file(&bind8::make_chroot($pidfile, 1));
}

# backup_dns(&domain, file)
# Save all the virtual server's DNS records as a separate file
sub backup_dns
{
&require_bind();
return 1 if ($_[0]->{'dns_submode'});	# backed up in parent
&$first_print($text{'backup_dnscp'});
local $z = &get_bind_zone($_[0]->{'dom'});
if ($z) {
	local $file = &bind8::find("file", $z->{'members'});
	local $filename = &bind8::make_chroot(
		&bind8::absolute_path($file->{'values'}->[0]));
	&execute_command("cp ".quotemeta($filename)." ".quotemeta($_[1]));
	&$second_print($text{'setup_done'});
	return 1;
	}
else {
	&$second_print($text{'backup_dnsnozone'});
	return 0;
	}
}

# restore_dns(&domain, file, &options)
# Update the virtual server's DNS records from the backup file, except the SOA
sub restore_dns
{
&require_bind();
return 1 if ($_[0]->{'dns_submode'});	# restored in parent
&$first_print($text{'restore_dnscp'});
local $z = &get_bind_zone($_[0]->{'dom'});
if ($z) {
	local $file = &bind8::find("file", $z->{'members'});
	local $filename = &bind8::make_chroot(
			&bind8::absolute_path($file->{'values'}->[0]));

	if ($_[2]->{'wholefile'}) {
		# Copy whole file
		&lock_file($filename);
		&copy_source_dest($_[1], $filename);
		&bind8::set_ownership($filename);
		}
	else {
		# Only copy section after SOA
		local $srclref = &read_file_lines($_[1]);
		local $dstlref = &read_file_lines($filename);
		&lock_file($filename);
		local ($srcstart, $srcend) = &except_soa($_[0], $_[1]);
		local ($dststart, $dstend) = &except_soa($_[0], $filename);
		splice(@$dstlref, $dststart, $dstend - $dststart + 1,
		       @$srclref[$srcstart .. $srcend]);
		&flush_file_lines();
		}

	# Need to bump SOA
	local $fn = $file->{'values'}->[0];
	local @recs = &bind8::read_zone_file($fn, $_[0]->{'dom'});
	&bind8::bump_soa_record($file->{'values'}->[0], \@recs);

	# Need to update IP addresses
	local $r;
	local ($baserec) = grep { $_->{'type'} eq "A" &&
				  ($_->{'name'} eq $_[0]->{'dom'}."." ||
				   $_->{'name'} eq '@') } @recs;
	local $ip = $_[0]->{'dns_ip'} || $_[0]->{'ip'};
	local $baseip = $baserec ? $baserec->{'values'}->[0] : undef;
	foreach $r (@recs) {
		if ($r->{'type'} eq "A" &&
		    $r->{'values'}->[0] eq $baseip) {
			&bind8::modify_record($fn, $r, $r->{'name'},
					      $r->{'ttl'},$r->{'class'},
					      $r->{'type'},
					      $_[0]->{'ip'},
					      $r->{'comment'});
			}
		}

	&unlock_file($filename);
	&$second_print($text{'setup_done'});

	&register_post_action(\&restart_bind);
	return 1;
	}
else {
	&$second_print($text{'backup_dnsnozone'});
	return 0;
	}
}

# except_soa(&domain, file)
sub except_soa
{
local $bind8::config{'chroot'} = "/";	# make sure path is absolute
local @recs = &bind8::read_zone_file($_[1], $_[0]->{'dom'});
local ($r, $start, $end);
foreach $r (@recs) {
	if ($r->{'type'} ne "SOA" && !$r->{'generate'} && !$r->{'defttl'} &&
	    !defined($start)) {
		$start = $r->{'line'};
		}
	$end = $r->{'eline'};
	}
return ($start, $end);
}

# get_bind_view([&conf], view)
# Returns the view object for the view to add domains to
sub get_bind_view
{
&require_bind();
local $conf = $_[0] || &bind8::get_config();
local @views = &bind8::find("view", $conf);
local ($view) = grep { $_->{'values'}->[0] eq $_[1] } @views;
return $view;
}

# show_restore_dns(&options)
# Returns HTML for DNS restore option inputs
sub show_restore_dns
{
local ($opts, $d) = @_;
return &ui_checkbox("dns_wholefile", 1, $text{'restore_dnswholefile'},
		    $opts->{'wholefile'});
}

# parse_restore_dns(&in)
# Parses the inputs for DNS restore options
sub parse_restore_dns
{
local ($in, $d) = @_;
return { 'wholefile' => $in->{'dns_wholefile'} };
}

# sysinfo_dns()
# Returns the BIND version
sub sysinfo_dns
{
&require_bind();
if (!$bind8::bind_version) {
	local $out = `$bind8::config{'named_path'} -v 2>&1`;
	if ($out =~ /(bind|named)\s+([0-9\.]+)/i) {
		$bind8::bind_version = $2;
		}
	}
return ( [ $text{'sysinfo_bind'}, $bind8::bind_version ] );
}

# links_dns(&domain)
# Returns a link to the BIND module
sub links_dns
{
local ($d) = @_;
if ($config{'avail_dns'} && !$d->{'dns_submode'}) {
	return ( { 'mod' => 'bind8',
		   'desc' => $text{'links_dns'},
		   'page' => "edit_master.cgi?zone=".&urlize($d->{'dom'}),
		   'cat' => 'services',
		 } );
	}
return ( );
}

sub startstop_dns
{
local ($typestatus) = @_;
local $bpid = defined($typestatus{'bind8'}) ?
		$typestatus{'bind8'} == 1 : &get_bind_pid();
if ($bpid && kill(0, $bpid)) {
	return ( { 'status' => 1,
		   'name' => $text{'index_bname'},
		   'desc' => $text{'index_bstop'},
		   'restartdesc' => $text{'index_brestart'},
		   'longdesc' => $text{'index_bstopdesc'} } );
	}
else {
	return ( { 'status' => 0,
		   'name' => $text{'index_bname'},
		   'desc' => $text{'index_bstart'},
		   'longdesc' => $text{'index_bstartdesc'} } );
	}
}

sub start_service_dns
{
&require_bind();
return &bind8::start_bind();
}

sub stop_service_dns
{
&require_bind();
return &bind8::stop_bind();
}

# show_template_dns(&tmpl)
# Outputs HTML for editing BIND related template options
sub show_template_dns
{
local ($tmpl) = @_;
&require_bind();
$conf = &bind8::get_config();
@views = &bind8::find("view", $conf);

# DNS records
local $ndi = &none_def_input("dns", $tmpl->{'dns'}, $text{'tmpl_dnsbelow'}, 1,
     0, undef, [ "dns", "bind_replace", @views ? ( "newdns_view" ) : ( ) ]);
print &ui_table_row(&hlink($text{'tmpl_dns'}, "template_dns"),
	$ndi."<br>\n".
	&ui_textarea("dns", $tmpl->{'dns'} eq "none" ? "" :
				join("\n", split(/\t/, $tmpl->{'dns'})),
		     10, 60)."<br>\n".
	&ui_radio("bind_replace", int($tmpl->{'dns_replace'}),
		  [ [ 0, $text{'tmpl_replace0'} ],
		    [ 1, $text{'tmpl_replace1'} ] ]));
	

# Option for view to add to, for BIND 9
if (@views) {
	print &ui_table_row($text{'newdns_view'},
		&ui_select("view", $config{'dns_view'},
			[ [ "", $text{'newdns_noview'} ],
			  map { [ $_->{'values'}->[0] ] } @views ]));
	}

print &ui_table_hr();

# Master NS hostnames
print &ui_table_row(&hlink($text{'tmpl_dnsmaster'},
                           "template_dns_master"),
	&none_def_input("dns_master", $tmpl->{'dns_master'},
			$text{'tmpl_dnsmnames'}, 0, 0, $text{'tmpl_dnsmauto'},
			[ "dns_master" ])." ".
	&ui_textbox("dns_master", $tmpl->{'dns_master'} eq 'none' ? '' :
					$tmpl->{'dns_master'}, 40));

# Option for SPF record
print &ui_table_row(&hlink($text{'tmpl_spf'},
                           "template_dns_spf_mode"),
	&none_def_input("dns_spf", $tmpl->{'dns_spf'},
		        $text{'tmpl_spfyes'}, 0, 0, $text{'no'},
			[ "dns_spfhosts", "dns_spfall", "dns_sub_mode" ]));

# Extra SPF hosts
print &ui_table_row(&hlink($text{'tmpl_spfhosts'},
			   "template_dns_spfhosts"),
	&ui_textbox("dns_spfhosts", $tmpl->{'dns_spfhosts'}, 40));

# SPF ~all mode
print &ui_table_row(&hlink($text{'tmpl_spfall'},
			   "template_dns_spfall"),
	&ui_yesno_radio("dns_spfall", $tmpl->{'dns_spfall'} ? 1 : 0));

# Add sub-domains to parent domain DNS
print &ui_table_row(&hlink($text{'tmpl_dns_sub'},
                           "template_dns_sub"),
	&none_def_input("dns_sub", $tmpl->{'dns_sub'},
		        $text{'yes'}, 0, 0, $text{'no'}));

# Extra named.conf directives
print &ui_table_hr();

print &ui_table_row(&hlink($text{'tmpl_namedconf'}, "namedconf"),
    &none_def_input("namedconf", $tmpl->{'namedconf'},
		    $text{'tmpl_namedconfbelow'}, 0, 0, undef,
		    [ "namedconf" ])."<br>".
    &ui_textarea("namedconf",
		 $tmpl->{'namedconf'} eq 'none' ? '' :
			join("\n", split(/\t/, $tmpl->{'namedconf'})),
		 5, 60));
}

# parse_template_dns(&tmpl)
# Updates BIND related template options from %in
sub parse_template_dns
{
local ($tmpl) = @_;

# Save DNS settings
$tmpl->{'dns'} = &parse_none_def("dns");
if ($in{"dns_mode"} == 2) {
	$tmpl->{'default'} || $tmpl->{'dns'} ||
		&error($text{'tmpl_edns'});
	$tmpl->{'dns_replace'} = $in{'bind_replace'};
	$tmpl->{'dns_view'} = $in{'view'};

	&require_bind();
	$fakeip = "1.2.3.4";
	$fakedom = "foo.com";
	$recs = &substitute_template(
		join("\n", split(/\t+/, $in{'dns'}))."\n",
		{ 'ip' => $fakeip,
		  'dom' => $fakedom });
	$temp = &transname();
	&open_tempfile(TEMP, ">$temp");
	&print_tempfile(TEMP, $recs);
	&close_tempfile(TEMP);
	$bind8::config{'short_names'} = 0;	# force canonicalization
	$bind8::config{'chroot'} = '/';		# turn off chroot for temp path
	$bind8::config{'auto_chroot'} = undef;
	@recs = &bind8::read_zone_file($temp, $fakedom);
	unlink($temp);
	foreach $r (@recs) {
		$soa++ if ($r->{'name'} eq $fakedom."." &&
			   $r->{'type'} eq "SOA");
		$ns++ if ($r->{'name'} eq $fakedom."." &&
			  $r->{'type'} eq "NS");
		$dom++ if ($r->{'name'} eq $fakedom."." &&
			   ($r->{'type'} eq "A" || $r->{'type'} eq "MX"));
		$www++ if ($r->{'name'} eq "www.".$fakedom."." &&
			   $r->{'type'} eq "A" ||
			   $r->{'type'} eq "CNAME");
		}

	if ($in{'bind_replace'}) {
		# Make sure an SOA and NS records exist
		$soa == 1 || &error($text{'newdns_esoa'});
		$ns || &error($text{'newdns_ens'});
		$dom || &error($text{'newdns_edom'});
		$www || &error($text{'newdns_ewww'});
		}
	else {
		# Make sure SOA doesn't exist
		$soa && &error($text{'newdns_esoa2'});
		}
	}

# Save NS hostname
$in{'dns_master_mode'} != 2 ||
   ($in{'dns_master'} =~ /^[a-z0-9\.\-\_]+$/i && $in{'dns_master'} =~ /\./) ||
	&error($text{'tmpl_ednsmaster'});
$tmpl->{'dns_master'} = $in{'dns_master_mode'} == 0 ? "none" :
		        $in{'dns_master_mode'} == 1 ? undef : $in{'dns_master'};

# Save SPF
$tmpl->{'dns_spf'} = $in{'dns_spf_mode'} == 0 ? "none" :
		     $in{'dns_spf_mode'} == 1 ? undef : "yes";
$tmpl->{'dns_spfhosts'} = $in{'dns_spfhosts'};
$tmpl->{'dns_spfall'} = $in{'dns_spfall'};

# Save sub-domain DNS mode
$tmpl->{'dns_sub'} = $in{'dns_sub_mode'} == 0 ? "none" :
		     $in{'dns_sub_mode'} == 1 ? undef : "yes";

# Save named.conf
$tmpl->{'namedconf'} = &parse_none_def("namedconf");
if ($in{'namedconf_mode'} == 2) {
	# Make sure the directives are valid
	local @recs = &text_to_named_conf($tmpl->{'namedconf'});
	if ($tmpl->{'namedconf'} =~ /\S/ && !@recs) {
		&error($text{'newdns_enamedconf'});
		}
	}
}

# get_domain_spf(&domain)
# Returns the SPF object for a domain from its DNS records, or undef.
sub get_domain_spf
{
local ($d) = @_;
local @recs = &get_domain_dns_records($d);
foreach my $r (@recs) {
	if ($r->{'type'} eq 'SPF' &&
	    $r->{'name'} eq $d->{'dom'}.'.') {
		return &bind8::parse_spf($r->{'values'}->[0]);
		}
	}
return undef;
}

# save_domain_spf(&domain, &spf)
# Updates/creates/deletes a domain's SPF record.
sub save_domain_spf
{
local ($d, $spf) = @_;
local @recs = &get_domain_dns_records($d);
return if (!@recs);		# Domain not found!
local ($r) = grep { $_->{'type'} eq 'SPF' &&
		    $_->{'name'} eq $d->{'dom'}.'.' } @recs;
local $str = $spf ? &bind8::join_spf($spf) : undef;
if ($r && $spf) {
	# Update record
	&bind8::modify_record($r->{'file'}, $r, $r->{'name'}, $r->{'ttl'},
			      $r->{'class'}, $r->{'type'}, "\"$str\"",
			      $r->{'comment'});
	}
elsif ($r && !$spf) {
	# Remove record
	&bind8::delete_record($r->{'file'}, $r);
	}
elsif (!$r && $spf) {
	# Add record
	&bind8::create_record($recs[0]->{'file'}, $d->{'dom'}.'.', undef,
			      "IN", "TXT", "\"$str\"");
	}
else {
	return;
	}
&bind8::bump_soa_record($recs[0]->{'file'}, \@recs);
&register_post_action(\&restart_bind);
}

# get_domain_dns_records(&domain)
# Returns an array of DNS records for a domain, or empty if the file couldn't
# be found.
sub get_domain_dns_records
{
local ($d) = @_;
&require_bind();
local $z = &get_bind_zone($d->{'dom'});
return ( ) if (!$z);
local $file = &bind8::find("file", $z->{'members'});
return ( ) if (!$file);
local $fn = $file->{'values'}->[0];
return &bind8::read_zone_file($fn, $d->{'dom'});
}

# default_domain_spf(&domain)
# Returns a default SPF object for a domain, based on its template
sub default_domain_spf
{
local ($d) = @_;
local $tmpl = &get_template($d->{'template'});
local $defip = &get_default_ip();
local $spf = { 'a' => 1, 'mx' => 1,
	       'a:' => [ $d->{'dom'} ],
	       'ip4:' => [ $defip ] };
local $hosts = &substitute_domain_template(
	$tmpl->{'dns_spfhosts'}, $d);
foreach my $h (split(/\s+/, $hosts)) {
	if (&check_ipaddress($h) ||
	    $h =~ /^(\S+)\// &&
	    &check_ipaddress($1)) {
		push(@{$spf->{'ip4:'}}, $h);
		}
	else {
		push(@{$spf->{'a:'}}, $h);
		}
	}
$spf->{'all'} = $tmpl->{'dns_spfall'} ? 2 : 1;
return $spf;
}

# text_to_named_conf(text)
# Converts a text string which contains zero or more BIND directives into an
# array of directive objects.
sub text_to_named_conf
{
local ($str) = @_;
local $temp = &transname();
&open_tempfile(TEMP, ">$temp");
&print_tempfile(TEMP, $str);
&close_tempfile(TEMP);
&require_bind();
local %oldconfig = %bind8::config;	# turn off chroot temporarily
$bind8::config{'chroot'} = undef;
$bind8::config{'auto_chroot'} = undef;
local @rv = grep { $_->{'name'} ne 'dummy' }
	    &bind8::read_config_file($temp, 0);
%bind8::config = %oldconfig;
return @rv;
}

$done_feature_script{'dns'} = 1;

1;

