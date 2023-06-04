# Functions for finding and changing proxy balancer blocks
# Like :
# <Proxy balancer://mongrel_cluster>
#     BalancerMember http://127.0.0.1:8000
#     BalancerMember http://127.0.0.1:8001
#     BalancerMember http://127.0.0.1:8002
# </Proxy>
# ProxyPass / balancer://mongrel_cluster/
# or
# ProxyPass / http://127.0.0.1:8000/

# list_proxy_balancers(&domain)
# Returns a list of URL paths and backends for balancer blocks
sub list_proxy_balancers
{
local ($d) = @_;
local $p = &domain_has_website($d);
if ($p && $p ne 'web') {
        return &plugin_call($p, "feature_list_web_balancers", $d);
        }
&require_apache();
local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $d->{'web_port'});
return ( ) if (!$virt);
local @rv;
foreach my $pp (&apache::find_directive("ProxyPass", $vconf)) {
	if ($pp =~ /^(\/\S*)\s+balancer:\/\/([^\/ ]+)/) {
		# Balancer proxy
		push(@rv, { 'path' => $1,
			    'balancer' => $2 });
		}
	elsif ($pp =~ /^(\/\S*)\s+((http|http):\/\/\S+)/) {
		# Single-host proxy
		push(@rv, { 'path' => $1,
			    'urls' => [ $2 ] });
		}
	elsif ($pp =~ /^(\/\S*)\s+\!/) {
		# Proxying disabled for path
		push(@rv, { 'path' => $1,
			    'none' => 1 });
		}
	}
foreach my $proxy (&apache::find_directive_struct("Proxy", $vconf)) {
	if ($proxy->{'value'} =~ /^balancer:\/\/([^\/ ]+)/) {
		local ($rv) = grep { $_->{'balancer'} eq $1 } @rv;
		if ($rv) {
			$rv->{'urls'} = [ &apache::find_directive(
				"BalancerMember", $proxy->{'members'}) ];
			}
		}
	}
return @rv;
}

# create_proxy_balancer(&domain, &balancer)
# Adds the ProxyPass and Proxy directives for a new balancer. Returns an error
# message on failure, undef on success.
sub create_proxy_balancer
{
local ($d, $balancer) = @_;
local $p = &domain_has_website($d);
if ($p && $p ne 'web') {
        return &plugin_call($p, "feature_create_web_balancer", $d, $balancer);
        }
&require_apache();
local $conf = &apache::get_config();
local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $d->{'web_port'});
return "Failed to find Apache config for $d->{'dom'}" if (!$virt);

# Check for clashes
local @pp = &apache::find_directive("ProxyPass", $vconf);
local ($clash) = grep { $_ =~ /^(\/\S*)\s+/ && $1 eq $balancer->{'path'} } @pp;
return "A ProxyPass for $balancer->{'path'} already exists" if ($clash);
if ($balancer->{'balancer'}) {
	local @proxy = &apache::find_directive("Proxy", $vconf);
	local ($clash) = grep { $_ =~ /balancer:\/\/([^\/ ]+)/ &&
				$1 eq $balancer->{'balancer'} } @proxy;
	return "A Proxy block for $balancer->{'balancer'} already exists"
		if ($clash);
	}

# Add the directives
local @ports = ( $d->{'web_port'},
		 $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
foreach my $port (@ports) {
	if ($port != $d->{'web_port'}) {
		($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $port);
		}
	next if (!$virt);
	local $slash = $balancer->{'path'} eq '/' ? '/' : undef;
	local $ssl = 0;
	foreach my $u (@{$balancer->{'urls'}}) {
		$ssl++ if ($u =~ /^https:/i);
		}
	if ($balancer->{'balancer'}) {
		# To multiple URLs
		local $lref = &read_file_lines($virt->{'file'});
		local @pdirs = (map { "BalancerMember $_" } @{$balancer->{'urls'}});
		if (&supports_check_peer_name() && $ssl) {
			push(@pdirs, "SSLProxyCheckPeerName off");
			push(@pdirs, "SSLProxyCheckPeerCN off");
			push(@pdirs, "SSLProxyCheckPeerExpire off");
			}
		splice(@$lref, $virt->{'eline'}, 0,
		   "<Proxy balancer://$balancer->{'balancer'}>",
		   @pdirs,
		   "</Proxy>",
		   "ProxyPass $balancer->{'path'} balancer://$balancer->{'balancer'}$slash",
		   "ProxyPassReverse $balancer->{'path'} balancer://$balancer->{'balancer'}$slash",
		   );
		undef(@apache::get_config_cache);
		}
	else {
		# To just one URL - longest paths must always go first
		local $url = $balancer->{'none'} ? "!" :
				$balancer->{'urls'}->[0];
		if ($path eq "/" && $url ne "!" &&
		    $url =~ /^(http|https):\/\/[a-z0-9\_\-:]+$/i) {
			# If the path is just / and the URL is top-level with
			# no trailing /, add one
			$url .= "/";
			}
		foreach my $dir ("ProxyPass", "ProxyPassReverse") {
			local @pp = &apache::find_directive($dir, $vconf);
			@pp = &sort_proxy_paths(@pp,
				"$balancer->{'path'} $url");
			&apache::save_directive($dir, \@pp, $vconf, $conf);
			}
		}
	&flush_file_lines($virt->{'file'});
	}

# If proxying to SSL, turn on SSLProxyEngine
local $ssl = 0;
foreach my $url (@{$balancer->{'urls'}}) {
	$ssl = 1 if ($url =~ /^https:/i);
	}
if ($ssl) {
	foreach my $port (@ports) {
		local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $port);
		local @spe = &apache::find_directive("SSLProxyEngine", $vconf);
		if (!@spe && lc($spe[0]) ne "on") {
			&apache::save_directive("SSLProxyEngine", [ "on" ],
						$vconf, $conf);
			&flush_file_lines($virt->{'file'});
			}
		}
	}

