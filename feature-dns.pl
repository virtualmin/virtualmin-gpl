
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
local $ip = $_[0]->{'dns_ip'} || $_[0]->{'ip'};
local @extra_slaves = split(/\s+/, $tmpl->{'dns_ns'});

if ($_[0]->{'provision_dns'}) {
	# Create on provisioning server
	&$first_print($text{'setup_bind_provision'});
	local $info = { 'domain' => $_[0]->{'dom'} };
	if (@extra_slaves) {
		$info->{'slave'} = [ grep { $_ } map { &to_ipaddress($_) }
						     @extra_slaves ];
		}
	local $temp = &transname();
	local $bind8::config{'auto_chroot'} = undef;
	local $bind8::config{'chroot'} = undef;
	if ($_[0]->{'alias'}) {
		&create_alias_records($temp, $_[0], $ip);
		}
	else {
		&create_standard_records($temp, $_[0], $ip);
		}
	local @recs = &bind8::read_zone_file($temp, $_[0]->{'dom'});
	$info->{'record'} = [ &records_to_text($_[0], \@recs) ];
	my ($ok, $msg) = &provision_api_call(
		"provision-dns-zone", $info, 0);
	if (!$ok || $msg !~ /host=(\S+)/) {
		&$second_print(&text('setup_ebind_provision', $msg));
		return 0;
		}
	$_[0]->{'provision_dns_host'} = $1;
	&$second_print(&text('setup_bind_provisioned',
			     $_[0]->{'provision_dns_host'}));
	}
elsif (!$_[0]->{'subdom'} && !&under_parent_domain($_[0]) ||
       $tmpl->{'dns_sub'} ne 'yes' ||
       $_[0]->{'alias'}) {
	# Creating a new real zone
	&$first_print($text{'setup_bind'});
	&obtain_lock_dns($_[0], 1);
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

	# Also notify slave servers, unless already added
	local @slaves = &bind8::list_slave_servers();
	if (@slaves && !$tmpl->{'namedconf_no_also_notify'}) {
		local ($also) = grep { $_->{'name'} eq 'also-notify' }
				     @{$dir->{'members'}};
		if (!$also) {
			$also = { 'name' => 'also-notify',
				  'type' => 1 };
			local @also;
			foreach my $s (@slaves) {
				push(@also,
				     { 'name' => &to_ipaddress($s->{'host'}) });
				}
			foreach my $s (@extra_slaves) {
				push(@also, { 'name' => &to_ipaddress($s) });
				}
			@also = grep { $_->{'name'} } @also;
			$also->{'members'} = \@also;
			push(@{$dir->{'members'}}, $also);
			push(@{$dir->{'members'}}, 
				{ 'name' => 'notify',
				  'values' => [ 'yes' ] });
			}
		}

	# Allow only localhost and slaves to transfer
	local @trans = ( { 'name' => '127.0.0.1' },
			 { 'name' => 'localnets' }, );
	foreach my $s (@slaves) {
		push(@trans, { 'name' => &to_ipaddress($s->{'host'}) });
		my $s6 = &to_ip6address($s->{'host'});
		if ($s6) {
			push(@trans, { 'name' => $s6 });
			}
		}
	foreach my $s (@extra_slaves) {
		push(@trans, { 'name' => &to_ipaddress($s) });
		my $s6 = &to_ip6address($s);
		if ($s6) {
			push(@trans, { 'name' => $s6 });
			}
		}
	@trans = grep { $_->{'name'} } @trans;
	local ($trans) = grep { $_->{'name'} eq 'allow-transfer' }
			      @{$dir->{'members'}};
	if (!$trans && !$tmpl->{'namedconf_no_allow_transfer'}) {
		$trans = { 'name' => 'allow-transfer',
			   'type' => 1,
			   'members' => \@trans };
		push(@{$dir->{'members'}}, $trans);
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
			if ($bind8::config{'zones_file'} &&
			    $view->{'file'} ne $bind8::config{'zones_file'}) {
				# BIND module config asks for a file .. make
				# sure it is included in the view
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
			$_[0]->{'dns_view'} = $tmpl->{'dns_view'};
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
	&bind8::save_directive($pconf, undef, [ $dir ], $indent);
	&flush_file_lines();
	unlink($bind8::zone_names_cache);
	undef(@bind8::list_zone_names_cache);
	undef(@bind8::get_config_cache);

	# Work out if can copy from alias target - not possible if target
	# is a sub-domain, as they don't have their own domain. Also not
	# possible if target uses another domain's zone file to store its
	# records.
	local $copyfromalias = 0;
	if ($_[0]->{'alias'}) {
		local $target = &get_domain($_[0]->{'alias'});
		if ($target && !$target->{'subdom'} &&
		    !$target->{'dns_submode'}) {
			$copyfromalias = 1;
			}
		}

	# Create the records file
	local $rootfile = &bind8::make_chroot($file);
	if (!-r $rootfile) {
		if ($copyfromalias) {
			&create_alias_records($file, $_[0], $ip);
			}
		else {
			&create_standard_records($file, $_[0], $ip);
			}
		&bind8::set_ownership($rootfile);
		}
	&$second_print($text{'setup_done'});

	# If DNSSEC was requested, set it up
	if ($tmpl->{'dnssec'} eq 'yes') {
		&$first_print($text{'setup_dnssec'});
		local $zone = &get_bind_zone($_[0]->{'dom'});
		if (!defined(&bind8::supports_dnssec) ||
		    !&bind8::supports_dnssec()) {
			# Not supported
			&$second_print($text{'setup_enodnssec'});
			}
		else {
			local ($ok, $size) = &bind8::compute_dnssec_key_size(
				$tmpl->{'dnssec_alg'}, 1);
			local $err;
			if (!$ok) {
				# Key size failed
				&$second_print(
					&text('setup_ednssecsize', $size));
				}
			elsif ($err = &bind8::create_dnssec_key(
					$zone, $tmpl->{'dnssec_alg'}, $size,
					$tmpl->{'dnssec_single'})) {
				# Key generation failed
				&$second_print(
					&text('setup_ednsseckey', $err));
				}
			elsif ($err = &bind8::sign_dnssec_zone($zone)) {
				# Zone signing failed
				&$second_print(
					&text('setup_ednssecsign', $err));
				}
			else {
				# All done!
				&$second_print($text{'setup_done'});
				}
			}
		}

	# Create on slave servers
	local $myip = $bconfig{'this_ip'} ||
		      &to_ipaddress(&get_system_hostname());
	if (@slaves && !$_[0]->{'noslaves'}) {
		local $slaves = join(" ", map { $_->{'nsname'} ||
						$_->{'host'} } @slaves);
		&create_zone_on_slaves($_[0], $slaves);
		}

	# If website has a *.domain.com ServerAlias, add * DNS record now
	if ($_[0]->{'web'} && &get_domain_web_star($_[0])) {
		&save_domain_matchall_record($_[0], 1);
		}

	&release_lock_dns($_[0], 1);
	}
else {
	# Creating a sub-domain - add to parent's DNS zone.
	# This only happens if the parent zone has the same owner, and this
	# feature is enabled in templates, and this zone isn't an alias.
	local $parent = &get_domain($_[0]->{'subdom'}) ||
			&get_domain($_[0]->{'parent'});
	&$first_print(&text('setup_bindsub', $parent->{'dom'}));
	&obtain_lock_dns($parent);
	local $z = &get_bind_zone($parent->{'dom'});
	if (!$z) {
		&error(&text('setup_ednssub', $parent->{'dom'}));
		}
	local $file = &bind8::find("file", $z->{'members'});
	local $fn = $file->{'values'}->[0];
	local @recs = &bind8::read_zone_file($fn, $parent->{'dom'});
	$_[0]->{'dns_submode'} = 1;	# So we know how this was done
	local ($already) = grep { $_->{'name'} eq $_[0]->{'dom'}."." }
				grep { $_->{'type'} eq 'A' } @recs;
	if ($already) {
		# A record with the same name as the sub-domain exists .. we
		# don't want to delete this later
		$_[0]->{'dns_subalready'} = 1;
		}
	local $ip = $_[0]->{'dns_ip'} || $_[0]->{'ip'};
	&create_standard_records($fn, $_[0], $ip);
	&post_records_change($parent, \@recs);

	&release_lock_dns($parent);
	&$second_print($text{'setup_done'});
	}
&register_post_action(\&restart_bind, $_[0]);
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
if ($_[0]->{'provision_dns'}) {
	# Delete from provisioning server
	&$first_print($text{'delete_bind_provision'});
	if ($_[0]->{'provision_dns_host'}) {
		local $info = { 'domain' => $_[0]->{'dom'},
				'host' => $_[0]->{'provision_dns_host'} };
		my ($ok, $msg) = &provision_api_call(
			"unprovision-dns-zone", $info, 0);
		if (!$ok) {
			&$second_print(&text('delete_ebind_provision', $msg));
			return 0;
			}
		delete($_[0]->{'provision_dns_host'});
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'delete_bind_provision_none'});
		}
	}
elsif (!$_[0]->{'dns_submode'}) {
	# Delete real domain
	&$first_print($text{'delete_bind'});
	&obtain_lock_dns($_[0], 1);
	local $z = &get_bind_zone($_[0]->{'dom'});
	if ($z) {
		# Delete any dnssec key
		if (defined(&bind8::supports_dnssec) &&
		    &bind8::supports_dnssec()) {
			&bind8::delete_dnssec_key($z);
			}

		# Delete the records file
		local $file = &bind8::find("file", $z->{'members'});
		if ($file) {
			local $zonefile =
			    &bind8::make_chroot($file->{'values'}->[0]);
			&unlink_file($zonefile);
			local $logfile = $zonefile.".log";
			if (!-r $logfile) { $logfile = $zonefile.".jnl"; }
			if (-r $logfile) {
				&unlink_logged($logfile);
				}
			}

		# Delete from named.conf
		local $rootfile = &bind8::make_chroot($z->{'file'});
		local $lref = &read_file_lines($rootfile);
		splice(@$lref, $z->{'line'}, $z->{'eline'} - $z->{'line'} + 1);
		&flush_file_lines($rootfile);

		# Clear zone names caches
		unlink($bind8::zone_names_cache);
		undef(@bind8::list_zone_names_cache);
		undef(@bind8::get_config_cache);
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'save_nobind'});
		}

	&delete_zone_on_slaves($_[0]);
	&release_lock_dns($_[0], 1);
	}
else {
	# Delete records from parent zone
	local $parent = &get_domain($_[0]->{'subdom'}) ||
			&get_domain($_[0]->{'parent'});
	&$first_print(&text('delete_bindsub', $parent->{'dom'}));
	&obtain_lock_dns($parent);
	local $z = &get_bind_zone($parent->{'dom'});
	if (!$z) {
		&$second_print($text{'save_nobind'});
		return;
		}
	local $file = &bind8::find("file", $z->{'members'});
	local $fn = $file->{'values'}->[0];
	local @recs = &bind8::read_zone_file($fn, $parent->{'dom'});
	local $withdot = $_[0]->{'dom'}.".";
	foreach $r (reverse(@recs)) {
		# Don't delete if outside sub-domain
		next if ($r->{'name'} !~ /\Q$withdot\E$/);
		# Don't delete if the same as an existing record
		next if ($r->{'name'} eq $withdot && $r->{'type'} eq 'A' &&
			 $_[0]->{'dns_subalready'});
		&bind8::delete_record($fn, $r);
		}
	&post_records_change($parent, \@recs);
	&release_lock_dns($parent);
	&$second_print($text{'setup_done'});
	$_[0]->{'dns_submode'} = 0;
	}
&register_post_action(\&restart_bind, $_[0]);
}

# clone_dns(&domain, &old-domain)
# Copy all DNS records to a new domain
sub clone_dns
{
local ($d, $oldd) = @_;
&$first_print($text{'clone_dns'});
if ($d->{'dns_submode'}) {
	# Record cloning not supported for DNS sub-domains
	&$second_print($text{'clone_dnssub'});
	return 1;
	}
local ($orecs, $ofile) = &get_domain_dns_records_and_file($oldd);
local ($recs, $file) = &get_domain_dns_records_and_file($d);
if (!$orecs) {
	&$second_print($text{'clone_dnsold'});
	return 0;
	}
if (!$recs) {
	&$second_print($text{'clone_dnsnew'});
	return 0;
	}
&obtain_lock_dns($d);

# Copy over the records file
local $absfile = &bind8::make_chroot($file);
local $absofile = &bind8::make_chroot($ofile);
&copy_source_dest($absofile, $absfile);
$recs = [ &bind8::read_zone_file($file, $d->{'dom'}) ];
&modify_records_domain_name($recs, $file, $oldd->{'dom'}, $d->{'dom'});
local $oldip = $oldd->{'dns_ip'} || $oldd->{'ip'};
local $newip = $d->{'dns_ip'} || $d->{'ip'};
if ($oldip ne $newip) {
	&modify_records_ip_address($recs, $file, $oldip, $newip);
	}
if ($d->{'ip6'} && $d->{'ip6'} ne $oldd->{'ip6'}) {
	&modify_records_ip_address($recs, $file, $oldd->{'ip6'}, $d->{'ip6'});
	}

# Find and delete sub-domain records
local @sublist = grep { $_->{'id'} ne $oldd->{'id'} &&
			$_->{'dom'} =~ /\.\Q$oldd->{'dom'}\E$/ }
		      &list_domains();
foreach my $r (reverse(@$recs)) {
	foreach my $sd (@sublist) {
		if ($r->{'name'} eq $sd->{'dom'}."." ||
		    $r->{'name'} =~ /\.\Q$sd->{'dom'}\E\.$/) {
			&bind8::delete_record($file, $r);
			}
		}
	}

&post_records_change($d, $recs, $file);
&release_lock_dns($d);
&register_post_action(\&restart_bind, $_[0]);
&$second_print($text{'setup_done'});
return 1;
}

