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
		$rd->{'id'} = $al->{'name'}."_".$rd->{'path'};

		my ($already) = grep { $_->{'path'} eq $rd->{'path'} } @rv;
		if ($already) {
			$already->{$proto} = 1;
			}
		else {
			push(@rv, $rd);
			}
		}

	# Find rewrite rules used for redirects that preserve the hostname
	my @rws = (&apache::find_directive_struct("RewriteCond", $vconf),
		   &apache::find_directive_struct("RewriteRule", $vconf));
	@rws = sort { $a->{'line'} <=> $b->{'line'} } @rws;
	for(my $i=0; $i<@rws; $i++) {
		my $rwc = $rws[$i];
		next if ($rwc->{'name'} ne 'RewriteCond');
		my $rwr = $i+1 < @rws ? $rws[$i+1] : undef;
		next if (!$rwr || $rwr->{'name'} ne 'RewriteRule');
		next if ($rwc->{'words'}->[0] ne '%{HTTPS}');
		next if ($rwr->{'words'}->[2] !~ /^\[R(=\d+)?\]$/);
		my $rd = { 'alias' => 0,
			   'dir' => $rwc,
			   'dir2' => $rwr,
			 };
		if (lc($rwc->{'words'}->[1]) eq 'on') {
			$rd->{'https'} = 1;
			}
		elsif (lc($rwc->{'words'}->[1]) eq 'off') {
			$rd->{'http'} = 1;
			}
		else {
			next;
			}
		$rd->{'path'} = $rwr->{'words'}->[0];
		$rd->{'dest'} = $rwr->{'words'}->[1];
		if ($rd->{'path'} =~ /^(.*)\.\*\$$/ ||
		    $rd->{'path'} =~ /^(.*)\(\.\*\)\$$/) {
			$rd->{'path'} = $1;
			$rd->{'regexp'} = 1;
			}
		if ($rwr->{'words'}->[2] =~ /^\[R=(\d+)\]$/) {
			$rd->{'code'} = $1;
			}
		$rd->{'id'} = $rwc->{'name'}.'_'.$rd->{'path'};
		push(@rv, $rd);
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
foreach my $p (@ports) {
	my ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'}, $p);
	my $proto = $p == $d->{'web_port'} ? 'http' : 'https';
	next if (!$redirect->{$proto});
	next if (!$virt);
	if ($redirect->{'dest'} =~ /%\{HTTP_/) {
		# Destination uses variables, so RewriteRule is needed
		my @rwes = &apache::find_directive("RewriteEngine", $vconf);
		my @rwcs = &apache::find_directive("RewriteCond", $vconf);
		my @rwrs = &apache::find_directive("RewriteRule", $vconf);
		my $flag = $redirect->{'code'} ? "[R=".$redirect->{'code'}."]"
					       : "[R]";
		push(@rwcs, "%{HTTPS} ".($proto eq 'http' ? 'off' : 'on'));
		my $path = $redirect->{'path'};
		$path .= "(\.\*)\$" if ($redirect->{'regexp'});
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
		$dir .= "Match" if ($redirect->{'regexp'});
		my @aliases = &apache::find_directive($dir, $vconf);
		push(@aliases, ($redirect->{'code'} ? $redirect->{'code'}." " : "").
			       $redirect->{'path'}.
			       ($redirect->{'regexp'} ? "(\.\*)\$" : "").
			       " ".$redirect->{'dest'});
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
	if ($redirect->{'dir2'}) {
		# Remove RewriteCond and RewriteRule
		my @rwcs = &apache::find_directive_struct("RewriteCond",$vconf);
		my @rwrs = &apache::find_directive_struct("RewriteRule",$vconf);
		my @newrwcs = map { join(" ", @{$_->{'words'}}) }
		  grep { $_->{'line'} != $redirect->{'dir'}->{'line'} } @rwcs;
		my @newrwrs = map { join(" ", @{$_->{'words'}}) }
		  grep { $_->{'line'} != $redirect->{'dir2'}->{'line'} } @rwrs;
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
		$dir .= "Match" if ($redirect->{'regexp'});
		my @aliases = &apache::find_directive($dir, $vconf);
		my $re = $redirect->{'path'};
		my @newaliases;
		if ($redirect->{'regexp'}) {
			# Handle .*$ or (.*)$ at the end
			@newaliases = grep { !/^(\d+\s+)?\Q$re\E(\.\*|\(\.\*\))\$\s/ } @aliases;
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
if ($redir->{'path'} eq '/' && !$redir->{'alias'} && !$redir->{'regexp'}) {
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
if ($redir->{'path'} eq '^/(?!.well-known)' && !$redir->{'alias'} && $redir->{'regexp'}) {
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

1;
