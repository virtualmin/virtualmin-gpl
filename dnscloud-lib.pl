# Functions for DNS cloud providers

# list_dns_clouds()
# Returns a list of supported cloud DNS providers
sub list_dns_clouds
{
my @rv = ( { 'name' => 'route53',
	     'desc' => 'Amazon Route 53',
	     'comments' => 0,
	     'defttl' => 0,
	     'proxy' => 0,
	     'disable' => 0,
	     'import' => 0,
	     'url' => 'https://aws.amazon.com/route53/',
	     'longdesc' => $text{'dnscloud_route53_longdesc'} } );
if (defined(&list_pro_dns_clouds)) {
	push(@rv, &list_pro_dns_clouds());
	}
return @rv;
}

# can_dns_cloud(&cloud)
# Returns 1 if some clopud can be used
sub can_dns_cloud
{
my ($c) = @_;
if (&master_admin()) {
	return 1;
	}
if (&reseller_admin()) {
	return $config{'dnscloud_'.$c->{'name'}.'_reseller'} ? 1 : 0;
	}
return $config{'dnscloud_'.$c->{'name'}.'_owner'} ? 1 : 0;
}

# default_dns_cloud([&template])
# Returns the DNS cloud provider used by default for new domains
sub default_dns_cloud
{
my ($tmpl) = @_;
$tmpl ||= &get_template(0);
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

# get_domain_dns_cloud(&domain)
# Returns the cloud provider hash for a domain
sub get_domain_dns_cloud
{
my ($d) = @_;
if ($d->{'dns_subof'}) {
	return &get_domain_dns_cloud(&get_domain($d->{'dns_subof'}));
	}
foreach my $c (&list_dns_clouds()) {
	return $c if (&dns_uses_cloud($d, $c));
	}
return undef;
}

# dnscloud_route53_check()
# Returns an error message if any requirements for Route 53 are missing
sub dnscloud_route53_check
{
return $text{'dnscloud_eaws'} if (!&has_aws_cmd());
eval "use JSON::PP";
return &text('dnscloud_eperl', 'JSON::PP') if ($@);
return undef;
}

# dnscloud_route53_get_state()
# Returns a status object indicating if this provider is setup or not
sub dnscloud_route53_get_state
{
if ($config{'route53_akey'}) {
	return { 'ok' => 1,
		 'desc' => &text('dnscloud_53account',
                                 "<tt>$config{'route53_akey'}</tt>"),
	       };
	}
elsif (&can_use_aws_s3_creds()) {
        return { 'ok' => 1,
                 'desc' => $text{'cloud_s3creds'},
               };
        }
else {
	return { 'ok' => 0 };
	}
}

# dnscloud_route53_test()
# Returns an error message if route53 API calls fail, or undef if OK
sub dnscloud_route53_test
{
my $rv = &call_route53_cmd(
	$config{'route53_akey'},
	[ 'list-hosted-zones' ],
	undef, 1);
return ref($rv) ? undef : $rv;
}

# dnscloud_route53_show_inputs()
# Show fields for entering credentials for AWS
sub dnscloud_route53_show_inputs
{
my $rv;

# AWS login
if (!$config{'route53_akey'} && &can_use_aws_route53_creds()) {
	$rv .= &ui_table_row($text{'cloud_s3_access'},
		"<i>$text{'cloud_s3_creds'}</i>");
	}
else {
	$rv .= &ui_table_row($text{'cloud_s3_access'},
		&ui_textbox("route53_akey", $config{'route53_akey'}, 50));
	$rv .= &ui_table_row($text{'cloud_s3_secret'},
		&ui_textbox("route53_skey", $config{'route53_skey'}, 50));
	}

# Default location for zones
my @locs = &s3_list_aws_locations();
if (&get_ec2_aws_region()) {
	unshift(@locs, [ "", $text{'dnscloud_route53_def'} ]);
	}
$rv .= &ui_table_row($text{'dnscloud_route53_location'},
	&ui_select("route53_location", $config{'route53_location'}, \@locs));

return $rv;
}

# dnscloud_route53_parse_inputs(&in)
# Parse inputs from dnscloud_route53_show_inputs
sub dnscloud_route53_parse_inputs
{
my ($in) = @_;

# Parse default login
if ($config{'route53_akey'} || !&can_use_aws_route53_creds()) {
	if ($in->{'route53_akey_def'}) {
		delete($config{'route53_akey'});
		delete($config{'route53_skey'});
		}
	else {
		$in->{'route53_akey'} =~ /^\S+$/ ||
			&error($text{'backup_eakey'});
		$in->{'route53_skey'} =~ /^\S+$/ ||
			&error($text{'backup_eskey'});
		$config{'route53_akey'} = $in->{'route53_akey'};
		$config{'route53_skey'} = $in->{'route53_skey'};
		}
	}

# Parse new bucket location
$in->{'route53_location'} || &get_ec2_aws_region() ||
	&error($text{'dnscloud_eawsregion'});
$config{'route53_location'} = $in->{'route53_location'};

# Validate that they work
delete($can_use_aws_cmd_cache{$in->{'route53_akey'}});
my ($ok, $err) = &can_use_aws_route53_cmd(
    $in->{'route53_akey'}, $in->{'route53_skey'}, $in->{'route53_location'});
$ok || &error(&text('dnscloud_eawscreds', $err));

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

# Does it already exist?
my $rv = &call_route53_cmd(
	$config{'route53_akey'},
	[ 'list-hosted-zones' ], undef, 1);
my $already;
foreach my $z (@{$rv->{'HostedZones'}}) {
	if ($z->{'Name'} eq $info->{'domain'}.".") {
		$already = $z;
		}
	}
if ($already) {
	# Yes .. just take it over but leave the records
	$info->{'id'} = $already>{'Id'};
	$info->{'location'} = $location;
	return (1, $already->{'Id'}, $location);
	}

my $rv = &call_route53_cmd(
	$config{'route53_akey'},
	[ 'create-hosted-zone',
	  '--name', $info->{'domain'}, '--caller-reference', $ref ],
	undef, 1);
return (0, $rv) if (!ref($rv));
$info->{'id'} = $rv->{'HostedZone'}->{'Id'};
$info->{'location'} = $location;
my ($ok, $err) = &dnscloud_route53_put_records($d, $info, 1);
return (2, $rv->{'HostedZone'}->{'Id'}, $location, "Failed to create records : $err") if (!$ok);
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
	$config{'route53_akey'},
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
	$config{'route53_akey'},
	[ 'list-hosted-zones' ],
	undef, 1);
return 0 if (!ref($rv));
foreach my $h (@{$rv->{'HostedZones'}}) {
	if ($h->{'Name'} eq $info->{'domain'}.".") {
		return 1;
		}
	}
return 0;
}