# create_zone_on_slaves(&domain, space-separate-slave-list)
# Create a zone on all specified slaves, and updates the dns_slave key.
# May print messages.
sub create_zone_on_slaves
{
local ($d, $slaves) = @_;
&require_bind();
local $myip = $bconfig{'this_ip'} ||
	      &to_ipaddress(&get_system_hostname());
&$first_print(&text('setup_bindslave', $slaves));
local @slaveerrs = &bind8::create_on_slaves(
	$d->{'dom'}, $myip, undef, $slaves,
	$d->{'dns_view'} || $tmpl->{'dns_view'});
if (@slaveerrs) {
	&$second_print($text{'setup_eslaves'});
	foreach my $sr (@slaveerrs) {
		&$second_print(
		  ($sr->[0]->{'nsname'} || $sr->[0]->{'host'}).
		  " : ".$sr->[1]);
		}
	}
else {
	&$second_print($text{'setup_done'});
	}

# Add to list of slaves where it succeeded
local @newslaves;
foreach my $s (split(/\s+/, $slaves)) {
	local ($err) = grep { $_->[0]->{'host'} eq $s } @slaveerrs;
	if (!$err) {
		push(@newslaves, $s);
		}
	}
local @oldslaves = split(/\s+/, $d->{'dns_slave'});
$d->{'dns_slave'} = join(" ", &unique(@oldslaves, @newslaves));

&register_post_action(\&restart_bind, $d);
}

# delete_zone_on_slaves(&domain, [space-separate-slave-list])
# Delete a zone on all slave servers, from the dns_slave key. May print messages
sub delete_zone_on_slaves
{
local ($d, $slaveslist) = @_;
local @delslaves = $slaveslist ? split(/\s+/, $slaveslist)
			       : split(/\s+/, $d->{'dns_slave'});
&require_bind();
if (@delslaves) {
	# Delete from slave servers
	&$first_print(&text('delete_bindslave', join(" ", @delslaves)));
	local $tmpl = &get_template($d->{'template'});
	local @slaveerrs = &bind8::delete_on_slaves(
			$d->{'dom'}, \@delslaves,
			$d->{'dns_view'} || $tmpl->{'dns_view'});
	if (@slaveerrs) {
		&$second_print($text{'delete_bindeslave'});
		foreach my $sr (@slaveerrs) {
			&$second_print(
			  ($sr->[0]->{'nsname'} || $sr->[0]->{'host'}).
			  " : ".$sr->[1]);
			}
		}
	else {
		&$second_print($text{'setup_done'});
		}

	# Update domain data
	my @newslaves;
	if ($slaveslist) {
		foreach my $s (split(/\s+/, $d->{'dns_slave'})) {
			if (&indexof($s, @delslaves) < 0) {
				push(@newslaves, $s);
				}
			}
		}
	if (@newslaves) {
		$d->{'dns_slave'} = join(" ", @newslaves);
		}
	else {
		delete($d->{'dns_slave'});
		}
	}

&register_post_action(\&restart_bind, $d);
}

# exists_on_slave(zone-name, &slave)
# Returns "OK" if some zone exists on the given DNS slave, undef if not, or
# an error message otherwise.
sub exists_on_slave
{
my ($name, $slave) = @_;
&remote_error_setup(\&bind8::slave_error_handler);
&remote_foreign_require($slave, "bind8", "bind8-lib.pl");
return $bind8::slave_error if ($bind8::slave_error);
my $z = &remote_foreign_call($slave, "bind8", "get_zone_name", $name, "any");
return $z ? "OK" : undef;
}

# modify_dns(&domain, &olddomain)
# If the IP for this server has changed, update all records containing the old
# IP to the new.
sub modify_dns
{
if (!$_[0]->{'subdom'} && $_[1]->{'subdom'} && $_[0]->{'dns_submode'} ||
    !&under_parent_domain($_[0]) && $_[0]->{'dns_submode'}) {
	# Converting from a sub-domain to top-level .. just delete and re-create
	&delete_dns($_[1]);
	delete($_[0]->{'dns_submode'});
	&setup_dns($_[0]);
	return 1;
	}

&require_bind();
local $tmpl = &get_template($_[0]->{'template'});
local ($oldzonename, $newzonename, $lockon, $lockconf, $zdom);
if ($_[0]->{'dns_submode'}) {
	# Get parent domain
	local $parent = &get_domain($_[0]->{'subdom'}) ||
			&get_domain($_[0]->{'parent'});
	&obtain_lock_dns($parent);
	$lockon = $parent;
	$zdom = $parent;
	$oldzonename = $newzonename = $parent->{'dom'};
	}
else {
	# Get this domain
	&obtain_lock_dns($_[0], 1);
	$lockon = $_[0];
	$lockconf = 1;
	$zdom = $_[1];
	$newzonename = $_[1]->{'dom'};
	$oldzonename = $_[1]->{'dom'};
	}
local $oldip = $_[1]->{'dns_ip'} || $_[1]->{'ip'};
local $newip = $_[0]->{'dns_ip'} || $_[0]->{'ip'};
local $rv = 0;

# Zone file name and records, if we read them
local ($file, $recs);

if ($_[0]->{'dom'} ne $_[1]->{'dom'} && $_[0]->{'provision_dns'}) {
	# Domain name has changed .. rename via API call
	&$first_print($text{'save_dns2_provision'});
	local $info = { 'domain' => $_[1]->{'dom'},
			'host' => $_[0]->{'provision_dns_host'},
			'new-domain' => $_[0]->{'dom'} };
	my ($ok, $msg) = &provision_api_call("modify-dns-zone", $info, 0);
	if (!$ok) {
		&$second_print(&text('disable_ebind_provision', $msg));
		return 0;
		}
	&$second_print($text{'setup_done'});

	# Rename records
	($recs, $file) = &get_domain_dns_records_and_file($_[0]) if (!$file);
	if (!$file) {
		&$second_print($text{'save_nobind'});
		&release_lock_dns($lockon, $lockconf);
		return 0;
		}
	&modify_records_domain_name($recs, $file,
				    $_[1]->{'dom'}, $_[0]->{'dom'});
	}
elsif ($_[0]->{'dom'} ne $_[1]->{'dom'} && !$_[0]->{'provision_dns'}) {
	# Domain name has changed .. rename locally
	local $z = &get_bind_zone($zdom->{'dom'});
	if (!$z) {
		# Zone not found!
		&$second_print($text{'save_dns2_ezone'});
		&release_lock_dns($lockon, $lockconf);
		return 0;
		}
	local $nfn;
	local $file = &bind8::find("file", $z->{'members'});
	if (!$_[0]->{'dns_submode'}) {
		# Domain name has changed .. rename zone file
		&$first_print($text{'save_dns2'});
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
		}
	else {
		&$first_print($text{'save_dns6'});
		$nfn = $file->{'values'}->[0];
		}

	# Modify any records containing the old name
	&lock_file(&bind8::make_chroot($nfn));
        local @recs = &bind8::read_zone_file($nfn, $oldzonename);
	&modify_records_domain_name(\@recs, $nfn,
				    $_[1]->{'dom'}, $_[0]->{'dom'});

        # Update SOA record
	&post_records_change($_[0], \@recs);
	$recs = \@recs;
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
					&$second_print(
					  ($sr->[0]->{'nsname'} ||
					   $sr->[0]->{'host'})." : ".$sr->[1]);
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
	($recs, $file) = &get_domain_dns_records_and_file($_[0]) if (!$file);
	if (!$file) {
		&$second_print($text{'save_nobind'});
		&release_lock_dns($lockon, $lockconf);
		return 0;
		}
	&modify_records_ip_address($recs, $file, $oldip, $newip,
				   $_[0]->{'dom'});
	$rv++;
	&$second_print($text{'setup_done'});
	}

if ($_[0]->{'mail'} && !$_[1]->{'mail'} && !$tmpl->{'dns_replace'}) {
	# Email was enabled .. add MX records
	($recs, $file) = &get_domain_dns_records_and_file($_[0]) if (!$file);
	if (!$file) {
		&$second_print($text{'save_nobind'});
		&release_lock_dns($lockon, $lockconf);
		return 0;
		}
	local ($mx) = grep { $_->{'type'} eq 'MX' &&
			     $_->{'name'} eq $_[0]->{'dom'}."." ||
			     $_->{'type'} eq 'A' &&
			     $_->{'name'} eq "mail.".$_[0]->{'dom'}."."} @$recs;
	if (!$mx) {
		&$first_print($text{'save_dns4'});
		local $ip = $_[0]->{'dns_ip'} || $_[0]->{'ip'};
		local $ip6 = $_[0]->{'ip6'};
		&create_mx_records($file, $_[0], $ip, $ip6);
		&$second_print($text{'setup_done'});
		$rv++;
		}
	}
elsif (!$_[0]->{'mail'} && $_[1]->{'mail'} && !$tmpl->{'dns_replace'}) {
	# Email was disabled .. remove MX records, but only those that
	# point to this system or secondaries.
	($recs, $file) = &get_domain_dns_records_and_file($_[0]) if (!$file);
	if (!$file) {
		&$second_print($text{'save_nobind'});
		&release_lock_dns($lockon, $lockconf);
		return 0;
		}
	local $ip = $_[0]->{'dns_ip'} || $_[0]->{'ip'};
	local $ip6 = $_[0]->{'ip6'};
	local %ids = map { $_, 1 }
		split(/\s+/, $_[0]->{'mx_servers'});
	local @slaves = grep { $ids{$_->{'id'}} } &list_mx_servers();
	local @slaveips = map { &to_ipaddress($_->{'mxname'} || $_->{'host'}) }
			      @slaves;
	foreach my $r (@$recs) {
		if ($r->{'type'} eq 'A' &&
		    $r->{'name'} eq "mail.".$_[0]->{'dom'}."." &&
		    $r->{'values'}->[0] eq $ip) {
			# mail.domain A record, pointing to our IP
			push(@mx, $r);
			}
		elsif ($r->{'type'} eq 'AAAA' &&
		       $r->{'name'} eq "mail.".$_[0]->{'dom'}."." &&
		       $r->{'values'}->[0] eq $ip6) {
			# mail.domain AAAA record, pointing to our IP
			push(@mx, $r);
			}
		elsif ($r->{'type'} eq 'MX' &&
		       $r->{'name'} eq $_[0]->{'dom'}.".") {
			# MX record for domain .. does it point to our IP?
			local $mxip = &to_ipaddress($r->{'values'}->[1]);
			if ($mxip eq $ip || &indexof($mxip, @slaveips) >= 0) {
				push(@mx, $r);
				}
			}
		}
	if (@mx) {
		&$first_print($text{'save_dns5'});
		foreach my $r (reverse(@mx)) {
			&bind8::delete_record($file, $r);
			}
		&$second_print($text{'setup_done'});
		$rv++;
		}
	}

if ($_[0]->{'mx_servers'} ne $_[1]->{'mx_servers'} && $_[0]->{'mail'} &&
    !$config{'secmx_nodns'}) {
	# Secondary MX servers have been changed - add or remove MX records
	&$first_print($text{'save_dns7'});
	($recs, $file) = &get_domain_dns_records_and_file($_[0]) if (!$file);
	if (!$file) {
		&$second_print($text{'save_nobind'});
		&release_lock_dns($lockon, $lockconf);
		return 0;
		}
	local @newmxs = split(/\s+/, $_[0]->{'mx_servers'});
	local @oldmxs = split(/\s+/, $_[1]->{'mx_servers'});
	&foreign_require("servers", "servers-lib.pl");
	local %servers = map { $_->{'id'}, $_ }
			     (&servers::list_servers(), &list_mx_servers());
	local $withdot = $_[0]->{'dom'}.".";

	# Add missing MX records
	foreach my $id (@newmxs) {
		if (&indexof($id, @oldmxs) < 0) {
			# A new MX .. add a record for it, if there isn't one
			local $s = $servers{$id};
			local $mxhost = $s->{'mxname'} || $s->{'host'};
			local $already = 0;
			foreach my $r (@$recs) {
				if ($r->{'type'} eq 'MX' &&
				    $r->{'name'} eq $withdot &&
				    $r->{'values'}->[1] eq $mxhost.".") {
					$already = 1;
					}
				}
			if (!$already) {
				&bind8::create_record($file, $withdot, undef,
					      "IN", "MX", "10 $mxhost.");
				}
			}
		}

	# Remove those that are no longer needed
	local @mxs;
	foreach my $id (@oldmxs) {
		if (&indexof($id, @newmxs) < 0) {
			# An old MX .. remove it
			local $s = $servers{$id};
			local $mxhost = $s->{'mxname'} || $s->{'host'};
			foreach my $r (@$recs) {
				if ($r->{'type'} eq 'MX' &&
				    $r->{'name'} eq $withdot &&
				    $r->{'values'}->[1] eq $mxhost.".") {
					push(@mxs, $r);
					}
				}
			}
		}
	foreach my $r (reverse(@mxs)) {
		&bind8::delete_record($file, $r);
		}

	&$second_print($text{'setup_done'});
	$rv++;
	}

if ($_[0]->{'ip6'} && !$_[1]->{'ip6'}) {
	# IPv6 enabled
	&$first_print($text{'save_dnsip6on'});
	($recs, $file) = &get_domain_dns_records_and_file($_[0]) if (!$file);
	if (!$file) {
		&$second_print($text{'save_nobind'});
		&release_lock_dns($lockon, $lockconf);
		return 0;
		}
	&add_ip6_records($_[0], $file);
	&$second_print($text{'setup_done'});
	$rv++;
	}
elsif (!$_[0]->{'ip6'} && $_[1]->{'ip6'}) {
	# IPv6 disabled
	&$first_print($text{'save_dnsip6off'});
	($recs, $file) = &get_domain_dns_records_and_file($_[0]) if (!$file);
	if (!$file) {
		&$second_print($text{'save_nobind'});
		&release_lock_dns($lockon, $lockconf);
		return 0;
		}
	&remove_ip6_records($_[1], $file);
	&$second_print($text{'setup_done'});
	$rv++;
	}
elsif ($_[0]->{'ip6'} && $_[1]->{'ip6'} &&
       $_[0]->{'ip6'} ne $_[1]->{'ip6'}) {
	# IPv6 address changed
	&$first_print($text{'save_dnsip6'});
	($recs, $file) = &get_domain_dns_records_and_file($_[0]) if (!$file);
	if (!$file) {
		&$second_print($text{'save_nobind'});
		&release_lock_dns($lockon, $lockconf);
		return 0;
		}
	&modify_records_ip_address($recs, $file, $_[1]->{'ip6'}, $_[0]->{'ip6'},
				   $_[0]->{'dom'});
	$rv++;
	&$second_print($text{'setup_done'});
	}

# Update SOA and upload records to provisioning server
if ($file) {
	&post_records_change($_[0], $recs, $file);
	}

# Release locks
&release_lock_dns($lockon, $lockconf);

&register_post_action(\&restart_bind, $_[0]) if ($rv);
return $rv;
}

