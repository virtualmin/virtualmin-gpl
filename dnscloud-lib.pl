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
