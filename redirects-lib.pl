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

# has_web_host_redirects(&domain)
# Returns 1 if redirect editing by hostname is supported for this domain's
# webserver
sub has_web_host_redirects
{
my ($d) = @_;
return 1 if ($d->{'web'});
my $p = &domain_has_website($d);
return 0 if (!$p);
return &plugin_defined($p, "feature_supports_web_host_redirects") &&
	&plugin_call($p, "feature_supports_web_host_redirects", $d);
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
my $p = &domain_has_website($d);
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
	my ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $p);
	next if (!$virt);
	my $proto = $p == $d->{'web_port'} ? 'http' : 'https';
	foreach my $al (&apache::find_directive_struct("Alias", $vconf),
			&apache::find_directive_struct("AliasMatch", $vconf),
			&apache::find_directive_struct("Redirect", $vconf),
			&apache::find_directive_struct("RedirectMatch", $vconf),
		       ) {
		my $rd = { 'alias' => $al->{'name'} =~ /^Alias/i ? 1 : 0,
			   'dirs' => [ $al ],
			   $proto => 1 };
		my @w = @{$al->{'words'}};
		if (@w == 3) {
			# Has a code
			$rd->{'code'} = shift(@w);
			}
		$rd->{'dest'} = $w[1];
		if ($al->{'name'} eq 'Alias' || $al->{'name'} eq 'Redirect') {
			# Like Redirect /foo /bar
			# or   Alias /foo /home/smeg/public_html/bar
			# or   Redirect /foo http://bar.com/smeg
			$rd->{'path'} = $w[0];
			}
		elsif (($al->{'name'} eq 'AliasMatch' ||
			$al->{'name'} eq 'RedirectMatch') &&
		       ($w[0] =~ /^(.*)\.\*\$$/ ||
			$w[0] =~ /^(.*)\(\.\*\)\$$/)) {
			# Like RedirectMatch /foo(.*)$ /bar
			# or   AliasMatch /foo(.*)$ /home/smeg/public_html/bar
			$rd->{'path'} = $1;
			$rd->{'regexp'} = 1;
			}
		elsif (($al->{'name'} eq 'AliasMatch' ||
			$al->{'name'} eq 'RedirectMatch') &&
		       ($w[0] =~ /^\^(.*)\$$/ ||
			$w[0] =~ /^\^(.*)\$$/)) {
			# Like RedirectMatch ^/foo$ /bar
			# or   Alias ^/foo$ /home/smeg/public_html/bar
			# or   RedirectMatch ^/foo$ http://bar.com/smeg
			$rd->{'path'} = $1;
			$rd->{'exact'} = 1;
			}
		else {
			next;
			}
		$rd->{'id'} = $al->{'name'}."_".$rd->{'path'};

		my ($already) = grep { $_->{'path'} eq $rd->{'path'} } @rv;
		if ($already) {
			$already->{$proto} = 1;
			push(@{$already->{'dirs'}}, @{$rd->{'dirs'}});
			}
		else {
			push(@rv, $rd);
			}
		}

	# Find rewrite rules used for redirects that preserve the hostname.
	# We expect that the config be formatted like :
	# RewriteCond ...
	# RewriteCond ...
	# RewriteRule ...
	my @rws = (&apache::find_directive_struct("RewriteCond", $vconf),
		   &apache::find_directive_struct("RewriteRule", $vconf));
	@rws = sort { $a->{'line'} <=> $b->{'line'} } @rws;
	for(my $i=0; $i<@rws; $i++) {
		next if ($rws[$i]->{'name'} ne 'RewriteCond');
		my $j = $i;
		my $rwr;
		my ($rwc, $rwh);
		while($j < @rws) {
			if ($rws[$j]->{'name'} eq 'RewriteRule') {
				# Found final rule
				$rwr = $rws[$j];
				last;
				}
			if ($rws[$j]->{'words'}->[0] eq '%{HTTPS}') {
				# Found protocol selector condition
				$rwc = $rws[$j];
				}
			if ($rws[$j]->{'words'}->[0] eq '%{HTTP_HOST}') {
				# Found host selector condition
				$rwh = $rws[$j];
				}
			$j++;
			}
		next if (!$rwr || !$rwc && !$rwh);
		next if ($rwr->{'words'}->[2] !~ /^\[R(=\d+)?\]$/);
		my @dirs = ( $rwr );
		push(@dirs, $rwc) if ($rwc);
		push(@dirs, $rwh) if ($rwh);
		my $rd = { 'alias' => 0,
			   'dirs' => \@dirs,
			 };
		if ($rwc) {
			# Has HTTP / HTTPS condition
			if (lc($rwc->{'words'}->[1]) eq 'on') {
				$rd->{'https'} = 1;
				}
			elsif (lc($rwc->{'words'}->[1]) eq 'off') {
				$rd->{'http'} = 1;
				}
			else {
				next;
				}
			}
		else {
			# Protocol comes from port
			$rd->{$proto} = 1;
			}
		if ($rwh) {
			# Has hostname condition
			if ($rwh->{'words'}->[1] =~ /^=(.*)$/) {
				$rd->{'host'} = $1;
				$rd->{'hostregexp'} = 0;
				}
			elsif ($rwh->{'words'}->[1] =~ /\S/) {
				$rd->{'host'} = $rwh->{'words'}->[1];
				$rd->{'hostregexp'} = 1;
				}
			else {
				next;
				}
			}
		$rd->{'path'} = $rwr->{'words'}->[0];
		$rd->{'dest'} = $rwr->{'words'}->[1];
		if ($rd->{'path'} =~ /^(.*)\.\*\$$/ ||
		    $rd->{'path'} =~ /^(.*)\(\.\*\)\$$/) {
			$rd->{'path'} = $1;
			$rd->{'regexp'} = 1;
			}
		elsif ($rd->{'path'} =~ /^\^(.*)\$$/) {
			$rd->{'path'} = $1;
			$rd->{'exact'} = 1;
			}
		if ($rwr->{'words'}->[2] =~ /^\[R=(\d+)\]$/) {
			$rd->{'code'} = $1;
			}
		$rd->{'id'} = $rwc->{'name'}.'_'.$rd->{'path'};
		$rd->{'id'} .= '_'.$rd->{'host'} if ($rd->{'host'});
		my ($already) = grep { $_->{'path'} eq $rd->{'path'} &&
				       $_->{'host'} eq $rd->{'host'} } @rv;
		if ($already) {
			$already->{$proto} = 1;
			push(@{$already->{'dirs'}}, @{$rd->{'dirs'}});
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
if ($redirect->{'dest'} =~ /%\{HTTP_/ &&
    $redirect->{'http'} && $redirect->{'https'}) {
	return "Redirects using HTTP_ variables cannot be applied to both ".
	       "HTTP and HTTPS modes";
	}
if ($redirect->{'host'} && $redirect->{'alias'}) {
	return "Redirects to a directory cannot be limited to a ".
	       "specific hostname";
	}
foreach my $p (@ports) {
	my ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'}, $p);
	my $proto = $p == $d->{'web_port'} ? 'http' : 'https';
	next if (!$redirect->{$proto});
	next if (!$virt);
	if ($redirect->{'dest'} =~ /%\{HTTP_/ || $redirect->{'host'}) {
		# Destination uses variables or matches on a hostname,
		# so RewriteRule is needed
		my @rwes = &apache::find_directive("RewriteEngine", $vconf);
		my @rwcs = &apache::find_directive("RewriteCond", $vconf);
		my @rwrs = &apache::find_directive("RewriteRule", $vconf);
		my $flag = $redirect->{'code'} ? "[R=".$redirect->{'code'}."]"
					       : "[R]";
		if ($redirect->{'host'}) {
			push(@rwcs, "%{HTTP_HOST} ".
			     ($redirect->{'hostregexp'} ? "" : "=").
			     $redirect->{'host'});
			}
		my $path = $redirect->{'path'};
		$path .= "(\.\*)\$" if ($redirect->{'regexp'});
		$path = "^".$path."\$" if ($redirect->{'exact'});
		push(@rwrs, $path." ".$redirect->{'dest'}." ".$flag);
		if (!@rwes) {
			&apache::save_directive(
				"RewriteEngine", ["on"], $vconf, $conf);
			}
		&apache::save_directive("RewriteCond", \@rwcs, $vconf, $conf,1);
		&apache::save_directive("RewriteRule", \@rwrs, $vconf, $conf,1);
		}
	else {
		# Can just use Alias or Redirect
		my $dir = $redirect->{'alias'} ? "Alias" : "Redirect";
		$dir .= "Match" if ($redirect->{'regexp'} ||
				    $redirect->{'exact'});
		my @aliases = &apache::find_directive($dir, $vconf);
		my $path;
		if ($redirect->{'exact'}) {
			$path = "^".$redirect->{'path'}."\$";
			}
		else {
			$path = $redirect->{'path'}.
				($redirect->{'regexp'} ? "(\.\*)\$" : "");
			}
		push(@aliases,
			($redirect->{'code'} && !$redirect->{'alias'} ?
				$redirect->{'code'}." " : "").
			$path." ".$redirect->{'dest'});
		&apache::save_directive($dir, \@aliases, $vconf, $conf);
		}
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
	my $changed = 0;
	if ($redirect->{'dirs'}->[0]->{'name'} =~ /^Rewrite/i) {
		# Remove RewriteCond and RewriteRule
		my @rwcs = &apache::find_directive_struct("RewriteCond",$vconf);
		my @rwrs = &apache::find_directive_struct("RewriteRule",$vconf);
		my @dirlines = map { $_->{'line'} } @{$redirect->{'dirs'}};
		my @newrwcs = map { join(" ", @{$_->{'words'}}) }
		  grep { &indexof($_->{'line'}, @dirlines) < 0 } @rwcs;
		my @newrwrs = map { join(" ", @{$_->{'words'}}) }
		  grep { &indexof($_->{'line'}, @dirlines) < 0 } @rwrs;
		if (@rwcs != @newrwcs || @rwrs != @newrwrs) {
			&apache::save_directive(
				"RewriteCond", \@newrwcs, $vconf, $conf);
			&apache::save_directive(
				"RewriteRule", \@newrwrs, $vconf, $conf);
			$changed++;
			}
		}
	else {
		# Remove a single Alias or Redirect line
		my $dir = $redirect->{'alias'} ? "Alias" : "Redirect";
		$dir .= "Match" if ($redirect->{'regexp'} ||
				    $redirect->{'exact'});
		my @aliases = &apache::find_directive($dir, $vconf);
		my $re = $redirect->{'path'};
		my @newaliases;
		if ($redirect->{'regexp'}) {
			# Handle .*$ or (.*)$ at the end
			@newaliases = grep { !/^(\d+\s+)?\Q$re\E(\.\*|\(\.\*\))\$\s/ } @aliases;
			}
		elsif ($redirect->{'exact'}) {
			# Handle ^ at start and $ at end
			@newaliases = grep { !/^(\d+\s+)?\^\Q$re\E\$\s/ } @aliases;
			}
		else {
			# Match on path only
			@newaliases = grep { !/^(\d+\s+)?\Q$re\E\s/ } @aliases;
			}
		if (scalar(@aliases) != scalar(@newaliases)) {
			&apache::save_directive($dir, \@newaliases, $vconf, $conf);
			$changed++;
			}
		}
	if ($changed) {
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

# add_wellknown_redirect(&redir)
# If a redirect is for everything, modify it to be for a regexp that skips
# .well-known
sub add_wellknown_redirect
{
my ($redir) = @_;
if ($redir->{'path'} eq '/' && !$redir->{'alias'} &&
    !$redir->{'regexp'} && !$redir->{'exact'}) {
	$redir->{'path'} = '^/(?!.well-known)';
	$redir->{'regexp'} = 1;
	}
return $redir;
}

# remove_wellknown_redirect(&redir)
# If a redirect is for everything except .well-known, modify it to be for just /
sub remove_wellknown_redirect
{
my ($redir) = @_;
if (($redir->{'path'} eq '^/(?!.well-known)' ||
     $redir->{'path'} eq '^(?!/.well-known)') &&
    !$redir->{'alias'} && $redir->{'regexp'}) {
	$redir->{'path'} = '/';
	$redir->{'regexp'} = 0;
	}
return $redir;
}

# get_redirect_to_ssl(&domain)
# Returns a default non-SSL to SSL redirect
sub get_redirect_to_ssl
{
my ($d) = @_;
return { 'path' => '^/(?!.well-known)(.*)$',
	 'dest' => 'https://%{HTTP_HOST}/$1',
	 'alias' => 0,
	 'regexp' => 0,
	 'http' => 1,
	 'https' => 0 };
}

# is_webmail_redirect(&domain, &redirect)
# Returns 1 if a redirect is for use by admin sub-domain, 2 if for the webmail
# sub-domain, or 0 otherwise.
sub is_webmail_redirect
{
my ($d, $r) = @_;
return 0 if (!$r->{'host'});
return 1 if ($r->{'host'} =~ /^admin\.\Q$d->{'dom'}\E$/);
return 2 if ($r->{'host'} =~ /^webmail\.\Q$d->{'dom'}\E$/);
return 0;
}

# is_www_redirect(&domain, &redirect)
# Returns 1 if a redirect is from www.domain to domain, 2 if from domain to
# www.domain, 3 if from any sub-domain to domain. and 0 otherwise
sub is_www_redirect
{
my ($d, $r) = @_;
return 0 if (!$r);
return 0 if (!$r->{'host'});
return 0 if ($r->{'path'} ne '/');
foreach my $ad ($d, &get_domain_by("alias", $d->{'id'})) {
	if ($r->{'host'} eq 'www.'.$ad->{'dom'} &&
	    $r->{'dest'} =~ /^(http|https):\/\/\Q$ad->{'dom'}\E\//) {
		return 1;
		}
	if ($r->{'host'} eq $ad->{'dom'} &&
	    $r->{'dest'} =~ /^(http|https):\/\/www\.\Q$ad->{'dom'}\E\//) {
		return 2;
		}
	if ($r->{'host'} eq '[a-z0-9_\-]+.'.$ad->{'dom'} &&
	    $r->{'dest'} =~ /^(http|https):\/\/\Q$ad->{'dom'}\E\//) {
		return 3;
		}
	}
return 0;
}

# get_www_redirect(&domain)
# Returns the objects for a redirect from domain to www.domain, for passing to
# create_redirect
sub get_www_redirect
{
my ($d) = @_;
my @rv;
foreach my $ad ($d, &get_domain_by("alias", $d->{'id'})) {
	push(@rv, { 'path' => '/',
		    'host' => $d->{'dom'},
		    'http' => 1,
		    'https' => 1,
		    'regexp' => 1,
		    'dest' => (&domain_has_ssl($d) ? 'https://' : 'http://').
		   	      'www.'.$d->{'dom'}.'/$1',
	          });
	}
return @rv;
}

# get_non_www_redirect(&domain)
# Returns the objects for a redirect from www.domain to domain, for passing to
# create_redirect
sub get_non_www_redirect
{
my ($d) = @_;
my @rv;
foreach my $ad ($d, &get_domain_by("alias", $d->{'id'})) {
	push(@rv, { 'path' => '/',
		    'host' => 'www.'.$ad->{'dom'},
		    'http' => 1,
		    'https' => 1,
		    'regexp' => 1,
		    'dest' => (&domain_has_ssl($ad) ? 'https://' : 'http://').
			      $ad->{'dom'}.'/$1',
		  });
	}
return @rv;
}

# get_non_canonical_redirect(&domain)
# Returns the objects for a redirect from any sub-domain to domain, for passing
# to create_redirect
sub get_non_canonical_redirect
{
my ($d) = @_;
my @rv;
foreach my $ad ($d, &get_domain_by("alias", $d->{'id'})) {
	push(@rv, { 'path' => '/',
		    'host' => '[a-z0-9_\-]+.'.$ad->{'dom'},
		    'hostregexp' => 1,
		    'http' => 1,
		    'https' => 1,
		    'regexp' => 1,
		    'dest' => (&domain_has_ssl($ad) ? 'https://' : 'http://').
			      $ad->{'dom'}.'/$1',
		  });
	}
return @rv;
}

# get_redirect_by_mode(&domain, mode)
# Returns the redirect objects based on the same mode number returned by
# is_www_redirect
sub get_redirect_by_mode
{
my ($d, $mode) = @_;
return $mode == 1 ? &get_non_www_redirect($d) :
       $mode == 2 ? &get_www_redirect($d) :
       $mode == 3 ? &get_non_canonical_redirect($d) : ( );
}

1;