# dnscloud_route53_valid_domain(&domain, &info)
# Returns an error message if a domain cannot be hosted by Route53
sub dnscloud_route53_valid_domain
{
my ($d, $info) = @_;
return undef;
}

# dnscloud_route53_rename_domain(&domain, &info)
# Rename a domain on route53 by deleting and re-creating it. Returns an ok flag,
# either an error message or the name domain ID.
sub dnscloud_route53_rename_domain
{
my ($d, $info) = @_;

# Check for a clash
my $exists = &dnscloud_route53_check_domain($d, $info);
return (0, "New domain name $info->{'domain'} already exists on Route53")
	if ($exists);

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
my ($ok, $err, $location) = &dnscloud_route53_create_domain($d, $info);
return ($ok, $err, $location);
}

# dnscloud_route53_get_records(&domain, &info)
# Returns records for a domain in Webmin's format
sub dnscloud_route53_get_records
{
my ($d, $info) = @_;
my $rv = &call_route53_cmd(
	$config{'route53_akey'},
	[ 'list-resource-record-sets',
	  '--hosted-zone-id', $info->{'id'} ],
	$info->{'location'}, 1);
return (0, $rv) if (!ref($rv));
my @recs;
foreach my $rrs (@{$rv->{'ResourceRecordSets'}}) {
	foreach my $rr (@{$rrs->{'ResourceRecords'}}) {
		push(@recs, { 'name' => $rrs->{'Name'},
			      'realname' => $rrs->{'Name'},
			      'class' => 'IN',
			      'type' => $rrs->{'Type'},
			      'ttl' => int($rrs->{'TTL'}),
			      'values' => [ &split_quoted_string($rr->{'Value'}) ] });
		}
	}
return (1, \@recs);
}

