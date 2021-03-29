# Functions for DNS cloud providers

# list_dns_clouds()
# Returns a list of supported cloud DNS providers
sub list_dns_clouds
{
return ( { 'name' => 'route53',
	   'desc' => 'Amazon Route 53',
	   'url' => 'https://aws.amazon.com/route53/' },
       );
}

# default_dns_cloud()
# Returns the DNS cloud provider used by default for new domains
sub default_dns_cloud
{
my $tmpl = &get_template(0);
return undef if (!$tmpl->{'dns_cloud'} || $tmpl->{'dns_cloud'} eq 'local' ||
		 $tmpl->{'dns_cloud'} eq 'services');
my ($cloud) = grep { $_->{'name'} eq $tmpl->{'dns_cloud'} }
		   &list_dns_clouds();
return $cloud;
}

# dns_uses_cloud(&domain, &cloud)
# Checks if DNS for some domain is setup on this provider
sub dns_uses_cloud
{
my ($d, $c) = @_;
return $d->{'dns'} && $d->{'dns_cloud'} eq $c->{'name'};
}

# dnscloud_route53_check()
# Returns an error message if any requirements for Route 53 are missing
sub dnscloud_route53_check
{
return $text{'dnscloud_eaws'} if (!$config{'aws_cmd'} ||
				  !&has_command($config{'aws_cmd'}));
eval "use JSON::PP";
return &text('dnscloud_eperl', 'JSON::PP') if ($@);
return undef;
}

# dnscloud_route53_get_state(&cloud)
# Returns a status object indicating if this provider is setup or not
sub dnscloud_route53_get_state
{
if ($config{'route53_akey'}) {
	return { 'ok' => 1,
		 'desc' => &text('dnscloud_53account',
                                 "<tt>$config{'route53_akey'}</tt>"),
	       };
	}
return { 'ok' => 0 };
}

# dnscloud_route53_show_inputs()
# Show fields for selecting 
sub dnscloud_route53_show_inputs
{
my $rv;

# AWS login
$rv .= &ui_table_row($text{'cloud_s3_access'},
	&ui_textbox("route53_akey", $config{'route53_akey'}, 50));
$rv .= &ui_table_row($text{'cloud_s3_secret'},
	&ui_textbox("route53_skey", $config{'route53_skey'}, 50));

# Default location for zones
$rv .= &ui_table_row($text{'dnscloud_route53_location'},
	&ui_select("route53_location", $config{'route53_location'},
		   [ &s3_list_locations() ]));

return $rv;
}

# dnscloud_route53_parse_inputs(&in)
# Parse inputs from dnscloud_route53_show_inputs
sub dnscloud_route53_parse_inputs
{
my ($in) = @_;

# Parse default login
if ($in->{'route53_akey_def'}) {
	delete($config{'route53_akey'});
	delete($config{'route53_skey'});
	}
else {
	$in->{'route53_akey'} =~ /^\S+$/ || &error($text{'backup_eakey'});
	$in->{'route53_skey'} =~ /^\S+$/ || &error($text{'backup_eskey'});
	$config{'route53_akey'} = $in->{'route53_akey'};
	$config{'route53_skey'} = $in->{'route53_skey'};
	}

# Parse new bucket location
$config{'route53_location'} = $in->{'route53_location'};

# Validate that they work
&can_use_aws_cmd($in->{'route53_akey'}, $in->{'route53_skey'},
	 $in->{'route53_location'}) || &error($text{'dnscloud_eawscreds'});

&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);

return undef;
}

# dnscloud_route53_clear()
# Reset the S3 account to the default
sub dnscloud_route53_clear
{
delete($config{'route53_akey'});
delete($config{'route53_skey'});
&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);
}

