# Functions for DNS cloud providers

sub list_dns_clouds
{
return ( { 'name' => 'route53',
	   'desc' => 'Amazon Route 53',
	   'url' => 'https://aws.amazon.com/route53/' },
       );
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
		 $in->{'route53_location'}) || &error($text{'dnscloud_eaws'});

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