# dnscloud_route53_put_records(&domain, &info, [ignore-fail])
# Updates records for a domain in Webmin's format
sub dnscloud_route53_put_records
{
my ($d, $info, $ignore) = @_;
my $recs = $info->{'recs'};
my ($ok, $oldrecs) = &dnscloud_route53_get_records($d, $info);
return ($ok, $oldrecs) if (!$ok);

# Create an op to delete all existing records (apart from NS and SOA) and 
# re-add the new ones
my $js = { 'Changes' => [] };
my %keep = map { &dns_record_key($_), 1 } @$recs;
foreach my $r (@$oldrecs) {
	next if ($r->{'type'} eq 'NS' || $r->{'type'} eq 'SOA');
	next if ($keep{&dns_record_key($r)});
	my $v = join(" ", @{$r->{'values'}});
	$v = &normalize_route53_txt($r) if ($r->{'type'} =~ /TXT|SPF/);
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
	next if ($r->{'type'} eq 'NS' || $r->{'type'} eq 'SOA');
	next if (!$r->{'name'} || !$r->{'type'});	# $ttl or similar
	my $v = join(" ", @{$r->{'values'}});
	$type = $r->{'type'};
	$type = "TXT" if ($type eq "SPF" || $type eq "DMARC");
	$v = &normalize_route53_txt($r) if ($type eq "TXT");
	push(@{$js->{'Changes'}},
	     { 'Action' => 'UPSERT',
	       'ResourceRecordSet' => {
	         'Name' => $r->{'name'},
		 'Type' => $type,
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
	$config{'route53_akey'},
	[ 'change-resource-record-sets',
	  '--hosted-zone-id', $info->{'id'},
	  '--change-batch', 'file://'.$temp ],
	$info->{'location'}, 1);
return ref($rv) ? (1, $rv) : (0, $rv);
}

sub normalize_route53_txt
{
my ($r) = @_;
my $v = &split_long_txt_record("\"".join("", @{$r->{'values'}})."\"");
$v =~ s/^\(\s*//;
$v =~ s/\s*\)$//;
$v =~ s/[\n\t]+/ /g;
return $v;
}

# call_route53_cmd(akey, params, [region], [parse-json])
# Run the aws command for route53 with some params, and return output
sub call_route53_cmd
{
my ($akey, $params, $region, $json) = @_;
$region ||= $config{'route53_location'};
$region ||= &get_ec2_aws_region();
$params ||= [];
unshift(@$params, "--region", $region);
my $out = &call_aws_cmd($akey, "route53", $params, undef);
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

# can_use_aws_route53_cmd(akey, skey, region)
# Returns 1 if the aws command can be used to access route53 with the given
# credentials and region
sub can_use_aws_route53_cmd
{
my ($akey, $skey, $region) = @_;
return &can_use_aws_cmd($akey, $skey, $zone, \&call_route53_cmd, [ "list-hosted-zones" ], $region);
}

# can_use_aws_route53_creds()
# Returns 1 if the AWS command can be used with local credentials, such as on
# an EC2 instance with IAM
sub can_use_aws_route53_creds
{
return 0 if (!&has_aws_cmd());
my $region = &get_ec2_aws_region() || "us-east1";
my $ok = &can_use_aws_cmd(undef, undef, undef, \&call_route53_cmd, [ "list-hosted-zones" ], $region);
return 0 if (!$ok);
return &has_aws_ec2_creds() ? 1 : 0;
}

1;