# dnscloud_route53_create_domain(&domain, &info)
# Create a new DNS zone with amazon's route53
sub dnscloud_route53_create_domain
{
my ($d, $info) = @_;
my $ref = &generate_route53_ref();
my $location = $info->{'location'} || $config{'route53_location'};
my $rv = &call_route53_cmd(
	[ 'create-hosted-zone',
	  '--name', $info->{'domain'}, '--caller-reference', $ref ],
	undef, 1);
return (0, $rv) if (!ref($rv));
$info->{'id'} = $rv->{'HostedZone'}->{'Id'};
$info->{'location'} = $location;
my ($ok, $err) = &dnscloud_route53_put_records($d, $info);
return (1, $rv->{'HostedZone'}->{'Id'}, $location);
}

# dnscloud_route53_delete_domain(&domain, &info)
# Delete a DNS zone on amazon's route53
sub dnscloud_route53_delete_domain
{
my ($d, $info) = @_;

# Delete records first
my $rinfo = { %$info };
$rinfo->{'recs'} = [ ];
my ($ok, $err) = &dnscloud_route53_put_records($d, $rinfo);
return (0, $err) if (!$ok);

my $rv = &call_route53_cmd(
	[ 'delete-hosted-zone',
	  '--id', $info->{'id'} ],
	$info->{'location'}, 1);
return ref($rv) ? (1, $rv) : (0, $rv);
}

# dnscloud_route53_disable_domain(&domain, &info)
# Disable a DNS zone on amazon's route53, by renaming it
sub dnscloud_route53_disable_domain
{
my ($d, $info) = @_;
my $rninfo = { 'id' => $info->{'id'},
	       'location' => $info->{'location'},
	       'olddomain' => $info->{'domain'},
	       'domain' => $info->{'domain'}.'.disabled' };
return &dnscloud_route53_rename_domain($d, $rninfo);
}

# dnscloud_route53_enable_domain(&domain, &info)
# Enable a DNS zone on amazon's route53, by renaming it back
sub dnscloud_route53_enable_domain
{
my ($d, $info) = @_;
my $rninfo = { 'id' => $info->{'id'},
	       'location' => $info->{'location'},
	       'domain' => $info->{'domain'},
	       'olddomain' => $info->{'domain'}.'.disabled' };
return &dnscloud_route53_rename_domain($d, $rninfo);
}

# dnscloud_route53_check_domain(&domain, &info)
# Returns 1 if a domain already exists on route53, under the configured account
sub dnscloud_route53_check_domain
{
my ($d, $info) = @_;
my $rv = &call_route53_cmd(
	[ 'list-hosted-zones' ],
	undef, 1);
return 0 if (!ref($rv));
foreach my $h (@{$rv->{'HostedZones'}}) {
	if ($h->{'name'} eq $info->{'domain'}.".") {
		return 1;
		}
	}
return 0;
}

# dnscloud_route53_rename_domain(&domain, &info)
# Rename a domain on route53 by deleting and re-creating it
sub dnscloud_route53_rename_domain
{
my ($d, $info) = @_;

# Get current records, and fix them
my ($ok, $recs) = &dnscloud_route53_get_records($d, $info);
return (0, $recs) if (!$ok);
&modify_records_domain_name(
	$recs, undef, $info->{'olddomain'}, $info->{'domain'});

# Delete the old domain
my ($ok, $err) = &dnscloud_route53_delete_domain($d, $info);
return (0, $err) if (!$ok);

# Create the new one with the original records
$info->{'recs'} = $recs;
my ($ok, $err) = &dnscloud_route53_create_domain($d, $info);
return ($ok, $err);
}

# dnscloud_route53_get_records(&domain, &info)
# Returns records for a domain in Webmin's format
sub dnscloud_route53_get_records
{
my ($d, $info) = @_;
my $rv = &call_route53_cmd(
	[ 'list-resource-record-sets',
	  '--hosted-zone-id', $info->{'id'} ],
	$info->{'location'}, 1);
return (0, $rv) if (!ref($rv));
my @recs;
foreach my $rrs (@{$rv->{'ResourceRecordSets'}}) {
	foreach my $rr (@{$rrs->{'ResourceRecords'}}) {
		$rr->{'Value'} =~ s/^"(.*)"$/$1/
			if ($rrs->{'Type'} =~ /TXT|SPF/);
		push(@recs, { 'name' => $rrs->{'Name'},
			      'realname' => $rrs->{'Name'},
			      'class' => 'IN',
			      'type' => $rrs->{'Type'},
			      'ttl' => int($rrs->{'TTL'}),
			      'values' => [ split(/\s+/, $rr->{'Value'}) ] });
		}
	}
return (1, \@recs);
}

