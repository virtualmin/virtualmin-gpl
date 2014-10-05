# Functions for generically handling cloud storage providers

# list_cloud_providers()
# Returns a list of hash refs with details of known providers
sub list_cloud_providers
{
return ( { 'name' => 's3',
	   'desc' => $text{'cloud_s3desc'} },
	 { 'name' => 'rs',
	   'desc' => $text{'cloud_rsdesc'} },
       );
}

sub show_cloud_provider_form
{
}

sub parse_cloud_provider_form
{
}

1;
