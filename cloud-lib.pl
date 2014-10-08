# Functions for generically handling cloud storage providers

# list_cloud_providers()
# Returns a list of hash refs with details of known providers
sub list_cloud_providers
{
return ( { 'name' => 's3',
	   'prefix' => [ 's3', 's3rrs' ],
	   'desc' => $text{'cloud_s3desc'} },
	 { 'name' => 'rs',
	   'prefix' => [ 'rs' ],
	   'desc' => $text{'cloud_rsdesc'} },
       );
}

# backup_uses_cloud(&backup, &provider)
# Checks if any dest of a backup uses this provider
sub backup_uses_cloud
{
my ($backup, $prov) = @_;
my @rv;
foreach my $d (&get_scheduled_backup_dests($backup)) {
	foreach my $p (@{$prov->{'prefix'}}) {
		if ($d =~ /^\Q$p\E:/) {
			push(@rv, $d);
			last;
			}
		}
	}
return wantarray ? @rv : $rv[0];
}

sub cloud_s3_get_state
{
if ($config{'s3_akey'}) {
	return { 'ok' => 1,
		 'desc' => &text('cloud_s3account', $config{'s3_akey'}),
	       };
	}
else {
	return { 'ok' => 0 };
	}
}

sub cloud_rs_get_state
{
if ($config{'rs_user'}) {
	return { 'ok' => 1,
		 'desc' => &text('cloud_rsuser', $config{'rs_user'}),
	       };
	}
else {
	return { 'ok' => 0 };
	}
}

sub cloud_google_get_state
{
}

sub cloud_dropbox_get_state
{
}

1;
