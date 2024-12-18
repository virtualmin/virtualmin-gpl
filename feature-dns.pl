
# require_bind([&domain])
sub require_bind
{
my ($d) = @_;
my $r = &get_domain_remote_dns($d);
return $r if ($require_bind{$r->{'id'}}++);
&foreign_require("bind8");
&remote_foreign_require($r, "bind8");
%bconfig = &foreign_config("bind8");
return $r;
}

# check_depends_dns(&domain)
# For a sub-domain that is being added to a parent DNS domain, make sure the
# parent zone actually exists
sub check_depends_dns
{
my ($d) = @_;
if ($d->{'subdom'}) {
	my $tmpl = &get_template($d->{'template'});
	my $parent = &get_domain($d->{'subdom'});
	if ($tmpl->{'dns_sub'} && !$parent->{'dns'}) {
		return $text{'setup_edepdnssub'};
		}
	}
return undef;
}

# check_anti_depends_dns(&dom)
# Ensure that a parent server without DNS does not have any sub-domains with it
sub check_anti_depends_dns
{
my ($d) = @_;
if (!$d->{'dns'}) {
	foreach my $sd (&get_domain_by("dns_subof", $d->{'id'})) {
		if ($sd->{'dns'}) {
			return $text{'setup_edepdnssub2'};
			}
		}
	}
return undef;
}

# setup_dns(&domain)
# Set up a zone for a domain
sub setup_dns
{
my ($d) = @_;
&require_bind();
my $tmpl = &get_template($d->{'template'});
my $ip = $d->{'dns_ip'} || $d->{'ip'};
my @extra_slaves = split(/\s+/, &substitute_domain_template(
					$tmpl->{'dns_ns'}, $d));

# Find the DNS domain that this could be placed under
my $dnsparent;
my $dns_submode = defined($d->{'dns_submode'}) ? $d->{'dns_submode'} :
			$tmpl->{'dns_sub'} eq 'yes' ? 1 : 0;
if ($d->{'subdom'}) {
	# Special subdom mode, always under that domain
	$dnsparent = &get_domain($d->{'subdom'});
	}
elsif ($dns_submode) {
	# Find most suitable domain with the same owner that has it's own file
	$dnsparent = &find_parent_dns_domain($d);
	}

# Set alias domain DNS records mode from template
if ($d->{'alias'} && !defined($d->{'aliasdns'})) {
	$d->{'aliasdns'} = $tmpl->{'dns_alias'} eq 'yes' ? 1 : 0;
	}

# Create the list of DNS records
my $recs = [ ];
my $recstemp = &transname();
my $recserr;
eval {
	local $bind8::config{'auto_chroot'} = undef;
	local $bind8::config{'chroot'} = undef;
	if ($d->{'alias'} && !$d->{'aliasdns'}) {
		$recserr = &create_alias_records($recs, $recstemp, $d, $ip);
		}
	else {
		$recserr = &create_standard_records($recs, $recstemp, $d, $ip);
		}
	};
$recserr ||= $@;

# Create domain info object
my $info;
if ($d->{'provision_dns'} || $d->{'dns_cloud'}) {
	$info = { 'domain' => $d->{'dom'} };
	if (@extra_slaves) {
		$info->{'slave'} = [ grep { $_ } map { &to_ipaddress($_) }
						     @extra_slaves ];
		}
	$info->{'recs'} = $recs;
	}

if ($d->{'provision_dns'}) {
	# Create on provisioning server
	$d->{'dns_submode'} = 0;	# Adding to existing domain not
					# supported by Cloudmin Services
	my @precs = grep { $_->{'type'} ne 'NS' } @{$info->{'recs'}};
	$info->{'record'} = [ &records_to_text($d, \@precs) ];
	delete($info->{'recs'});
	&$first_print($text{'setup_bind_provision'});
	if ($recserr) {
		&$second_print(&text('setup_bind_erecs', $err));
		return 0;
		}
	my ($ok, $msg) = &provision_api_call(
		"provision-dns-zone", $info, 0);
	if (!$ok || $msg !~ /host=(\S+)/) {
		&$second_print(&text('setup_ebind_provision', $msg));
		return 0;
		}
	$d->{'provision_dns_host'} = $1;
	&$second_print(&text('setup_bind_provisioned',
			     $d->{'provision_dns_host'}));
	}
elsif ($d->{'dns_cloud'} && !$dnsparent) {
	# Create on Cloud DNS service
	my $ctype = $d->{'dns_cloud'};
	my ($cloud) = grep { $_->{'name'} eq $ctype } &list_dns_clouds();
	if ($cloud->{'import'}) {
		&$first_print(&text('setup_bind_cloudi', $cloud->{'desc'}));
		}
	else {
		&$first_print(&text('setup_bind_cloud', $cloud->{'desc'}));
		}
	if ($recserr) {
		&$second_print(&text('setup_bind_erecs', $err));
		return 0;
		}
	my $vfunc = "dnscloud_".$ctype."_valid_domain";
	my $err = &$vfunc($d, $info);
	if ($err) {
		&$second_print(&text('setup_ebind_cloud', $err));
		return 0;
		}
	my $cfunc = "dnscloud_".$ctype."_create_domain";
	my ($ok, $msg, $location, $err2) = &$cfunc($d, $info);
	my $efunc = "dnscloud_".$ctype."_post_validate";
	($ok, $msg, $location, $err2) =
		&$efunc($d, $ok, $msg, $location, $err2)
			if (defined(&$efunc));
	if ($ok == 0) {
		&$second_print(&text('setup_ebind_cloud', $msg));
		return 0;
		}
	$d->{'dns_cloud_id'} = $msg;
	$d->{'dns_cloud_location'} = $location;
	if ($ok == 1) {
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print(&text('setup_ebind_cloud2', $err2));
		}
	}
elsif (!$dnsparent) {
	# Creating a new real BIND zone
	&obtain_lock_dns($d, 1);
	my $r = &require_bind($d);
	if ($r->{'id'} == 0) {
		&$first_print($text{'setup_bind'});
		}
	else {
		&$first_print(&text('setup_bindremote', $r->{'host'}));
		}
	if ($recserr) {
		&$second_print(&text('setup_bind_erecs', $err));
		return 0;
		}
	my $conf = &remote_foreign_call($r, "bind8", "get_config");
	my $czone = &get_bind_zone($d->{'dom'}, $conf, $d);
	if ($czone) {
		# Clashing zone already exists, but it's probably a slave.
		# Just remove it.
		my $pconf = &remote_foreign_call(
			$r, "bind8", "get_config_parent", $czone->{'file'});
		&remote_foreign_call($r, "bind8", "save_directive", $pconf,
				     [ $czone ], [ ]);
		}
	my $rbconfig = &remote_foreign_config($r, "bind8");
	my $base = $rbconfig->{'master_dir'} ||
	      &remote_foreign_call($r, "bind8", "base_directory", $conf);
	my $file = &remote_foreign_call($r, "bind8", "automatic_filename",
					   $d->{'dom'}, 0, $base);
	my $dir = {
		 'name' => 'zone',
		 'values' => [ $d->{'dom'} ],
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
	local @slaves = &get_default_domain_slaves($d);
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
			my %donealso;
			@also = grep { $_->{'name'} && !$donealso{$_->{'name'}}++ } @also;
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
	my $opts = &bind8::find("options", $conf);
	my $gat = &bind8::find("allow-transfer", $opts->{'members'});
	if ($gat) {
		push(@trans, @{$gat->{'members'}});
		}
	my %donetrans;
	@trans = grep { $_->{'name'} && !$donetrans{$_->{'name'}}++ } @trans;
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
	local $addfile = &remote_foreign_call($r, "bind8", "add_to_file");
	if ($tmpl->{'dns_view'}) {
		# Adding inside a view. This may use named.conf, or an include
		# file references inside the view, if any
		$pconf = &remote_foreign_call($r, "bind8", "get_config_parent");
		local $view = &get_bind_view($conf, $tmpl->{'dns_view'});
		if ($view) {
			local $addfileok;
			if ($rbconfig->{'zones_file'} &&
			    $view->{'file'} ne $rbconfig->{'zones_file'}) {
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
				$pconf = &remote_foreign_call($r, "bind8",
					"get_config_parent", $addfile);
				}
			$d->{'dns_view'} = $tmpl->{'dns_view'};
			}
		else {
			&error(&text('setup_ednsview', $tmpl->{'dns_view'}));
			}
		}
	else {
		# Adding at top level .. but perhaps in a different file
		$dir->{'file'} = $addfile;
		$pconf = &remote_foreign_call($r, "bind8", "get_config_parent",
					      $dir->{'file'});
		}
	&remote_foreign_call($r, "bind8", "save_directive", $pconf, undef, [ $dir ], $indent);
	&remote_foreign_call($r, "bind8", "flush_file_lines");
	&remote_foreign_call($r, "bind8", "flush_zone_names");
	&remote_foreign_call($r, "bind8", "clear_config_cache");

	# Work out if can copy from alias target - not possible if target
	# is a sub-domain, as they don't have their own domain. Also not
	# possible if target uses another domain's zone file to store its
	# records.
	local $copyfromalias = &copy_alias_records($d);

	# Create the records file
	local $rootfile = &remote_foreign_call($r, "bind8", "make_chroot", $file);
	if (!-d $rootfile) {
		&remote_foreign_call($r, "bind8", "unlink_logged", $rootfile);
		}
	if ($r->{'id'} == 0) {
		# If DNS is local, just copy over the records file file we
		# created above. Otherwise, it will be uploaded in
		# post_records_change
		&copy_source_dest($recstemp, $rootfile);
		}
	&post_records_change($d, $recs, $recstemp);
	&remote_foreign_call($r, "bind8", "set_ownership", $rootfile);
	&$second_print($text{'setup_done'});

	# If DNSSEC was requested, set it up
	if ($tmpl->{'dnssec'} eq 'yes' && &can_domain_dnssec($d)) {
		&$first_print($text{'setup_dnssec'});
		$err = &enable_domain_dnssec($d);
		if (!$err) {
			&add_parent_dnssec_ds_records($d);
			}
		&$second_print($err || $text{'setup_done'});
		}

	# Create on slave servers
	local $myip = $rbconfig->{'this_ip'} ||
		      &to_ipaddress(&get_system_hostname());
	if (@slaves && !$d->{'noslaves'}) {
		local $slaves = join(" ", map { $_->{'nsname'} ||
						$_->{'host'} } @slaves);
		&create_zone_on_slaves($d, $slaves);
		}

	# If website has a *.domain.com ServerAlias, add * DNS record now
	if ($d->{'web'} && &get_domain_web_star($d)) {
		&save_domain_matchall_record($d, 1);
		}

	&release_lock_dns($d, 1);
	}
else {
	# Creating a sub-domain - add to parent's DNS zone.
	&$first_print(&text('setup_bindsub', $dnsparent->{'dom'}));
	delete($d->{'dns_cloud'});	# Cloud always comes from parent
	&obtain_lock_dns($dnsparent);
	&pre_records_change($dnsparent);
	my ($recs, $file) = &get_domain_dns_records_and_file($dnsparent);
	if (!$file) {
		&error(&text('setup_ednssub', $dnsparent->{'dom'}));
		}
	$d->{'dns_submode'} = 1;	# So we know how this was done
	$d->{'dns_subof'} = $dnsparent->{'id'};
	local ($already) = grep { $_->{'name'} eq $d->{'dom'}."." }
				grep { $_->{'type'} eq 'A' } @$recs;
	if ($already) {
		# A record with the same name as the sub-domain exists .. we
		# don't want to delete this later
		$d->{'dns_subalready'} = 1;
		}
	my $ip = $d->{'dns_ip'} || $d->{'ip'};
	&create_standard_records($recs, $file, $d, $ip);
	&post_records_change($dnsparent, $recs, $file);

	&release_lock_dns($dnsparent);
	&add_parent_dnssec_ds_records($d);
	&$second_print($text{'setup_done'});
	}
&register_post_action(\&restart_bind, $d);
return 1;
}

sub slave_error_handler
{
$slave_error = $_[0];
}

# delete_dns(&domain)
# Delete a domain from the BIND config
sub delete_dns
{
local ($d) = @_;
&require_bind();
if ($d->{'dns_cloud'} && !$d->{'dns_submode'}) {
	# Delete from Cloud DNS provider
	my $ctype = $d->{'dns_cloud'};
	my ($cloud) = grep { $_->{'name'} eq $ctype } &list_dns_clouds();
	&$first_print(&text('delete_bind_cloud', $cloud->{'desc'}));
	my $info = { 'domain' => $d->{'dom'},
		     'id' => $d->{'dns_cloud_id'},
		     'location' => $d->{'dns_cloud_location'} };
	my $dfunc = "dnscloud_".$ctype."_delete_domain";
	my ($ok, $msg) = &$dfunc($d, $info);
	if (!$ok) {
		&$second_print(&text('delete_ebind_cloud', $msg));
		return 0;
		}
	delete($d->{'dns_cloud_id'});
	delete($d->{'dns_cloud_location'});
	delete($domain_dns_records_cache{$d->{'id'}});
	&$second_print($text{'setup_done'});
	}
elsif ($d->{'provision_dns'}) {
	# Delete from provisioning server
	&$first_print($text{'delete_bind_provision'});
	if ($d->{'provision_dns_host'}) {
		local $info = { 'domain' => $d->{'dom'},
				'host' => $d->{'provision_dns_host'} };
		my ($ok, $msg) = &provision_api_call(
			"unprovision-dns-zone", $info, 0);
		if (!$ok) {
			&$second_print(&text('delete_ebind_provision', $msg));
			return 0;
			}
		delete($d->{'provision_dns_host'});
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'delete_bind_provision_none'});
		}
	delete($domain_dns_records_cache{$d->{'id'}});
	}
elsif (!$d->{'dns_submode'}) {
	# Delete real domain
	my $r = &require_bind($d);
	if ($r->{'id'} == 0) {
		&$first_print($text{'delete_bind'});
		}
	else {
		&$first_print(&text('delete_bindremote', $r->{'host'}));
		}
	&obtain_lock_dns($d, 1);
	local $z = &get_bind_zone($d->{'dom'}, undef, $d);
	if ($z) {
		# Delete DS records in parent
		&delete_parent_dnssec_ds_records($d);

		# Delete any dnssec key
		if (&remote_foreign_call($r, "bind8", "supports_dnssec")) {
			&remote_foreign_call($r, "bind8",
					     "delete_dnssec_key", $z, 0);
			&remote_foreign_call($r, "bind8",
					     "dt_delete_dnssec_state", $z);
			}

		# Delete the records file
		local $file = &bind8::find("file", $z->{'members'});
		if ($file) {
			local $zonefile = &remote_foreign_call($r, "bind8",
				"make_chroot", $file->{'values'}->[0]);
			&remote_foreign_call($r, "bind8", "unlink_logged",
					     $zonefile,
					     $zonefile.".log",
					     $zonefile.".jnl");
			}

		# Delete from named.conf
		$pconf = &remote_foreign_call($r, "bind8", "get_config_parent",
					      $z->{'file'});
		&remote_foreign_call($r, "bind8", "save_directive", $pconf,
				     [ $z ], [ ]);
		&remote_foreign_call($r, "bind8", "flush_file_lines");

		# Clear zone names caches
		&remote_foreign_call($r, "bind8", "flush_zone_names");
		&remote_foreign_call($r, "bind8", "clear_config_cache");
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'save_nobind'});
		}

	&delete_zone_on_slaves($d);
	&release_lock_dns($d, 1);
	delete($domain_dns_records_cache{$d->{'id'}});
	}
else {
	# Delete records from parent zone
	local $dnsparent = &get_domain($d->{'dns_subof'});
	if (!$dnsparent) {
		&$second_print($text{'delete_ebindsub'});
		return;
		}
	&$first_print(&text('delete_bindsub', $dnsparent->{'dom'}));
	&obtain_lock_dns($dnsparent);
	&delete_parent_dnssec_ds_records($d);
	local ($recs, $file) = &get_domain_dns_records_and_file($dnsparent);
	if (!$file) {
		&$second_print(&text('save_nobind2', $recs));
		return;
		}
	&pre_records_change($dnsparent);
	local $withdot = $d->{'dom'}.".";
	foreach $r (@$recs) {
		# Don't delete if outside sub-domain
		next if ($r->{'name'} !~ /\Q$withdot\E$/);
		# Don't delete if the same as an existing record
		next if ($r->{'name'} eq $withdot && $r->{'type'} eq 'A' &&
			 $d->{'dns_subalready'});
		push(@delrecs, $r);
		}
	foreach my $r (@delrecs) {
		&delete_dns_record($recs, $file, $r);
		}
	&post_records_change($dnsparent, $recs, $file);
	&release_lock_dns($dnsparent);
	&$second_print($text{'setup_done'});
	delete($d->{'dns_submode'});
	}
&register_post_action(\&restart_bind, $d);
return 1;
}

# clone_dns(&domain, &old-domain)
# Copy all DNS records to a new domain
sub clone_dns
{
local ($d, $oldd) = @_;
&$first_print($text{'clone_dns'});
if ($d->{'dns_submode'}) {
	# Record cloning not needed for DNS sub-domains
	&$second_print($text{'clone_dnssub'});
	return 1;
	}
local ($orecs, $ofile) = &get_domain_dns_records_and_file($oldd);
local ($recs, $file) = &get_domain_dns_records_and_file($d);
local @dnskeys = grep { $_->{'type'} eq 'DNSKEY' } @$recs;
if (!$orecs) {
	&$second_print($text{'clone_dnsold'});
	return 0;
	}
if (!$recs) {
	&$second_print($text{'clone_dnsnew'});
	return 0;
	}
&obtain_lock_dns($d);

# Remove all existing records, and create new ones
&pre_records_change($d);
my @delrecs;
foreach my $r (@$recs) {
	next if ($r->{'type'} eq 'SOA');
	push(@delrecs, $r);
	}
foreach my $r (@delrecs) {
	&delete_dns_record($recs, $file, $r);
	}
foreach my $r (@$orecs) {
	next if ($r->{'type'} eq 'SOA');
	my $nr = &clone_dns_record($r);
	&create_dns_record($recs, $file, $nr);
	}
&modify_records_domain_name($recs, $file, $oldd->{'dom'}, $d->{'dom'});
local $oldip = $oldd->{'dns_ip'} || $oldd->{'ip'};
local $newip = $d->{'dns_ip'} || $d->{'ip'};
if ($oldip ne $newip) {
	&modify_records_ip_address($recs, $file, $oldip, $newip);
	}
if ($d->{'ip6'} && $d->{'ip6'} ne $oldd->{'ip6'}) {
	&modify_records_ip_address($recs, $file, $oldd->{'ip6'}, $d->{'ip6'});
	}

# Find and delete sub-domain records, plus any DNSSEC records (since we need
# to re-sign the zone)
local @sublist = grep { $_->{'id'} ne $oldd->{'id'} &&
			$_->{'id'} ne $d->{'id'} &&
			$_->{'dom'} =~ /\.\Q$oldd->{'dom'}\E$/ }
		      &list_domains();
RECORD: foreach my $r (@$recs) {
	foreach my $sd (@sublist) {
		if ($r->{'name'} eq $sd->{'dom'}."." ||
		    $r->{'name'} =~ /\.\Q$sd->{'dom'}\E\.$/) {
			&delete_dns_record($recs, $file, $r);
			next RECORD;
			}
		}
	if (&is_dnssec_record($r)) {
		&delete_dns_record($recs, $file, $r);
		}
	}

# If DNSSEC was enabled in the clone, put back the DNSKEY records
foreach my $r (@dnskeys) {
	&create_dns_record($recs, $file, $r);
	}

&post_records_change($d, $recs, $file);
&release_lock_dns($d);
&register_post_action(\&restart_bind, $d);
&$second_print($text{'setup_done'});
return 1;
}

# get_default_domain_slaves(&domain)
# Returns a list of slave nameservers to use when setting up DNS for this domain
sub get_default_domain_slaves
{
my ($d) = @_;
&require_bind();
my $tmpl = &get_template($d->{'template'});
my @slaves = &bind8::list_slave_servers();
if ($tmpl->{'dns_slaves'} eq 'none') {
	return ( );
	}
if ($tmpl->{'dns_slaves'} eq '') {
	return @slaves;
	}
my %smap = map { $_, 1 } split(/\s+/, $tmpl->{'dns_slaves'});
return grep { $smap{$_->{'id'}} } @slaves;
}

# create_zone_on_slaves(&domain, space-separate-slave-list)
# Create a zone on all specified slaves, and updates the dns_slave key.
# May print messages.
sub create_zone_on_slaves
{
my ($d, $slaves) = @_;
my $r = &require_bind($d);
my $rbconfig = &remote_foreign_config($r, "bind8");
my $tmpl = &get_template($d->{'template'});
my @extra_slaves = grep { $_ } map { &to_ipaddress($_) }
	split(/\s+/, &substitute_domain_template($tmpl->{'dns_ns'}, $d));
my $myip = $rbconfig->{'this_ip'} ||
	   &remote_foreign_call($r, "bind8", "to_ipaddress",
		&remote_foreign_call($r, "bind8", "get_system_hostname"));
&$first_print(&text('setup_bindslave', $slaves));
if (!$myip) {
	# IP lookup failed
	&$second_print($text{'setup_ebindslaveip2'});
	return;
	}
if ($myip =~ /^127\.0/) {
	# Looks like a my network, which can't be correct
	&$second_print(&text('setup_ebindslaveip', $myip));
	return;
	}
my @slaveerrs = &bind8::create_on_slaves(
	$d->{'dom'}, $myip, undef, [ split(/\s+/, $slaves) ],
	$d->{'dns_view'} || $tmpl->{'dns_view'},
	\@extra_slaves);
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
my @newslaves;
foreach my $s (split(/\s+/, $slaves)) {
	my ($err) = grep { $_->[0]->{'host'} eq $s } @slaveerrs;
	if (!$err) {
		push(@newslaves, $s);
		}
	}
my @oldslaves = split(/\s+/, $d->{'dns_slave'});
$d->{'dns_slave'} = join(" ", &unique(@oldslaves, @newslaves));

&register_post_action(\&restart_bind, $d);
}