# join_record_values(&record, [always-one-line])
# Given the values for a record, joins them into a space-separated string
# with quoting if needed
sub join_record_values
{
local ($r, $oneline) = @_;
if ($r->{'type'} eq 'SOA' && !$oneline) {
	# Multiliple lines, with brackets
	local $v = $r->{'values'};
	local $sep = "\n\t\t\t";
	return "$v->[0] $v->[1] ($sep$v->[2]$sep$v->[3]".
	       "$sep$v->[4]$sep$v->[5]$sep$v->[6] )";
	}
else {
	# All one one line
	local @rv;
	foreach my $v (@{$r->{'values'}}) {
		push(@rv, $v =~ /\s/ ? "\"$v\"" : $v);
		}
	return join(" ", @rv);
	}
}

# split_long_txt_record(string)
# Split a TXT record at 80 char boundaries
sub split_long_txt_record
{
local ($str) = @_;
$str =~ s/^"//;
$str =~ s/"$//;
local @rv;
while($str) {
	local $first = substr($str, 0, 80);
	$str = substr($str, 80);
	push(@rv, $first);
	}
return "( ".join("\n\t", map { '"'.$_.'"' } @rv)." )";
}

# create_mx_records(file, &domain, ip, ip6)
# Adds MX records to a DNS domain
sub create_mx_records
{
local ($file, $d, $ip, $ip6) = @_;
local $withdot = $d->{'dom'}.".";
&bind8::create_record($file, "mail.$withdot", undef,
		      "IN", "A", $ip);
if ($d->{'ip6'} && $ip6) {
	&bind8::create_record($file, "mail.$withdot", undef,
			      "IN", "AAAA", $ip6);
	}
&bind8::create_record($file, $withdot, undef,
		      "IN", "MX", "5 mail.$withdot");

# Add MX records for slaves, if enabled
if (!$config{'secmx_nodns'}) {
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
}

# create_standard_records(file, &domain, ip)
# Adds to a records file the needed records for some domain
sub create_standard_records
{
local ($file, $d, $ip) = @_;
&require_bind();
local $rootfile = &bind8::make_chroot($file);
local $tmpl = &get_template($d->{'template'});
local $serial = $bconfig{'soa_style'} ?
	&bind8::date_serial().sprintf("%2.2d", $bconfig{'soa_start'}) :
	time();
local %zd;
&bind8::get_zone_defaults(\%zd);
local @created_ns;
if (!$tmpl->{'dns_replace'} || $d->{'dns_submode'}) {
	# Create records that are appropriate for this domain, as long as the
	# user hasn't selected a completely custom template, or records are
	# being added to an existing domain
	if (!$d->{'dns_submode'}) {
		# Only add SOA and NS if this is a new file, not a sub-domain
		# in an existing file
		&open_tempfile(RECS, ">$rootfile");
		if ($bconfig{'master_ttl'}) {
			# Add a default TTL
			if ($tmpl->{'dns_ttl'} eq '') {
				&print_tempfile(RECS,
				    "\$ttl $zd{'minimum'}$zd{'minunit'}\n");
				}
			elsif ($tmpl->{'dns_ttl'} ne 'none') {
				&print_tempfile(RECS,
				    "\$ttl $tmpl->{'dns_ttl'}\n");
				}
			}
		&close_tempfile(RECS);
		local $master = &get_master_nameserver($tmpl);
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

		# Get nameservers from reseller, if any
		my @reselns;
		if ($d->{'reseller'} && defined(&get_reseller)) {
			my $resel = &get_reseller($d->{'reseller'});
			if ($resel->{'acl'}->{'defns'}) {
				@reselns = split(/\s+/,
					$resel->{'acl'}->{'defns'});
				}
			}

		if (@reselns) {
			# NS records come from reseller
			foreach my $ns (@reselns) {
				$ns .= "." if ($ns !~ /\.$/);
				&bind8::create_record($file, "@", undef, "IN",
						      "NS", $ns);
				push(@created_ns, $ns);
				}
			}
		else {
			# Add NS records for master and auto-configured slaves
			if ($tmpl->{'dns_prins'}) {
				&bind8::create_record($file, "@", undef, "IN",
						      "NS", $master);
				push(@created_ns, $master);
				}
			local $slave;
			local @slaves = &bind8::list_slave_servers();
			foreach $slave (@slaves) {
				local @bn = $slave->{'nsname'} ?
						( $slave->{'nsname'} ) :
						gethostbyname($slave->{'host'});
				if ($bn[0]) {
					local $full = "$bn[0].";
					&bind8::create_record(
						$file, "@", undef, "IN",
						"NS", $bn[0].".");
					push(@created_ns, $bn[0].".");
					}
				}

			# Add NS records from template
			foreach my $ns (&get_slave_nameservers($tmpl)) {
				&bind8::create_record($file, "@", undef, "IN",
						      "NS", $ns);
				push(@created_ns, $ns);
				}
			}
		}
	
	# Work out which records are already in the file
	local $rd = $d;
	if ($d->{'dns_submode'}) {
		$rd = &get_domain($d->{'subdom'}) ||
		      &get_domain($d->{'parent'});
		}
	local %already = map { $_->{'name'}, $_ }
			     grep { $_->{'type'} eq 'A' }
				  &bind8::read_zone_file($file, $rd->{'dom'});

	# Work out which records to add
	local $withdot = $d->{'dom'}.".";
	local @addrecs = split(/\s+/, $tmpl->{'dns_records'});
	if (!@addrecs || $addrecs[0] eq 'none') {
		@addrecs = @automatic_dns_records;
		}
	local %addrecs = map { $_ eq "@" ? $withdot : $_.".".$withdot, 1 }
			     @addrecs;
	delete($addrescs{'noneselected'});

	# Add standard records we don't have yet
	foreach my $n ($withdot, "www.$withdot", "ftp.$withdot", "m.$withdot") {
		if (!$already{$n} && $addrecs{$n}) {
			&bind8::create_record($file, $n, undef,
					      "IN", "A", $ip);
			}
		}

	# If the master NS is in this zone and there is no A for it yet, add now
	foreach my $ns (@created_ns) {
		if ($ns !~ /\.$/) {
			$ns .= ".".$withdot;
			}
		if ($ns =~ /^([^\.]+)\.(\S+\.)$/ && $2 eq $withdot &&
		    !$already{$ns}) {
			&bind8::create_record($file, $ns, undef,
					      "IN", "A", $ip);
			}
		}

	# Add the localhost record - yes, I know it's lame, but some
	# registrars require it!
	local $n = "localhost.$withdot";
	if (!$already{$n} && $addrecs{$n}) {
		&bind8::create_record($file, $n, undef,
				      "IN", "A", "127.0.0.1");
		}

	# If requested, add webmail and admin records
	if ($d->{'web'} && &has_webmail_rewrite($d)) {
		&add_webmail_dns_records_to_file($d, $tmpl, $file, \%already);
		}

	# For mail domains, add MX to this server. Any IPv6 AAAA record is
	# cloned later
	if ($d->{'mail'}) {
		&create_mx_records($file, $d, $ip, undef);
		}

	# Add SPF record for domain, if defined and if it's not a sub-domain
	if ($tmpl->{'dns_spf'} ne "none" &&
	    !$d->{'dns_submode'}) {
		local $str = &bind8::join_spf(&default_domain_spf($d));
		&bind8::create_record($file, $withdot, undef,
				      "IN", "TXT", "\"$str\"");
		if ($bind8::config{'spf_record'}) {
			&bind8::create_record($file, $withdot, undef,
					      "IN", "SPF", "\"$str\"");
			}
		}
	}

if ($tmpl->{'dns'} && (!$d->{'dns_submode'} || !$tmpl->{'dns_replace'})) {
	# Add or use the user-defined records template, if defined and if this
	# isn't a sub-domain being added to an existing file OR if we are just
	# adding records
	&open_tempfile(RECS, ">>$rootfile");
	local %subs = %$d;
	$subs{'serial'} = $serial;
	$subs{'dnsemail'} = $d->{'emailto_addr'};
	$subs{'dnsemail'} =~ s/\@/./g;
	local $recs = &substitute_domain_template(
		join("\n", split(/\t+/, $tmpl->{'dns'}))."\n", \%subs);
	&print_tempfile(RECS, $recs);
	&close_tempfile(RECS);
	}

if ($d->{'ip6'}) {
	# Create IPv6 records for IPv4
	&add_ip6_records($d, $file);
	}
}

# create_alias_records(file, &domain, ip)
# For a domain that is an alias, copy records from its target
sub create_alias_records
{
local ($file, $d, $ip) = @_;
local $tmpl = &get_template($d->{'template'});
local $aliasd = &get_domain($d->{'alias'});
local ($recs, $aliasfile) = &get_domain_dns_records_and_file($aliasd);
$aliasfile || &error("No zone file for alias target $aliasd->{'dom'} found");
@$recs || &error("No records for alias target $aliasd->{'dom'} found");
local $olddom = $aliasd->{'dom'};
local $dom = $d->{'dom'};
local $oldip = $aliasd->{'ip'};
local @sublist = grep { $_->{'id'} ne $aliasd->{'id'} &&
			$_->{'dom'} =~ /\.\Q$aliasd->{'dom'}\E$/ }
		      &list_domains();
RECORD: foreach my $r (@$recs) {
	if ($d->{'dns_submode'} && ($r->{'type'} eq 'NS' || 
				    $r->{'type'} eq 'SOA')) {
		# Skip SOA and NS records for sub-domains in the same file
		next;
		}
	if ($r->{'type'} eq 'NSEC' || $r->{'type'} eq 'NSEC3' ||
	    $r->{'type'} eq 'RRSIG' || $r->{'type'} eq 'DNSKEY') {
		# Skip DNSSEC records, as they get re-generated
		next;
		}
	if ($r->{'defttl'}) {
		# Add default TTL
		&bind8::create_defttl($file, $r->{'defttl'});
		next;
		}
	if (!$r->{'type'}) {
		# Skip special directives, like $generate
		next;
		}
	foreach my $sd (@sublist) {
		if ($r->{'name'} eq $sd->{'dom'}."." ||
		    $r->{'name'} =~ /\.\Q$sd->{'dom'}\E\.$/) {
			# Skip records in sub-domains of the source
			next RECORD;
			}
		}
	$r->{'name'} =~ s/\Q$olddom\E\.$/$dom\./i;

	# Change domain name to alias in record values, unless it is an NS
	# that is set in the template
	my %tmplns;
	my $master = &get_master_nameserver($tmpl);
	$tmplns{$master} = 1;
	foreach my $ns (&get_slave_nameservers($tmpl)) {
		$tmplns{$ns} = 1;
		}
	if ($r->{'type'} ne 'NS' || !$tmplns{$r->{'values'}->[0]}) {
		foreach my $v (@{$r->{'values'}}) {
			$v =~ s/\Q$olddom\E/$dom/i;
			$v =~ s/\Q$oldip\E$/$ip/i;
			}
		}
	my $str;
	my $joined = join("", @{$r->{'values'}});
	if ($r->{'type'} eq 'TXT' && length($joined) > 80) {
		$str = &split_long_txt_record($joined);
		}
	else {
		$str = &join_record_values($r);
		}
	&bind8::create_record($file, $r->{'name'}, $r->{'ttl'},
			      'IN', $r->{'type'}, $str);
	}
}

# get_master_nameserver(&template)
# Returns default primary NS name
sub get_master_nameserver
{
local ($tmpl) = @_;
&require_bind();
local $tmaster = $tmpl->{'dns_master'} eq 'none' ? undef :
			$tmpl->{'dns_master'};
local $master = $tmaster ||
		$bconfig{'default_prins'} ||
		&get_system_hostname();
$master .= "." if ($master !~ /\.$/);
return $master;
}

# get_slave_nameserver(&template)
# Returns default additional slave NS names
sub get_slave_nameservers
{
local ($tmpl) = @_;
local @rv;
foreach my $ns (split(/\s+/, $tmpl->{'dns_ns'})) {
	$ns .= "." if ($ns !~ /\.$/);
	push(@rv, $ns);
	}
return @rv;
}

# add_webmail_dns_records(&domain)
# Adds the webmail and admin DNS records, if requested in the template
sub add_webmail_dns_records
{
local ($d) = @_;
local $tmpl = &get_template($d->{'template'});
local ($recs, $file) = &get_domain_dns_records_and_file($d);
return 0 if (!$file);
local $count = &add_webmail_dns_records_to_file($d, $tmpl, $file);
if ($count) {
	&post_records_change($d, $recs, $file);
	&register_post_action(\&restart_bind, $d);
	}
return $count;
}

# add_webmail_dns_records_to_file(&domain, &tmpl, file, [&already-got])
# Adds the webmail and admin DNS records to a specific file, if requested
# in the template
sub add_webmail_dns_records_to_file
{
local ($d, $tmpl, $file, $already) = @_;
local $count = 0;
local $ip = $d->{'dns_ip'} || $d->{'ip'};
foreach my $r ('webmail', 'admin') {
	local $n = "$r.$d->{'dom'}.";
	if ($tmpl->{'web_'.$r} && (!$already || !$already->{$n})) {
		&bind8::create_record($file, $n, undef,
				      "IN", "A", $ip);
		$count++;
		}
	}
return $count;
}

# remove_webmail_dns_records(&domain)
# Remove the webmail and admin DNS records
sub remove_webmail_dns_records
{
local ($d) = @_;
local ($recs, $file) = &get_domain_dns_records_and_file($d);
return 0 if (!$file);
local $count = 0;
foreach my $r (reverse('webmail', 'admin')) {
	local $n = "$r.$d->{'dom'}.";
	local ($rec) = grep { $_->{'name'} eq $n } @$recs;
	if ($rec) {
		&bind8::delete_record($rec->{'file'}, $rec);
		$count++;
		}
	}
if ($count) {
	&post_records_change($d, $recs, $file);
	&register_post_action(\&restart_bind, $d);
	}
return $count;
}

# add_ip6_records(&domain, [file])
# For each A record for the domain whose value is it's IPv4 address, add an
# AAAA record with the v6 address.
sub add_ip6_records
{
local ($d, $file) = @_;
&require_bind();
$file ||= &get_domain_dns_file($d);
return 0 if (!$file);

# Work out which AAAA records we already have
local @recs = &bind8::read_zone_file($file, $d->{'dom'});
local %already;
foreach my $r (@recs) {
	if ($r->{'type'} eq 'AAAA' && $r->{'values'}->[0] eq $d->{'ip6'}) {
		$already{$r->{'name'}}++;
		}
	}

# Find all possible sub-domains, so we don't clone IPs for them
my @dnames;
foreach my $od (&list_domains()) {
	if ($od->{'dns'} && $od->{'id'} ne $d->{'id'} &&
	    $od->{'dom'} =~ /\.\Q$d->{'dom'}\E$/) {
		push(@dnames, $od->{'dom'});
		}
	}

# Clone A records
my $count = 0;
my $withdot = $d->{'dom'}.".";
foreach my $r (@recs) {
	if ($r->{'type'} eq 'A' && $r->{'values'}->[0] eq $d->{'ip'} &&
	    !$already{$r->{'name'}} &&
	    ($r->{'name'} eq $withdot || $r->{'name'} =~ /\.\Q$withdot\E$/)) {
		# Check if this record is in any sub-domain of this one
		my $insub = 0;
		foreach my $od (@dnames) {
			my $odwithdot = $od.".";
			if ($r->{'name'} eq $odwithdot ||
			    $r->{'name'} =~ /\.\Q$odwithdot\E$/) {
				$insub = 1;
				last;
				}
			}
		if (!$insub) {
			&bind8::create_record($file, $r->{'name'}, $r->{'ttl'},
					      'IN', 'AAAA', $d->{'ip6'});
			$count++;
			}
		}
	}

return $count;
}

# remove_ip6_records(&domain, [file], [&records])
# Delete all AAAA records whose value is the domain's IP6 address
sub remove_ip6_records
{
local ($d, $file, $recs) = @_;
&require_bind();
$file ||= &get_domain_dns_file($d);
return 0 if (!$file);
$recs ||= [ &bind8::read_zone_file($file, $d->{'dom'}) ];
my $withdot = $d->{'dom'}.".";
for(my $i=@$recs-1; $i>=0; $i--) {
	my $r = $recs->[$i];
	if ($r->{'type'} eq 'AAAA' && $r->{'values'}->[0] eq $d->{'ip6'} &&
	    ($r->{'name'} eq $withdot || $r->{'name'} =~ /\.\Q$withdot\E$/)) {
		&bind8::delete_record($file, $r);
		splice(@$recs, $i, 1);
		}
	}
}

# save_domain_matchall_record(&domain, star)
# Add or remove a *.domain.com wildcard DNS record, pointing to the main
# IP address. Used in conjuction with save_domain_web_star.
sub save_domain_matchall_record
{
local ($d, $star) = @_;
local ($recs, $file) = &get_domain_dns_records_and_file($d);
return 0 if (!$file);
local $withstar = "*.".$d->{'dom'}.".";
local ($r) = grep { $_->{'name'} eq $withstar } @$recs;
local $any = 0;
if ($star && !$r) {
	# Need to add
	my $ip = $d->{'dns_ip'} || $d->{'ip'};
	&bind8::create_record($file, $withstar, undef, "IN", "A", $ip);
	$any++;
	}
elsif (!$star && $r) {
	# Need to remove
	&bind8::delete_record($file, $r);
	$any++;
	}
if ($any) {
	my $err = &post_records_change($d, $recs, $file);
	return 0 if ($err);
	&register_post_action(\&restart_bind, $d);
	}
return $any;
}

# validate_dns(&domain, [&records], [records-only])
# Check for the DNS domain and records file
sub validate_dns
{
local ($d, $recs, $recsonly) = @_;
local $file;
if ($d->{'dns_submode'}) {
	# For a sub-domain, don't complain if parent is disabled
	my $parent = &get_domain($d->{'parent'});
	if ($parent && $parent->{'disabled'}) {
		return undef;
		}
	}
if (!$recs) {
	($recs, $file) = &get_domain_dns_records_and_file($d);
	return &text('validate_edns', "<tt>$d->{'dom'}</tt>") if (!$file);
	}
return &text('validate_ednsfile', "<tt>$d->{'dom'}</tt>") if (!@$recs);
local $absfile;
if (!$d->{'provision_dns'} && $file) {
	$absfile = &bind8::make_chroot(
				&bind8::absolute_path($file));
	return &text('validate_ednsfile2', "<tt>$absfile</tt>")
		if (!-r $absfile);
	}
if (!$d->{'provision_dns'} && !$d->{'dns_submode'}) {
	# Make sure it is a master
	local $zone = &get_bind_zone($d->{'dom'});
	return &text('validate_edns', "<tt>$d->{'dom'}</tt>") if (!$zone);
	local $type = &bind8::find_value("type", $zone->{'members'});
	return &text('validate_ednsnotype', "<tt>$d->{'dom'}</tt>") if (!$type);
	return &text('validate_ednstype', "<tt>$d->{'dom'}</tt>",
	     "<tt>$type</tt>", "<tt>master</tt>") if ($type ne "master");
	}

# Check for critical records, and that www.$dom and $dom resolve to the
# expected IP address (if we have a website)
if ($d->{'dns_submode'}) {
	# Only care about records within this domain
	$recs = [ grep { $_->{'name'} eq $d->{'dom'}.'.' ||
			 $_->{'name'} =~ /\.\Q$d->{'dom'}\E\.$/ } @$recs ];
	}
local %got;
local $ip = $d->{'dns_ip'} || $d->{'ip'};
foreach my $r (@$recs) {
	$got{uc($r->{'type'})}++;
	}
$d->{'dns_submode'} || $got{'SOA'} || return $text{'validate_ednssoa2'};
$got{'A'} || return $text{'validate_ednsa2'};
if (&domain_has_website($d)) {
	foreach my $n ($d->{'dom'}.'.', 'www.'.$d->{'dom'}.'.') {
		my @nips = map { $_->{'values'}->[0] }
			       grep { $_->{'type'} eq 'A' &&
				      $_->{'name'} eq $n } @$recs;
		if (@nips && &indexof($ip, @nips) < 0) {
			return &text('validate_ednsip', "<tt>$n</tt>",
			    "<tt>".join(' or ', @nips)."</tt>", "<tt>$ip</tt>");
			}
		}
	}

# If domain has email, make sure MX record points to this system
if ($d->{'mail'} && $config{'mx_validate'}) {
	local @mxs = grep { $_->{'name'} eq $d->{'dom'}.'.' &&
			    $_->{'type'} eq 'MX' } @$recs;
	local $defip = &get_default_ip();
	local %inuse = &interface_ip_addresses();
	if (@mxs) {
		local $found;
		local @mxips;
		foreach my $mx (@mxs) {
			local $mxh = $mx->{'values'}->[1];
			$mxh .= ".".$d->{'dom'} if ($mxh !~ /\.$/);
			$mxh =~ s/\.$//;
			local $ip = &to_ipaddress($mxh);
			if ($ip eq $d->{'ip'} ||
			    $ip eq $d->{'dns_ip'} ||
			    $ip eq $defip ||
			    $inuse{$ip}) {
				$found = $ip;
				last;
				}
			local ($arec) = grep { $_->{'name'} eq $mxh."." &&
					       $_->{'type'} eq 'A' } @$recs;
			if ($arec) {
				$ip = $arec->{'values'}->[0];
				if ($ip eq $d->{'ip'} ||
				    $ip eq $d->{'dns_ip'} ||
				    $ip eq $defip) {
					$found = $ip;
					last;
					}
				}
			push(@mxips, $mxh);
			}
		if (!$found) {
			return &text('validate_ednsmx', join(" ", @mxips));
			}
		}
	}

# If possible, run named-checkzone
if (defined(&bind8::supports_check_zone) && &bind8::supports_check_zone() &&
    !$d->{'provision_dns'} && !$d->{'dns_submode'} && !$recsonly) {
	local $z = &get_bind_zone($d->{'dom'});
	if ($z) {
		local @errs = &bind8::check_zone_records($z);
		if (@errs) {
			return &text('validate_ednscheck',
				join("<br>", map { &html_escape($_) } @errs));
			}
		}
	}

# Check slave servers
if (!$d->{'dns_submode'} && !$recsonly) {
	my @slaves = &bind8::list_slave_servers();
	foreach my $sn (split(/\s+/, $d->{'dns_slave'})) {
		my ($slave) = grep { $_->{'nsname'} eq $sn ||
				     $_->{'host'} eq $sn } @slaves;
		if ($slave) {
			my $ok = &exists_on_slave($d->{'dom'}, $slave);
			if (!$ok) {
				return &text('validate_ednsslave',
					     $slave->{'host'});
				}
			elsif ($ok ne "OK") {
				return &text('validate_ednsslave2',
					     $slave->{'host'}, $ok);
				}
			}
		}
	}

return undef;
}

# disable_dns(&domain)
# Re-names this domain in named.conf with the .disabled suffix
sub disable_dns
{
local ($d) = @_;
if ($d->{'provision_dns'}) {
	# Lock on provisioning server
	&$first_print($text{'disable_bind_provision'});
	local $info = { 'domain' => $d->{'dom'},
			'host' => $d->{'provision_dns_host'},
			'disable' => '' };
	my ($ok, $msg) = &provision_api_call("modify-dns-zone", $info, 0);
	if (!$ok) {
		&$second_print(&text('disable_ebind_provision', $msg));
		return 0;
		}
	&$second_print($text{'setup_done'});
	}
else {
	# Lock locally
	&$first_print($text{'disable_bind'});
	if ($d->{'dns_submode'}) {
		# Disable is not done for sub-domains
		&$second_print($text{'disable_bindnosub'});
		return;
		}
	&obtain_lock_dns($d, 1);
	&require_bind();
	local $z = &get_bind_zone($d->{'dom'});
	if ($z) {
		local $rootfile = &bind8::make_chroot($z->{'file'});
		$z->{'values'}->[0] = $d->{'dom'}.".disabled";
		&bind8::save_directive(&bind8::get_config_parent(),
					[ $z ], [ $z ], 0);
		&flush_file_lines();

		# Rename all records in the domain with the new .disabled name
		local $file = &bind8::find("file", $z->{'members'});
		local $fn = $file->{'values'}->[0];
		local @recs = &bind8::read_zone_file(
				$fn, $d->{'dom'}.".disabled");
		foreach my $r (@recs) {
			if ($r->{'name'} =~ /\.\Q$d->{'dom'}\E\.$/ ||
			    $r->{'name'} eq $d->{'dom'}.".") {
				# Need to rename
				&bind8::modify_record($fn, $r,
					      $r->{'name'}."disabled.",
					      $r->{'ttl'}, $r->{'class'},
					      $r->{'type'},
					      &join_record_values($r),
					      $r->{'comment'});
				}
			}

		# Clear zone names caches
		undef(@bind8::list_zone_names_cache);
		&$second_print($text{'setup_done'});
		&register_post_action(\&restart_bind, $d);

		# If on any slaves, delete there too
		$d->{'old_dns_slave'} = $d->{'dns_slave'};
		&delete_zone_on_slaves($d);
		}
	else {
		&$second_print($text{'save_nobind'});
		}
	&release_lock_dns($d, 1);
	}
}

# enable_dns(&domain)
# Re-names this domain in named.conf to remove the .disabled suffix
sub enable_dns
{
if ($d->{'provision_dns'}) {
	# Unlock on provisioning server
	&$first_print($text{'enable_bind_provision'});
	local $info = { 'domain' => $d->{'dom'},
			'host' => $d->{'provision_dns_host'},
			'enable' => '' };
	my ($ok, $msg) = &provision_api_call("modify-dns-zone", $info, 0);
	if (!$ok) {
		&$second_print(&text('disable_ebind_provision', $msg));
		return 0;
		}
	&$second_print($text{'setup_done'});
	}
else {
	&$first_print($text{'enable_bind'});
	if ($d->{'dns_submode'}) {
		# Disable is not done for sub-domains
		&$second_print($text{'enable_bindnosub'});
		return;
		}
	&obtain_lock_dns($d, 1);
	&require_bind();
	local $z = &get_bind_zone($d->{'dom'});
	if ($z) {
		local $rootfile = &bind8::make_chroot($z->{'file'});
		$z->{'values'}->[0] = $d->{'dom'};
		&bind8::save_directive(
			&bind8::get_config_parent(), [ $z ], [ $z ], 0);
		&flush_file_lines();

		# Fix all records in the domain with the .disabled name
		local $file = &bind8::find("file", $z->{'members'});
		local $fn = $file->{'values'}->[0];
		local @recs = &bind8::read_zone_file($fn, $d->{'dom'});
		foreach my $r (@recs) {
			if ($r->{'name'} =~ /\.\Q$d->{'dom'}\E\.disabled\.$/
			    ||
			    $r->{'name'} eq $d->{'dom'}.".disabled.") {
				# Need to rename
				$r->{'name'} =~ s/\.disabled\.$/\./;
				&bind8::modify_record($fn, $r,
					      $r->{'name'},
					      $r->{'ttl'}, $r->{'class'},
					      $r->{'type'},
					      &join_record_values($r),
					      $r->{'comment'});
				}
			}

		# Clear zone names caches
		undef(@bind8::list_zone_names_cache);
		&$second_print($text{'setup_done'});
		&register_post_action(\&restart_bind, $d);

		# If it used to be on any slaves, enable too
		$d->{'dns_slave'} = $d->{'old_dns_slave'};
		&create_zone_on_slaves($d, $d->{'dns_slave'});
		delete($d->{'old_dns_slave'});
		}
	else {
		&$second_print($text{'save_nobind'});
		}
	&release_lock_dns($d, 1);
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
local $p = $_[0] ? $_[0]->{'provision_dns'} : $config{'provision_dns'};
if ($p) {
	# Hosted on a provisioning server, so nothing to do
	return 1;
	}
&$first_print($text{'setup_bindpid'});
&require_bind();
local $bindlock = "$module_config_directory/bind-restart";
&lock_file($bindlock);
local $pid = &get_bind_pid();
if ($pid) {
	my $err = &bind8::restart_bind();
	if ($err) {
		&$second_print(&text('setup_ebindpid', $err));
		}
	else {
		&$second_print($text{'setup_done'});
		}
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
&unlock_file($bindlock);
return $rv;
}

# reload_bind_records(&domain)
# Tell BIND to reload the DNS records in some zone, using rndc / ndc if possible
sub reload_bind_records
{
local ($d) = @_;
if ($d->{'provision_dns'}) {
	# Done remotely when records are uploaded
	return undef;
	}
&require_bind();
if (defined(&bind8::restart_zone)) {
	local $err = &bind8::restart_zone($d->{'dom'}, $d->{'dns_view'});
	return undef if (!$err);
	}
&push_all_print();
&set_all_null_print();
local $rv = &restart_bind($d);
&pop_all_print();
return $rv;
}

# check_dns_clash(&domain, [changing])
# Returns 1 if a domain already exists in BIND
sub check_dns_clash
{
local ($d, $field) = @_;
if ($d->{'provision_dns'}) {
	# Check on remote provisioning server
	if (!$field || $field eq 'dom') {
		my ($ok, $msg) = &provision_api_call(
			"check-dns-zone", { 'domain' => $d->{'dom'} });
		return &text('provision_ednscheck', $msg) if (!$ok);
		if ($msg =~ /host=/) {
			return &text('provision_edns', $d->{'db'});
			}
		}
	}
else {
	# Check locally
	if (!$field || $field eq 'dom') {
		local ($czone) = &get_bind_zone($d->{'dom'});
		return $czone ? 1 : 0;
		}
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
local ($recs, $file) = &get_domain_dns_records_and_file($_[0]);
if ($file) {
	local $absfile = &bind8::make_chroot(
			&bind8::absolute_path($file));
	if (-r $absfile) {
		&copy_source_dest($absfile, $_[1]);
		&$second_print($text{'setup_done'});
		return 1;
		}
	else {
		&$second_print(&text('backup_dnsnozonefile',
				     "<tt>$file</tt>"));
		return 0;
		}
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
&obtain_lock_dns($_[0], 1);
local ($recs, $file) = &get_domain_dns_records_and_file($_[0]);
if ($file) {
	local $absfile = &bind8::make_chroot(
			&bind8::absolute_path($file));
	local @thisrecs;

	if ($_[2]->{'wholefile'}) {
		# Copy whole file
		&copy_source_dest($_[1], $absfile);
		&bind8::set_ownership($file);
		}
	else {
		# Only copy section after SOA
		@thisrecs = &bind8::read_zone_file($file, $_[0]->{'dom'});
		local $srclref = &read_file_lines($_[1], 1);
		local $dstlref = &read_file_lines($absfile);
		local ($srcstart, $srcend) = &except_soa($_[0], $_[1]);
		local ($dststart, $dstend) = &except_soa($_[0], $absfile);
		splice(@$dstlref, $dststart, $dstend - $dststart + 1,
		       @$srclref[$srcstart .. $srcend]);
		&flush_file_lines($absfile);
		}

	# Re-read records, bump SOA and upload records to provisioning server
	local @recs = &bind8::read_zone_file($file, $_[0]->{'dom'});
	&post_records_change($_[0], \@recs, $file);

	# Need to update IP addresses
	local $r;
	local ($baserec) = grep { $_->{'type'} eq "A" &&
				  ($_->{'name'} eq $_[0]->{'dom'}."." ||
				   $_->{'name'} eq '@') } @recs;
	local $ip = $_[0]->{'dns_ip'} || $_[0]->{'ip'};
	local $baseip = $_[0]->{'old_dns_ip'} ? $_[0]->{'old_dns_ip'} :
		        $_[0]->{'old_ip'} ? $_[0]->{'old_ip'} :
				$baserec ? $baserec->{'values'}->[0] : undef;
	if ($baseip) {
		&modify_records_ip_address(\@recs, $file, $baseip, $ip);
		}

	# Need to update IPv6 address
	local ($baserec6) = grep { $_->{'type'} eq "AAAA" &&
				   ($_->{'name'} eq $_[0]->{'dom'}."." ||
				    $_->{'name'} eq '@') } @recs;
	local $ip6 = $_[0]->{'ip6'};
	local $baseip6 = $_[0]->{'old_ip6'} ? $_[0]->{'old_ip6'} :
				$baserec6 ? $baserec6->{'values'}->[0] : undef;
	if ($baseip6 && $ip6) {
		# Update to new v6 address
		&modify_records_ip_address(\@recs, $file, $baseip6, $ip6);
		}
	elsif ($baseip6 && !$ip6) {
		# This domain doesn't have a v6 address now, so remove AAAAs
		&remove_ip6_records($_[0], $file, \@recs);
		}

	# Replace NS records with those from new system
	if (!$_[2]->{'wholefile'}) {
		local @thisns = grep { $_->{'type'} eq 'NS' } @thisrecs;
		local @ns = grep { $_->{'type'} eq 'NS' } @recs;
		foreach my $r (@thisns) {
			# Create NS records that were in new system's file
			&bind8::create_record($file, $r->{'name'}, $r->{'ttl'},
					      $r->{'class'}, $r->{'type'},
					      &join_record_values($r),
					      $r->{'comment'});
			}
		foreach my $r (reverse(@ns)) {
			# Remove old NS records that we copied over
			&bind8::delete_record($file, $r);
			}
		}

	# Make sure any SPF record contains this system's default IP
	local @types = $bind8::config{'spf_record'} ? ( "SPF", "TXT" )
						    : ( "SPF" );
	foreach my $t (@types) {
		local ($r) = grep { $_->{'type'} eq $t &&
				    $r->{'name'} eq $d->{'dom'}.'.' } @recs;
		next if (!$r);
		local $spf = &bind8::parse_spf(@{$r->{'values'}});
		local $defip = &get_default_ip();
		if (&indexof($defip, @{$spf->{'ip4'}}) < 0) {
			push(@{$spf->{'ip4'}}, $defip);
			local $str = &bind8::join_spf($spf);
			&bind8::modify_record($r->{'file'}, $r, $r->{'name'},
					      $r->{'ttl'}, $r->{'class'},
					      $r->{'type'}, "\"$str\"",
					      $r->{'comment'});
			}
		}

	&$second_print($text{'setup_done'});

	&register_post_action(\&restart_bind, $_[0]);
	return 1;
	}
else {
	&$second_print($text{'backup_dnsnozone'});
	return 0;
	}
&release_lock_dns($_[0], 1);
}

# modify_records_ip_address(&records, filename, oldip, newip, [domain])
# Update the IP address in all DNS records
sub modify_records_ip_address
{
local ($recs, $fn, $oldip, $newip, $dname) = @_;
local $count = 0;
foreach my $r (@$recs) {
	my $changed = 0;
	if ($dname && $r->{'name'} !~ /\.\Q$dname\E\.$/i &&
		      $r->{'name'} !~ /^\Q$dname\E\.$/i) {
		# Out of zone record .. skip it
		next;
		}
	if (($r->{'type'} eq "A" || $r->{'type'} eq "AAAA") &&
	    $r->{'values'}->[0] eq $oldip) {
		# Address record - just replace IP
		$r->{'values'}->[0] = $newip;
		$changed = 1;
		}
	elsif (($r->{'type'} eq "SPF" ||
		$r->{'type'} eq "TXT" && $r->{'values'}->[0] =~ /^v=spf/) &&
	       $r->{'values'}->[0] =~ /$oldip/) {
		# SPF record - replace ocurrances of IP
		$r->{'values'}->[0] =~ s/$oldip/$newip/g;
		$changed = 1;
		}
	if ($changed) {
		&bind8::modify_record($fn, $r, $r->{'name'},
				      $r->{'ttl'},$r->{'class'},
				      $r->{'type'},
				      &join_record_values($r,
					$r->{'eline'} == $r->{'line'}),
				      $r->{'comment'});
		$count++;
		}
	}
return $count;
}

# modify_records_domain_name(&records, file, old-domain, new-domain)
# Change the domain name in DNS record names and values
sub modify_records_domain_name
{
local ($recs, $fn, $olddom, $newdom) = @_;
foreach my $r (@$recs) {
	next if (!$r->{'name'});	# TTL or generator
	if ($r->{'name'} eq $olddom.".") {
		$r->{'name'} = $newdom.".";
		}
	elsif ($r->{'name'} eq $olddom.".disabled.") {
		$r->{'name'} = $newdom.".disabled.";
		}
	else {
		$r->{'name'} =~ s/\.$olddom(\.disabled)?\.$/\.$newdom$1\./;
		}
	if ($r->{'realname'} eq $olddom.".") {
		$r->{'realname'} = $newdom.".";
		}
	elsif ($r->{'realname'} eq $olddom.".disabled.") {
		$r->{'realname'} = $newdom.".";
		}
	else {
		$r->{'realname'} =~ s/\.$olddom(\.disabled)?\.$/\.$newdom$1\./;
		}
	if ($r->{'type'} eq 'SPF' ||
	    $r->{'type'} eq 'TXT' && $r->{'values'}->[0] =~ /^v=spf/) {
		# Fix SPF TXT record
		$r->{'values'}->[0] =~ s/$olddom/$newdom/;
		}
	if ($r->{'type'} eq 'MX') {
		# Fix mail server in MX record
		$r->{'values'}->[1] =~ s/$olddom/$newdom/;
		}
	&bind8::modify_record($fn, $r, $r->{'name'},
			      $r->{'ttl'}, $r->{'class'},
			      $r->{'type'},
			      &join_record_values($r,
				$r->{'eline'} == $r->{'line'}),
			      $r->{'comment'});
	}
}

# except_soa(&domain, file)
# Returns the start and end lines of a records file for the entries
# after the SOA.
sub except_soa
{
local $bind8::config{'chroot'} = "/";	# make sure path is absolute
local $bind8::config{'auto_chroot'} = undef;
undef($bind8::get_chroot_cache);
local @recs = &bind8::read_zone_file($_[1], $_[0]->{'dom'});
local ($r, $start, $end);
foreach $r (@recs) {
	if ($r->{'type'} ne "SOA" && !$r->{'generate'} && !$r->{'defttl'} &&
	    !defined($start)) {
		$start = $r->{'line'};
		}
	$end = $r->{'eline'};
	}
undef($bind8::get_chroot_cache);	# Reset cache back
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
if ($config{'provision_dns'}) {
	# No local BIND in provisioning mode
	return ( );
	}
if (!$bind8::bind_version) {
	local $out = `$bind8::config{'named_path'} -v 2>&1`;
	if ($out =~ /(bind|named)\s+([0-9\.]+)/i) {
		$bind8::bind_version = $2;
		}
	}
return ( [ $text{'sysinfo_bind'}, $bind8::bind_version ] );
}

sub startstop_dns
{
local ($typestatus) = @_;
if ($config{'provision_dns'}) {
	# Cannot start or stop when remote
	return ();
	}
local $bpid = defined($typestatus{'bind8'}) ?
		$typestatus{'bind8'} == 1 : &get_bind_pid();
local @links = ( { 'link' => '/bind8/',
		   'desc' => $text{'index_bmanage'},
		   'manage' => 1 } );
if ($bpid && kill(0, $bpid)) {
	return ( { 'status' => 1,
		   'name' => $text{'index_bname'},
		   'desc' => $text{'index_bstop'},
		   'restartdesc' => $text{'index_brestart'},
		   'longdesc' => $text{'index_bstopdesc'},
		   'links' => \@links } );
	}
else {
	return ( { 'status' => 0,
		   'name' => $text{'index_bname'},
		   'desc' => $text{'index_bstart'},
		   'longdesc' => $text{'index_bstartdesc'},
		   'links' => \@links } );
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
local ($conf, @views);
if (!$config{'provision_dns'}) {
	$conf = &bind8::get_config();
	@views = &bind8::find("view", $conf);
	}

# DNS records
local $ndi = &none_def_input("dns", $tmpl->{'dns'}, $text{'tmpl_dnsbelow'}, 1,
     0, undef, [ "dns", "bind_replace", "dnsns", "dns_ttl_def", "dns_ttl",
		 "dnsprins", "dns_records",
		 @views || $tmpl->{'dns_view'} ? ( "view" ) : ( ) ]);
print &ui_table_row(&hlink($text{'tmpl_dns'}, "template_dns"),
	$ndi."<br>\n".
	&ui_textarea("dns", $tmpl->{'dns'} eq "none" ? "" :
				join("\n", split(/\t/, $tmpl->{'dns'})),
		     10, 60)."<br>\n".
	&ui_radio("bind_replace", int($tmpl->{'dns_replace'}),
		  [ [ 0, $text{'tmpl_replace0'} ],
		    [ 1, $text{'tmpl_replace1'} ] ]));

# Address records to add
my @add_records = split(/\s+/, $tmpl->{'dns_records'});
if (!@add_records || $add_records[0] eq 'none') {
	@add_records = @automatic_dns_records;
	}
my @grid = map { &ui_checkbox("dns_records", $_, $text{'tmpl_dns_record_'.$_},
			      &indexof($_, @add_records) >= 0) }
	       @automatic_dns_records;
print &ui_table_row(&hlink($text{'tmpl_dnsrecords'}, "template_dns_records"),
	&ui_grid_table(\@grid, scalar(@grid)));

# Default TTL
local $tmode = $tmpl->{'dns_ttl'} eq 'none' ? 0 :
	       $tmpl->{'dns_ttl'} eq 'skip' ? 1 : 2;
print &ui_table_row(&hlink($text{'tmpl_dnsttl'}, "template_dns_ttl"),
	&ui_radio("dns_ttl_def", $tmpl->{'dns_ttl'} eq '' ? 0 :
				 $tmpl->{'dns_ttl'} eq 'none' ? 1 : 2,
	  [ [ 0, $text{'tmpl_dnsttl0'} ],
	    [ 1, $text{'tmpl_dnsttl1'} ],
	    [ 2, $text{'tmpl_dnsttl2'}." ".
	      &ui_textbox("dns_ttl", $tmode == 2 ? $tmpl->{'dns_ttl'} : "", 15)
	    ] ]));

# Manual NS records
print &ui_table_row(&hlink($text{'tmpl_dnsns'}, "template_dns_ns"),
	&ui_textarea("dnsns", join("\n", split(/\s+/, $tmpl->{'dns_ns'})),
		     3, 50)."<br>\n".
	&ui_checkbox("dnsprins", 1, $text{'tmpl_dnsprins'},
		     $tmpl->{'dns_prins'}));

# Option for view to add to, for BIND 9
if (@views || $tmpl->{'dns_view'}) {
	print &ui_table_row($text{'newdns_view'},
		&ui_select("view", $tmpl->{'dns_view'},
			[ [ "", $text{'newdns_noview'} ],
			  map { [ $_->{'values'}->[0] ] } @views ]));
	}

# Add sub-domains to parent domain DNS
print &ui_table_row(&hlink($text{'tmpl_dns_sub'},
                           "template_dns_sub"),
	&none_def_input("dns_sub", $tmpl->{'dns_sub'},
		        $text{'yes'}, 0, 0, $text{'no'}));

print &ui_table_hr();

# Master NS hostnames
print &ui_table_row(&hlink($text{'tmpl_dnsmaster'},
                           "template_dns_master"),
	&none_def_input("dns_master", $tmpl->{'dns_master'},
			$text{'tmpl_dnsmnames'}, 0, 0,
			$text{'tmpl_dnsmauto'}."<br>", [ "dns_master" ])." ".
	&ui_textbox("dns_master", $tmpl->{'dns_master'} eq 'none' ? '' :
					$tmpl->{'dns_master'}, 40));

print &ui_table_hr();

# Option for SPF record
print &ui_table_row(&hlink($text{'tmpl_spf'},
                           "template_dns_spf_mode"),
	&none_def_input("dns_spf", $tmpl->{'dns_spf'},
		        $text{'tmpl_spfyes'}, 0, 0, $text{'no'},
			[ "dns_spfhosts", "dns_spfall", "dns_spfincludes" ]));

# Extra SPF hosts
print &ui_table_row(&hlink($text{'tmpl_spfhosts'},
			   "template_dns_spfhosts"),
	&ui_textbox("dns_spfhosts", $tmpl->{'dns_spfhosts'}, 40));

# Extra SPF includes
print &ui_table_row(&hlink($text{'tmpl_spfincludes'},
			   "template_dns_spfincludes"),
	&ui_textbox("dns_spfincludes", $tmpl->{'dns_spfincludes'}, 40));

# SPF ~all mode
print &ui_table_row(&hlink($text{'tmpl_spfall'},
			   "template_dns_spfall"),
	&ui_radio("dns_spfall", $tmpl->{'dns_spfall'},
		  [ [ 0, $text{'tmpl_spfall0'} ],
		    [ 1, $text{'tmpl_spfall1'} ],
		    [ 2, $text{'tmpl_spfall2'} ] ]));

if (!$config{'provision_dns'}) {
	print &ui_table_hr();

	# Extra named.conf directives
	print &ui_table_row(&hlink($text{'tmpl_namedconf'}, "namedconf"),
	    &none_def_input("namedconf", $tmpl->{'namedconf'},
			    $text{'tmpl_namedconfbelow'}, 0, 0, undef,
			    [ "namedconf", "namedconf_also_notify",
			      "namedconf_allow_transfer" ])."<br>".
	    &ui_textarea("namedconf",
			 $tmpl->{'namedconf'} eq 'none' ? '' :
				join("\n", split(/\t/, $tmpl->{'namedconf'})),
			 5, 60));

	# Add also-notify and allow-transfer
	print &ui_table_row(&hlink($text{'tmpl_dnsalso'}, "template_dns_also"),
		&ui_checkbox("namedconf_also_notify", 1, 'also-notify',
			     !$tmpl->{'namedconf_no_also_notify'})." ".
		&ui_checkbox("namedconf_allow_transfer", 1, 'allow-transfer',
			     !$tmpl->{'namedconf_no_allow_transfer'}));

	# DNSSEC for new domains
	if (defined(&bind8::supports_dnssec) && &bind8::supports_dnssec()) {
		print &ui_table_hr();

		# Setup for new domains?
		print &ui_table_row(&hlink($text{'tmpl_dnssec'}, "dnssec"),
			&none_def_input("dnssec", $tmpl->{'dnssec'},
				$text{'yes'}, 0, 0,
				$text{'no'}, [ "dnssec_alg", "dnssec_single" ]));

		# Encryption algorithm
		print &ui_table_row(&hlink($text{'tmpl_dnssec_alg'}, "dnssec_alg"),
			&ui_select("dnssec_alg", $tmpl->{'dnssec_alg'} || "RSASHA1",
				   [ &bind8::list_dnssec_algorithms() ]));

		# One key or two?
		print &ui_table_row(&hlink($text{'tmpl_dnssec_single'},
					   "dnssec_single"),
			&ui_radio("dnssec_single", $tmpl->{'dnssec_single'} ? 1 : 0,
				  [ [ 0, $bind8::text{'zonedef_two'} ],
				    [ 1, $bind8::text{'zonedef_one'} ] ]));
		}
	}
}

# parse_template_dns(&tmpl)
# Updates BIND related template options from %in
sub parse_template_dns
{
local ($tmpl) = @_;

# Save DNS settings
$tmpl->{'dns'} = &parse_none_def("dns");
if ($in{"dns_mode"} == 2) {
	$tmpl->{'default'} || $tmpl->{'dns'} || $in{'bind_replace'} == 0 ||
		&error($text{'tmpl_edns'});
	$tmpl->{'dns_replace'} = $in{'bind_replace'};
	$tmpl->{'dns_view'} = $in{'view'};

	&require_bind();
	local $fakeip = "1.2.3.4";
	local $fakedom = "foo.com";
	local $recs = &substitute_virtualmin_template(
			join("\n", split(/\t+/, $in{'dns'}))."\n",
			{ 'ip' => $fakeip,
			  'dom' => $fakedom,
		 	  'web' => 1, });
	local $temp = &transname();
	&open_tempfile(TEMP, ">$temp");
	&print_tempfile(TEMP, $recs);
	&close_tempfile(TEMP);
	local $bind8::config{'short_names'} = 0;  # force canonicalization
	local $bind8::config{'chroot'} = '/';	  # turn off chroot for temp path
	local $bind8::config{'auto_chroot'} = undef;
	undef($bind8::get_chroot_cache);
	local @recs = &bind8::read_zone_file($temp, $fakedom);
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
	undef($bind8::get_chroot_cache);	# reset cache back

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

	# Save default TTL
	if ($in{'dns_ttl_def'} == 0) {
		$tmpl->{'dns_ttl'} = '';
		}
	elsif ($in{'dns_ttl_def'} == 1) {
		$tmpl->{'dns_ttl'} = 'none';
		}
	else {
		$in{'dns_ttl'} =~ /^\d+(h|d|m|y|w|)$/i ||
			&error($text{'tmpl_ednsttl'});
		$tmpl->{'dns_ttl'} = $in{'dns_ttl'};
		}

	# Save automatic A records
	$tmpl->{'dns_records'} = join(" ", split(/\0/, $in{'dns_records'})) ||
				 'noneselected';

	# Save additional nameservers
	$in{'dnsns'} =~ s/\r//g;
	local @ns = split(/\n+/, $in{'dnsns'});
	foreach my $n (@ns) {
		&check_ipaddress($n) && &error(&text('newdns_ensip', $n));
		&to_ipaddress($n) || &error(&text('newdns_enshost', $n));
		}
	$tmpl->{'dns_ns'} = join(" ", @ns);
	$tmpl->{'dns_prins'} = $in{'dnsprins'};
	}

# Save NS hostname
$in{'dns_master_mode'} != 2 ||
   ($in{'dns_master'} =~ /^[a-z0-9\.\-\_]+$/i && $in{'dns_master'} =~ /\./ &&
    !&check_ipaddress($in{'dns_master'})) ||
	&error($text{'tmpl_ednsmaster'});
$tmpl->{'dns_master'} = $in{'dns_master_mode'} == 0 ? "none" :
		        $in{'dns_master_mode'} == 1 ? undef : $in{'dns_master'};

# Save SPF
$tmpl->{'dns_spf'} = $in{'dns_spf_mode'} == 0 ? "none" :
		     $in{'dns_spf_mode'} == 1 ? undef : "yes";
$tmpl->{'dns_spfhosts'} = $in{'dns_spfhosts'};
$tmpl->{'dns_spfincludes'} = $in{'dns_spfincludes'};
$tmpl->{'dns_spfall'} = $in{'dns_spfall'};

# Save sub-domain DNS mode
$tmpl->{'dns_sub'} = $in{'dns_sub_mode'} == 0 ? "none" :
		     $in{'dns_sub_mode'} == 1 ? undef : "yes";

if (!$config{'provision_dns'}) {
	# Save named.conf
	$tmpl->{'namedconf'} = &parse_none_def("namedconf");
	if ($in{'namedconf_mode'} == 2) {
		# Make sure the directives are valid
		local @recs = &text_to_named_conf($tmpl->{'namedconf'});
		if ($tmpl->{'namedconf'} =~ /\S/ && !@recs) {
			&error($text{'newdns_enamedconf'});
			}
		$tmpl->{'namedconf'} ||= " ";	# So it can be empty

		# Save other auto-add directives
		$tmpl->{'namedconf_no_also_notify'} =
			!$in{'namedconf_also_notify'};
		$tmpl->{'namedconf_no_allow_transfer'} =
			!$in{'namedconf_allow_transfer'};
		}

	# Save DNSSEC
	if (defined($in{'dnssec_mode'})) {
		$tmpl->{'dnssec'} = $in{'dnssec_mode'} == 0 ? "none" :
				    $in{'dnssec_mode'} == 1 ? undef : "yes";
		$tmpl->{'dnssec_alg'} = $in{'dnssec_alg'};
		$tmpl->{'dnssec_single'} = $in{'dnssec_single'};
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
		return &bind8::parse_spf(@{$r->{'values'}});
		}
	}
return undef;
}

# save_domain_spf(&domain, &spf)
# Updates/creates/deletes a domain's SPF record.
sub save_domain_spf
{
local ($d, $spf) = @_;
local ($recs, $file) = &get_domain_dns_records_and_file($d);
if (!$file) {
	# Domain not found!
	return;
	}
local $bump = 0;
local @types = $bind8::config{'spf_record'} ? ( "SPF", "TXT" ) : ( "SPF" );
foreach my $t (@types) {
	local ($r) = grep { $_->{'type'} eq $t &&
			    $_->{'values'}->[0] =~ /^v=spf/ &&
			    $_->{'name'} eq $d->{'dom'}.'.' } @$recs;
	local $str = $spf ? &bind8::join_spf($spf) : undef;
	if ($r && $spf) {
		# Update record
		&bind8::modify_record(
			$r->{'file'}, $r, $r->{'name'}, $r->{'ttl'},
			$r->{'class'}, $r->{'type'}, "\"$str\"",
			$r->{'comment'});
		$bump = 1;
		}
	elsif ($r && !$spf) {
		# Remove record
		&bind8::delete_record($r->{'file'}, $r);
		$bump = 1;
		}
	elsif (!$r && $spf) {
		# Add record
		&bind8::create_record($file, $d->{'dom'}.'.', undef,
				      "IN", $t, "\"$str\"");
		$bump = 1;
		}
	}
if ($bump) {
	&post_records_change($d, $recs, $file);
	&register_post_action(\&restart_bind, $d);
	}
}

# get_domain_dns_records(&domain)
# Returns an array of DNS records for a domain, or empty if the file couldn't
# be found.
sub get_domain_dns_records
{
local ($d) = @_;
local ($recs, $file) = &get_domain_dns_records_and_file($d);
return ( ) if (!$file);
return @$recs;
}

# get_domain_dns_file(&domain)
# Returns the chroot-relative path to a domain's DNS records
sub get_domain_dns_file
{
local ($d) = @_;
if ($d->{'provision_dns'}) {
	&error("get_domain_dns_file($d->{'dom'}) cannot be called ".
	       "for provisioning domains");
	}
&require_bind();
local $z;
if ($d->{'dns_submode'}) {
	# Records are in super-domain
	local $parent = &get_domain($d->{'subdom'}) ||
			&get_domain($d->{'parent'});
	$z = &get_bind_zone($parent->{'dom'});
	}
else {
	# In this domain
	$z = &get_bind_zone($d->{'dom'});
	}
return undef if (!$z);
local $file = &bind8::find("file", $z->{'members'});
return undef if (!$file);
return $file->{'values'}->[0];
}

# get_domain_dns_records_and_file(&domain)
# Returns an array ref of a domain's DNS records and the file they are in.
# For a provisioned domain, this may be a local temp file.
sub get_domain_dns_records_and_file
{
local ($d) = @_;
&require_bind();
local $bind8::config{'short_names'} = 0;
if ($d->{'provision_dns'}) {
	# Download to temp file, and read it
	local $temp = &transname();
	local $abstemp = $temp;
	local $chroot = &bind8::get_chroot();
	if ($chroot && $chroot ne "/") {
		# Actual temp file needs to be under chroot dir
		$abstemp = &bind8::make_chroot($temp);
		local $absdir = $abstemp;
		$absdir =~ s/\/[^\/]+$//;
		if (!-d $absdir) {
			&make_dir($absdir, 0755, 1);
			}
		}
	local $info = { 'domain' => $d->{'dom'},
			'host' => $d->{'provision_dns_host'} };
	my ($ok, $msg) = &provision_api_call(
		"list-dns-records", $info, 1);
	if (!$ok) {
		return ("Failed to fetch DNS records from provisioning ".
			"server : $msg");
		}
	local @recs;
	local $lnum = 0;
	foreach my $r (@$msg) {
		local $rec;
		if ($r->{'name'} eq '$ttl') {
			$rec = { 'defttl' => $r->{'values'}->{'value'}->[0] };
			&bind8::create_defttl($temp, $rec->{'defttl'});
			}
		elsif ($r->{'name'} eq '$generate') {
			$rec = { 'generate' => $r->{'values'}->{'value'} };
			&bind8::create_generator($temp, @{$rec->{'generate'}});
			}
		else {
			$rec = { 'name' => $r->{'name'},
				 'realname' => $r->{'name'},
				 'class' => $r->{'values'}->{'class'}->[0],
				 'type' => $r->{'values'}->{'type'}->[0],
				 'ttl' => $r->{'values'}->{'ttl'}->[0],
				 'comment' => $r->{'values'}->{'comment'}->[0],
				 'values' => $r->{'values'}->{'value'},
			       };
			&bind8::create_record($temp, $rec->{'name'},
				$rec->{'ttl'}, $rec->{'class'}, $rec->{'type'},
				&join_record_values($rec, 1),
				$rec->{'comment'});
			}
		$rec->{'line'} = $lnum;
		$rec->{'eline'} = $lnum;
		$rec->{'num'} = $lnum;
		$rec->{'file'} = $temp;
		$rec->{'rootfile'} = $abstemp;
		push(@recs, $rec);
		$lnum++;
		}
	&set_record_ids(\@recs);
	return (\@recs, $temp);
	}
else {
	# Find local file
	local $file = &get_domain_dns_file($d);
	return ("No zone file found for $d->{'dom'}") if (!$file);
	local $rd = $d->{'dns_submode'} ? &get_domain($d->{'subdom'} ||
						      $d->{'parent'}) : $d;
	local @recs = &bind8::read_zone_file($file, $rd->{'dom'});
	&set_record_ids(\@recs);
	return (\@recs, $file);
	}
}

# set_record_ids(&records)
# Sets the ID field on a bunch of DNS records
sub set_record_ids
{
local ($recs) = @_;
foreach my $r (@$recs) {
	if ($r->{'defttl'}) {
		$r->{'id'} = join("/", '$ttl', $r->{'defttl'});
		}
	elsif ($r->{'generate'}) {
		$r->{'id'} = join("/", '$generate', @{$r->{'generate'}});
		}
	else {
		$r->{'id'} = join("/", $r->{'name'}, $r->{'type'},
				       @{$r->{'values'}});
		}
	}
}

# default_domain_spf(&domain)
# Returns a default SPF object for a domain, based on its template
sub default_domain_spf
{
local ($d) = @_;
local $tmpl = &get_template($d->{'template'});
local $defip = &get_default_ip();
local $defip6 = &get_default_ip6();
local $spf = { 'a' => 1, 'mx' => 1,
	       'a:' => [ $d->{'dom'} ],
	       'ip4:' => [ ],
	       'ip6:' => [ ] };
if ($defip ne "127.0.0.1") {
	push(@{$spf->{'ip4:'}}, $defip);
	}
if ($defip6) {
	push(@{$spf->{'ip6:'}}, $defip6);
	}
local $hosts = &substitute_domain_template($tmpl->{'dns_spfhosts'}, $d);
foreach my $h (split(/\s+/, $hosts)) {
	if (&check_ipaddress($h) ||
	    $h =~ /^(\S+)\// && &check_ipaddress($1)) {
		push(@{$spf->{'ip4:'}}, $h);
		}
	else {
		push(@{$spf->{'a:'}}, $h);
		}
	}
local $includes = &substitute_domain_template($tmpl->{'dns_spfincludes'}, $d);
foreach my $i (split(/\s+/, $includes)) {
	push(@{$spf->{'include:'}}, $i);
	}
if ($d->{'dns_ip'}) {
	push(@{$spf->{'ip4:'}}, $d->{'dns_ip'});
	}
if ($d->{'ip'} ne $defip) {
	push(@{$spf->{'ip4:'}}, $d->{'ip'});
	}
if ($d->{'ip6'} && $d->{'ip6'} ne $defip) {
	push(@{$spf->{'ip6:'}}, $d->{'ip6'});
	}
$spf->{'all'} = $tmpl->{'dns_spfall'} + 1;
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
local $bind8::config{'chroot'} = undef;		# turn off chroot temporarily
local $bind8::config{'auto_chroot'} = undef;
undef($bind8::get_chroot_cache);
local @rv = grep { $_->{'name'} ne 'dummy' }
	    &bind8::read_config_file($temp, 0);
undef($bind8::get_chroot_cache);		# reset cache back
return @rv;
}

# post_records_change(&domain, &recs, [file])
# Called after some records in a domain are changed, to bump to SOA
# and possibly re-sign
sub post_records_change
{
local ($d, $recs, $fn) = @_;
&require_bind();
local $z;
if (!$fn) {
	# Use local file by default
	$z = &get_bind_zone($d->{'dom'});
	return "Failed to find zone for $d->{'dom'}" if (!$z);
	local $file = &bind8::find("file", $z->{'members'});
	return "Failed to find records file for $d->{'dom'}" if (!$file);
	$fn = $file->{'values'}->[0];
	}

# Increase the SOA
&bind8::bump_soa_record($fn, $recs);

# If the domain is disabled, make sure all records end with .disabled
if ($d->{'disabled'} && &indexof("dns", split(/,/, $d->{'disabled'})) >= 0) {
	local @disrecs = &bind8::read_zone_file($fn, $d->{'dom'});
	foreach my $r (@disrecs) {
		if ($r->{'name'} =~ /\.\Q$d->{'dom'}\E\.$/ ||
		    $r->{'name'} eq $d->{'dom'}.".") {
			# Not disabled - make it so
			&bind8::modify_record($fn, $r,
				      $r->{'name'}."disabled.",
				      $r->{'ttl'}, $r->{'class'},
				      $r->{'type'},
				      &join_record_values($r),
				      $r->{'comment'});
			}
		}
	}

if (defined(&bind8::supports_dnssec) &&
    &bind8::supports_dnssec() &&
    !$d->{'provision_dns'}) {
	# Re-sign too
	$z ||= &get_bind_zone($d->{'dom'});
	eval {
		local $main::error_must_die = 1;
		&bind8::sign_dnssec_zone_if_key($z, $recs, 0);
		};
	if ($@) {
		return "DNSSEC signing failed : $@";
		}
	}
if ($d->{'provision_dns'}) {
	# Upload records to provisioning server
	local $info = { 'domain' => $d->{'dom'},
			'replace' => '',
			'host' => $d->{'provision_dns_host'} };
	local @newrecs = &bind8::read_zone_file($fn, $d->{'dom'});
	$info->{'record'} = [ &records_to_text($d, \@newrecs) ];
	my ($ok, $msg) = &provision_api_call("modify-dns-records", $info, 0);
	if (!ok) {
		return "Error from provisioning server updating records : $msg";
		}
	}

# If this domain has aliases, update their DNS records too
if (!$d->{'subdom'} && !$d->{'dns_submode'}) {
	local @aliases = grep { $_->{'dns'} }
			      &get_domain_by("alias", $d->{'id'});
	foreach my $ad (@aliases) {
		# XXX provision mode
		&obtain_lock_dns($ad);
		local $file;
		local $recs;
		if ($ad->{'provision_dns'}) {
			# On provisioning server
			$file = &transname();
			local $bind8::config{'auto_chroot'} = undef;
			local $bind8::config{'chroot'} = undef;
			&create_alias_records($file, $ad,
					      $ad->{'dns_ip'} || $ad->{'ip'});
			$recs = [ &bind8::read_zone_file($temp, $ad->{'dom'}) ];
			}
		else {
			# On local BIND
			$file = &get_domain_dns_file($ad);
			&open_tempfile(EMPTY, ">$file", 0, 1);
			&close_tempfile(EMPTY);
			&create_alias_records($file, $ad,
					      $ad->{'dns_ip'} || $ad->{'ip'});
			$recs = [ get_domain_dns_records($ad) ];
			}
		&post_records_change($ad, $recs, $file);
		&reload_bind_records($ad);
		&release_lock_dns($ad);
		}
	}

return undef;
}

# records_to_text(&domain, &records)
# Given a list of record hashes, return text-format equivalents for an API call
sub records_to_text
{
local ($d, $recs) = @_;
local @rv;
&require_bind();
foreach my $r (@$recs) {
	next if ($r->{'type'} eq 'NS' &&	# Exclude NS for domain
		 $r->{'name'} eq $d->{'dom'}.".");
	if ($r->{'defttl'}) {
		push(@rv, '$ttl '.$r->{'defttl'});
		}
	elsif ($r->{'generate'}) {
		push(@rv, '$generate '.join(' ', @{$r->{'generate'}}));
		}
	elsif ($r->{'type'}) {
		my $t = $r->{'type'};
		$t = "TXT" if ($t eq "SPF" &&
			       $bind8::config{'spf_record'} == 0);
		push(@rv, join(" ", $r->{'name'}, $r->{'ttl'}, $r->{'class'},
				    $t, &join_record_values($r, 1)));
		}
	}
return @rv;
}

# under_parent_domain(&domain, [&parent])
# Returns 1 if some domain's DNS zone is under a given parent's DNS zone
sub under_parent_domain
{
local ($d, $parent) = @_;
if (!$parent && $d->{'parent'}) {
	$parent = &get_domain($d->{'parent'});
	}
if ($parent && $d->{'dom'} =~ /\.\Q$parent->{'dom'}\E$/i && $parent->{'dns'}) {
	return 1;
	}
return 0;
}

# can_edit_record(&record, &domain)
# Returns 1 if some DNS record can be edited.
sub can_edit_record
{
local ($r, $d) = @_;
if ($r->{'type'} eq 'NS' &&
    $r->{'name'} eq $d->{'dom'}.'.' &&
    $d->{'provision_dns'}) {
	# NS record for domain is automatically set in provisioning mode
	return 0;
	}
elsif (($r->{'type'} eq 'SPF' ||
	$r->{'type'} eq 'TXT' && $r->{'values'}->[0] =~ /^v=spf/) &&
       $r->{'name'} eq $d->{'dom'}.'.') {
	# SPF is edited separately
	return 0;
	}
elsif ($r->{'type'} eq 'TXT' &&
       $r->{'values'}->[0] =~ /^(t=|k=|v=)/) {
	# DKIM, managed by Virtualmin
	return 0;
	}
elsif ($r->{'type'} eq 'SOA') {
	# Always auto-generate
	return 0;
	}
return 1;
}

# can_delete_record(&record, &domain)
# Returns 1 if some DNS record can be removed.
sub can_delete_record
{
local ($r, $d) = @_;
if ($r->{'type'} eq 'NS' &&
    $r->{'name'} eq $d->{'dom'}.'.' &&
    $d->{'provision_dns'}) {
	# NS record for domain is automatically set in provisioning mode
	return 0;
	}
elsif ($r->{'type'} eq 'SOA') {
	# Don't allow removal of SOA ever
	return 0;
	}
return 1;
}

# list_dns_record_types(&domain)
# Returns a list of hash refs, one per supported record type. Each contains the
# following keys :
# type - A, NS, etc..
# desc - Human-readable description
# domain - Can be same as domain name
# values - Array ref of hash refs, with keys :
#   desc - Human-readable description of this value
#   regexp - Validation regexp for value
#   func - Validation function ref for value
sub list_dns_record_types
{
local ($d) = @_;
return ( { 'type' => 'A',
	   'desc' => $text{'records_typea'},
	   'domain' => 1,
	   'create' => 1,
	   'values' => [ { 'desc' => $text{'records_valuea'},
			   'size' => 20,
			   'func' => sub { &check_ipaddress($_[0]) ? undef :
						$text{'records_evaluea'} }
			 },
		       ],
	 },
	 { 'type' => 'AAAA',
	   'desc' => $text{'records_typeaaaa'},
	   'domain' => 1,
	   'create' => 1,
	   'values' => [ { 'desc' => $text{'records_valueaaaa'},
			   'size' => 20,
			   'func' => sub { &check_ip6address($_[0]) ? undef :
						$text{'records_evalueaaaa'} }
			 },
		       ],
	 },
	 { 'type' => 'CNAME',
	   'desc' => $text{'records_typecname'},
	   'domain' => 0,
	   'create' => 1,
	   'values' => [ { 'desc' => $text{'records_valuecname'},
                           'size' => 40,
                           'func' => sub { $_[0] =~ /^[a-z0-9\.\_\-]+$/i ?
					undef : $text{'records_evaluecname'} },
			   'dot' => 1,
                         },
                       ],
         },
	 { 'type' => 'NS',
	   'desc' => $text{'records_typens'},
	   'domain' => 1,
	   'create' => 1,
	   'values' => [ { 'desc' => $text{'records_valuens'},
                           'size' => 40,
                           'func' => sub { $_[0] =~ /^[a-z0-9\.\_\-]+$/i ?
					undef : $text{'records_evaluens'} },
			   'dot' => 1,
                         },
                       ],
         },
	 { 'type' => 'MX',
	   'desc' => $text{'records_typemx'},
	   'domain' => 1,
	   'create' => 1,
	   'values' => [ { 'desc' => $text{'records_valuemx1'},
                           'size' => 5,
                           'func' => sub { $_[0] =~ /^\d+$/ ?
					undef : $text{'records_evaluemx1'} },
			   'suffix' => $text{'records_valuemx1a'},
                         },
		         { 'desc' => $text{'records_valuemx2'},
                           'size' => 40,
                           'func' => sub { $_[0] =~ /^[a-z0-9\.\_\-]+$/i ?
                                        undef : $text{'records_evaluemx2'} },
			   'dot' => 1,
                         },
                       ],
	 },
	 { 'type' => 'TXT',
	   'desc' => $text{'records_typetxt'},
	   'domain' => 1,
	   'create' => 1,
	   'values' => [ { 'desc' => $text{'records_valuetxt'},
                           'size' => 40,
			   'regexp' => '\S',
			   'dot' => 0,
                         },
                       ],
         },
	 { 'type' => 'SOA',
	   'desc' => $text{'records_typesoa'},
	   'domain' => 1,
	   'create' => 0,
	 },
	 { 'type' => 'SPF',
	   'desc' => $text{'records_typespf'},
	   'domain' => 1,
	   'create' => 0,
	 },
	 { 'type' => 'PTR',
	   'desc' => $text{'records_typeptr'},
	   'domain' => 0,
	   'create' => 1,
	   'values' => [ { 'desc' => $text{'records_valueptr'},
			   'size' => 40,
			   'func' => sub { $_[0] =~ /^[a-z0-9\.\_\-]+\.$/i ?
					    undef : $text{'records_evalueptr'} }
			 },
		       ],
	 },
	 { 'type' => 'SRV',
	   'desc' => $text{'records_typesrv'},
	   'domain' => 1,
	   'create' => 1,
	   'values' => [ { 'desc' => $text{'records_valuesrv1'},
                           'size' => 5,
                           'func' => sub { $_[0] =~ /^\d+$/ ?
					undef : $text{'records_evaluesrv1'} },
                         },
		         { 'desc' => $text{'records_valuesrv2'},
                           'size' => 5,
                           'func' => sub { $_[0] =~ /^\d+$/i ?
                                        undef : $text{'records_evaluesrv2'} },
                         },
		         { 'desc' => $text{'records_valuesrv3'},
                           'size' => 10,
                           'func' => sub { $_[0] =~ /^\d+$/i ?
                                        undef : $text{'records_evaluesrv3'} },
                         },
		         { 'desc' => $text{'records_valuesrv4'},
                           'size' => 40,
                           'func' => sub { $_[0] =~ /^[a-z0-9\.\_\-]+$/i ?
                                        undef : $text{'records_evaluesrv4'} },
			   'dot' => 1,
                         },
                       ],
	 },

       );
}

# ttl_to_seconds(string)
# Converts a TTL string like 1h to a number of seconds, like 3600
sub ttl_to_seconds
{
my ($str) = @_;
return $str =~ /^(\d+)s$/i ? $1 :
       $str =~ /^(\d+)m$/i ? $1*60 :
       $str =~ /^(\d+)h$/i ? $1*3600 :
       $str =~ /^(\d+)d$/i ? $1*86400 :
       $str =~ /^(\d+)w$/i ? $1*7*86400 : $str;
}

# obtain_lock_dns(&domain, [named-conf-too])
# Lock a domain's zone file and named.conf file
sub obtain_lock_dns
{
local ($d, $conftoo) = @_;
return if (!$config{'dns'});
&obtain_lock_anything($d);
local $prov = $d ? $d->{'provision_dns'} : $config{'provision_dns'};

# Lock records file
if ($d && !$prov) {
	if ($main::got_lock_dns_zone{$d->{'id'}} == 0) {
		&require_bind();
		local $conf = &bind8::get_config();
		local $z = &get_bind_zone($d->{'dom'}, $conf);
		local $fn;
		if ($z) {
			local $file = &bind8::find("file", $z->{'members'});
			$fn = $file->{'values'}->[0];
			}
		else {
			local $base = $bconfig{'master_dir'} ||
				      &bind8::base_directory($conf);
			$fn = &bind8::automatic_filename($d->{'dom'}, 0, $base);
			}
		local $rootfn = &bind8::make_chroot($fn);
		&lock_file($rootfn);
		$main::got_lock_dns_file{$d->{'id'}} = $rootfn;
		}
	$main::got_lock_dns_zone{$d->{'id'}}++;
	}

# Lock named.conf for this domain, if needed. We assume that all domains are
# in the same .conf file, even though that may not be true.
if ($conftoo && !$prov) {
	if ($main::got_lock_dns == 0) {
		&require_bind();
		undef(@bind8::get_config_cache);
		undef(%bind8::get_config_parent_cache);
		&lock_file(&bind8::make_chroot($bind8::config{'zones_file'} ||
					       $bind8::config{'named_conf'}));
		}
	$main::got_lock_dns++;
	}
}

# release_lock_dns(&domain, [named-conf-too])
# Unlock the zone's records file and possibly named.conf entry
sub release_lock_dns
{
local ($d, $conftoo) = @_;
return if (!$config{'dns'});
local $prov = $d ? $d->{'provision_dns'} : $config{'provision_dns'};

# Unlock records file
if ($d && !$prov) {
	if ($main::got_lock_dns_zone{$d->{'id'}} == 1) {
		local $rootfn = $main::got_lock_dns_file{$d->{'id'}};
		&unlock_file($rootfn) if ($rootfn);
		}
	$main::got_lock_dns_zone{$d->{'id'}}--
		if ($main::got_lock_dns_zone{$d->{'id'}});
	}

# Unlock named.conf
if ($conftoo && !$prov) {
	if ($main::got_lock_dns == 1) {
		&require_bind();
		&unlock_file(&bind8::make_chroot($bind8::config{'zones_file'} ||
					         $bind8::config{'named_conf'}));
		}
	$main::got_lock_dns-- if ($main::got_lock_dns);
	}

&release_lock_anything($d);
}

$done_feature_script{'dns'} = 1;

1;