# dnscloud_route53_put_records(&domain, &info)
# Updates records for a domain in Webmin's format
sub dnscloud_route53_put_records
{
my ($d, $info) = @_;
my $recs = $info->{'recs'};
my ($ok, $oldrecs) = &dnscloud_route53_get_records($d, $info);
return ($ok, $oldrecs) if (!$ok);

# Create an op to delete all existing records (apart from NS and SOA) and 
# re-add the new ones
my $js = { 'Changes' => [] };
my %keep = map { $_->{'name'}."/".$_->{'type'}, 1 } @$recs;
foreach my $r (@$oldrecs) {
	next if ($r->{'type'} eq 'NS' || $r->{'type'} eq 'SOA');
	next if ($keep{$r->{'name'}."/".$r->{'type'}});
	my $v = join(" ", @{$r->{'values'}});
	$v = "\"$v\"" if ($r->{'type'} =~ /TXT|SPF/);
	push(@{$js->{'Changes'}},
	     { 'Action' => 'DELETE',
	       'ResourceRecordSet' => {
	         'Name' => $r->{'name'},
		 'Type' => $r->{'type'},
		 'TTL' => int($r->{'ttl'}),
		 'ResourceRecords' => [
		   { 'Value' => $v },
		 ]
	       }
	     });
	}
foreach my $r (@$recs) {
	next if ($r->{'type'} eq 'NS');
	next if (!$r->{'name'} || !$r->{'type'});	# $ttl or similar
	my $v = join(" ", @{$r->{'values'}});
	$v = "\"$v\"" if ($r->{'type'} =~ /TXT|SPF/);
	push(@{$js->{'Changes'}},
	     { 'Action' => 'UPSERT',
	       'ResourceRecordSet' => {
	         'Name' => $r->{'name'},
		 'Type' => $r->{'type'},
		 'TTL' => int($r->{'ttl'} || 86400),
		 'ResourceRecords' => [
		   { 'Value' => $v },
		 ]
	       }
	     });
	}
if (!@{$js->{'Changes'}}) {
	# Nothing to do!
	return (1, undef);
	}

# Write the JSON to a temp file for calling the API
my $temp = &transname();
eval "use JSON::PP";
my $coder = JSON::PP->new->pretty;
&open_tempfile(JSON, ">$temp");
&print_tempfile(JSON, $coder->encode($js));
&close_tempfile(JSON);
my $rv = &call_route53_cmd(
	[ 'change-resource-record-sets',
	  '--hosted-zone-id', $info->{'id'},
	  '--change-batch', 'file://'.$temp ],
	$info->{'location'}, 1);
return ref($rv) ? (1, $rv) : (0, $rv);
}

# call_route53_cmd(akey, params, [region], [parse-json])
# Run the aws command for route53 with some params, and return output
sub call_route53_cmd
{
my ($params, $region, $json) = @_;
my $akey = $config{'route53_akey'};
$region ||= $config{'route53_location'};
if (ref($params)) {
	$params = join(" ", map { quotemeta($_) } @$params);
	}
my $out = &backquote_command(
	"TZ=GMT $config{'aws_cmd'} route53 --profile=".quotemeta($akey)." ".
	"--region ".quotemeta($region)." ".$params." 2>&1");
if (!$? && $json) {
	eval "use JSON::PP";
	my $coder = JSON::PP->new->pretty;
	eval {
		$out = $coder->decode($out);
		};
	}
return $out;
}

sub generate_route53_ref
{
return time().$$.(++$generate_route53_ref_count);
}