# delete_zone_on_slaves(&domain, [space-separate-slave-list])
# Delete a zone on all slave servers, from the dns_slave key. May print messages
sub delete_zone_on_slaves
{
local ($d, $slaveslist) = @_;
local $oldd = { %$d };
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

&register_post_action(\&restart_bind, $oldd);
}

# update_dns_slave_ip_addresses(ip, old-ip, [&doms])
# Update all DNS slave servers for a change in master IP. May print stuff.
sub update_dns_slave_ip_addresses
{
my ($ip, $oldip, $doms) = @_;
$doms ||= [ &list_domains() ];
&require_bind();
my @bdoms = grep { $_->{'dns'} && $_->{'dns_slave'} ne '' } @$doms;
my $oldmasterip = $bconfig{'this_ip'} ||
                  &to_ipaddress(&get_system_hostname());
my $bc = 0;
if ($oldmasterip eq $oldip && $oldip ne $ip) {
	if ($bconfig{'this_ip'} eq $oldip) {
		$bconfig{'this_ip'} = $ip;
		&save_module_config(\%bconfig, "bind8");
		}
	foreach my $d (@bdoms) {
		my $oldslaves = $d->{'dns_slave'};
		&delete_zone_on_slaves($d);
		if ($oldslaves) {
			&create_zone_on_slaves($d, $oldslaves);
			}
		$bc++;
		}
	}
return $bc;
}

# exists_on_slave(zone-name, &slave)
# Returns "OK" if some zone exists on the given DNS slave, undef if not, or
# an error message otherwise.
sub exists_on_slave
{
my ($name, $slave) = @_;
&remote_error_setup(\&bind8::slave_error_handler);
&remote_foreign_require($slave, "bind8");
return $bind8::slave_error if ($bind8::slave_error);
my $z = &remote_foreign_call($slave, "bind8", "get_zone_name", $name, "any");
return $z ? "OK" : undef;
}