&register_post_action(\&restart_apache);
return undef;
}

# delete_proxy_balancer(&domain, &balancer)
# Removes the ProxyPass directive and Proxy block for a balancer
sub delete_proxy_balancer
{
local ($d, $balancer) = @_;
local $p = &domain_has_website($d);
if ($p && $p ne 'web') {
        return &plugin_call($p, "feature_delete_web_balancer", $d, $balancer);
        }
&require_apache();
local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $d->{'web_port'});
return "Failed to find Apache config for $d->{'dom'}" if (!$virt);

local @ports = ( $d->{'web_port'},
		 $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
local $done = 0;
foreach my $port (@ports) {
	local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $port);
	next if (!$virt);

	# Find the directives
	local @pp = &apache::find_directive_struct("ProxyPass", $vconf);
	local ($pp) = grep { $_->{'value'} =~ /^(\/\S*)\s+/ &&
			     $1 eq $balancer->{'path'} } @pp;
	local @ppr = &apache::find_directive_struct("ProxyPassReverse", $vconf);
	local ($ppr) = grep { $_->{'value'} =~ /^(\/\S*)\s+/ &&
			     $1 eq $balancer->{'path'} } @ppr;
	local @proxy = &apache::find_directive_struct("Proxy", $vconf);
	local ($proxy) = grep { $_->{'value'} =~ /balancer:\/\/([^\/ ]+)/ &&
				$1 eq $balancer->{'balancer'} } @proxy;

	# Splice them out
	local $lref = &read_file_lines($virt->{'file'});
	foreach my $r (sort { $b->{'line'} <=> $a->{'line'} }
			    grep { $_ } $pp, $ppr, $proxy) {
		splice(@$lref, $r->{'line'},
			       $r->{'eline'} - $r->{'line'} + 1);
		$done++;
		}
	&flush_file_lines($virt->{'file'});
	undef(@apache::get_config_cache);
	}

&register_post_action(\&restart_apache);
return $done ? undef : "No proxy directives for $balancer->{'path'} found";
}

# modify_proxy_balancer(&domain, &balancer, &oldbalancer)
# Updates a balancer block - the name of which cannot change
sub modify_proxy_balancer
{
local ($d, $b, $oldb) = @_;
local $p = &domain_has_website($d);
if ($p && $p ne 'web') {
        return &plugin_call($p, "feature_modify_web_balancer", $d, $b, $oldb);
        }
&require_apache();
local $bn = $b->{'balancer'};
local $conf = &apache::get_config();

local $done = 0;
local @ports = ( $d->{'web_port'},
		 $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
foreach my $port (@ports) {
	local ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $port);
	next if (!$virt);

	# Find and fix the ProxyPass and ProxyPassReverse
	local $slash = $b->{'path'} eq '/' ? '/' : undef;
	foreach my $dir ("ProxyPass", "ProxyPassReverse") {
		local @npp;
		foreach my $pp (&apache::find_directive($dir, $vconf)) {
			local ($dirpath, $dirurl) = split(/\s+/, $pp);
			if ($dirpath eq $oldb->{'path'} &&
			    $dirurl =~ /^(balancer:\/\/\Q$bn\E)/) {
				# Balancer
				$pp = "$b->{'path'} $1$slash";
				$done++;
				}
			elsif ($dirpath eq $oldb->{'path'} &&
			       $dirurl =~ /^((http|https):\/\/)|\!/) {
				# Single URL
				if ($b->{'none'}) {
					$pp = "$b->{'path'} !";
					}
				else {
					$pp = "$b->{'path'} $b->{'urls'}->[0]";
					}
				$done++;
				}
			push(@npp, $pp);
			}
		if ($b->{'path'} ne $oldb->{'path'}) {
			# Re-order so that new longer path is first
			@npp = &sort_proxy_paths(@npp);
			}
		&apache::save_directive($dir, \@npp, $vconf, $conf);
		}

	# Find and fix the URLs in the <Proxy> block
	if ($bn) {
		local ($proxy) = grep
			{ $_->{'value'} =~ /^balancer:\/\/\Q$bn\E/ }
			&apache::find_directive_struct("Proxy", $vconf);
		if ($proxy) {
			&apache::save_directive("BalancerMember", $b->{'urls'},
						$proxy->{'members'}, $conf);
			$done++;
			}
		}
	&flush_file_lines($virt->{'file'});
	}

&register_post_action(\&restart_apache);
return $done ? undef : "No proxy directives for $oldb->{'path'} found";
}

# sort_proxy_paths(path, ...)
# Sorts proxy paths by path length, so that the longest are first
sub sort_proxy_paths
{
return sort { my ($pa, $ua) = split(/\s+/, $a, 2);
	      my ($pb, $ub) = split(/\s+/, $b, 2);
	      return length($pb) <=> length($pa) } @_;
}

1;

