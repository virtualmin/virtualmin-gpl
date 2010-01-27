# Functions for finding and editing aliases and redirects for a website

# list_redirects(&domain)
# Returns a list of URL paths and destinations for redirects and aliases. Each
# is a hash ref with keys :
#   path - A URL path like /foo
#   dest - Either a URL or a directory
#   alias - Set to 1 for an alias, 0 for a redirect
#   regexp - If set to 1, any sub-path is redirected to the same destination
sub list_redirects
{
my ($d) = @_;
&require_apache();
local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $d->{'web_port'});
return ( ) if (!$virt);
my @rv;

# Find and add aliases
foreach my $al (&apache::find_directive_struct("Alias", $vconf),
		&apache::find_directive_struct("AliasMatch", $vconf)) {
	my $rd = { 'path' => $al->{'words'}->[0],
		   'alias' => 1,
		   'dir' => $al };
	if ($al->{'name'} eq 'Alias') {
		$rd->{'dest'} = $al->{'words'}->[1];
		push(@rv, $rd);
		}
	elsif ($al->{'name'} eq 'AliasMatch' &&
	       $al->{'words'}->[1] =~ /^(.*)\.\*\$$/) {
		$rd->{'dest'} = $1;
		$rd->{'regexp'} = 1;
		push(@rv, $rd);
		}
	}

# Find and add redirects
# XXX

return @rv;
}

# create_redirect(&domain, &redirect)
# XXX
sub create_redirect
{
}

sub delete_redirect
{
}

sub modify_redirect
{
}

1;