# modify_dns(&domain, &olddomain)
# If the IP for this server has changed, update all records containing the old
# IP to the new.
sub modify_dns
{
my ($d, $oldd) = @_;
my $tmpl = &get_template($d->{'template'});

my $subof = $d->{'dns_submode'} ? &get_domain($d->{'dns_subof'}) : undef;
if (!$d->{'subdom'} && $oldd->{'subdom'} && $d->{'dns_submode'} ||
    !&under_parent_domain($d, $subof) && $d->{'dns_submode'}) {
	# Converting from a sub-domain to top-level .. first move the records
	# out into their own file
	&$first_print($text{'save_dns8'});
	&push_all_print();
	&set_all_null_print();
	&save_dns_submode($oldd, 0);
	$d->{'dns_submode'} = 0;
	delete($d->{'dns_subof'});
	&delete_parent_dnssec_ds_records($oldd);
	&pop_all_print();
	&$second_print($text{'setup_done'});
	}
if ($d->{'alias'} && $oldd->{'alias'} &&
    $d->{'alias'} != $oldd->{'alias'}) {
	# Alias target changed, just delete and re-create
	&delete_dns($oldd);
	&setup_dns($d);
	return 1;
	}

my $r = &require_bind($d);
my ($oldzonename, $newzonename, $lockon, $lockconf, $zdom);
if ($d->{'dns_submode'}) {
	# Get parent domain
	my $dnsparent = &get_domain($d->{'dns_subof'});
	&obtain_lock_dns($dnsparent);
	$lockon = $dnsparent;
	$zdom = $dnsparent;
	$oldzonename = $newzonename = $dnsparent->{'dom'};
	}
else {
	# Get this domain
	&obtain_lock_dns($d, 1);
	$lockon = $d;
	$lockconf = 1;
	$zdom = $oldd;
	$newzonename = $oldd->{'dom'};
	$oldzonename = $oldd->{'dom'};
	}
my $oldip = $oldd->{'dns_ip'} || $oldd->{'ip'};
my $newip = $d->{'dns_ip'} || $d->{'ip'};
my $rv = 0;

# Zone file name and records, if we read them
my ($file, $recs);
&pre_records_change($d);

my $check_submode = 0;
if ($d->{'dom'} ne $oldd->{'dom'} && $d->{'provision_dns'}) {
	# Domain name has changed .. rename via API call
	&$first_print($text{'save_dns2_provision'});
	my $info = { 'domain' => $oldd->{'dom'},
			'host' => $d->{'provision_dns_host'},
			'new-domain' => $d->{'dom'} };
	my ($ok, $msg) = &provision_api_call("modify-dns-zone", $info, 0);
	if (!$ok) {
		&$second_print(&text('disable_ebind_provision', $msg));
		return 0;
		}
	&$second_print($text{'setup_done'});

	# Rename records
	($recs, $file) = &get_domain_dns_records_and_file($d) if (!$file);
	if (!$file) {
		&$second_print(&text('save_nobind2', $recs));
		&release_lock_dns($lockon, $lockconf);
		return 0;
		}
	&modify_records_domain_name($recs, $file,
				    $oldd->{'dom'}, $d->{'dom'});
	}
elsif ($d->{'dom'} ne $oldd->{'dom'} && $d->{'dns_cloud'}) {
	# Domain name has changed .. rename on cloud provider
	my $ctype = $d->{'dns_cloud'};
	my ($cloud) = grep { $_->{'name'} eq $ctype } &list_dns_clouds();
	&$first_print(&text('save_bind_cloud', $cloud->{'desc'}));
	my $info = { 'domain' => $d->{'dom'},
		     'olddomain' => $oldd->{'dom'},
		     'id' => $d->{'dns_cloud_id'},
		     'location' => $d->{'dns_cloud_location'} };
	my $vfunc = "dnscloud_".$ctype."_valid_domain";
	my $err = &$vfunc($d, $info);
	if ($err) {
		&$second_print(&text('setup_ebind_cloud', $err));
		}
	else {
		my $rfunc = "dnscloud_".$ctype."_rename_domain";
		my ($ok, $id) = &$rfunc($d, $info);
		my $efunc = "dnscloud_".$ctype."_post_validate";
		($ok, $id) = &$efunc($d, $ok, $id) if (defined(&$efunc));
		if (!$ok) {
			&$second_print(&text('save_bind_ecloud', $id));
			}
		else {
			$d->{'dns_cloud_id'} = $id;
			&$second_print($text{'setup_done'});
			}
		}
	}
elsif ($d->{'dom'} ne $oldd->{'dom'}) {
	# Domain name has changed .. rename locally
	my $z = &get_bind_zone($zdom->{'dom'}, undef, $d);
	if (!$z) {
		# Zone not found!
		&$second_print($text{'save_dns2_ezone'});
		&release_lock_dns($lockon, $lockconf);
		return 0;
		}
	my $f = &bind8::find("file", $z->{'members'});
	if (!$d->{'dns_submode'}) {
		# Domain name has changed .. rename zone file
		&$first_print($text{'save_dns2'});
		my $fn = $f->{'values'}->[0];
		my $nfn = $fn;
		$nfn =~ s/$oldd->{'dom'}/$d->{'dom'}/;
		if ($fn ne $nfn) {
			&remote_foreign_call($r, "bind8", "rename_logged",
			  &remote_foreign_call($r, "bind8", "make_chroot", $fn),
			  &remote_foreign_call($r, "bind8", "make_chroot", $nfn));
			}
		$f->{'values'}->[0] = $nfn;
		$f->{'value'} = $nfn;

		# Change zone in .conf file
		$z->{'values'}->[0] = $d->{'dom'};
		$z->{'value'} = $d->{'dom'};
		my $pconf = &remote_foreign_call(
			$r, "bind8", "get_config_parent");
		&remote_foreign_call($r, "bind8", "save_directive", $pconf,
			[ $z ], [ $z ], 0);
		&remote_foreign_call($r, "bind8", "flush_file_lines");
		&remote_foreign_call($r, "bind8", "clear_config_cache");
		}
	else {
		&$first_print($text{'save_dns6'});
		}
	&clear_domain_dns_records_and_file($d);

	# Modify any records containing the old name
	#&lock_file(&bind8::make_chroot($nfn));
	&pre_records_change($d);
	($recs, $file) = &get_domain_dns_records_and_file($d);
	if (!$file) {
		&$second_print(&text('save_dns2_enewfile', $recs));
		&release_lock_dns($lockon, $lockconf);
		return 0;
		}
	&modify_records_domain_name($recs, $file,
				    $oldd->{'dom'}, $d->{'dom'});

        # Update SOA record
	&post_records_change($d, $recs, $file);
	#&unlock_file(&bind8::make_chroot($nfn));
	$rv++;

	# Clear zone names caches
	unlink($bind8::zone_names_cache);
	undef(@bind8::list_zone_names_cache);
	&$second_print($text{'setup_done'});

	# After a rename, DNS records may now be eligible to be hosted by
	# the parent DNS zone
	$check_submode = 1;

	if (!$d->{'dns_submode'}) {
		my @slaves = split(/\s+/, $d->{'dns_slave'});
		if (@slaves) {
			# Rename on slave servers too
			&$first_print(&text('save_dns3', $d->{'dns_slave'}));
			my @slaveerrs = &bind8::rename_on_slaves(
				$oldd->{'dom'}, $d->{'dom'}, \@slaves);
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
elsif ($d->{'parent'} ne $oldd->{'parent'}) {
	# Parent domain has changed, but domain name has not. May be eligible
	# for a sub-domain transfer
	$check_submode = 1;
	}

if ($check_submode) {
	my $dnsparent = &find_parent_dns_domain($d);
	if (!$d->{'dns_submode'} && $tmpl->{'dns_sub'} eq 'yes' && $dnsparent) {
		&$first_print($text{'save_dns8'});
		&push_all_print();
		&set_all_null_print();
		&save_dns_submode($d, 1);
		&pop_all_print();
		delete($domain_dns_records_cache{$d->{'id'}});
		$recs = $file = undef;
		&$second_print($text{'setup_done'});
		}
	}

if ($oldip ne $newip) {
	# IP address has changed .. need to update any records that use
	# the old IP
	&$first_print($text{'save_dns'});
	($recs, $file) = &get_domain_dns_records_and_file($d) if (!$file);
	if (!$file) {
		&$second_print(&text('save_nobind2', $recs));
		&release_lock_dns($lockon, $lockconf);
		return 0;
		}
	&modify_records_ip_address($recs, $file, $oldip, $newip,
				   $d->{'dom'});
	$rv++;
	&$second_print($text{'setup_done'});
	}
elsif ($oldd->{'ip'} ne $d->{'ip'}) {
	# Internal IP address changed, but external IP didn't
	&$first_print($text{'save_dnsinternal'});
	($recs, $file) = &get_domain_dns_records_and_file($d) if (!$file);
	if (!$file) {
		&$second_print(&text('save_nobind2', $recs));
		&release_lock_dns($lockon, $lockconf);
		return 0;
		}
	&modify_records_ip_address($recs, $file, $oldd->{'ip'}, $d->{'ip'},
				   $d->{'dom'});
	$rv++;
	&$second_print($text{'setup_done'});
	}

if ($d->{'mail'} && !$oldd->{'mail'} && !$tmpl->{'dns_replace'}) {
	# Email was enabled .. add MX records
	($recs, $file) = &get_domain_dns_records_and_file($d) if (!$file);
	if (!$file) {
		&$second_print(&text('save_nobind2', $recs));
		&release_lock_dns($lockon, $lockconf);
		return 0;
		}
	&$first_print($text{'save_dns4'});
	my $ip = $d->{'dns_ip'} || $d->{'ip'};
	my $ip6 = $d->{'ip6'};
	&create_mail_records($recs, $file, $d, $ip, $ip6);
	&$second_print($text{'setup_done'});
	$rv++;
	}
elsif (!$d->{'mail'} && $oldd->{'mail'} && !$tmpl->{'dns_replace'}) {
	# Email was disabled .. remove MX records, but only those that
	# point to this system or secondaries.
	($recs, $file) = &get_domain_dns_records_and_file($d) if (!$file);
	if (!$file) {
		&$second_print(&text('save_nobind2', $recs));
		&release_lock_dns($lockon, $lockconf);
		return 0;
		}
	my $ip = $d->{'dns_ip'} || $d->{'ip'};
	my $ip6 = $d->{'ip6'};
	my %ids = map { $_, 1 }
		split(/\s+/, $d->{'mx_servers'});
	my @slaves = grep { $ids{$_->{'id'}} } &list_mx_servers();
	my @slaveips = map { &to_ipaddress($_->{'mxname'} || $_->{'host'}) }
			      @slaves;
	foreach my $r (@$recs) {
		if ($r->{'type'} eq 'A' &&
		    $r->{'name'} eq "mail.".$d->{'dom'}."." &&
		    $r->{'values'}->[0] eq $ip) {
			# mail.domain A record, pointing to our IP
			push(@mx, $r);
			}
		elsif ($r->{'type'} eq 'AAAA' &&
		       $r->{'name'} eq "mail.".$d->{'dom'}."." &&
		       $r->{'values'}->[0] eq $ip6) {
			# mail.domain AAAA record, pointing to our IP
			push(@mx, $r);
			}
		elsif ($r->{'type'} eq 'MX' &&
		       $r->{'name'} eq $d->{'dom'}.".") {
			# MX record for domain .. does it point to our IP?
			my $mxip = &to_ipaddress($r->{'values'}->[1]);
			if (!$mxip) {
				my ($mxr) = grep { $_->{'name'} eq
						   $r->{'values'}->[1] } @$recs;
				$mxip = $mxr->{'values'}->[0] if ($mxr);
				}
			if ($mxip && ($mxip eq $ip ||
				      &indexof($mxip, @slaveips) >= 0)) {
				push(@mx, $r);
				}
			}
		}
	if (@mx) {
		&$first_print($text{'save_dns5'});
		foreach my $r (@mx) {
			&delete_dns_record($recs, $file, $r);
			}
		&$second_print($text{'setup_done'});
		$rv++;
		}
	}

if ($d->{'mx_servers'} ne $oldd->{'mx_servers'} && $d->{'mail'} &&
    !$config{'secmx_nodns'}) {
	# Secondary MX servers have been changed - add or remove MX records
	&$first_print($text{'save_dns7'});
	($recs, $file) = &get_domain_dns_records_and_file($d) if (!$file);
	if (!$file) {
		&$second_print(&text('save_nobind2', $recs));
		&release_lock_dns($lockon, $lockconf);
		return 0;
		}
	my @newmxs = split(/\s+/, $d->{'mx_servers'});
	my @oldmxs = split(/\s+/, $oldd->{'mx_servers'});
	&foreign_require("servers");
	my %servers = map { $_->{'id'}, $_ }
			     (&servers::list_servers(), &list_mx_servers());
	my $withdot = $d->{'dom'}.".";

	# Add missing MX records
	foreach my $id (@newmxs) {
		if (&indexof($id, @oldmxs) < 0) {
			# A new MX .. add a record for it, if there isn't one
			my $s = $servers{$id};
			my $mxhost = $s->{'mxname'} || $s->{'host'};
			my $already = 0;
			foreach my $r (@$recs) {
				if ($r->{'type'} eq 'MX' &&
				    $r->{'name'} eq $withdot &&
				    $r->{'values'}->[1] eq $mxhost.".") {
					$already = 1;
					}
				}
			if (!$already) {
				my $r = { 'name' => $withdot,
					  'type' => 'MX',
					  'values' => [ 10, $mxhost."." ] };
				&create_dns_record($recs, $file, $r);
				}
			}
		}

	# Remove those that are no longer needed
	my @mxs;
	foreach my $id (@oldmxs) {
		if (&indexof($id, @newmxs) < 0) {
			# An old MX .. remove it
			my $s = $servers{$id};
			my $mxhost = $s->{'mxname'} || $s->{'host'};
			foreach my $r (@$recs) {
				if ($r->{'type'} eq 'MX' &&
				    $r->{'name'} eq $withdot &&
				    $r->{'values'}->[1] eq $mxhost.".") {
					push(@mxs, $r);
					}
				}
			}
		}
	foreach my $r (@mxs) {
		&delete_dns_record($recs, $file, $r);
		}

	&$second_print($text{'setup_done'});
	$rv++;
	}

if ($d->{'ip6'} && !$oldd->{'ip6'}) {
	# IPv6 enabled
	&$first_print($text{'save_dnsip6on'});
	($recs, $file) = &get_domain_dns_records_and_file($d) if (!$file);
	if (!$file) {
		&$second_print(&text('save_nobind2', $recs));
		&release_lock_dns($lockon, $lockconf);
		return 0;
		}
	&add_ip6_records($d, $recs, $file);
	&$second_print($text{'setup_done'});
	$rv++;
	}
elsif (!$d->{'ip6'} && $oldd->{'ip6'}) {
	# IPv6 disabled
	&$first_print($text{'save_dnsip6off'});
	($recs, $file) = &get_domain_dns_records_and_file($d) if (!$file);
	if (!$file) {
		&$second_print(&text('save_nobind2', $recs));
		&release_lock_dns($lockon, $lockconf);
		return 0;
		}
	&remove_ip6_records($oldd, $file, $recs);
	&$second_print($text{'setup_done'});
	$rv++;
	}
elsif ($d->{'ip6'} && $oldd->{'ip6'} &&
       $d->{'ip6'} ne $oldd->{'ip6'}) {
	# IPv6 address changed
	&$first_print($text{'save_dnsip6'});
	($recs, $file) = &get_domain_dns_records_and_file($d) if (!$file);
	if (!$file) {
		&$second_print(&text('save_nobind2', $recs));
		&release_lock_dns($lockon, $lockconf);
		return 0;
		}
	&modify_records_ip_address($recs, $file, $oldd->{'ip6'}, $d->{'ip6'},
				   $d->{'dom'});
	$rv++;
	&$second_print($text{'setup_done'});
	}

# Update SOA and upload records to provisioning server
if ($file) {
	&post_records_change($d, $recs, $file);
	}
else {
	&after_records_change($d);
	}

# Release locks
&release_lock_dns($lockon, $lockconf);

&register_post_action(\&restart_bind, $d) if ($rv);
return $rv;
}

# join_record_values(&record, [always-one-line])
# Given the values for a record, joins them into a space-separated string
# with quoting if needed
sub join_record_values
{
local ($r, $oneline) = @_;
local $j = join("", @{$r->{'values'}});
if ($r->{'type'} eq 'SOA' && !$oneline) {
	# Multiliple lines, with brackets
	local $v = $r->{'values'};
	local $sep = "\n\t\t\t";
	return "$v->[0] $v->[1] ($sep$v->[2]$sep$v->[3]".
	       "$sep$v->[4]$sep$v->[5]$sep$v->[6] )";
	}
elsif (($r->{'type'} eq 'TXT' || $r->{'type'} eq 'SPF') &&
       (length($j) > 255 || @{$r->{'values'}} > 1)) {
	# Text that needs to be split up
	my $rv = &split_long_txt_record($j);
	$rv =~ s/\r?\n\s*/ /g;
	return $rv;
	}
else {
	# All one one line
	local @rv;
	foreach my $v (@{$r->{'values'}}) {
		push(@rv, $v =~ /\s|\(|;/ || $r->{'type'} eq 'TXT' ?
				"\"$v\"" : $v);
		}
	return join(" ", @rv);
	}
}

# split_long_txt_record(string, [no-brackets])
# Split a TXT record at 80 char boundaries
sub split_long_txt_record
{
local ($str, $nobrackets) = @_;
$str =~ s/^"//;
$str =~ s/"$//;
local @rv;
while($str) {
	local $first = substr($str, 0, 80);
	$str = substr($str, 80);
	push(@rv, $first);
	}
return @rv == 1 ? '"'.$rv[0].'"' :
       $nobrackets ? join(" ", map { '"'.$_.'"' } @rv) :
		     "( ".join("\n\t", map { '"'.$_.'"' } @rv)." )";
}

# create_mail_records(&records, file, &domain, ip, ip6)
# Adds MX and mail.domain records to a DNS domain
sub create_mail_records
{
my ($recs, $file, $d, $ip, $ip6) = @_;
my $tmpl = &get_template($d->{'template'});
my $proxied = $tmpl->{'dns_cloud_proxy'};
local $withdot = $d->{'dom'}.".";
my $r = { 'name' => "mail.$withdot",
	  'type' => "A",
	  'proxied' => $proxied == 1 ? 1 : 0,
	  'values' => [ $ip ] };
my ($already) = grep { $_->{'name'} eq $r->{'name'} &&
		       $_->{'type'} eq $r->{'type'} } @$recs;
&create_dns_record($recs, $file, $r) if (!$already);
if ($d->{'ip6'} && $ip6) {
	my $r = { 'name' => "mail.$withdot",
		  'type' => "AAAA",
		  'proxied' => $proxied == 1 ? 1 : 0,
		  'values' => [ $ip6 ] };
	my ($already) = grep { $_->{'name'} eq $r->{'name'} &&
			       $_->{'type'} eq $r->{'type'} } @$recs;
	&create_dns_record($recs, $file, $r) if (!$already);
	}
&create_mx_records($recs, $file, $d, $ip, $ip6);
}

# create_mx_records(&records, file, &domain, ip, ip6)
# Adds MX records to a DNS domain
sub create_mx_records
{
local ($recs, $file, $d, $ip, $ip6) = @_;
local $withdot = $d->{'dom'}.".";

# MX for this system
local $mxname = $tmpl->{'dns_mx'} && $tmpl->{'dns_mx'} ne 'none' ?
			$tmpl->{'dns_mx'}."." : "mail.$withdot";
$mxname = &substitute_domain_template($mxname, $d);
my $r = { 'name' => $withdot,
	  'type' => "MX",
	  'values' => [ 5, $mxname ] };
my ($already) = grep { $_->{'name'} eq $r->{'name'} &&
		       $_->{'type'} eq $r->{'type'} } @$recs;
&create_dns_record($recs, $file, $r) if (!$already);

# Add MX records for slaves, if enabled
if (!$config{'secmx_nodns'}) {
	local %ids = map { $_, 1 }
		split(/\s+/, $d->{'mx_servers'});
	local @servers = grep { $ids{$_->{'id'}} } &list_mx_servers();
	local $n = 10;
	foreach my $s (@servers) {
		local $mxhost = ($s->{'mxname'} || $s->{'host'}).".";
		my $r = { 'name' => $withdot,
			  'type' => "MX",
			  'values' => [ $n, $mxhost ] };
		my ($already) = grep { $_->{'name'} eq $r->{'name'} &&
				       $_->{'type'} eq $r->{'type'} } @$recs;
		&create_dns_record($recs, $file, $r) if (!$already);
		$n += 5;
		}
	}
}

# create_standard_records(&recs, file, &domain, ip)
# Adds to a records file the needed records for some domain
sub create_standard_records
{
local ($recs, $file, $d, $ip) = @_;
my $tmpl = &get_template($d->{'template'});
my $proxied = $tmpl->{'dns_cloud_proxy'};
&require_bind();
local $rootfile = &bind8::make_chroot($file);
local $master = &get_master_nameserver($tmpl, $d);
local $soa = &get_default_soa_record($d, $master);
local @created_ns;

# Extract custom records from the template
my @tmplrecs;
if ($tmpl->{'dns'} && $tmpl->{'dns'} ne 'none') {
	my %subs = %$d;
	$subs{'serial'} = $soa->{'values'}->[2];
	$subs{'dnsemail'} = $d->{'emailto_addr'};
	$subs{'dnsemail'} =~ s/\@/./g;
	my $recstxt = &substitute_domain_template(
		join("\n", split(/\t+/, $tmpl->{'dns'}))."\n", \%subs);
	@tmplrecs = &text_to_dns_records($recstxt, $d->{'dom'});
	foreach my $r (@tmplrecs) {
		$r->{'proxied'} = $proxied == 1 ? 1 : 0;
		}
	}

if (!$tmpl->{'dns_replace'} || $d->{'dns_submode'}) {
	# Create records that are appropriate for this domain, as long as the
	# user hasn't selected a completely custom template, or records are
	# being added to an existing domain
	if (!$d->{'dns_submode'}) {
		# Only add SOA and NS if this is a new file, not a sub-domain
		# in an existing file
		if ($bconfig{'master_ttl'}) {
			# Add a default TTL
			if ($tmpl->{'dns_ttl'} eq '') {
				&create_dns_record($recs, $file,
					{ 'defttl' => $soa->{'values'}->[6] });
				}
			elsif ($tmpl->{'dns_ttl'} ne 'none') {
				&create_dns_record($recs, $file,
					{ 'defttl' => $tmpl->{'dns_ttl'} });
				}
			}
		&create_dns_record($recs, $file, $soa);

		# Get nameservers from reseller, if any
		my @reselns;
		if ($d->{'reseller'} && defined(&get_reseller)) {
			foreach my $r (split(/\s+/, $d->{'reseller'})) {
				my $resel = &get_reseller($r);
				if ($resel->{'acl'}->{'defns'}) {
					@reselns = split(/\s+/,
						$resel->{'acl'}->{'defns'});
					last;
					}
				}
			}

		if (@reselns) {
			# NS records come from reseller
			foreach my $ns (@reselns) {
				$ns .= "." if ($ns !~ /\.$/);
				my $r = { 'name' => '@',
					  'type' => 'NS',
					  'values' => [ $ns ] };
				&create_dns_record($recs, $file, $r);
				push(@created_ns, $ns);
				}
			}
		else {
			# Add NS records for master and auto-configured slaves
			if ($tmpl->{'dns_prins'}) {
				push(@created_ns, $master);
				}
			local $slave;
			local @slaves = &get_default_domain_slaves($d);
			foreach $slave (@slaves) {
				local @bn = $slave->{'nsname'} ?
					( $slave->{'nsname'} ) :
					gethostbyname($slave->{'host'});
				if ($bn[0]) {
					local $full = $bn[0].".";
					push(@created_ns, $full);
					}
				}

			# Add NS records from template
			push(@created_ns, &get_slave_nameservers($d));

			# Make sure we have some NS records
			@created_ns = &unique(@created_ns);
			if ($tmpl->{'dns_indom'}) {
				@created_ns = grep { &to_ipaddress($_) } @created_ns;
				}
			if (!@created_ns) {
				return $text{'setup_ednsns'};
				}

			if ($tmpl->{'dns_indom'}) {
				# Add A records pointing to the nameserver IPs
				my $i = 1;
				foreach my $ns (@created_ns) {
					my $a = &to_ipaddress($ns);
					my $r = "ns".$i.".".$d->{'dom'}.".";
					&create_dns_record($recs, $file,
						{ 'name' => '@',
						  'type' => 'NS',
						  'values' => [ $r ] });
					&create_dns_record($recs, $file,
						{ 'name' => $r,
						  'type' => 'A',
						  'proxied' => $proxied == 1 ? 1 : 0,
						  'values' => [ $a ] });
					$i++;
					}
				}
			else {
				# Just add NS records
				foreach my $ns (@created_ns) {
					my $nsr = { 'name' => '@',
						    'type' => 'NS',
						    'values' => [ $ns ] };
					&create_dns_record($recs, $file, $nsr);
					}
				}
			}
		}
	
	# Add all records from the template at the top of the file,
	# so that they take precedence over any default records
	foreach my $r (@tmplrecs) {
		&create_dns_record($recs, $file, $r);
		}
	
	# Work out which records are already in the file
	local $rd = $d;
	if ($d->{'dns_submode'}) {
		$rd = &get_domain($d->{'dns_subof'});
		}
	local %already = map { $_->{'name'}, $_ }
			     grep { $_->{'type'} eq 'A' } @$recs;

	# Work out which records to add
	local $withdot = $d->{'dom'}.".";
	local @addrecs = split(/\s+/, $tmpl->{'dns_records'});
	if ($d->{'dns_initial_records'}) {
		@addrecs = split(/\s+/, $d->{'dns_initial_records'});
		}
	if (!@addrecs || $addrecs[0] eq 'none') {
		@addrecs = @automatic_dns_records;
		}
	local %addrecs = map { $_ eq "@" ? $withdot : $_.".".$withdot, 1 }
			     @addrecs;
	delete($addrescs{'noneselected'});

	# Add standard records we don't have yet
	my @recsstd = ($withdot, "www.$withdot", "ftp.$withdot");
	foreach my $n (@recsstd) {
		if (!$already{$n} && $addrecs{$n}) {
			&create_dns_record($recs, $file,
				{ 'name' => $n,
				  'type' => 'A',
				  'proxied' => $proxied ? 1 : 0,
				  'values' => [ $ip ] });
			$already{$n}++;
			}
		}

	# If the master NS is in this zone and there is no A for it yet, add now
	foreach my $ns (@created_ns) {
		if ($ns !~ /\.$/) {
			$ns .= ".".$withdot;
			}
		if ($ns =~ /^([^\.]+)\.(\S+\.)$/ && $2 eq $withdot &&
		    !$already{$ns}) {
			&create_dns_record($recs, $file,
				{ 'name' => $ns,
				  'type' => 'A',
				  'proxied' => $proxied == 1 ? 1 : 0,
				  'values' => [ $ip ] });
			$already{$ns}++;
			}
		}

	# Add the localhost record - yes, I know it's lame, but some
	# registrars require it!
	local $n = "localhost.$withdot";
	if (!$already{$n} && $addrecs{$n}) {
		&create_dns_record($recs, $file,
			{ 'name' => $n,
			  'type' => 'A',
			  'values' => [ "127.0.0.1" ] });
		$already{$n}++;
		}

	# If the hostname of the system is within this domain, add a record
	# for it
	my $hn = &get_system_hostname().".";
	if ($hn =~ /\.\Q$withdot\E$/ && !$already{$hn}) {
		&create_dns_record($recs, $file,
			{ 'name' => $hn,
			  'type' => 'A',
			  'proxied' => $proxied == 1 ? 1 : 0,
			  'values' => [ &get_default_ip() ] });
		$already{$hn}++;
		}

	# If enabled in the template, add webmail and admin records
	if (&domain_has_website($d) && &has_webmail_rewrite($d) &&
	    !$d->{'nowebmailredirect'}) {
		&add_webmail_dns_records_to_file($d, $tmpl, $file, $recs,
						 \%already);
		}

	# For mail domains, add MX to this server. Any IPv6 AAAA record is
	# cloned later
	if ($d->{'mail'}) {
		&create_mail_records($recs, $file, $d, $ip, undef);
		}

	# Add SPF record for domain, if defined and if it's not a sub-domain
	if ($tmpl->{'dns_spf'} ne "none" &&
	    !$d->{'dns_submode'} && !$d->{'nodnsspf'}) {
		local $str = &bind8::join_spf(&default_domain_spf($d));
		&create_dns_record($recs, $file,
			{ 'name' => $withdot, type => 'TXT',
			  'values' => [ $str ] });
		if ($bind8::config{'spf_record'}) {
			&create_dns_record($recs, $file,
				{ 'name' => $withdot, type => 'SPF',
				  'values' => [ $str ] });
			}
		}

	# Add DMARC record for domain, if defined and if it's not a sub-domain
	if ($tmpl->{'dns_dmarc'} ne "none" &&
	    !$d->{'dns_submode'} && !$d->{'nodnsdmarc'}) {
		local $str = &bind8::join_dmarc(&default_domain_dmarc($d));
		&create_dns_record($recs, $file,
			{ 'name' => "_dmarc.".$withdot, type => 'TXT',
			  'values' => [ $str ] });
		}
	}

if ($d->{'ip6'}) {
	# Create IPv6 records for IPv4
	&add_ip6_records($d, $recs, $file);
	}

if ($tmpl->{'dns_replace'} && !$d->{'dns_submode'}) {
	# DNS records come entirely from the template
	foreach my $r (@tmplrecs) {
		&create_dns_record($recs, $file, $r);
		}
	}
return undef;
}

# get_default_soa_record(&domain, master-nameserver)
# Returns the default SOA record object for a new domain
sub get_default_soa_record
{
my ($d, $master) = @_;
&require_bind();
my $email = $bconfig{'tmpl_email'} || "root\@$master";
$email = &bind8::email_to_dotted($email);
my %zd;
&bind8::get_zone_defaults(\%zd);
my $serial = $bconfig{'soa_style'} ?
	&bind8::date_serial().sprintf("%2.2d", $bconfig{'soa_start'}) :
	time();
my $soa = { 'name' => $d->{'dom'}.'.',
	    'type' => 'SOA',
	    'values' => [ $master, $email, $serial,
			  $zd{'refresh'}.$zd{'refunit'},
			  $zd{'retry'}.$zd{'retunit'},
			  $zd{'expiry'}.$zd{'expunit'},
			  $zd{'minimum'}.$zd{'minunit'} ] };
return $soa;
}

# create_alias_records(&records, file, &domain, ip, [diff-mode])
# For a domain that is an alias, copy records from its target
sub create_alias_records
{
local ($recs, $file, $d, $ip, $diff) = @_;
local $tmpl = &get_template($d->{'template'});
local $aliasd = &get_domain($d->{'alias'});
local ($aliasrecs, $aliasfile) = &get_domain_dns_records_and_file($aliasd);
$aliasfile || return "No zone file for alias target $aliasd->{'dom'} found";
@$aliasrecs || return "No records for alias target $aliasd->{'dom'} found";
local $olddom = $aliasd->{'dom'};
local $dom = $d->{'dom'};
local $oldip = $aliasd->{'ip'};
local @sublist = grep { $_->{'dns'} &&
			$_->{'id'} ne $aliasd->{'id'} &&
			$_->{'dom'} =~ /\.\Q$aliasd->{'dom'}\E$/ }
		      &list_domains();

# Find records we already have
local %already;
foreach my $r (@$recs) {
	$already{&dns_record_key($r, 1)}++;
	}
local %keep;

# Build list of master nameservers
my %tmplns;
my $master = &get_master_nameserver($tmpl, $d);
$tmplns{$master} = 1;
foreach my $ns (&get_slave_nameservers($d)) {
	$tmplns{$ns} = 1;
	}
local @slaves = &get_default_domain_slaves($d);
foreach my $slave (@slaves) {
	local @bn = $slave->{'nsname'} ?
		( $slave->{'nsname'} ) :
		gethostbyname($slave->{'host'});
	$tmplns{$bn[0]."."} = 1 if ($bn[0]);
	}

# Check if the source domain has an SOA record - if not (perhaps because it's
# on a DNS cloud provider), we will need to create it here
my $soacount = 0;
my $nscount = 0;
foreach my $r (@$aliasrecs) {
	$soacount++ if ($r->{'type'} eq 'SOA');
	$nscount++ if ($r->{'type'} eq 'NS');
	}
if (!$soacount) {
	# Source zone has no SOA, so we need to create one in the alias
	my ($soa) = grep { $_->{'type'} eq 'SOA' } @$recs;
	if (!$soa) {
		$soa = &get_default_soa_record($d, $master);
		&create_dns_record($recs, $file, $soa);
		}
	$keep{&dns_record_key($soa, 1)} = 1;
	}
if (!$nscount) {
	# Source zone has no NS records, so need to add the defaults in the
	# alias if they are missing
	foreach my $ns (keys %tmplns) {
		my ($nsr) = grep { $_->{'type'} eq 'NS' &&
				   $_->{'values'}->[0] eq $ns } @$recs;
		if (!$nsr) {
			$nsr = { 'name' => $d->{'dom'}.'.',
				 'type' => 'NS',
				 'values' => [ $ns ] };
			&create_dns_record($recs, $file, $nsr);
			}
		$keep{&dns_record_key($nsr, 1)} = 1;
		}
	}

RECORD: foreach my $r (@$aliasrecs) {
	my $nr = &clone_dns_record($r);
	if ($d->{'dns_submode'} && ($r->{'type'} eq 'NS' || 
				    $r->{'type'} eq 'SOA')) {
		# Skip SOA and NS records for sub-domains in the same file
		next;
		}
	if (&is_dnssec_record($r)) {
		# Skip DNSSEC records, as they get re-generated
		next;
		}
	if ($r->{'defttl'}) {
		# Add default TTL
		$keep{&dns_record_key($nr, 1)} = 1;
		next if ($diff && $already{&dns_record_key($nr, 1)}--);
		&create_dns_record($recs, $file, $nr);
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

	# Update the record name, and skip if it's not in the target domain.
	# For NS and SOA records, always update them to use this domain.
	if ($nr->{'name'} =~ /\Q$olddom\E\.$/) {
		$nr->{'name'} =~ s/\Q$olddom\E\.$/$dom\./i;
		}
	elsif ($nr->{'type'} eq 'SOA' || $nr->{'type'} eq 'NS') {
		$nr->{'name'} = $d->{'dom'}.'.';
		}
	else {
		next RECORD;
		}

	# Change domain name to alias in record values, unless it is an NS
	# that is set in the template
	if ($nr->{'type'} ne 'NS' || !$tmplns{$nr->{'values'}->[0]}) {
		foreach my $v (@{$nr->{'values'}}) {
			$v =~ s/\Q$olddom\E/$dom/i;
			$v =~ s/\Q$oldip\E$/$ip/i;
			}
		}
	$keep{&dns_record_key($nr, 1)} = 1;

	# Create unless it already exists
	next if ($diff && $already{&dns_record_key($nr, 1)}--);
	next if ($diff && $nr->{'type'} eq 'SOA');
	&create_dns_record($recs, $file, $nr);
	}

# Delete records that are missing now, if diffing
if ($diff) {
	my @delrecs;
	foreach my $r (@$recs) {
		next if ($r->{'type'} eq 'SOA');
		next if (&is_dnssec_record($r));
		next if ($keep{&dns_record_key($r, 1)});
		push(@delrecs, $r);
		}
	foreach my $r (@delrecs) {
		&delete_dns_record($recs, $file, $r);
		}
	}
return undef;
}

# get_master_nameserver(&template, &domain)
# Returns default primary NS name (with a . appended)
sub get_master_nameserver
{
my ($tmpl, $d) = @_;
my $r = &require_bind($d);
my $tmaster = $tmpl->{'dns_master'} eq 'none' ? undef :
			$tmpl->{'dns_master'};
my $master = $tmaster ||
	     $rbconfig->{'default_prins'} ||
	     &remote_foreign_call($r, "bind8", "get_system_hostname");
$master .= "." if ($master !~ /\.$/);
if ($d) {
	$master = &substitute_domain_template($master, $d);
	}
return $master;
}

# get_slave_nameserver(&domain)
# Returns default additional slave NS names (with . appended)
sub get_slave_nameservers
{
my ($d) = @_;
my $tmpl = &get_template($d->{'template'});
my @rv;
foreach my $ns (split(/\s+/, &substitute_domain_template($tmpl->{'dns_ns'}, $d))) {
	$ns .= "." if ($ns !~ /\.$/);
	push(@rv, $ns);
	}
return @rv;
}

# add_webmail_dns_records(&domain, [force-enable])
# Adds the webmail and admin DNS records, if requested in the template
sub add_webmail_dns_records
{
local ($d, $force) = @_;
local $tmpl = &get_template($d->{'template'});
&pre_records_change($d);
local ($recs, $file) = &get_domain_dns_records_and_file($d);
return 0 if (!$file);
local $count = &add_webmail_dns_records_to_file($d, $tmpl, $file, $recs,
						undef, $force);
if ($count) {
	&post_records_change($d, $recs, $file);
	&register_post_action(\&restart_bind, $d);
	}
else {
	&after_records_change($d);
	}
return $count;
}

# add_webmail_dns_records_to_file(&domain, &tmpl, file, &records,
#			          [&already-got], [force-add])
# Adds the webmail and admin DNS records to a specific file, if requested
# in the template
sub add_webmail_dns_records_to_file
{
local ($d, $tmpl, $file, $recs, $already, $force) = @_;
local $count = 0;
local $ip = $d->{'dns_ip'} || $d->{'ip'};
my $proxied = $tmpl->{'dns_cloud_proxy'};
foreach my $r ('webmail', 'admin') {
	local $n = "$r.$d->{'dom'}.";
	if (($tmpl->{'web_'.$r} || $force) && (!$already || !$already->{$n})) {
		my $r = { 'name' => $n,
			  'type' => 'A',
			  'proxied' => $proxied == 1 ? 1 : 0,
			  'values' => [ $ip ] };
		&create_dns_record($recs, $file, $r);
		$already->{$n}++ if ($already);
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
&pre_records_change($d);
local ($recs, $file) = &get_domain_dns_records_and_file($d);
return 0 if (!$file);
local $count = 0;
foreach my $r (reverse('webmail', 'admin')) {
	local $n = "$r.$d->{'dom'}.";
	local ($rec) = grep { $_->{'name'} eq $n } @$recs;
	if ($rec) {
		&delete_dns_record($recs, $rec->{'file'}, $rec);
		$count++;
		}
	}
if ($count) {
	&post_records_change($d, $recs, $file);
	&register_post_action(\&restart_bind, $d);
	}
else {
	&after_records_change($d);
	}
return $count;
}

# add_ip6_records(&domain, [&records, file])
# For each A record for the domain whose value is it's IPv4 address, add an
# AAAA record with the v6 address.
sub add_ip6_records
{
local ($d, $recs, $file) = @_;
&require_bind();
if (!$file) {
	($recs, $file) = &get_domain_dns_records_and_file($d);
	}
return 0 if (!$file);

# Work out which AAAA records we already have
local %already;
foreach my $r (@$recs) {
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

# Clone A records with the correct IP
my $count = 0;
my $withdot = $d->{'dom'}.".";
my $domip = $d->{'dns_ip'} || $d->{'ip'};
my $domip6 = $d->{'dns_ip6'} || $d->{'ip6'};
foreach my $r (@$recs) {
	if ($r->{'type'} &&
	    $r->{'type'} eq 'A' &&
	    $r->{'values'}->[0] eq $domip &&
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
			my $nr = &clone_dns_record($r);
			$nr->{'type'} = 'AAAA';
			$nr->{'values'} = [ $domip6 ];
			&create_dns_record($recs, $file, $nr);
			$count++;
			}
		}
	}

return $count;
}

# remove_ip6_records(&domain, file, &records)
# Delete all AAAA records whose value is the domain's IP6 address
sub remove_ip6_records
{
local ($d, $file, $recs) = @_;
&require_bind();
my $withdot = $d->{'dom'}.".";
foreach my $r (@$recs) {
	if ($r->{'type'} eq 'AAAA' && $r->{'values'}->[0] eq $d->{'ip6'} &&
	    ($r->{'name'} eq $withdot || $r->{'name'} =~ /\.\Q$withdot\E$/)) {
		push(@delrecs, $r);
		}
	}
foreach my $r (@delrecs) {
	&delete_dns_record($recs, $file, $r);
	}
}

# save_domain_matchall_record(&domain, star)
# Add or remove a *.domain.com wildcard DNS record, pointing to the main
# IP address. Used in conjuction with save_domain_web_star.
sub save_domain_matchall_record
{
local ($d, $star) = @_;
my $tmpl = &get_template($d->{'template'});
&pre_records_change($d);
local ($recs, $file) = &get_domain_dns_records_and_file($d);
return 0 if (!$file);
local $withstar = "*.".$d->{'dom'}.".";
local ($r) = grep { $_->{'name'} eq $withstar } @$recs;
local $any = 0;
if ($star && !$r) {
	# Need to add
	my $ip = $d->{'dns_ip'} || $d->{'ip'};
	$r = { 'name' => $withstar,
	       'type' => 'A',
	       'proxied' => $tmpl->{'dns_cloud_proxy'} == 1 ? 1 : 0,
	       'values' => [ $ip ] };
	&create_dns_record($recs, $file, $r);
	$any++;
	}
elsif (!$star && $r) {
	# Need to remove
	&delete_dns_record($recs, $file, $r);
	$any++;
	}
if ($any) {
	my $err = &post_records_change($d, $recs, $file);
	return 0 if ($err);
	&register_post_action(\&restart_bind, $d);
	}
else {
	&after_records_change($d);
	}
return $any;
}

# validate_dns(&domain, [&records], [records-only])
# Check for the DNS domain and records file
sub validate_dns
{
local ($d, $recs, $recsonly) = @_;
my $r = &require_bind($d);
local $file;
if ($d->{'dns_submode'}) {
	# For a sub-domain, don't complain if parent is disabled
	my $parent = &get_domain($d->{'dns_subof'});
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
if (!$d->{'provision_dns'} && !$d->{'dns_cloud'} &&
    !$d->{'dns_remote'} && $file) {
	# Make sure file exists
	$absfile = &bind8::make_chroot(
				&bind8::absolute_path($file));
	return &text('validate_ednsfile2', "<tt>$absfile</tt>")
		if (!-r $absfile);
	}
if (!$d->{'provision_dns'} && !$d->{'dns_cloud'} && !$d->{'dns_submode'}) {
	# Make sure it is a master
	local $zone = &get_bind_zone($d->{'dom'}, undef, $d);
	return &text('validate_edns', "<tt>$d->{'dom'}</tt>") if (!$zone);
	local $type = &bind8::find_value("type", $zone->{'members'});
	return &text('validate_ednsnotype', "<tt>$d->{'dom'}</tt>") if (!$type);
	return &text('validate_ednstype', "<tt>$d->{'dom'}</tt>",
	     "<tt>$type</tt>", "<tt>master</tt>") if ($type ne "master");
	}
if ($d->{'dns_cloud'}) {
	# Make sure the cloud provider knows about it
	my $cfunc = "dnscloud_".$d->{'dns_cloud'}."_check_domain";
	my $info = { 'domain' => $d->{'dom'} };
	my $ok = &$cfunc($d, $info);
	return &text('validate_ecloud', $d->{'dns_cloud'}) if (!$ok);
	}
if ($d->{'dns_cloud'}) {
	# Make sure there is NOT a local zone file
	my $file = &get_domain_dns_file_from_bind($d);
	return &text('validate_enoncloud', $d->{'dns_cloud'}) if ($file);
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
local $ip6 = $d->{'dns_ip6'} || $d->{'ip6'};
foreach my $r (@$recs) {
	$got{uc($r->{'type'})}++;
	}
$d->{'dns_submode'} || $d->{'dns_cloud'} || $got{'SOA'} ||
	return $text{'validate_ednssoa2'};
$got{'A'} || return $text{'validate_ednsa2'};
if ($d->{'virt6'}) {
	$got{'AAAA'} || return $text{'validate_ednsa6'};
	}
my @recerrs;
if (&domain_has_website($d)) {
	foreach my $n ($d->{'dom'}.'.', 'www.'.$d->{'dom'}.'.') {
		my @nips = map { $_->{'values'}->[0] }
			       grep { $_->{'type'} eq 'A' &&
				      $_->{'name'} eq $n } @$recs;
		my @nips6 = map { $_->{'values'}->[0] }
			       grep { $_->{'type'} eq 'AAAA' &&
				      $_->{'name'} eq $n } @$recs;
		if (@nips && &indexof($ip, @nips) < 0) {
			push(@recerrs, &text('validate_ednsip', "<tt>$n</tt>",
			    "<tt>".join(' or ', @nips)."</tt>", "<tt>$ip</tt>"));
			}
		if ($d->{'virt6'} && @nips6 && &indexof($ip6, @nips6) < 0) {
			push(@recerrs, &text('validate_ednsip6', "<tt>$n</tt>",
			  "<tt>".join(' or ', @nips6)."</tt>", "<tt>$ip6</tt>"));
			}
		}
	}

# If domain has email, make sure MX record points to this system
local $prov = &get_domain_cloud_mail_provider($d, $d->{'cloud_mail_id'});
if ($d->{'mail'} && $config{'mx_validate'} && !$prov) {
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
			if ($ip && ($ip eq $d->{'ip'} ||
				    $ip eq $d->{'dns_ip'} ||
				    $ip eq $d->{'ip6'} ||
				    $ip eq $d->{'dns_ip6'} ||
				    $ip eq $defip ||
				    $inuse{$ip})) {
				$found = $ip;
				last;
				}
			local ($arec) = grep { $_->{'name'} eq $mxh."." &&
					       $_->{'type'} eq 'A' } @$recs;
			if ($arec) {
				$ip = $arec->{'values'}->[0];
				if ($ip && ($ip eq $d->{'ip'} ||
					    $ip eq $d->{'dns_ip'} ||
					    $ip eq $d->{'ip6'} ||
					    $ip eq $d->{'dns_ip6'} ||
					    $ip eq $defip)) {
					$found = $ip;
					last;
					}
				}
			push(@mxips, $mxh);
			}
		if (!$found) {
			push(@recerrs, &text('validate_ednsmx', join(" ", @mxips)));
			}
		}
	}

# Make sure the domain has NS records, and that they are resolvable
if (!$d->{'dns_submode'}) {
	$got{'NS'} || $d->{'dns_cloud'} || return $text{'validate_ednsns2'};
	foreach my $ns (map { $_->{'values'}->[0] }
			    grep { $_->{'type'} eq 'NS' } @$recs) {
		local ($arec) = grep { $_->{'name'} eq $ns &&
				       ($_->{'type'} eq 'A' ||
					$_->{'type'} eq 'AAAA') } @$recs;
		$arec || &to_ipaddress($ns) || &to_ip6address($ns) ||
			push(@recerrs, &text('validate_ednsns', $ns));
		}
	}
return join("<br>\n", @recerrs) if (@recerrs);

# If possible, run named-checkzone
if (defined(&bind8::supports_check_zone) && &bind8::supports_check_zone() &&
    !$d->{'provision_dns'} && !$d->{'dns_cloud'} && !$d->{'dns_submode'} &&
    !$recsonly) {
	local $z = &get_bind_zone($d->{'dom'}, undef, $d);
	if ($z) {
		local @errs = &remote_foreign_call(
			$r, "bind8", "check_zone_records", $z);
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

# If DNSSEC is enabled and the parent domain is hosted by Virtualmin, make
# sure DS records exist
my $pname = $d->{'dom'};
$pname =~ s/^([^\.]+)\.//;
my $superdom = &get_domain_by("dom", $pname);
if (!$d->{'dns_submode'} && $superdom && &can_domain_dnssec($d)) {
	my $dsrecs = &get_domain_dnssec_ds_records($d);
	if (ref($dsrecs)) {
		my ($srecs, $sfile) =
			&get_domain_dns_records_and_file($superdom);
		my @missing;
		foreach my $dr (@$dsrecs) {
			my $key = &dns_record_key($dr, 1);
			my ($found) = grep { &dns_record_key($_, 1) eq $key }
					   @$srecs;
			push(@missing, $dr) if (!$found);
			}
		if (@missing) {
			return &text('validate_edsrecs',
			     &show_domain_name($superdom), scalar(@missing));
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
elsif ($d->{'dns_cloud'}) {
	# Lock on cloud DNS provider
	my $ctype = $d->{'dns_cloud'};
	my ($cloud) = grep { $_->{'name'} eq $ctype } &list_dns_clouds();
	&$first_print(&text('disable_bind_cloud', $cloud->{'desc'}));
	if (!$cloud->{'disable'}) {
		&$second_print($text{'disable_ebind_discloud'});
		return 0;
		}
	my $info = { 'domain' => $d->{'dom'},
		     'id' => $d->{'dns_cloud_id'},
		     'location' => $d->{'dns_cloud_location'} };
	my $dfunc = "dnscloud_".$ctype."_disable_domain";
	if (!defined(&$dfunc)) {
		&$second_print($text{'disable_ebind_cloud2'});
		return 0;
		}
	my ($ok, $msg) = &$dfunc($d, $info);
	if (!$ok) {
		&$second_print(&text('disable_ebind_cloud', $msg));
		return 0;
		}
	$d->{'dns_cloud_id'} = $msg;
	&$second_print($text{'setup_done'});
	return 1;
	}
else {
	# Lock locally
	&$first_print($text{'disable_bind'});
	if ($d->{'dns_submode'}) {
		# Disable is not done for sub-domains
		&$second_print($text{'disable_bindnosub'});
		return 0;
		}
	&obtain_lock_dns($d, 1);
	my $r = &require_bind($d);
	local $z = &get_bind_zone($d->{'dom'}, undef, $d);
	local $ok;
	if ($z) {
		local ($recs, $file) = &get_domain_dns_records_and_file($d);
		local $rootfile = &remote_foreign_call(
			$r, "bind8", "make_chroot", $z->{'file'});
		$z->{'values'}->[0] = $d->{'dom'}.".disabled";
		my $pconf = &remote_foreign_call($r, "bind8",
						 "get_config_parent");
		&remote_foreign_call($r, "bind8", "save_directive", $pconf,
				     [ $z ], [ $z ], 0);
		&remote_foreign_call($r, "bind8", "flush_file_lines",$rootfile);

		# Rename all records in the domain with the new .disabled name
		foreach my $r (@$recs) {
			if ($r->{'name'} =~ /\.\Q$d->{'dom'}\E\.$/ ||
			    $r->{'name'} eq $d->{'dom'}.".") {
				# Need to rename
				$r->{'name'} = $r->{'realname'} =
					$r->{'name'}."disabled.";
				&modify_dns_record($recs, $file, $r);
				}
			}
		&post_records_change($d, $recs, $file);

		# Clear zone names caches
		&remote_foreign_call($r, "bind8", "flush_zone_names");
		&$second_print($text{'setup_done'});
		&register_post_action(\&restart_bind, $d);

		# If on any slaves, delete there too
		$d->{'old_dns_slave'} = $d->{'dns_slave'};
		&delete_zone_on_slaves($d);
		$ok = 1;
		}
	else {
		&$second_print($text{'save_nobind'});
		$ok = 0;
		}
	&release_lock_dns($d, 1);
	return $ok;
	}
}

# enable_dns(&domain)
# Re-names this domain in named.conf to remove the .disabled suffix
sub enable_dns
{
local ($d) = @_;
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
	return 1;
	}
elsif ($d->{'dns_cloud'}) {
	# Unlock on cloud DNS provider
	my $ctype = $d->{'dns_cloud'};
	my ($cloud) = grep { $_->{'name'} eq $ctype } &list_dns_clouds();
	&$first_print(&text('enable_bind_cloud', $cloud->{'desc'}));
	if (!$cloud->{'disable'}) {
		&$second_print($text{'disable_ebind_discloud'});
		return 0;
		}
	my $info = { 'domain' => $d->{'dom'},
		     'id' => $d->{'dns_cloud_id'},
		     'location' => $d->{'dns_cloud_location'} };
	my $dfunc = "dnscloud_".$ctype."_enable_domain";
	if (!defined(&$dfunc)) {
		&$second_print($text{'disable_ebind_cloud2'});
		return 0;
		}
	my ($ok, $msg) = &$dfunc($d, $info);
	if (!$ok) {
		&$second_print(&text('enable_ebind_cloud', $msg));
		return 0;
		}
	$d->{'dns_cloud_id'} = $msg;
	&$second_print($text{'setup_done'});
	return 1;
	}
else {
	&$first_print($text{'enable_bind'});
	if ($d->{'dns_submode'}) {
		# Disable is not done for sub-domains
		&$second_print($text{'enable_bindnosub'});
		return 0;
		}
	&obtain_lock_dns($d, 1);
	my $r = &require_bind($d);
	local $z = &get_bind_zone($d->{'dom'}, undef, $d);
	local $ok;
	if ($z) {
		local ($recs, $file) = &get_domain_dns_records_and_file($d);
		local $rootfile = &remote_foreign_call(
			$r, "bind8", "make_chroot", $z->{'file'});
		$z->{'values'}->[0] = $d->{'dom'};
		my $pconf = &remote_foreign_call($r, "bind8",
						 "get_config_parent");
		&remote_foreign_call($r, "bind8", "save_directive", $pconf,
				     [ $z ], [ $z ], 0);
		&remote_foreign_call($r, "bind8", "flush_file_lines",$rootfile);

		# Fix all records in the domain with the .disabled name
		foreach my $r (@$recs) {
			if ($r->{'name'} =~ /\.\Q$d->{'dom'}\E\.disabled\.$/ ||
			    $r->{'name'} eq $d->{'dom'}.".disabled.") {
				# Need to rename
				$r->{'name'} =~ s/\.disabled\.$/\./;
				$r->{'realname'} =~ s/\.disabled\.$/\./;
				&modify_dns_record($recs, $file, $r);
				}
			}
		&post_records_change($d, $recs, $file);

		# Clear zone names caches
		&remote_foreign_call($r, "bind8", "flush_zone_names");
		&$second_print($text{'setup_done'});
		&register_post_action(\&restart_bind, $d);

		# If it used to be on any slaves, enable too
		$d->{'dns_slave'} = $d->{'old_dns_slave'};
		if ($d->{'dns_slave'}) {
			&create_zone_on_slaves($d, $d->{'dns_slave'});
			}
		delete($d->{'old_dns_slave'});
		$ok = 1;
		}
	else {
		&$second_print($text{'save_nobind'});
		$ok = 0;
		}
	&release_lock_dns($d, 1);
	return $ok;
	}
}

# get_bind_zone(name, [&config], [&domain])
# Returns the zone structure for the named domain, possibly with .disabled
sub get_bind_zone
{
my ($name, $conf, $d) = @_;
my $r = &require_bind($d);
$conf ||= &remote_foreign_call($r, "bind8", "get_config");
local @zones = &bind8::find("zone", $conf);
local ($v, $z);
foreach $v (&bind8::find("view", $conf)) {
	push(@zones, &bind8::find("zone", $v->{'members'}));
	}
local ($z) = grep { lc($_->{'value'}) eq lc($name) ||
		    lc($_->{'value'}) eq lc($name.".disabled") } @zones;
return $z;
}

# restart_bind(&domain)
# Signal BIND to re-load its configuration
sub restart_bind
{
local ($d) = @_;
if ($d && $d->{'dns_subof'}) {
	$d = &get_domain($d->{'dns_subof'});
	}
local $p = $d ? $d->{'provision_dns'} || $d->{'dns_cloud'}
	      : $config{'provision_dns'} || &default_dns_cloud();
if ($p) {
	# Hosted on a provisioning server, so nothing to do
	return 1;
	}
if ($d) {
	&$first_print(&text('setup_bindpid2', &show_domain_name($d)));
	}
else {
	&$first_print($text{'setup_bindpid'});
	}
my $r = &require_bind($d);
local $bindlock = "$module_config_directory/bind-restart";
&lock_file($bindlock);
local $pid = &get_bind_pid($d);
if ($pid) {
	my $err = &remote_foreign_call($r, "bind8", "restart_bind");
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

local @shosts = split(/\s+/, $d->{'dns_slave'});
if (&bind8::list_slave_servers() && @shosts) {
	# Re-start on slaves too
	&$first_print(&text('setup_bindslavepids'));
	local @slaveerrs = &bind8::restart_on_slaves(\@shosts);
	if (@slaveerrs) {
		&$second_print($text{'setup_bindeslave'});
		foreach $sr (@slaveerrs) {
			&$second_print($sr->[0]->{'host'}." : ".$sr->[1]);
			}
		}
	else {
		&$second_print($text{'setup_done'});
		}
	if (defined(&bind8::restart_zone_on_slaves)) {
		&bind8::restart_zone_on_slaves($d->{'dom'}, \@shosts);
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
if ($d->{'dns_submode'}) {
	# Reload in parent, which might be cloud hosted
	$d = &get_domain($d->{'dns_subof'});
	}
if ($d->{'provision_dns'} || $d->{'dns_cloud'}) {
	# Done remotely when records are uploaded
	return undef;
	}
my $r = &require_bind($d);
local $err = &remote_foreign_call($r, "bind8", "restart_zone",
				  $d->{'dom'}, $d->{'dns_view'});
return undef if (!$err);
&push_all_print();
&set_all_null_print();
local $rv = &restart_bind($d);
&pop_all_print();
return $rv;
}

# check_dns_clash(&domain, [changing], [replication-mode])
# Returns 1 if a domain already exists in BIND, or remotely
sub check_dns_clash
{
my ($d, $field, $repl) = @_;
if (!$field || $field eq 'dom') {
	if ($d->{'provision_dns'}) {
		# Check on remote provisioning server
		my ($ok, $msg) = &provision_api_call(
			"check-dns-zone", { 'domain' => $d->{'dom'} });
		return &text('provision_ednscheck', $msg) if (!$ok);
		if ($msg =~ /host=/) {
			return &text('provision_edns', $d->{'dom'});
			}
		}
	elsif ($d->{'dns_cloud'}) {
		# Check on cloud provider
		return 0 if ($d->{'dns_cloud_import'} || $repl);
		my $ctype = $d->{'dns_cloud'};
		my ($cloud) = grep { $_->{'name'} eq $ctype }
				   &list_dns_clouds();
		if (!$cloud) {
			return $text{'setup_ednscloudexists'};
			}
		my $sfunc = "dnscloud_".$ctype."_get_state";
		my $state = &$sfunc($cloud);
		if (!$state->{'ok'}) {
			return &text('setup_ednscloudstate', $cloud->{'desc'});
			}
		return 0 if ($cloud->{'import'});  # Must always already exist
						   # for this cloud provider
		my $tfunc = "dnscloud_".$ctype."_check_domain";
		my $info = { 'domain' => $d->{'dom'} };
		my $exists = &$tfunc($d, $info);
		if ($exists) {
			# Already exists
			return &text('setup_dnscloudclash', $cloud->{'desc'});
			}
		}
	else {
		# Check locally
		my $czone = &get_bind_zone($d->{'dom'});
		if (!$czone) {
			return 0;
			}
		my $type = &bind8::find_value("type", $czone->{'members'});
		if ($type eq "master") {
			return 1;
			}
		return 0;
		}
	}
return 0;
}

# get_bind_pid([&domain])
# Returns the BIND PID, if it is running
sub get_bind_pid
{
my ($d) = @_;
my $r = &require_bind($r);
local $pidfile = &remote_foreign_call($r, "bind8", "get_pid_file");
$pidfile = &remote_foreign_call($r, "bind8", "make_chroot", $pidfile, 1);
return &remote_foreign_call($r, "bind8", "check_pid_file", $pidfile);
}

# backup_dns(&domain, file)
# Save all the virtual server's DNS records as a separate file
sub backup_dns
{
my ($d, $file) = @_;
my $r = &require_bind($d);
&$first_print($text{'backup_dnscp'});
my ($recs, $zonefile) = &get_domain_dns_records_and_file($d);
if (!$zonefile) {
	# Zone file doesn't exist!
	&$second_print($text{'backup_dnsnozone2'});
	return 0;
	}
if (!$d->{'dns_submode'}) {
	# Can just copy the whole zone file
	my $z = &get_bind_zone($d->{'dom'}, undef, $d);
	my $absfile;
	if ($z) {
		# Use the absolute file path from BIND
		my $f = &bind8::find("file", $z->{'members'});
		$absfile = &remote_foreign_call($r, "bind8", "make_chroot",
		    &remote_foreign_call($r, "bind8", "absolute_path",
					 $f->{'values'}->[0]));
		}
	else {
		# Fall back to using a local copy, such as when DNS is hosted
		# remotely
		$absfile = $zonefile;
		}
	&copy_write_remote_as_domain_user($d, $r, $absfile, $file);

	# Also save DNSSEC keys, if possible
	if ($z && &can_domain_dnssec($d)) {
		my @keys = &remote_foreign_call(
			$r, "bind8", "get_dnssec_key", $z);
		@keys = grep { ref($_) &&
			       $_->{'privatefile'} &&
			       $_->{'publicfile'} } @keys;
		my $i = 0;
		my %kinfo;
		foreach my $key (@keys) {
			foreach my $t ('private', 'public') {
				&copy_write_remote_as_domain_user($d, $r,
					$key->{$t.'file'},
					$file.'_dnssec_'.$t.'_'.$i);
				$key->{$t.'file'} =~ /^.*\/([^\/]+)$/;
				$kinfo{$t.'_'.$i} = $1;
				}
			$i++;
			}
		&write_as_domain_user($d, sub {
			&write_file($file."_dnssec_keyinfo", \%kinfo);
			});
		}
	}
else {
	# Extract the appropriate records to a temp file. This must use the
	# BIND module API directly, because it's just writing to a file.
	local $bind8::chroot = "/";	# So that create_record will write to the backup file
	$recs = &filter_domain_dns_records($d, $recs);
	foreach my $rec (@$recs) {
		next if ($rec->{'name'} eq '$ttl' ||
			 $rec->{'name'} eq '$generate');
		&bind8::create_record($file, $rec->{'name'},
			$rec->{'ttl'}, $rec->{'class'}, $rec->{'type'},
			&join_record_values($rec, 1),
			$rec->{'comment'});
		}
	}

# Also write out the records in serialized format, to preserve non-standard
# attributes like 'proxied'
my $rfile = $file."_records";
&write_file_contents($rfile, &serialise_variable($recs));

&$second_print($text{'setup_done'});
return 1;
}

# restore_dns(&domain, file, &options)
# Update the virtual server's DNS records from the backup file, except the SOA
sub restore_dns
{
my ($d, $file, $opts) = @_;
my $r = &require_bind($d);
&$first_print($text{'restore_dnscp'});
&obtain_lock_dns($d, 1);
&pre_records_change($d);
my ($recs, $zonefile) = &get_domain_dns_records_and_file($d);
my $z = &get_bind_zone($d->{'dom'}, undef, $d);
if (!$zonefile) {
	# DNS zone not found!
	&$second_print($text{'backup_dnsnozone'});
	&release_lock_dns($d, 1);
	return 0;
	}
my @thisrecs = @$recs;

# Read records from the backup file
my $brecs;
my $rfile = $file."_records";
if (-r $rfile && $d->{'dns_cloud'}) {
	$brecs = &unserialise_variable(&read_file_contents($rfile));
	}
else {
	$brecs = [ &bind8::read_zone_file($file,
	    $d->{'dom'}.($d->{'disabled'} ? ".disabled" : ""), undef, 0, 1) ];
	}

my $dnskeys = 0;
if ($d->{'dns_submode'}) {
	# Only replacing records for this sub-domain
	my $oldsubrecs = &filter_domain_dns_records($d, $recs);
	$oldsubrecs = &filter_domain_dns_records($d, $oldsubrecs);
	my $newsubrecs = &filter_domain_dns_records($d, $brecs);
	foreach my $r (@$oldsubrecs) {
		&delete_dns_record($recs, $zonefile, $r);
		}
	foreach my $r (@$newsubrecs) {
		&create_dns_record($recs, $zonefile, $r);
		}
	}
else {
	# Delete old records and create ones from the backup
	my @delrecs;
	foreach my $r (@$recs) {
		next if ($r->{'type'} eq 'SOA');
		push(@delrecs, $r);
		}
	foreach my $r (@delrecs) {
		&delete_dns_record($recs, $zonefile, $r);
		}
	foreach my $r (@$brecs) {
		next if ($r->{'type'} eq 'SOA');
		next if (&is_dnssec_record($r) && $r->{'type'} ne 'DNSKEY');
		&create_dns_record($recs, $zonefile, $r);
		$dnskeys++ if ($r->{'type'} eq 'DNSKEY');
		}
	}

if (!$d->{'dns_submode'} && &can_domain_dnssec($d) && $tmpl->{'dnssec_alg'}) {
	# If the backup contained a DNSSEC key and this system has the zone
	# signed, copy them in (but under the OLD filenames, so they match
	# up with the key IDs in records)
	my @keys = &remote_foreign_call($r, "bind8", "get_dnssec_key", $z);
	if (!@keys && $dnskeys) {
		# DNSSEC was enabled before but not now, perhaps because it's
		# not in the template. So enable it.
		&$indent_print();
		&$first_print($text{'restore_dnssec'});
		if (my $err = &enable_domain_dnssec($d)) {
			&$second_print(&text('restore_ednssec', $err));
			}
		else {
			&$second_print($text{'setup_done'});
			}
		&$outdent_print();
		@keys = &remote_foreign_call($r, "bind8", "get_dnssec_key", $z);
		}
	@keys = grep { ref($_) && $_->{'privatefile'} && $_->{'publicfile'} }
		     @keys;
	my $i = 0;
	my %kinfo;
	my $rok;
	&read_file($file."_dnssec_keyinfo", \%kinfo);
	foreach my $key (@keys) {
		foreach my $t ('private', 'public') {
			next if (!-r $file.'_dnssec_'.$t.'_'.$i);
			&remote_foreign_call($r, "bind8", "unlink_file",
					     $key->{$t.'file'});
			$key->{$t.'file'} =~ /^(.*)\// || next;
			my $keydir = $1;
			if ($kinfo{$t.'_'.$i}) {
				$key->{$t.'file'} = $keydir.'/'.
					$kinfo{$t.'_'.$i};
				}
			&remote_write($r, $file.'_dnssec_'.$t.'_'.$i,
				      $key->{$t.'file'});
			&remote_foreign_call($r, "bind8", "set_ownership",
					     $key->{$t.'file'});
			$rok++;
			}
		$i++;
		}

	# Check if DNSSEC keys were restored correctly
	if ($dnskeys) {
		&$indent_print();
		&$first_print($text{'restore_dnssec2'});
		if (!@keys) {
			&$second_print($text{'restore_ednssec2a'});
			}
		elsif (!$rok) {
			&$second_print($text{'restore_ednssec2b'});
			}
		else {
			&$second_print($text{'setup_done'});
			}
		&$outdent_print();
		}
	}

# Need to update IP addresses
my $r;
my ($baserec) = grep { $_->{'type'} eq "A" &&
			  ($_->{'name'} eq $d->{'dom'}."." ||
			   $_->{'name'} eq '@') } @$recs;
my $dns_ip = $d->{'dns_ip'} || $d->{'ip'};
my $dns_baseip = $d->{'old_dns_ip'} ? $d->{'old_dns_ip'} :
		    $d->{'old_ip'} ? $d->{'old_ip'} :
			$baserec ? $baserec->{'values'}->[0] : undef;
my $ip = $d->{'ip'};
my $baseip = $d->{'old_ip'};
if ($dns_baseip && $dns_baseip ne $baseip) {
	&modify_records_ip_address($recs, $zonefile, $dns_baseip, $dns_ip);
	}
if ($baseip) {
	&modify_records_ip_address($recs, $zonefile, $baseip, $ip);
	}

# Need to update IPv6 address
my ($baserec6) = grep { $_->{'type'} eq "AAAA" &&
			   ($_->{'name'} eq $d->{'dom'}."." ||
			    $_->{'name'} eq '@') } @$recs;
my $ip6 = $d->{'ip6'};
my $baseip6 = $d->{'old_ip6'} ? $d->{'old_ip6'} :
			$baserec6 ? $baserec6->{'values'}->[0] : undef;
if ($baseip6 && $ip6) {
	# Update to new v6 address
	&modify_records_ip_address($recs, $zonefile, $baseip6, $ip6);
	}
elsif ($baseip6 && !$ip6) {
	# This domain doesn't have a v6 address now, so remove AAAAs
	&remove_ip6_records($d, $zonefile, $recs);
	}

# Replace NS records with those from new system (if there are any)
my @thisns = grep { $_->{'type'} eq 'NS' } @thisrecs;
if (@thisns) {
	my @ns = grep { $_->{'type'} eq 'NS' } @$recs;
	foreach my $r (@thisns) {
		# Create NS records that were in new system's file
		my $name = $r->{'name'};
		$name =~ s/\.disabled\.$/\./;
		if (@ns && $ns[0]->{'name'} =~ /\.disabled\.$/) {
			$name .= "disabled.";
			}
		&create_dns_record($recs, $zonefile, $r);
		}
	foreach my $r (@ns) {
		# Remove old NS records that we copied over
		&delete_dns_record($recs, $zonefile, $r);
		}
	}

# Make sure any SPF record contains this system's default IP v4 and
# v6 addresses
my @types = $bind8::config{'spf_record'} ? ( "SPF", "TXT" )
					    : ( "SPF" );
foreach my $t (@types) {
	my ($r) = grep { $_->{'type'} eq $t &&
			    $_->{'name'} eq $d->{'dom'}.'.' } @$recs;
	next if (!$r);
	my $spf = &bind8::parse_spf(@{$r->{'values'}});
	my $changed = 0;
	my $defip = &get_default_ip();
	if (&indexof($defip, @{$spf->{'ip4'}}) < 0) {
		push(@{$spf->{'ip4'}}, $defip);
		$changed++;
		}
	my $defip6 = &get_default_ip6();
	if (&indexof($defip6, @{$spf->{'ip6'}}) < 0) {
		push(@{$spf->{'ip6'}}, $defip6);
		$changed++;
		}
	if ($changed) {
		my $str = &bind8::join_spf($spf);
		$r->{'values'} = [ $str ];
		&modify_dns_record($recs, $zonefile, $r);
		}
	}

&post_records_change($d, $recs, $zonefile);
&register_post_action(\&restart_bind, $d);
&release_lock_dns($d, 1);

# Refresh DNSSEC records in case it was enabled originally,
# as `post_records_change` cannot do it because public and
# private keys were restored afterwards
if ($dnskeys) {
	&$indent_print();
	&$first_print($text{'restore_dnssec_resign'});
	my $err = &disable_domain_dnssec($d) || &enable_domain_dnssec($d);
	if ($err) {
		&$second_print(&text('restore_ednssec_resign', $err));
		}
	else {
		&$second_print($text{'setup_done'});
		my ($recs, $file) = &get_domain_dns_records_and_file($d);
		&post_records_change($d, $recs, $file);
		&reload_bind_records($d);
		}
	&$outdent_print();
	}
&$second_print($text{'setup_done'});
return 1;
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
		&modify_dns_record($recs, $fn, $r);
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
		$r->{'values'}->[1] =~ s/$olddom(\.disabled)?\.$/$newdom$1\./;
		}
	if ($fn) {
		&modify_dns_record($recs, $fn, $r);
		}
	}
}

# get_bind_view([&conf], view)
# Returns the view object for the view to add domains to
sub get_bind_view
{
local ($conf, $vname) = @_;
&require_bind();
$conf ||= &bind8::get_config();
local @views = &bind8::find("view", $conf);
local ($view) = grep { $_->{'values'}->[0] eq $vname } @views;
return $view;
}

# sysinfo_dns()
# Returns the BIND version
sub sysinfo_dns
{
&require_bind();
if (&is_dns_remote()) {
	# No local BIND in provisioning mode
	return ( );
	}
my $ver = &bind8::get_bind_version();
if ($ver) {
	return ( [ $text{'sysinfo_bind'}, $ver ] );
	}
return ( );
}

sub startstop_dns
{
local ($typestatus) = @_;
if (&is_dns_remote()) {
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
if (!&is_dns_remote()) {
	$conf = &bind8::get_config();
	@views = &bind8::find("view", $conf);
	}

# DNS records
local $ndi = &none_def_input("dns", $tmpl->{'dns'}, $text{'tmpl_dnsbelow'}, 0,
			     0, $text{'tmpl_dnsnone'},
			     [ "dns", "bind_replace" ]);
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
		     3, 50));

# Hostname for MX record
print &ui_table_row(&hlink($text{'tmpl_dnsmx'}, "template_dns_mx"),
	&none_def_input("dns_mx", $tmpl->{'dns_mx'},
			$text{'tmpl_dnsmnames'}, 0, 0,
			$text{'tmpl_dnsmxauto'}."<br>", [ "dns_mx" ])." ".
	&ui_textbox("dns_mx", $tmpl->{'dns_mx'} eq 'none' ? '' :
				$tmpl->{'dns_mx'}, 40));

# Option for view to add to, for BIND 9
if (@views || $tmpl->{'dns_view'}) {
	print &ui_table_row(&hlink($text{'newdns_view'}, "template_dns_view"),
		&ui_select("view", $tmpl->{'dns_view'},
			[ [ "", $text{'newdns_noview'} ],
			  map { [ $_->{'values'}->[0] ] } @views ]));
	}

# Add sub-domains to parent domain DNS zone?
print &ui_table_row(&hlink($text{'tmpl_dns_sub'},
                           "template_dns_sub"),
	&none_def_input("dns_sub", $tmpl->{'dns_sub'},
		        $text{'yes'}, 0, 0, $text{'no'}));

# Alias domains can have own DNS records?
print &ui_table_row(&hlink($text{'tmpl_dns_alias'},
                           "template_dns_alias"),
	&none_def_input("dns_alias", $tmpl->{'dns_alias'},
		        $text{'yes'}, 0, 0, $text{'no'}));

# Where to create zones?
my @clouds = ( [ "", $text{'dns_cloud_def'} ] );
if ($config{'provision_dns'}) {
	push(@clouds, [ "services", $text{'dns_cloud_services'} ]);
	}
foreach my $c (&list_dns_clouds()) {
	my $sfunc = "dnscloud_".$c->{'name'}."_get_state";
	my $s = &$sfunc($c);
	if ($s->{'ok'}) {
		push(@clouds, [ $c->{'name'}, $c->{'desc'} ]);
		}
	}
if (defined(&list_remote_dns)) {
	foreach my $r (grep { $_->{'id'} != 0 && !$_->{'slave'} }
			    &list_remote_dns()) {
		push(@clouds, [ "remote_".$r->{'host'},
				&text('tmpl_dns_remote', $r->{'host'}) ]);
		}
	}
if (@clouds > 1) {
	splice(@clouds, 1, 0, [ "local", $text{'dns_cloud_local'} ]);
	}
print &ui_table_row(&hlink($text{'tmpl_dns_cloud'},
                           "template_dns_cloud"),
	&ui_select("dns_cloud", $tmpl->{'dns_cloud'}, \@clouds));

print &ui_table_row(&hlink($text{'tmpl_dns_cloud_import'},
			   "template_dns_cloud_import"),
	&ui_yesno_radio("dns_cloud_import", $tmpl->{'dns_cloud_import'}));

print &ui_table_row(&hlink($text{'tmpl_dns_cloud_proxy'},
			   "template_dns_cloud_proxy"),
	&ui_radio("dns_cloud_proxy", $tmpl->{'dns_cloud_proxy'} || 0,
		  [ [ 0, $text{'no'} ],
		    [ 1, $text{'tmpl_dns_cloud_proxy1'} ],
		    [ 2, $text{'tmpl_dns_cloud_proxy2'} ] ]));

# Create on slave DNS servers
local @slaves = &bind8::list_slave_servers();
if (@slaves) {
	print &ui_table_hr();

	my $smode = $tmpl->{'dns_slaves'} eq 'none' ? 2 :
		    $tmpl->{'dns_slaves'} ? 0 : 1;
	print &ui_table_row(&hlink($text{'tmpl_dns_slaves'},
				   "template_dns_slaves"),
		&ui_radio("dns_slaves_def", $smode,
			  [ [ 1, $text{'tmpl_dns_slaves_all'} ],
			    [ 2, $text{'tmpl_dns_slaves_none'} ],
			    [ 0, $text{'tmpl_dns_slaves_sel'} ] ])."<br>\n".
		&ui_select("dns_slaves",
			   [ split(/\s+/, $tmpl->{'dns_slaves'}) ],
			   [ map { [ $_->{'id'}, $_->{'host'} ] } @slaves ],
			   5, 1));
	}

print &ui_table_hr();

# Master NS hostname
print &ui_table_row(&hlink($text{'tmpl_dnsmaster'},
                           "template_dns_master"),
	&none_def_input("dns_master", $tmpl->{'dns_master'},
			$text{'tmpl_dnsmnames'}, 0, 0,
			$text{'tmpl_dnsmauto'}."<br>", [ "dns_master" ])." ".
	&ui_textbox("dns_master", $tmpl->{'dns_master'} eq 'none' ? '' :
					$tmpl->{'dns_master'}, 40));

# Add NS record for master?
my @opts = ( [ 1, $text{'yes'} ],
	     [ 0, $text{'no'} ] );
if (!$tmpl->{'default'}) {
	unshift(@opts, [ '', $text{'tmpl_default'} ]);
	}
print &ui_table_row(&hlink($text{'tmpl_dnsprins'}, "template_dns_prins"),
	&ui_radio("dnsprins", $tmpl->{'dns_prins'}, \@opts));

# Add NS records in this domain
if ($tmpl->{'dns_indom'}) {
	print &ui_table_row(&hlink($text{'tmpl_dnsindom'},
				   "template_dns_indom"),
		&ui_yesno_radio("dns_indom", $tmpl->{'dns_indom'}));
	}

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
	&ui_textbox("dns_spfhosts", $tmpl->{'dns_spfhosts'}, 40)."<br>\n".
	&ui_checkbox("dns_spfonly", 1, $text{'tmpl_spfonly'},
		     !$tmpl->{'dns_spfonly'}));

# Extra SPF includes
print &ui_table_row(&hlink($text{'tmpl_spfincludes'},
			   "template_dns_spfincludes"),
	&ui_textbox("dns_spfincludes", $tmpl->{'dns_spfincludes'}, 40));

# SPF ~all mode
print &ui_table_row(&hlink($text{'spf_all'},
			   "template_dns_spfall"),
	&ui_radio("dns_spfall", $tmpl->{'dns_spfall'},
		  [ [ 0, $text{'spf_all1'} ],
		    [ 1, $text{'spf_all2'} ],
		    [ 2, $text{'spf_all3'} ] ]));

print &ui_table_hr();

# Option for DMARC record
print &ui_table_row(&hlink($text{'tmpl_dmarc'},
                           "template_dns_dmarc_mode"),
	&none_def_input("dns_dmarc", $tmpl->{'dns_dmarc'},
		        $text{'tmpl_dmarcyes'}, 0, 0, $text{'no'},
			[ "dns_dmarcp", "dns_dmarcpct", "dns_dmarcextra" ]));

# DMARC policy
print &ui_table_row(&hlink($text{'tmpl_dmarcp'},
			   "template_dns_dmarcp"),
	&ui_radio("dns_dmarcp", $tmpl->{'dns_dmarcp'},
		  [ [ "none", $text{'tmpl_dmarcnone'} ],
		    [ "quarantine", $text{'tmpl_dmarcquar'} ],
		    [ "reject", $text{'tmpl_dmarcreject'} ] ]));

# DMARC percentage
print &ui_table_row(&hlink($text{'tmpl_dmarcpct'},
			   "template_dns_dmarcpct"),
	&ui_textbox("dns_dmarcpct", $tmpl->{'dns_dmarcpct'}, 5)."%");

# DMARC email templates
foreach my $r ('ruf', 'rua') {
	print &ui_table_row(&hlink($text{'tmpl_dmarc'.$r},
				   "template_dns_dmarc".$r),
		&ui_radio("dns_dmarc".$r."_def",
			  $tmpl->{'dns_dmarc'.$r} eq "" ? 1 :
			  $tmpl->{'dns_dmarc'.$r} eq "skip" ? 2 : 0,
			  [ [ 1, $text{'default'}.
				 " <tt>mailto:postmaster\@domain</tt>" ],
			    [ 2, $text{'tmpl_dmarcskip'} ],
			    [ 0, &ui_textbox('dns_dmarc'.$r,
					$tmpl->{'dns_dmarc'.$r}, 40) ] ]));
	}

# Extra DMARC fields
print &ui_table_row(&hlink($text{'tmpl_dmarcextra'},
			   "template_dns_dmarcextra"),
	&ui_textbox("dns_dmarcextra", $tmpl->{'dns_dmarcextra'}, 40));

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
	if (&bind8::supports_dnssec()) {
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
	$tmpl->{'default'} || $tmpl->{'dns'} =~ /\S/ ||
	    $in{'bind_replace'} == 0 || &error($text{'tmpl_edns'});
	$tmpl->{'dns_replace'} = $in{'bind_replace'};

	&require_bind();
	local $fakeip = "1.2.3.4";
	local $fakedom = "foo.com";
	local $recs = &substitute_virtualmin_template(
			join("\n", split(/\t+/, $in{'dns'}))."\n",
			{ 'ip' => $fakeip,
			  'dom' => $fakedom,
		 	  'web' => 1, });
	local @recs = &text_to_dns_records($recs, "example.com");
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
	}

if ($in{"dns_mode"} != 1) {
	$tmpl->{'dns_view'} = $in{'view'};

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
		$n =~ /\$/ || &to_ipaddress($n) || &to_ip6address($n) ||
			&error(&text('newdns_enshost', $n));
		}
	$tmpl->{'dns_ns'} = join(" ", @ns);
	$tmpl->{'dns_prins'} = $in{'dnsprins'};
	}

# Save NS hostname
$in{'dns_master_mode'} != 2 ||
   ($in{'dns_master'} =~ /^[a-z0-9\.\-\_\$\{\}]+$/i &&
    $in{'dns_master'} =~ /\.|\{|\$/ && !&check_ipaddress($in{'dns_master'})) ||
	&error($text{'tmpl_ednsmaster'});
$tmpl->{'dns_master'} = $in{'dns_master_mode'} == 0 ? "none" :
		        $in{'dns_master_mode'} == 1 ? undef : $in{'dns_master'};
if (defined($in{'dns_indom'})) {
	$tmpl->{'dns_indom'} = $in{'dns_indom'};
	}

# Save MX hostname
$in{'dns_mx_mode'} != 2 || $in{'dns_mx'} =~ /^[a-z0-9\.\-\_\$\{\}]+$/i ||
	&error($text{'tmpl_ednsmx'});
$tmpl->{'dns_mx'} = $in{'dns_mx_mode'} == 0 ? "none" :
		    $in{'dns_mx_mode'} == 1 ? undef : $in{'dns_mx'};

# Save SPF
$tmpl->{'dns_spf'} = $in{'dns_spf_mode'} == 0 ? "none" :
		     $in{'dns_spf_mode'} == 1 ? undef : "yes";
$tmpl->{'dns_spfhosts'} = $in{'dns_spfhosts'};
$tmpl->{'dns_spfonly'} = !$in{'dns_spfonly'};
$tmpl->{'dns_spfincludes'} = $in{'dns_spfincludes'};
$tmpl->{'dns_spfall'} = $in{'dns_spfall'};

# Save DMARC
$tmpl->{'dns_dmarc'} = $in{'dns_dmarc_mode'} == 0 ? "none" :
		       $in{'dns_dmarc_mode'} == 1 ? undef : "yes";
if ($in{'dns_dmarc_mode'} == 2) {
	$in{'dns_dmarcpct'} =~ /^\d+$/ && $in{'dns_dmarcpct'} >= 0 &&
	  $in{'dns_dmarcpct'} <= 100 || &error($text{'tmpl_edmarcpct'});
	}
$tmpl->{'dns_dmarcp'} = $in{'dns_dmarcp'};
$tmpl->{'dns_dmarcpct'} = $in{'dns_dmarcpct'};
foreach my $r ('ruf', 'rua') {
	$tmpl->{'dns_dmarc'.$r} = $in{'dns_dmarc'.$r.'_def'} == 1 ? undef :
	  $in{'dns_dmarc'.$r.'_def'} == 2 ? "skip" : $in{'dns_dmarc'.$r};
	}
$tmpl->{'dns_dmarcextra'} = $in{'dns_dmarcextra'};

# Save sub-domain DNS mode
$tmpl->{'dns_sub'} = $in{'dns_sub_mode'} == 0 ? "none" :
		     $in{'dns_sub_mode'} == 1 ? undef : "yes";

# Save DNS alias mode
$tmpl->{'dns_alias'} = $in{'dns_alias_mode'} == 0 ? "none" :
		       $in{'dns_alias_mode'} == 1 ? undef : "yes";

# Save cloud provider
$tmpl->{'dns_cloud'} = $in{'dns_cloud'};
$tmpl->{'dns_cloud_import'} = $in{'dns_cloud_import'};
$tmpl->{'dns_cloud_proxy'} = $in{'dns_cloud_proxy'};

# Save slave servers
if (defined($in{'dns_slaves_def'}) ||
    defined($in{'dns_slaves'})) {
	if ($in{'dns_slaves_def'} == 1) {
		$tmpl->{'dns_slaves'} = '';
		}
	elsif ($in{'dns_slaves_def'} == 2) {
		$tmpl->{'dns_slaves'} = 'none';
		}
	else {
		$in{'dns_slaves'} || &error($text{'tmpl_dns_eslaves'});
		$tmpl->{'dns_slaves'} = join(" ", split(/\0/, $in{'dns_slaves'}));
		}
	}

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
		$tmpl->{'dnssec_alg'} = $in{'dnssec_alg'} || 'RSASHA256';
		$tmpl->{'dnssec_single'} = $in{'dnssec_single'};
		}
	}
}

# get_domain_spf(&domain)
# Returns the SPF object for a domain from its DNS records, or undef.
sub get_domain_spf
{
local ($d) = @_;
&require_bind();
local @recs = &get_domain_dns_records($d);
foreach my $r (@recs) {
	if (($r->{'type'} eq 'SPF' ||
	     $r->{'type'} eq 'TXT' && $r->{'values'}->[0] =~ /^v=spf1/) &&
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
&require_bind();
local ($recs, $file) = &get_domain_dns_records_and_file($d);
if (!$file) {
	# Zone not found!
	return;
	}
local @types = map { $_->{'type'} }
		   grep { $_->{'values'}->[0] =~ /^v=spf/ &&
			  $_->{'name'} eq $d->{'dom'}.'.' } @$recs;
if (!@types) {
	@types = $bind8::config{'spf_record'} ? ( "SPF", "TXT" ) : ( "SPF" );
	}
local $bump = 0;
&pre_records_change($d);
foreach my $t (&unique(@types)) {
	local ($r) = grep { $_->{'type'} eq $t &&
			    $_->{'values'}->[0] =~ /^v=spf/ &&
			    $_->{'name'} eq $d->{'dom'}.'.' } @$recs;
	local $str = $spf ? &bind8::join_spf($spf) : undef;
	if ($r && $spf) {
		# Update record
		$r->{'values'} = [ $str ];
		&modify_dns_record($recs, $file, $r);
		$bump = 1;
		}
	elsif ($r && !$spf) {
		# Remove record
		&delete_dns_record($recs, $file, $r);
		$d->{'domain_spf_enabled'} = 0;
		&save_domain($d);
		$bump = 1;
		}
	elsif (!$r && $spf) {
		# Add record
		$r = { 'name' => $d->{'dom'}.'.',
		       'type' => $t,
		       'values' => [ $str ] };
		&create_dns_record($recs, $file, $r);
		$d->{'domain_spf_enabled'} = 1;
		&save_domain($d);
		$bump = 1;
		}
	}
if ($bump) {
	&post_records_change($d, $recs, $file);
	&reload_bind_records($d);
	}
else {
	&after_records_change($d);
	}
}

# update_smtpcloud_spf(&domain, [old-cloud])
# Update the SPF record for a domain's DNS cloud
sub update_smtpcloud_spf
{
my ($d, $oldcloud) = @_;
my $newcloud = $d->{'smtp_cloud'};
my $spf = &get_domain_spf($d);
return 0 if (!$spf);
if ($oldcloud) {
	# Remove SPF options for old cloud
	my $sfunc = "smtpcloud_".$oldcloud."_get_spf";
	my @oldspf = defined(&$sfunc) ? &$sfunc($d) : ( );
	foreach my $s (@oldspf) {
		my ($n, $v) = split(/:/, $s);
		$n .= ":";
		if ($spf->{$n}) {
			$spf->{$n} = [ grep { $_ ne $v } @{$s->{$n}} ];
			}
		}
	}
if ($newcloud) {
	# Add SPF options for new cloud
	my $sfunc = "smtpcloud_".$newcloud."_get_spf";
	my @newspf = defined(&$sfunc) ? &$sfunc($d) : ( );
	foreach my $s (@newspf) {
		my ($n, $v) = split(/:/, $s);
		$n .= ":";
		my @vals = $spf->{$n} ? @{$spf->{$n}} : ( );
		@vals = &unique(@vals, $v);
		$spf->{$n} = \@vals;
		}
	}
&save_domain_spf($d, $spf);
}

# is_domain_spf_enabled(&domain)
# Returns (possibly cached) SPF status
sub is_domain_spf_enabled
{
my ($d) = @_;
if (!defined($d->{'domain_spf_enabled'})) {
	my $spf = &get_domain_spf($d);
	$d->{'domain_spf_enabled'} = $spf ? 1 : 0;
	}
return $d->{'domain_spf_enabled'};
}

# build_spf_dmarc_caches()
# Set the local cache of SPF and DMARC status for all domains
sub build_spf_dmarc_caches
{
foreach my $d (grep { $_->{'dns'} } &list_domains()) {
	if (!defined($d->{'domain_spf_enabled'})) {
		&lock_domain($d);
		$d = &get_domain($d->{'id'}, undef, 1);
		&is_domain_spf_enabled($d);
		&save_domain($d);
		&unlock_domain($d);
		}
	if (!defined($d->{'domain_dmarc_enabled'})) {
		&lock_domain($d);
		$d = &get_domain($d->{'id'}, undef, 1);
		&is_domain_dmarc_enabled($d);
		&save_domain($d);
		&unlock_domain($d);
		}
	}
}

# get_domain_dmarc(&domain)
# Returns the DMARC object for a domain from its DNS records, or undef.
sub get_domain_dmarc
{
local ($d) = @_;
&require_bind();
local @recs = &get_domain_dns_records($d);
foreach my $r (@recs) {
	if (($r->{'type'} eq 'DMARC' || $r->{'type'} eq 'TXT') &&
	    lc($r->{'name'}) eq '_dmarc.'.$d->{'dom'}.'.') {
		return &bind8::parse_dmarc(@{$r->{'values'}});
		}
	}
return undef;
}

# save_domain_dmarc(&domain, &dmarc)
# Updates/creates/deletes a domain's SPF record.
sub save_domain_dmarc
{
local ($d, $dmarc) = @_;
&require_bind();
&pre_records_change($d);
local ($recs, $file) = &get_domain_dns_records_and_file($d);
if (!$file) {
	# Domain not found!
	return "DNS zone not found!";
	}
local $bump = 0;
local ($r) = grep { ($_->{'type'} eq 'TXT' ||
		     $_->{'type'} eq 'DMARC') &&
		    $_->{'values'}->[0] =~ /^v=DMARC1/i &&
		    lc($_->{'name'}) eq '_dmarc.'.$d->{'dom'}.'.' } @$recs;
local $str = $dmarc ? &bind8::join_dmarc($dmarc) : undef;
if ($r && $dmarc) {
	# Update record
	$r->{'values'} = [ $str ];
	&modify_dns_record($recs, $file, $r);
	$bump = 1;
	}
elsif ($r && !$dmarc) {
	# Remove record
	&delete_dns_record($recs, $file, $r);
	$bump = 1;
	}
elsif (!$r && $dmarc) {
	# Add record
	$r = { 'name' => '_dmarc.'.$d->{'dom'}.'.',
	       'type' => 'TXT',
	       'values' => [ $str ] };
	&create_dns_record($recs, $file, $r);
	$bump = 1;
	}
if ($bump) {
	my $err = &post_records_change($d, $recs, $file);
	return $err if ($err);
	&register_post_action(\&restart_bind, $d);
	}
else {
	&after_records_change($d);
	}
return undef;
}

# is_domain_dmarc_enabled(&domain)
# Returns (possibly cached) DMARC status
sub is_domain_dmarc_enabled
{
my ($d) = @_;
if (!defined($d->{'domain_dmarc_enabled'})) {
	my $dmarc = &get_domain_dmarc($d);
	$d->{'domain_dmarc_enabled'} = $dmarc ? 1 : 0;
	}
return $d->{'domain_dmarc_enabled'};
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
	       "for cloudmin services domains");
	}
if ($d->{'dns_cloud'}) {
	&error("get_domain_dns_file($d->{'dom'}) cannot be called ".
	       "for cloud hosted domains");
	}
return &get_domain_dns_file_from_bind($d);
}

# get_domain_dns_file_from_bind(&domain)
# Lookup the zone file in local BIND, or return undef. Path is relative to
# any chroot.
sub get_domain_dns_file_from_bind
{
my ($d) = @_;
my $r = &require_bind($d);
my $z;
if ($d->{'dns_submode'}) {
	# Records are in super-domain
	local $parent = &get_domain($d->{'dns_subof'});
	$z = &get_bind_zone($parent->{'dom'}, undef, $parent);
	}
else {
	# In this domain
	$z = &get_bind_zone($d->{'dom'}, undef, $d);
	}
return undef if (!$z);
my $file = &bind8::find("file", $z->{'members'});
return undef if (!$file);
return $file->{'values'}->[0];
}

# get_domain_dns_records_and_file(&domain, [force-reread])
# Returns an array ref of a domain's DNS records and the file they are in.
# For a provisioned domain, this may be a local temp file.
sub get_domain_dns_records_and_file
{
local ($d, $force) = @_;
if ($d->{'dns_submode'}) {
	# Records are in the parent domain, so just call this same method for it
	local $parent = &get_domain($d->{'dns_subof'});
	return &get_domain_dns_records_and_file($parent);
	}
my $cid = $d->{'id'};
if (defined($domain_dns_records_cache{$cid}) && !$force) {
	# Use cached values
	return @{$domain_dns_records_cache{$cid}};
	}
&require_bind();
local $bind8::config{'short_names'} = 0;

# Create a temp file for writing downloaded records
local ($temp, $abstemp);
if ($d->{'dns_cloud'} || $d->{'provision_dns'} || $d->{'dns_remote'}) {
	$temp = &transname();
	$abstemp = $temp;
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
	}

my @rv;
if ($d->{'dns_cloud'}) {
	# Fetch from the cloud provider and write to temp file. The underlying
	# BIND module API must be used here, because we need to write to an
	# actual file.
	my $ctype = $d->{'dns_cloud'};
	my $gfunc = "dnscloud_".$ctype."_get_records";
	if (!defined(&$gfunc)) {
		return (&text('spf_ecloudprov', $ctype));
		}
	my $info = { 'domain' => $d->{'dom'},
		     'id' => $d->{'dns_cloud_id'},
		     'location' => $d->{'dns_cloud_location'} };
	my $cloud = &get_domain_dns_cloud($d);
	$cloud || "Cloud provider $ctype does not exist!";
	my ($ok, $recs) = &$gfunc($d, $info);
	return (&text('save_ereaddnscloud', $cloud->{'desc'}, $recs)) if (!$ok);
	local $lnum = 0;
	foreach my $rec (@$recs) {
		&bind8::create_record($temp, $rec->{'name'},
			$rec->{'ttl'}, $rec->{'class'}, $rec->{'type'},
			&join_record_values($rec, 1),
			$rec->{'comment'});
		$rec->{'line'} = $lnum;
		$rec->{'eline'} = $lnum;
		$rec->{'num'} = $lnum;
		$rec->{'file'} = $temp;
		$rec->{'rootfile'} = $abstemp;
		$lnum++;
		}
	&set_record_ids($recs);
	@rv = ($recs, $temp);
	}
elsif ($d->{'provision_dns'}) {
	# Fetch from cloudmin services and write to temp file. The underlying
	# BIND module API must be used here, because we need to write to an
	# actual file.
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
	@rv = (\@recs, $temp);
	}
elsif ($d->{'dns_remote'}) {
	# Get records from remote Webmin server
	my $r = &require_bind($d);
	my $rfile = &get_domain_dns_file_from_bind($d);
	if (!$rfile) {
		return ("No zone file found for $d->{'dom'}");
		}
	eval {
		local $main::remote_error_handler = sub { die @_ };
		&remote_read($r, $abstemp, $rfile);
		};
	if ($@) {
		return ($@);
		}
	local @recs = &bind8::read_zone_file($temp, $d->{'dom'}, undef, 0, 1);
	&set_record_ids(\@recs);
	@rv = (\@recs, $temp);
	}
else {
	# Find local file
	local $file = &get_domain_dns_file($d);
	return ("No zone file found for $d->{'dom'}") if (!$file);
	local @recs = &bind8::read_zone_file($file, $d->{'dom'});
	&set_record_ids(\@recs);
	@rv = (\@recs, $file);
	}
$domain_dns_records_cache{$cid} = \@rv;
return @rv;
}

# clear_domain_dns_records_and_file(&domain)
# Clear any cache of a domain's DNS records or filename
sub clear_domain_dns_records_and_file
{
my ($d) = @_;
my $cid = $d->{'dns_submode'} ? $d->{'dns_subof'} : $d->{'id'};
delete($domain_dns_records_cache{$cid});
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

# create_dns_record(&records, file, &record)
# Update a zone file and records array ref with a new record
sub create_dns_record
{
my ($recs, $file, $r) = @_;
&require_bind();
my $lref = &read_file_lines($file, 1);
$r->{'realname'} ||= $r->{'name'};
$r->{'file'} = $file;
$r->{'line'} = scalar(@$lref);
$r->{'eline'} = $r->{'line'};
if (defined($r->{'defttl'})) {
	&bind8::create_defttl($file, $r->{'defttl'});

	# Defttl is always at the start, so move all other records down
	foreach my $e (@$recs) {
		$e->{'line'}++;
		$e->{'eline'}++ if (defined($e->{'eline'}));
		}
	}
else {
	my $vstr = &join_record_values($r);
	my @params = ( $r->{'name'}, $r->{'ttl'},
		       $r->{'class'} || "IN", $r->{'type'},
		       $vstr, $r->{'comment'} );
	my @vlines = split(/\n/, $vstr);
	$r->{'eline'} = $r->{'line'} + scalar(@vlines) - 1;
	&bind8::create_record($file, @params);
	}
push(@$recs, $r);
}

# modify_dns_record(&records, file, &record)
# Update a zone file with a changed record
sub modify_dns_record
{
my ($recs, $file, $r) = @_;
&require_bind();
if (defined($r->{'defttl'})) {
	&bind8::modify_defttl($file, $r, $r->{'defttl'});
	}
else {
	my @params = ( $r->{'name'}, $r->{'ttl'},
		       $r->{'class'} || "IN", $r->{'type'},
		       &join_record_values($r), $r->{'comment'} );
	&bind8::modify_record($file, $r, @params);
	}
}

# delete_dns_record(&records, file, &record)
# Update a zone file and records array ref to remove a record
sub delete_dns_record
{
my ($recs, $file, $r) = @_;
&require_bind();
if (defined($r->{'defttl'})) {
	&bind8::delete_defttl($file, $r);
	}
else {
	&bind8::delete_record($file, $r);
	}
my $idx = &indexof($r, @$recs);
if ($idx >= 0) {
	splice(@$recs, $idx, 1);
	}
my $len = defined($r->{'eline'}) ? $r->{'eline'} - $r->{'line'} + 1 : 1;
foreach my $o (@$recs) {
	$o->{'line'} -= $len if ($o->{'line'} > $r->{'line'});
	$o->{'eline'} -= $len if (defined($o->{'eline'}) &&
				  $o->{'eline'} > $r->{'eline'});
	}
}

# clone_dns_record(&rec)
# Returns a new hash ref for a record which is a deep copy of the original
sub clone_dns_record
{
my ($r) = @_;
my $nr = { %$r };
$nr->{'values'} = [ @{$r->{'values'}} ];
return $nr;
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
if ($defip ne "127.0.0.1" && !$tmpl->{'dns_spfonly'}) {
	push(@{$spf->{'ip4:'}}, $defip);
	}
if ($defip6 && !$tmpl->{'dns_spfonly'}) {
	push(@{$spf->{'ip6:'}}, $defip6);
	}
local $hosts = &substitute_domain_template($tmpl->{'dns_spfhosts'}, $d);
foreach my $h (split(/\s+/, $hosts)) {
	if (&check_ipaddress($h) ||
	    $h =~ /^(\S+)\// && &check_ipaddress("$1")) {
		push(@{$spf->{'ip4:'}}, $h);
		}
	elsif (&check_ip6address($h) ||
	       $h =~ /^(\S+)\// && &check_ip6address("$1")) {
		push(@{$spf->{'ip6:'}}, $h);
		}
	else {
		push(@{$spf->{'a:'}}, $h);
		}
	}
local $includes = &substitute_domain_template($tmpl->{'dns_spfincludes'}, $d);
foreach my $i (split(/\s+/, $includes)) {
	push(@{$spf->{'include:'}}, $i);
	}
if ($d->{'dns_ip'} && !$tmpl->{'dns_spfonly'}) {
	push(@{$spf->{'ip4:'}}, $d->{'dns_ip'});
	}
if ($d->{'ip'} ne $defip && $d->{'ip'} !~ /^(10\.|192\.168\.)/ &&
    !$tmpl->{'dns_spfonly'}) {
	push(@{$spf->{'ip4:'}}, $d->{'ip'});
	}
if ($d->{'ip6'} && $d->{'ip6'} ne $defip6 && !$tmpl->{'dns_spfonly'}) {
	push(@{$spf->{'ip6:'}}, $d->{'ip6'});
	}
@{$spf->{'ip4:'}} = &unique(@{$spf->{'ip4:'}});
@{$spf->{'ip6:'}} = &unique(@{$spf->{'ip6:'}});
$spf->{'all'} = $tmpl->{'dns_spfall'} + 1;

# Add SPF records for DNS cloud
my $cloud = $d->{'smtp_cloud'};
if ($cloud) {
	my $sfunc = "smtpcloud_".$cloud."_get_spf";
	if (defined(&$sfunc)) {
		my @newspf = &$sfunc($d);
		foreach my $s (@newspf) {
			my ($n, $v) = split(/:/, $s);
			$n .= ":";
			my @vals = $spf->{$n} ? @{$spf->{$n}} : ( );
			@vals = &unique(@vals, $v);
			$spf->{$n} = \@vals;
			}
		}
	}
return $spf;
}

# default_domain_dmarc(&domain)
# Returns a default DMARC object for a domain, based on its template
sub default_domain_dmarc
{
local ($d) = @_;
local $tmpl = &get_template($d->{'template'});
local $pm = 'mailto:postmaster@'.$d->{'dom'};
local $dmarc = { 'p' => $tmpl->{'dns_dmarcp'} || 'none',
		 'pct' => $tmpl->{'dns_dmarcpct'} || '100',
	       };
foreach my $r ('ruf', 'rua') {
	local $v = $tmpl->{'dns_dmarc'.$r};
	next if ($v eq "skip");
	if ($v && $v ne "none") {
		$dmarc->{$r} = &substitute_domain_template($v, $d);
		}
	else {
		$dmarc->{$r} = $pm;
		}
	}
$dmarc->{'other'} = [ split(/;\s*/, $tmpl->{'dns_dmarcextra'}) ];
return $dmarc;
}

# text_to_named_conf(text)
# Converts a text string which contains zero or more BIND directives into an
# array of directive objects.
sub text_to_named_conf
{
my ($str) = @_;
my $temp = &transname();
&open_tempfile(TEMP, ">$temp");
&print_tempfile(TEMP, $str);
&close_tempfile(TEMP);
&require_bind();
local $bind8::config{'chroot'} = undef;		# turn off chroot temporarily
local $bind8::config{'auto_chroot'} = undef;
undef($bind8::get_chroot_cache);
my @rv = grep { $_->{'name'} ne 'dummy' }
	    &bind8::read_config_file($temp, 0);
undef($bind8::get_chroot_cache);		# reset cache back
return @rv;
}

# text_to_dns_records(text, domain-name)
# Convert some text into an array of DNS records
sub text_to_dns_records
{
my ($str, $dname) = @_;
my $temp = &transname();
&open_tempfile(TEMP, ">$temp");
&print_tempfile(TEMP, $str);
&close_tempfile(TEMP);
&require_bind();
local $bind8::config{'chroot'} = undef;		# turn off chroot temporarily
local $bind8::config{'auto_chroot'} = undef;
undef($bind8::get_chroot_cache);
my @recs = &bind8::read_zone_file($temp, $dname, undef, 0, 1);
undef($bind8::get_chroot_cache);		# reset cache back
return @recs;
}

# pre_records_change(&domain)
# Called before records in a domain are changed or read, to freeze the zone
# if necessary
sub pre_records_change
{
local ($d) = @_;

# Freeze the zone, so that updates to dynamic zones work
if (!$d->{'provision_dns'} && !$d->{'dns_cloud'}) {
	&require_bind();
	my $z = &bind8::get_zone_name($d->{'dom'}, 'any');
	if ($z && defined(&bind8::before_editing)) {
		&bind8::before_editing($z);
		}
	}
}

# after_records_change(&domain)
# Should be called after pre_records_change, but only if nothing was changed
sub after_records_change
{
local ($d) = @_;
if (!$d->{'provision_dns'} && !$d->{'dns_cloud'}) {
	my $z = &bind8::get_zone_name($d->{'dom'}, 'any');
	if ($z && defined(&bind8::after_editing)) {
		&bind8::after_editing($z);
		}
	}
}

# post_records_change(&domain, &recs, file)
# Called after some records in a domain are changed, to bump to SOA
# and possibly re-sign and upload to a remote server
sub post_records_change
{
local ($d, $recs, $fn) = @_;
if ($d->{'dns_submode'}) {
	# Apply change in the parent zone, which is actually connected to the
	# Cloud DNS provider
	my $parent = &get_domain($d->{'dns_subof'});
	return &post_records_change($parent, $recs, $fn);
	}
my $r = &require_bind($d);
my $rds = &remote_foreign_call($r, "bind8", "supports_dnssec");

# Increase the SOA
&bind8::bump_soa_record($fn, $recs);

if ($rds && &can_domain_dnssec($d) && !$d->{'dns_remote'}) {
	# Re-sign DNSSEC, or remove records if no longer signed
	&sign_dnssec_zone($d, $recs);
	}

if ($d->{'provision_dns'}) {
	# Upload records to provisioning server
	local $info = { 'domain' => $d->{'dom'},
			'replace' => '',
			'host' => $d->{'provision_dns_host'} };
	$info->{'record'} = [ &records_to_text($d, $recs) ];
	my ($ok, $msg) = &provision_api_call("modify-dns-records", $info, 0);
	if (!ok) {
		return "Error from provisioning server updating records : $msg";
		}
	}
elsif ($d->{'dns_cloud'}) {
	# Upload records to cloud DNS provider
	local $ctype = $d->{'dns_cloud'};
	local $info = { 'domain' => $d->{'dom'},
	                'id' => $d->{'dns_cloud_id'},
	                'location' => $d->{'dns_cloud_location'},
	                'recs' => $recs };
	my $pfunc = "dnscloud_".$ctype."_put_records";
	my ($ok, $msg) = &$pfunc($d, $info);
	if (!$ok) {
		return "Failed to update DNS records : $msg";
		}
	}
elsif ($d->{'dns_remote'}) {
	# Upload records to remote Webmin server
	my $rfile = &get_domain_dns_file_from_bind($d);
	if (!$rfile) {
		return "Remote zone file not found!";
		}
	$rfile = &remote_foreign_call($r, "bind8", "make_chroot", $rfile);
	eval {
		local $main::remote_error_handler = sub { die @_ };
		&remote_write($r, $fn, $rfile);
		};
	if ($@) {
		return $@;
		}
	if ($rds && &can_domain_dnssec($d)) {
		# Sign DNSSEC on remote after uploading records
		&sign_dnssec_zone($d, $recs);
		}
	}

# Un-freeeze the zone
&after_records_change($d);

# If this domain has aliases, re-create their DNS records too
if (!$d->{'subdom'} && !$d->{'dns_submode'}) {
	local @aliases = grep { $_->{'dns'} && !$_->{'dns_submode'} &&
				!$_->{'aliasdns'} }
			      &get_domain_by("alias", $d->{'id'});
	foreach my $ad (@aliases) {
		&obtain_lock_dns($ad);
		&pre_records_change($d);
		local ($recs, $file) = &get_domain_dns_records_and_file($ad);
		&create_alias_records($recs, $file, $ad,
				      $ad->{'dns_ip'} || $ad->{'ip'}, 1);
		&post_records_change($ad, $recs, $file);
		&reload_bind_records($ad);
		&release_lock_dns($ad);
		}
	}

return undef;
}

# sign_dnssec_zone(&domain, &recs)
# Re-sign the zone with DNSSEC, and update the records array. Returns undef on
# success or an error message on failure.
sub sign_dnssec_zone
{
my ($d, $recs) = @_;
my $r = &require_bind($d);
my $z = &get_bind_zone($d->{'dom'}, undef, $d);
eval {
	local $main::error_must_die = 1;
	&remote_foreign_call($r, "bind8", "sign_dnssec_zone_if_key",
			     $z, $recs, 0);
	};
if ($@) {
	return "DNSSEC signing failed : $@";
	}
else {
	# Signing will have updated all the records, so re-read them
	my ($newrecs) = &get_domain_dns_records_and_file($d, 1);
	@$recs = ( );
	push(@$recs, @$newrecs);
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
       $r->{'values'}->[0] =~ /^(t=|k=|v=)/ &&
       $config{'dkim_enabled'}) {
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

# copy_alias_records(&domain)
# Returns 1 if an alias domain gets it's records copied from the target
sub copy_alias_records
{
my ($d) = @_;
if ($d->{'alias'} && !$d->{'aliasdns'}) {
	local $target = &get_domain($d->{'alias'});
	if ($target && !$target->{'subdom'} &&
	    !$target->{'dns_submode'}) {
		return 1;
		}
	}
return 0;
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
                           'width' => 60,
			   'height' => 5,
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
	   'values' => [ { 'desc' => $text{'records_valuespf'},
                           'size' => 60,
			   'regexp' => '\S',
			   'dot' => 0,
                         },
                       ],
	 },
	 { 'type' => 'CAA',
	   'desc' => $text{'records_typecaa'},
	   'domain' => 1,
	   'create' => 1,
	   'values' => [ { 'desc' => $text{'records_valuecaa0'},
			   'opts' => [ [ 0, $text{'records_caanon'} ],
				       [ 1, $text{'records_caacrit'} ] ],
			   'dot' => 0,
                         },
		  	 { 'desc' => $text{'records_valuecaa1'},
			   'opts' => [ [ 'issue', $text{'records_caaissue'} ],
				       [ 'issuewild', $text{'records_caaissuewild'} ],
				       [ 'iodef', $text{'records_caaiodef'} ] ],
			   'dot' => 0,
                         },
			 { 'desc' => $text{'records_valuecaa2'},
			   'size' => 60,
			   'regexp' => '^\S+$',
			   'dot' => 0,
                         },
                       ],
	 },
	 { 'type' => 'PTR',
	   'desc' => $text{'records_typeptr'},
	   'domain' => 0,
	   'create' => 0,
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

# can_domain_dnssec(&domain)
# Returns 1 if DNSSEC can be setup for a domain
sub can_domain_dnssec
{
my ($d) = @_;
return $d->{'provision_dns'} || $d->{'dns_cloud'} ? 0 : 1;
}

# has_domain_dnssec(&domain, [&records])
# Returns 1 if DNSSEC is enabled for a domain
sub has_domain_dnssec
{
my ($d, $recs) = @_;
if (!$recs) {
	($recs) = &get_domain_dns_records_and_file($d);
	}
local $withdot = $d->{'dom'}.".";
local ($dnskey) = grep { $_->{'type'} eq 'DNSKEY' &&
			 $_->{'name'} eq $withdot } @$recs;
return $dnskey ? 1 : 0;
}

# disable_domain_dnssec(&domain)
# Remove all DNSSEC records for a domain. Returns undef on success or an error
# message on failure.
sub disable_domain_dnssec
{
my ($d) = @_;
my $r = &require_bind($d);
&obtain_lock_dns($d);
my $zone = &get_bind_zone($d->{'dom'}, undef, $d);
my $key = &remote_foreign_call($r, "bind8", "get_dnssec_key", $zone);
my @keyfiles;
if ($key) {
	@keyfiles = map { $k->{$_} } ('publicfile', 'privatefile');
	}
foreach my $k (@keyfiles) {
        &lock_file($k);
        }
&delete_parent_dnssec_ds_records($d);
&remote_foreign_call($r, "bind8", "delete_dnssec_key", $zone, 1);
foreach my $k (@keyfiles) {
        &unlock_file($k);
        }
&get_domain_dns_records_and_file($d, 1);	# Force re-read of records
&release_lock_dns($d);
return undef;
}

# enable_domain_dnssec(&domain)
# Add appropriate DNSSEC records for a domain. Returns undef on success or an
# error message on failure.
sub enable_domain_dnssec
{
my ($d) = @_;
my $r = &require_bind($d);
my $tmpl = &get_template($d->{'template'});
if (!$tmpl->{'dnssec_alg'}) {
	return $text{'setup_enodnssecalg'};
	}
&obtain_lock_dns($d);
if (!&remote_foreign_call($r, "bind8", "supports_dnssec")) {
	# Not supported
	return $text{'setup_enodnssec'};
	}
else {
	my $zone = &get_bind_zone($d->{'dom'}, undef, $d);
	my ($ok, $size) = &remote_foreign_call(
				$r, "bind8", "compute_dnssec_key_size",
				$tmpl->{'dnssec_alg'}, 1);
	my $err;
	my $regen = $d->{'dnssec_alg'} &&
		    $tmpl->{'dnssec_alg'} ne $d->{'dnssec_alg'};
	if (!$ok) {
		# Key size failed
		return &text('setup_ednssecsize', $size);
		}
	elsif ($err = &remote_foreign_call($r, "bind8", "create_dnssec_key",
			$zone, $tmpl->{'dnssec_alg'}, $size,
			$tmpl->{'dnssec_single'}, $regen)) {
		# Key generation failed
		return &text('setup_ednsseckey', $err);
		}
	elsif ($err = &remote_foreign_call(
			$r, "bind8", "sign_dnssec_zone", $zone)) {
		# Zone signing failed
		return &text('setup_ednssecsign', $err);
		}
	$d->{'dnssec_alg'} = $tmpl->{'dnssec_alg'};

	# Force re-read of records from file, since dnssec-tools will have
	# changed them
	&get_domain_dns_records_and_file($d, 1);
	}
&release_lock_dns($d);
&add_parent_dnssec_ds_records($d);
return undef;
}

# add_parent_dnssec_ds_records(&domain)
# Add DS records to parent domain, if we also host it
sub add_parent_dnssec_ds_records
{
my ($d) = @_;
my $pname = $d->{'dom'};
$pname =~ s/^([^\.]+)\.//;
my $parent = &get_domain_by("dom", $pname);
my $dsrecs = &get_domain_dnssec_ds_records($d);
$dsrecs = [ ] if (!ref($dsrecs));
if ($parent) {
	@$dsrecs || return "Domain does not have DNSSEC enabled";
	&obtain_lock_dns($parent);
	&pre_records_change($parent);
	my ($precs, $pfile) = &get_domain_dns_records_and_file($parent);
	my %already;
	foreach my $rec (@$precs) {
		$already{$rec->{'name'},$rec->{'type'}}++;
		}
	foreach my $ds (@$dsrecs) {
		if (!$already{$ds->{'name'},$ds->{'type'}}) {
			my $dsr = { %$ds };
			&create_dns_record($prec, $pfile, $dsr);
			}
		}
	if (!$already{$d->{'dom'}.".","NS"} && !$d->{'dns_submode'}) {
		# Also need to add an NS record, or else signing will fail
		my $tmpl = &get_template($d->{'template'});
		my $master = &get_master_nameserver($tmpl, $d);
		my $r = { 'name' => $d->{'dom'}.".",
			  'type' => 'NS',
			  'values' => [ $master ] };
		if (!$already{$r->{'name'},$r->{'type'}}) {
			&create_dns_record($precs, $pfile, $r);
			}
		}
	&post_records_change($parent, $precs, $pfile);
	&release_lock_dns($parent);
	return undef;
	}
return "No parent DNS domain found";
}

# delete_parent_dnssec_ds_records(&domain)
# Delete any DS records in the parent for a sub-domain
sub delete_parent_dnssec_ds_records
{
my ($d) = @_;
my $pname = $d->{'dom'};
$pname =~ s/^([^\.]+)\.//;
my $parent = &get_domain_by("dom", $pname);
my $dsrecs = &get_domain_dnssec_ds_records($d);
$dsrecs = [ ] if (!ref($dsrecs));
if ($parent) {
	&obtain_lock_dns($parent);
	&pre_records_change($parent);
	my ($precs, $pfile) = &get_domain_dns_records_and_file($parent);
	if (!$pfile) {
		return "Failed to read parent DNS domain : $precs";
		}
	my $deleted = 0;
	my @delrecs;
	foreach my $rec (@$precs) {
		DS: foreach my $ds (@$dsrecs) {
			if ($rec->{'name'} eq $ds->{'name'} &&
			    $rec->{'type'} eq $ds->{'type'}) {
				push(@delrecs, $rec);
				$deleted++;
				last DS;
				}
			}
		if ($rec->{'name'} eq $d->{'dom'}."." &&
		    $rec->{'type'} eq 'NS') {
			push(@delrecs, $rec);
			}
		}
	foreach my $rec (@delrecs) {
		&delete_dns_record($precs, $pfile, $rec);
		}
	&post_records_change($parent, $precs, $pfile);
	&release_lock_dns($parent);
	return $deleted ? undef : "No DS records to remove found";
	}
return "No parent DNS domain found";
}

# get_domain_dnssec_ds_records(&domain)
# Returns the DS records for this domain (to be used at the registrar) in
# the bind8 module's format
sub get_domain_dnssec_ds_records
{
local ($d) = @_;
&require_bind();
local $withdot = $d->{'dom'}.".";
local ($recs, $file) = &get_domain_dns_records_and_file($d);
ref($recs) || return $recs;
local ($dnskey) = grep { $_->{'type'} eq 'DNSKEY' &&
			 $_->{'name'} eq $withdot } @$recs;
$dnskey || return "No DNSKEY record found for $withdot";
&has_command("dnssec-dsfromkey") ||
	return "The dnssec-dsfromkey command was not found";
$file = &bind8::make_chroot($file);
local $dstemp = &transname();
local $out = &backquote_command("dnssec-dsfromkey -f ".quotemeta($file)." ".
				quotemeta($d->{'dom'})." 2>&1 >$dstemp");
if ($?) {
	return "dnssec-dsfromkey failed : $out";
	}
local @dsrecs = &bind8::read_zone_file($dstemp, $d->{'dom'}, undef, undef, 1);
&unlink_file($dstemp);
@dsrecs = grep { $_->{'type'} eq 'DS' } @dsrecs;
@dsrecs || return "No DS records generated!";
return \@dsrecs;
}

# check_tlsa_support()
# Returns undef if TLSA is supported on the system, or an error message if not
sub check_tlsa_support
{
my $file = "$config_directory/miniserv.pem";
if (!-r $file) {
	$file = "$root_directory/miniserv.pem";
	}
my $out = &backquote_command(
	"(openssl x509 -in ".quotemeta($file)." -outform DER | ".
	"openssl sha256) 2>&1 >/dev/null");
return $? || $out =~ /invalid\s+command/i ? $text{'index_etlsassl'} : undef;
}

# create_tlsa_dns_record(cert-file, chain-file, port, hostname)
# Given an SSL cert file, port number (assumed TCP) and hostname, returns a
# BIND record structure for it
sub create_tlsa_dns_record
{
my ($file, $chain, $port, $host) = @_;
my $temp = &transname();
&open_tempfile(TEMP, ">$temp");
&print_tempfile(TEMP, &read_file_contents($file));
if ($chain) {
	&print_tempfile(TEMP, &read_file_contents($chain));
	}
&close_tempfile(TEMP);
my $hash = &backquote_command(
	"openssl x509 -in ".quotemeta($temp)." -outform DER 2>/dev/null | ".
	"openssl sha256 2>/dev/null");
return undef if ($?);
$hash =~ /=\s*([0-9a-f]+)/ || return undef;
return { 'name' => "_".$port."._tcp.".$host.".",
	 'class' => "IN",
	 'type' => "TLSA",
         'ttl' => 3600,
	 'values' => [ 3, 0, 1, $1 ] };
}

# create_sshfp_dns_record(key-file, key-type, hostname)
# Given an SSH key file and hostname, returns a BIND record structure for it
sub create_sshfp_dns_record
{
my ($file, $type, $host) = @_;
my $hash = &backquote_command(
	"awk '{ print \$2 }' ".quotemeta($file)." | ".
	"openssl base64 -d -A 2>/dev/null | openssl sha1 2>/dev/null");
return undef if ($?);
my @types = ( "rsa", "dsa", "ecdsa", "ed25519" );
my $tn = &indexof($type, @types) + 1;
return undef if (!$tn);
$hash =~ /=\s*([0-9a-f]+)/ || return undef;
return { 'name' => $host.".",
	 'class' => "IN",
	 'type' => "SSHFP",
	 'values' => [ $tn, 1, $1 ] };
}

# sync_domain_tlsa_records(&domain, [force-mode])
# Replace all TLSA records for a domain with its actual SSL certs (if enabled)
# force-mode 0 = use config, 1 = enable, 2 = disable
sub sync_domain_tlsa_records
{
my ($d, $force) = @_;
&pre_records_change($d);
my ($recs, $file) = &get_domain_dns_records_and_file($d);
if (!$file) {
	&after_records_change($d);
	return undef;
	}

# Find all existing TLSA records (without TTL, for easier comparison)
my $frecs = &filter_domain_dns_records($d, $recs);
my @oldrecs = grep { $_->{'type'} =~ /^(TLSA|SSHFP)$/ &&
		     ($_->{'name'} eq $d->{'dom'}."." ||
		      $_->{'name'} =~ /\.\Q$d->{'dom'}\E\.$/) } @$frecs;

# Exit now if TLSA is not enabled globally, unless it's being forced on OR
# there are already records
if (!$config{'tlsa_records'} && !$force && !@oldrecs) {
	&after_records_change($d);
	return undef;
	}

# Work out which TLSA records are needed
my @need;
if (&domain_has_website($d) && &domain_has_ssl_cert($d)) {
	# SSL website
	my $chain = &get_website_ssl_file($d, 'ca');
	foreach my $hn (&get_hostnames_for_ssl($d)) {
		if ($hn eq $d->{'dom'} ||
		    $hn =~ /\.\Q$d->{'dom'}\E$/) {
			push(@need, &create_tlsa_dns_record(
				$d->{'ssl_cert'}, $chain, $d->{'web_sslport'}, $hn));
			}
		}
	}
foreach my $svc (&get_all_service_ssl_certs($d, 1)) {
	my $cfile = $svc->{'cert'};
	my $chain = $svc->{'ca'};
	my @ports = ( $svc->{'port'} );
	push(@ports, @{$svc->{'sslports'}}) if ($svc->{'sslports'});
	foreach my $p (@ports) {
		push(@need, &create_tlsa_dns_record($cfile, $chain, $p,
			$svc->{'prefix'}.'.'.$d->{'dom'}));
		push(@need, &create_tlsa_dns_record($cfile, $chain, $p,
			$d->{'dom'}));
		}
	}

# Filter out dupes by name (which includes the port)
@need = grep { defined($_) } @need;
my %done;
@need = grep { !$done{$_->{'name'}}++ } @need;

# Also add local SSH host key
foreach my $t ("rsa", "dsa", "ecdsa", "ed25519") {
	my $hostkey = "/etc/ssh/ssh_host_${t}_key.pub";
	next if (!-r $hostkey);
	push(@need, &create_sshfp_dns_record($hostkey, $t, $d->{'dom'}));
	push(@need, &create_sshfp_dns_record($hostkey, $t, "www.".$d->{'dom'}));
	}

# Filter out dupes by name and algorithm
@need = grep { defined($_) } @need;
@need = grep { !$done{$_->{'name'},$_->{'values'}->[0]}++ } @need;

# Filter out clashes with CNAMEs
my %cnames = map { $_->{'name'}, $_ } grep { $_->{'type'} eq 'CNAME' } @$recs;
@need = grep { !$cnames{$_->{'name'}} } @need;

if ($force == 2) {
	# Just removing records
	@need = ();
	}

if (&dns_records_to_text(@oldrecs) ne &dns_records_to_text(@need)) {
	&obtain_lock_dns($d);

	# Delete all old records
	foreach my $r (@oldrecs) {
		&delete_dns_record($recs, $file, $r);
		}

	# Add the new ones
	foreach my $r (@need) {
		&create_dns_record($recs, $file, $r);
		}

	&post_records_change($d, $recs, $file);
	&release_lock_dns($d);
	}
else {
	&after_records_change($d);
	}
}

# get_domain_tlsa_records(&domain)
# Returns all TLSA records for a domain, to check if it's enabled or not
sub get_domain_tlsa_records
{
my ($d) = @_;
my ($recs, $file) = &get_domain_dns_records_and_file($d);
return () if (!$file);
my $frecs = &filter_domain_dns_records($d, $recs);
my @oldrecs = grep { $_->{'type'} =~ /^(TLSA|SSHFP)$/ &&
		     ($_->{'name'} eq $d->{'dom'}."." ||
		      $_->{'name'} =~ /\.\Q$d->{'dom'}\E\.$/) } @$frecs;
return @oldrecs;
}

# dns_records_to_text(&record, ...)
# Returns a newline-terminate text list of DNS records
sub dns_records_to_text
{
my $rv = "";
&require_bind();
foreach my $r (@_) {
	$rv .= &bind8::make_record($r->{'name'}, $r->{'ttl'}, $r->{'class'},
				   $r->{'type'}, &join_record_values($r));
	$rv .= "\n" if ($rv && &trim($rv));
	}
return $rv;
}

# format_dns_text_records($recs-text-list, [&opts])
# Formats records to be column like 
sub format_dns_text_records
{
my ($recs, $opts) = @_;
return $recs if (!length(&trim($recs)));
my $idelim = $opts->{'in-delimiter'} || "	";
my $odelim = $opts->{'out-delimiter'} || $idelim;
my @recs;
my %cols;
my @lines = split(/\n/, $recs);

# Build columns meta
foreach my $ln (@lines) {
	my @lc = split(/$idelim/, $ln);
	for my $x (0 .. $#lc) {
	    my $cl = length($lc[$x]);
	    $cols{"c${x}"} = $cl
	    	if (!$cols{"c${x}"} || $cols{"c${x}"} < $cl);
		}
	}
# Rebuild columns
foreach my $ln (@lines) {
	my @lc = split(/$odelim/, $ln);
	my @rec;
	for my $x (0 .. $#lc) {
	    my $cl = length($lc[$x]);
	    my $lm = $cols{"c${x}"} - $cl;
	    push(@rec, $lc[$x] . " " x $lm);
		}
	push(@recs, join('	', @rec))
	}
return join("\n", @recs);
}

# obtain_lock_dns(&domain, [named-conf-too])
# Lock a domain's zone file and named.conf file
sub obtain_lock_dns
{
my ($d, $conftoo) = @_;
return if (!$config{'dns'});
&obtain_lock_anything($d);
my $prov = &is_dns_remote($d);

# Lock records file
if ($d && !$prov) {
	if ($main::got_lock_dns_zone{$d->{'id'}} == 0) {
		&require_bind();
		my $lockd = $d->{'dns_submode'} ? &get_domain($d->{'dns_subof'}) : $d;
		my $conf = &bind8::get_config();
		my $z = &get_bind_zone($lockd->{'dom'}, $conf);
		my $fn;
		if ($z) {
			my $file = &bind8::find("file", $z->{'members'});
			$fn = $file->{'values'}->[0];
			}
		else {
			my $base = $bconfig{'master_dir'} ||
				      &bind8::base_directory($conf);
			$fn = &bind8::automatic_filename($lockd->{'dom'}, 0, $base);
			}
		my $rootfn = &bind8::make_chroot($fn);
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
my ($d, $conftoo) = @_;
return if (!$config{'dns'});
my $prov = &is_dns_remote($d);

# Unlock records file
if ($d && !$prov) {
	if ($main::got_lock_dns_zone{$d->{'id'}} == 1) {
		my $rootfn = $main::got_lock_dns_file{$d->{'id'}};
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

# is_dns_remote([&domain])
# Returns 1 if DNS is hosted remotely for a domain, or globally
sub is_dns_remote
{
my ($d) = @_;
if ($d) {
	return $d->{'provision_dns'} || $d->{'dns_cloud'} || $d->{'dns_remote'};
	}
else {
	return $config{'provision_dns'} || &default_dns_cloud() ||
	       $config{'dns_nolocal'};
	}
}

# filter_domain_dns_records(&domain, &recs)
# Given a domain and a list of DNS records, return only those records that are
# in the domain and not any sub-domains
sub filter_domain_dns_records
{
my ($d, $recs) = @_;

# Find sub-domains to exclude records in
my @subdoms;
foreach $sd (&list_domains()) {
	if ($sd->{'dns_submode'} && $sd->{'id'} ne $d->{'id'} &&
	    $sd->{'dom'} =~ /\.\Q$d->{'dom'}\E$/) {
		push(@subdoms, $sd->{'dom'});
		}
	}

my @rv;
RECORD: foreach my $r (@$recs) {
	# Skip sub-domain records
	foreach $sname (@subdoms) {
		next RECORD if ($r->{'name'} eq $sname."." ||
				$r->{'name'} =~ /\.\Q$sname\E\.$/);
		}
	# Skip records not in this domain, such as if we are in
	# a sub-domain
	next if ($r->{'name'} ne $d->{'dom'}."." &&
		 $r->{'name'} !~ /\.$d->{'dom'}\.$/);
	push(@rv, $r);
	}
return \@rv;
}

# filter_generated_dns_records(&domain, &recs)
# Given a domain and a list of DNS records, return only the ones that are not
# generated by Virtualmin
sub filter_generated_dns_records
{
my ($d, $recs) = @_;
my @rv;
foreach my $r (@$recs) {
	next if ($r->{'type'} =~ /^(TLSA|SSHFP)$/);
	push(@rv, $r);
	}
return \@rv;
}

# is_dnssec_record(&record)
sub is_dnssec_record
{
my ($r) = @_;
return $r->{'type'} eq 'NSEC' || $r->{'type'} eq 'NSEC3' ||
       $r->{'type'} eq 'RRSIG' || $r->{'type'} eq 'DNSKEY' ||
       $r->{'type'} eq 'NSEC3PARAM';
}

# get_whois_expiry(&domain)
# Returns the Unix time that a DNS domain is going to expire at it's registrar,
# and an error message.
sub get_whois_expiry
{
my ($d) = @_;
my $whois = &has_command("whois");
return (0, "Missing the <tt>whois</tt> command") if (!$whois);
my $out = &backquote_command($whois." ".quotemeta($d->{'dom'})." 2>/dev/null");
return (0, "No DNS registrar found for domain")
    if ($out =~ /No\s+whois\s+server\s+is\s+known/i);
return (0, "The <tt>whois</tt> command did not report expiry date")
        # google.com, google.fr, google.ru, google.sl
    if ($out !~ /(?|paid-till:|Expir(?:y|ation|es).*?(?:Date|Time|):)\s+(?<year>\d+)\-(?<month>\d+)\-(?<day>\d+).(?<hour>\d+):(?<minute>\d+):(?<second>\d+)(?:(?<utc>(?|[a-z\s])|[+-.][0-9a-z]+))/i &&
        # google.fi
        $out !~ /expires[\.]+:\s+(?<day>\d+)\.(?<month>\d+)\.(?<year>\d+).(?<hour>\d+):(?<minute>\d+):(?<second>\d+)/i &&
        # google.ml
        $out !~ /record.*?expire.*?:\s+(?<month>\d+)\/(?<day>\d+)\/(?<year>\d+)/i &&
        # google.it, google.sk
        $out !~ /(?|Valid\s+Until:|Expir(?:e).*?(?:Date):)\s+(?<year>\d+)\-(?<month>\d+)\-(?<day>\d+)/i &&
        # mit.edu
        $out !~ /(?|Domain\s+expires:)\s+(?<day>\d+)\-(?<month>[a-z]+)\-(?<year>\d+)/i);
my $tm;
my $monther = sub {
    my ($month) = @_;
    my %months = do {
        my $i = 1;
        map {$_ => $i++} (qw( jan feb mar apr may jun jul aug sep oct nov dec ));
        };
    if ($month =~ /[a-z]/i) {
        $month = $months{ lc($month) };
        }
    return $month;
};

eval {
    # Avoid further complexity and assume all time in GMT, as hourly
    # precisions is not important in the end, otherwise it's possible
    # to use `$+{utc}`, which returns either Z, .0Z, +03, +0000 or empty

    # Convert month name to month number (for .edu domains)
    $tm = timegm($+{second}, $+{minute}, $+{hour}, $+{day}, &$monther($+{month})-1, $+{year});
    };
return (0, "Expiry date is not valid") if ($@);
return ($tm);
}

# save_dns_submode(&domain, enabled?, [&old-domain])
# Move this domain into or out of it's parent DNS domain
sub save_dns_submode
{
my ($d, $enabled, $oldd) = @_;
$oldd ||= $d;
if ($d->{'dns_submode'} && $enabled ||
    !$d->{'dns_submode'} && !$enabled) {
	# Nothing to do
	return undef;
	}

# Get the current records
&require_bind();
&obtain_lock_dns($d);
my ($recs, $file) = &get_domain_dns_records_and_file($d);
my @srecs;
my $withdot = $d->{'dom'}.".";
foreach my $r (@$recs) {
	if (($r->{'name'} eq $withdot ||
	     $r->{'name'} =~ /\.$withdot$/) &&
	    $r->{'type'} !~ /SOA|NS/i &&
	    !&is_dnssec_record($r)) {
		push(@srecs, $r);
		}
	}

if ($d->{'dns_submode'} && !$enabled) {
	# Delete the old records, then setup in a new zone file
	&delete_dns($d);
	$d->{'dns_submode'} = 0;
	delete($d->{'dns_subof'});
	&setup_dns($d);
	}
elsif (!$d->{'dns_submode'} && $enabled) {
	# Move into the parent DNS zone file, if allowed
	my $dnsparent = &find_parent_dns_domain($d);
	if (!$dnsparent) {
		&release_lock_dns($d);
		return "No suitable parent DNS domain found";
		}
	&delete_dns($d);
	$d->{'dns_submode'} = 1;
	&setup_dns($d);
	}

# Add all the records that were in the old zone
&pre_records_change($d);
($recs, $file) = &get_domain_dns_records_and_file($d);
foreach my $r (@srecs) {
	my ($a) = grep { $_->{'name'} eq $r->{'name'} &&
			 $_->{'type'} eq $r->{'type'} } @$recs;
	if (!$a) {
		# Add record that was in the sub-domain
		&create_dns_record($recs, $file, $r);
		}
	}
&post_records_change($d, $recs, $file);
&release_lock_dns($d);
&register_post_action(\&restart_bind, $d);
&save_domain($d);
return undef;
}

# find_parent_dns_domain(&domain)
# Find a domain with the same owner that's a candidate as a parent DNS zone
sub find_parent_dns_domain
{
my ($d) = @_;
if ($d->{'parent'}) {
	foreach my $pd (sort { length($b->{'dom'}) cmp length($a->{'dom'}) }
			     (&get_domain_by("parent", $d->{'parent'}),
			      &get_domain($d->{'parent'}))) {
		if ($pd->{'id'} ne $d->{'id'} && !$pd->{'dns_submode'} &&
		    &under_parent_domain($d, $pd)) {
			return $pd;
			}
		}
	}
if ($d->{'dns_subany'} || $config{'dns_secany'}) {
	# Allow any domain to be the DNS parent 
	foreach my $pd (sort { length($b->{'dom'}) cmp length($a->{'dom'}) }
			     &list_domains()) {
		if ($pd->{'id'} ne $d->{'id'} && !$pd->{'dns_submode'} &&
		    &under_parent_domain($d, $pd)) {
			return $pd;
			}
		}
	}
return undef;
}

# dns_ttl_to_seconds(string)
# Convert a string like 1m to a number of seconds
sub dns_ttl_to_seconds
{
my ($ttl) = @_;
$ttl = $1 if ($ttl =~ /^(\d+)s$/);
$ttl = $1*60 if ($ttl =~ /^(\d+)m$/);
$ttl = $1*60*60 if ($ttl =~ /^(\d+)h$/);
$ttl = $1*24*60*60 if ($ttl =~ /^(\d+)d$/);
return int($ttl);
}

# dns_record_key(&rec, [value-too], [leave-spf])
# Returns a single string that represents a record for use in de-duping
sub dns_record_key
{
my ($r, $val, $nospf) = @_;
my @r;
if (defined($r->{'defttl'})) {
	# Default TTL
	@r = ( '$ttl' );
	push(@r, &dns_ttl_to_seconds($r->{'defttl'})) if ($val);
	}
else {
	# Regular record
	my $ttl = &dns_ttl_to_seconds($r->{'ttl'} || 0);
	my $type = $r->{'type'};
	$type = "TXT" if ($type eq "SPF" && !$nospf);
	@r = ($r->{'name'}, $type, $ttl);
	push(@r, join("", @{$r->{'values'}})) if ($val);
	if ($r->{'proxied'}) {
		$r[0] = "proxied_".$r[0];
		}
	}
return join("/", @r);
}

# expand_dns_record(name, &domain)
# If a DNS record name is relative, expand it to the full domain name
sub expand_dns_record
{
my ($name, $d) = @_;
if ($name eq '@') {
	return $d->{'dom'}.'.';
	}
elsif ($name =~ /\.$/) {
	return $name;
	}
else {
	return $name.'.'.$d->{'dom'}.'.';
	}
}

# modify_dns_cloud(&domain, cloud-name|"local"|"services", &remote-server)
# Update the Cloud DNS provider or remote server for a domain, while preserving
# the original records
sub modify_dns_cloud
{
my ($d, $cloud, $server) = @_;
my $oldcloud = $d->{'dns_cloud'} ? $d->{'dns_cloud'} :
	       $d->{'dns_remote'} ? "remote_".$d->{'dns_remote'} :
	       $d->{'provision_dns'} ? 'services' : 'local';
my $newcloud = $server ? "remote_".$server->{'host'}
		       : $cloud;
return undef if ($oldcloud eq $newcloud);

# Is the cloud provider working?
if ($newcloud !~ /^(local|services|remote_.*)$/) {
	my $cfunc = "dnscloud_".$cloud."_check";
	my $err = &$cfunc();
	return $err if ($err);
	my $sfunc = "dnscloud_".$cloud."_get_state";
	my $s = &$sfunc();
	return $s->{'desc'} if (!$s->{'ok'});
	my $tfunc = "dnscloud_".$cloud."_test";
	if (defined(&$tfunc)) {
		my $err = &$tfunc();
		return $err if ($err);
		}
	}

# Get current records, then re-create the DNS config
&push_all_print();
&set_all_capture_print();
$print_output = "";
my @oldrecs = &get_domain_dns_records($d);
my $ok = &delete_dns($d);
if (!$ok) {
	return "Failed to remove existing DNS zone : $print_output";
	}
my $oldcloud = $d->{'dns_cloud'};
delete($d->{'dns_cloud'});
delete($d->{'dns_remote'});
delete($d->{'provision_dns'});
if ($cloud eq "services") {
	$d->{'provision_dns'} = 1;
	}
elsif ($cloud && $cloud ne "local") {
	$d->{'dns_cloud'} = $cloud;
	}
elsif ($server) {
	$d->{'dns_remote'} = $server->{'host'};
	}
$print_output = "";
$ok = &setup_dns($d);
if (!$ok) {
	$d->{'dns_cloud'} = $oldcloud if ($oldcloud);
	return "Failed to setup new DNS zone : $print_output";
	}
&save_domain($d);
&pop_all_print();

# Delete all records that were created by default, and re-create original
# records from before the conversion
&obtain_lock_dns($d);
my ($recs, $file) = &get_domain_dns_records_and_file($d);
return $recs if (!ref($recs));
foreach my $r (reverse(@$recs)) {
	next if ($r->{'type'} eq 'SOA' || $r->{'type'} eq 'NS' ||
		 &is_dnssec_record($r));
	next if (!$r->{'name'} || !$r->{'type'});
	&delete_dns_record($recs, $file, $r);
	}
foreach my $r (@oldrecs) {
	next if ($r->{'type'} eq 'SOA' || $r->{'type'} eq 'NS' ||
		 &is_dnssec_record($r));
	next if (!$r->{'name'} || !$r->{'type'});
	&create_dns_record($recs, $file, $r);
	}
my $err = &post_records_change($d, $recs, $file);
&release_lock_dns($d);
return $err if ($err);
&reload_bind_records($d);
return undef;
}

# list_public_dns_suffixes()
# Returns a full list of known DNS public suffixes
sub list_public_dns_suffixes
{
if (@list_public_dns_suffixes_cache) {
	# Already in RAM
	return @list_public_dns_suffixes_cache;
	}
my @st = stat($public_dns_suffix_cache);
if (!@st || time() - $st[9] > 7*24*60*60) {
	# Attempt to download the suffix file for the first time, or if older
	# than a week
	my ($host, $port, $page,$ssl) = &parse_http_url($public_dns_suffix_url);
	&http_download($host, $port, $page, $public_dns_suffix_cache, \$err,
		       undef, $ssl, undef, undef, 5);
	}
my $f = $public_dns_suffix_cache;
$f = $public_dns_suffix_file if (!-r $f);
my $lref = &read_file_lines($f, 1);
foreach my $l (@$lref) {
	$l =~ s/\/\/.*$//;
	if ($l =~ /\S/) {
		push(@list_public_dns_suffixes_cache, $l);
		}
	}
return @list_public_dns_suffixes_cache;
}

# under_public_dns_suffix(domain)
# If a DNS domain is under a public suffix, return the prefix and suffix.
# Otherwise, return undef.
sub under_public_dns_suffix
{
my ($dname) = @_;
foreach my $sfx (sort { length($b) <=> length($a) }
		      &list_public_dns_suffixes()) {
	if ($sfx =~ /^\*\.(\S+)$/) {
		# Any sub-domain is a valid suffix
		my $ssfx = $1;
		if ($dname =~ /^(\S+)\.([^\.]+)\.\Q$ssfx\E$/) {
			return ($1, $2.".".$sfx);
			}
		}
	else {
		# Regular suffix
		if ($dname =~ /^(\S+)\.\Q$sfx\E$/) {
			return ($1, $sfx);
			}
		}
	}
return ();
}

# lookup_dns_records(name, [type], [external])
# Returns all DNS records matching some name and type,
# using the dig command, or an error string if the lookup 
# failed. Can additionally query external DNS, if set.
sub lookup_dns_records
{
my ($name, $type, $external) = @_;
my ($command, $command_params, $dnslookup, $temp, $err, @recs);
$command = quotemeta(&has_command("dig"));
$command || return "Missing the <tt>dig</tt> command";
$name || return "Missing domain name parameter";
$command_params = ($type ? " ".quotemeta($type) : "")." ".quotemeta($name);
$temp = &transname();
$dnsseccheck = $config{'dns_lookup_server_dnsseccheck'};
$dnslookup = quotemeta($config{'dns_lookup_server'} ||
                       # We need default DNS that returns clear EDE
                       '1.1.1.1');
&execute_command(("$command".' @'.$dnslookup."$command_params"), undef, $temp, \$err);
return $err if ($?);
if ($external) {
	my $ns_search_ok = sub {
		my ($templocal) = @_;
		my (@recsfound, $recfound);
		my $lref = &read_file_lines($templocal, 1);
		$type ||= "";
		foreach my $l (@$lref) {
			if ($l =~ /$name.*?IN.*?$type.*?(\S+)/) {
				my $rfound = "$1";
				$rfound =~ s/\.$//;
				push(@recsfound, $rfound);
				}
			}
		$recfound = join(", ", @recsfound)
		    if (@recsfound);
		return $recfound;
		};

	# If initial request wasn't successful try other DNS servers
	if (!&$ns_search_ok($temp)) {
		# Trying DNS servers which ignore DNSSEC
		# to find existing type of records
		my @nodnssecdnses = (
			# Miami, United States (AT&T Services)
			'12.121.117.201',
			# Oberhausen, Germany (Deutsche Telekom AG)
			'195.243.214.4',
			# Manchester, United Kingdom (M247 Ltd)
			'194.187.251.67',
			# Zaragoza, Spain (Diputacion Provincial de Zaragoza)
			'195.235.225.10',
			# Innsbruck, Austria (nemox.net)
			'83.137.41.9',
			# Zizers, Switzerland (Oskar Emmenegger)
			'194.209.157.109',
		);
		foreach my $dns (@nodnssecdnses) {
			my $tempexternal = &transname();
			my $cmd = ("$command " . "+time=5 +tries=1 @" .quotemeta($dns)."$command_params");
			&execute_command("$cmd", undef, $tempexternal, \$err);
			return $err if ($?);
			my $recmatch = &$ns_search_ok($tempexternal);
			if ($recmatch) {
				my $tempexternaldnssec = &transname();
				&execute_command(("$command +time=5 +tries=1".' @'.$dnslookup."$command_params"), undef, $tempexternaldnssec, \$err);
				return $err if ($?);
				my $dnsstatus;
				my $lref = &read_file_lines($tempexternaldnssec, 1);
				foreach my $l (@$lref) {
					if ($l =~ /.*?HEADER.*?status:\s*([a-zA-Z0-9]+)/) {
						$dnsstatus = "$1";
						}
					if ($l =~ /.*?;.*?(EDE:\s.*)/) {
						$dnsstatus = "$1";
						last;
						}
					}
				my $pform = $recmatch =~ /,/ ? 'were' : 'was';
				return "<tt>@{[&html_escape($recmatch)]}</tt> $pform found, however DNSSEC validation check failed with <tt>@{[&html_escape($dnsstatus)]}</tt> error"
					if (($dnsstatus !~ /NOERROR/i || $dnsstatus =~ /EDE:/i) && $dnsseccheck);
				$temp = $tempexternal;
				last;
				}
			}
		}
	}
&require_bind();
@recs = &bind8::read_zone_file($temp, $name, undef, 0, 1);
return \@recs;
}

# dns_check_record_mismatch(\recs, entry)
# Returns a list of mismatched records that don't belong
# Returns 0 if given entry matches all the records
sub dns_check_record_mismatch
{
my ($recs, $entry) = @_;
my @mismatched;
foreach my $rec (@{$recs}) {
	my (@mismatch) = grep { $_ =~ s/\.$//; $_ !~ /\Q$entry\E/ }
	    @{$rec->{'values'}};
	push(@mismatched, @mismatch);
	}
return \@mismatched if (@mismatched);
return 0;
}

# supports_dns_comments(&domain)
# Returns 1 if the DNS provider for a domain supports comments
sub supports_dns_comments
{
my ($d) = @_;
if ($d->{'dns_submode'}) {
	# Use super-domain cloud provider
	$d = &get_domain($d->{'dns_subof'});
	}
return 1 if ($d->{'provision_dns'} || !$d->{'dns_cloud'});
my ($c) = grep { $_->{'name'} eq $d->{'dns_cloud'} } &list_dns_clouds();
return $c && $c->{'comments'};
}

# supports_dns_defttl(&domain)
# Returns 1 if the DNS provider for a domain supports setting the default TTL
sub supports_dns_defttl
{
my ($d) = @_;
if ($d->{'dns_submode'}) {
	# TTL is per-file
	return 0;
	}
return 1 if ($d->{'provision_dns'} || !$d->{'dns_cloud'});
my ($c) = grep { $_->{'name'} eq $d->{'dns_cloud'} } &list_dns_clouds();
return $c && $c->{'defttl'};
}

# check_reset_dns(&domain)
# Check for non-standard DNS records
sub check_reset_dns
{
my ($d) = @_;
return undef if ($d->{'alias'} && !$d->{'aliasdns'});

# Get the default set of records
my $temp = &transname();
local $bind8::config{'auto_chroot'} = undef;
local $bind8::config{'chroot'} = undef;
local $defrecs = [ ];
&create_standard_records($defrecs, $temp, $d, $d->{'dns_ip'} || $d->{'ip'});

# Compare with the actual records
my $recs = [ &get_domain_dns_records($d) ];
$recs = &filter_domain_dns_records($d, $recs);
return undef if (!@$recs);
my @doomed;
foreach my $r (@$recs) {
	next if (&is_dnssec_record($r));
	next if (!$r->{'name'} || !$r->{'type'});
	my ($dr) = grep { &expand_dns_record($_->{'name'}, $d) eq
			    &expand_dns_record($r->{'name'}, $d) &&
			  ($_->{'type'} eq 'SPF' ? 'TXT' : $_->{'type'}) eq
			    ($r->{'type'} eq 'SPF' ? 'TXT' : $_->{'type'}) }
			@$defrecs;
	if (!$dr) {
		my $n = $r->{'name'};
		$n =~ s/\.\Q$d->{'dom'}\E\.//;
		push(@doomed, "$n ($r->{'type'})");
		}
	}

if (@doomed) {
	return &text('reset_edns', join(", ", @doomed));
	}
return undef;
}

# get_domain_remote_dns([&domain])
# Returns the Webmin server object for a domain's remote DNS server
sub get_domain_remote_dns
{
my ($d) = @_;
if ($d && $d->{'dns_remote'}) {
	my @remotes = defined(&list_remote_dns) ? &list_remote_dns() : ();
	my ($r) = grep { $_->{'host'} eq $d->{'dns_remote'} } @remotes;
	return $r if ($r);
	}
return { 'id' => 0,
	 'host' => &get_system_hostname(),
	 'master' => 1,
	 'this' => 1,
	 'local' => 1,
       };
}

$done_feature_script{'dns'} = 1;

1;

