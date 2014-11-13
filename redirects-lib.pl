# Functions for finding and editing aliases and redirects for a website

# has_web_redirects(&domain)
# Returns 1 if redirect editing is supported for this domain's webserver
sub has_web_redirects
{
my ($d) = @_;
return 1 if ($d->{'web'});
my $p = &domain_has_website($d);
return 0 if (!$p);
return &plugin_defined($p, "feature_supports_web_redirects") &&
	&plugin_call($p, "feature_supports_web_redirects", $d);
}

# list_redirects(&domain)
# Returns a list of URL paths and destinations for redirects and aliases. Each
# is a hash ref with keys :
#   path - A URL path like /foo
#   dest - Either a URL or a directory
#   alias - Set to 1 for an alias, 0 for a redirect
#   regexp - If set to 1, any sub-path is redirected to the same destination
#   http - Set in the non-SSL virtual host
#   https - Set in the SSL virtual host
sub list_redirects
{
my ($d) = @_;
local $p = &domain_has_website($d);
if ($p && $p ne 'web') {
        my @rv = &plugin_call($p, "feature_list_web_redirects", $d);
	foreach my $r (@rv) {
		if (!$r->{'http'} && !$r->{'https'}) {
			# Deal with plugin that doesn't support protocols
			$r->{'http'} = $r->{'https'} = 1;
			}
		}
	return @rv;
        }
&require_apache();
my @ports = ( $d->{'web_port'},
	      $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
my @rv;
foreach my $p (@ports) {
	local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $p);
	next if (!$virt);
	foreach my $al (&apache::find_directive_struct("Alias", $vconf),
			&apache::find_directive_struct("AliasMatch", $vconf),
			&apache::find_directive_struct("Redirect", $vconf),
			&apache::find_directive_struct("RedirectMatch", $vconf),
		       ) {
		my $proto = $p == $d->{'web_port'} ? 'http' : 'https';
		my $rd = { 'alias' => $al->{'name'} =~ /^Alias/i ? 1 : 0,
			   'dir' => $al,
			   $proto => 1 };
		my @w = @{$al->{'words'}};
		if (@w == 3) {
			# Has a code
			$rd->{'code'} = shift(@w);
			}
		$rd->{'dest'} = $w[1];
		if ($al->{'name'} eq 'Alias' || $al->{'name'} eq 'Redirect') {
			$rd->{'path'} = $w[0];
			}
		elsif (($al->{'name'} eq 'AliasMatch' ||
			$al->{'name'} eq 'RedirectMatch') &&
		       ($w[0] =~ /^(.*)\.\*\$$/ ||
			$w[0] =~ /^(.*)\(\.\*\)\$$/)) {
			$rd->{'path'} = $1;
			$rd->{'regexp'} = 1;
			}
		else {
			next;
			}

		my ($already) = grep { $_->{'path'} eq $rd->{'path'} } @rv;
		if ($already) {
			$already->{$proto} = 1;
			}
		else {
			push(@rv, $rd);
			}
		}
	}
return @rv;
}

# create_redirect(&domain, &redirect)
# Creates a new alias or redirect in some domain
sub create_redirect
{
my ($d, $redirect) = @_;
local $p = &domain_has_website($d);
if ($p && $p ne 'web') {
        return &plugin_call($p, "feature_create_web_redirect", $d, $redirect);
        }
&require_apache();
my @ports = ( $d->{'web_port'},
	      $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
my $count = 0;
foreach my $p (@ports) {
	my ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'}, $p);
	my $proto = $p == $d->{'web_port'} ? 'http' : 'https';
	next if (!$redirect->{$proto});
	next if (!$virt);
	my $dir = $redirect->{'alias'} ? "Alias" : "Redirect";
	$dir .= "Match" if ($redirect->{'regexp'});
	my @aliases = &apache::find_directive($dir, $vconf);
	push(@aliases, $redirect->{'path'}.
			($redirect->{'code'} ? $redirect->{'code'}." " : "").
			($redirect->{'regexp'} ? "(\.\*)\$" : "").
			" ".
			$redirect->{'dest'});
	&apache::save_directive($dir, \@aliases, $vconf, $conf);
	&flush_file_lines($virt->{'file'});
	$count++;
	}
if ($count) {
	&register_post_action(\&restart_apache);
	return undef;
	}
return "No Apache virtualhost found";
}

# delete_redirect(&domain, &redirect)
# Remove some redirect from a domain
sub delete_redirect
{
my ($d, $redirect) = @_;
local $p = &domain_has_website($d);
if ($p && $p ne 'web') {
        return &plugin_call($p, "feature_delete_web_redirect", $d, $redirect);
        }
&require_apache();
my @ports = ( $d->{'web_port'},
              $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
my $count = 0;
foreach my $port (@ports) {
	my ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'}, $port);
	next if (!$virt);
	my $dir = $redirect->{'alias'} ? "Alias" : "Redirect";
        $dir .= "Match" if ($redirect->{'regexp'});
	my @aliases = &apache::find_directive($dir, $vconf);
	my $re = $redirect->{'path'};
	my @newaliases;
	if ($redirect->{'regexp'}) {
		# Handle .*$ or (.*)$ at the end
		@newaliases = grep { !/^\Q$re\E(\.\*|\(\.\*\))\$\s/ } @aliases;
		}
	else {
		# Match on path only
		@newaliases = grep { !/^\Q$re\E\s/ } @aliases;
		}
	if (scalar(@aliases) != scalar(@newaliases)) {
		&apache::save_directive($dir, \@newaliases, $vconf, $conf);
		&flush_file_lines($virt->{'file'});
		$count++;
		}
	}
if ($count) {
	&register_post_action(\&restart_apache);
	return undef;
	}
return "No matching Alias or Redirect found";
}

# modify_redirect(&domain, &redirect, &old-redirect)
# Update some existing website redirect
sub modify_redirect
{
my ($d, $redirect, $oldredirect) = @_;
&delete_redirect($d, $oldredirect);
return &create_redirect($d, $redirect);
}

# get_redirect_root(&domain)
# Returns the allowed base directory for aliases for the current user
sub get_redirect_root
{
my ($d) = @_;
if (&master_admin()) {
	return "/";
	}
elsif ($d->{'parent'}) {
	my $pd = &get_domain($d->{'parent'});
	return &get_redirect_root($pd);
	}
else {
	return $d->{'home'};
	}
}

1;
