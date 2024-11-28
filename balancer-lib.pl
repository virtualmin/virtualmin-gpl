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

# Can the current user create a proxy balancer to a Unix socket?
sub can_balancer_unix
{
return &master_admin();
}

# list_proxy_balancers(&domain)
# Returns a list of URL paths and backends for balancer blocks
sub list_proxy_balancers
{
my ($d) = @_;
my $p = &domain_has_website($d);
if ($p && $p ne 'web') {
        return &plugin_call($p, "feature_list_web_balancers", $d);
        }
&require_apache();
my ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $d->{'web_port'});
return ( ) if (!$virt);
my @rwr = &apache::find_directive("RewriteRule", $vconf);
my @rv;
foreach my $pp (&apache::find_directive("ProxyPass", $vconf)) {
	my $b;
	if ($pp =~ /^(\/\S*)\s+balancer:\/\/([^\/ ]+)/) {
		# Balancer proxy
		$b = { 'path' => $1,
		       'balancer' => $2 };
		}
	elsif ($pp =~ /^(\/\S*)\s+((http|https|ajp|fcgi|scgi):\/\/\S+|unix:(\/\S+)\|\S+:\/\/\S+)$/) {
		# Single-host proxy
		$b = { 'path' => $1,
		       'urls' => [ $2 ] };
		}
	elsif ($pp =~ /^(\/\S*)\s+\!/) {
		# Proxying disabled for path
		$b = { 'path' => $1,
		       'none' => 1 };
		}
	if ($b) {
		my ($rwr) = grep { /^\Q^$b->{'path'}?(.*)\E\s+"ws?s:\/\// } @rwr;
		$b->{'websockets'} = 1 if ($rwr);
		push(@rv, $b);
		}
	}
foreach my $proxy (&apache::find_directive_struct("Proxy", $vconf)) {
	if ($proxy->{'value'} =~ /^balancer:\/\/([^\/ ]+)/) {
		my ($rv) = grep { $_->{'balancer'} eq $1 } @rv;
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
my ($d, $balancer) = @_;
my $p = &domain_has_website($d);
if ($p && $p ne 'web') {
        return &plugin_call($p, "feature_create_web_balancer", $d, $balancer);
        }
&require_apache();
my ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'}, $d->{'web_port'});
return "Failed to find Apache config for $d->{'dom'}" if (!$virt);

# Check for clashes
my @pp = &apache::find_directive("ProxyPass", $vconf);
my ($clash) = grep { $_ =~ /^(\/\S*)\s+/ && $1 eq $balancer->{'path'} } @pp;
return "A ProxyPass for $balancer->{'path'} already exists" if ($clash);
if ($balancer->{'balancer'}) {
	my @proxy = &apache::find_directive("Proxy", $vconf);
	my ($clash) = grep { $_ =~ /balancer:\/\/([^\/ ]+)/ &&
				$1 eq $balancer->{'balancer'} } @proxy;
	return "A Proxy block for $balancer->{'balancer'} already exists"
		if ($clash);
	}

# Add the directives
my @ports = ( $d->{'web_port'},
		 $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
foreach my $port (@ports) {
	if ($port != $d->{'web_port'}) {
		($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $port);
		}
	next if (!$virt);
	my $slash = $balancer->{'path'} eq '/' ? '/' : undef;
	my $ssl = 0;
	foreach my $u (@{$balancer->{'urls'}}) {
		$ssl++ if ($u =~ /^https:/i);
		}
	if ($balancer->{'balancer'}) {
		# To multiple URLs
		my @mems;
		my $pxy = { 'name' => 'Proxy',
			    'type' => 1,
			    'value' => "balancer://$balancer->{'balancer'}",
			    'members' => \@mems };
		foreach my $u (@{$balancer->{'urls'}}) {
			push(@mems, { 'name' => 'BalancerMember',
				      'value' => $u });
			}
		if (&supports_check_peer_name() && $ssl) {
			push(@mems, { 'name' => 'SSLProxyCheckPeerName',
				      'value' => 'off' });
			push(@mems, { 'name' => 'SSLProxyCheckPeerCN',
				      'value' => 'off' });
			push(@mems, { 'name' => 'SSLProxyCheckPeerExpire',
				      'value' => 'off' });
			}
		if ($d->{'ssl'} && $port == $d->{'web_sslport'} &&
		    &indexof('mod_headers', &apache::available_modules()) > 0) {
			push(@mems, { 'name' =>  'RequestHeader',
				      'value' => 'set X-Forwarded-Proto "https" env=HTTPS' });
			}
		&apache::save_directive_struct(undef, $pxy, $vconf, $conf);
		foreach my $dir ("ProxyPass", "ProxyPassReverse") {
			my @pp = &apache::find_directive($dir, $vconf);
			push(@pp, "$balancer->{'path'} balancer://$balancer->{'balancer'}$slash");
			&apache::save_directive($dir, \@pp, $vconf, $conf);
			}
		}
	else {
		# To just one URL - longest paths must always go first
		my $url = $balancer->{'none'} ? "!" :
				$balancer->{'urls'}->[0];
		if ($path eq "/" && $url ne "!" &&
		    $url =~ /^(http|https):\/\/[a-z0-9\_\-:]+$/i) {
			# If the path is just / and the URL is top-level with
			# no trailing /, add one
			$url .= "/";
			}
		foreach my $dir ("ProxyPass", "ProxyPassReverse") {
			my @pp = &apache::find_directive($dir, $vconf);
			@pp = &sort_proxy_paths(@pp,
				"$balancer->{'path'} $url");
			&apache::save_directive($dir, \@pp, $vconf, $conf);
			}
		}
	if ($balancer->{'websockets'} && !$balancer->{'none'}) {
		# Add RewriteCond and RewriteRule for the path
		my $wsurl = $balancer->{'urls'}->[0];
		my $wsprot = $wsurl =~ /^https:/i ? "wss" : "ws";
		$wsurl =~ s/^(http|https):\/\///;
		$wsurl =~ s/\/$//;
		$wsurl = "$wsprot://$wsurl/\$1";
		my @rwc = &apache::find_directive("RewriteCond", $vconf);
		push(@rwc, &websockets_rewriteconds(1));
		&apache::save_directive("RewriteCond", \@rwc, $vconf, $conf, 1);
		my @rwr = &apache::find_directive("RewriteRule", $vconf);
		push(@rwr, "^$balancer->{'path'}?(.*) \"$wsurl\" [P]");
		&apache::save_directive("RewriteRule", \@rwr, $vconf, $conf, 1);
		}
	&flush_file_lines($virt->{'file'});
	}

# If proxying to SSL, turn on SSLProxyEngine
my $ssl = 0;
foreach my $url (@{$balancer->{'urls'}}) {
	$ssl = 1 if ($url =~ /^https:/i);
	}
if ($ssl) {
	foreach my $port (@ports) {
		my ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $port);
		my @spe = &apache::find_directive("SSLProxyEngine", $vconf);
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

# websockets_rewriteconds(add)
# Returns the RewriteCond lines to either remove or add
sub websockets_rewriteconds
{
my ($add) = @_;
my @rv = ("%{HTTP:UPGRADE} ^WebSocket\$ [NC]",
	  "%{HTTP:CONNECTION} Upgrade [NC]");
push(@rv, "%{HTTP:CONNECTION} ^Upgrade\$ [NC]") if (!$add);
return @rv;
}

# delete_proxy_balancer(&domain, &balancer)
# Removes the ProxyPass directive and Proxy block for a balancer
sub delete_proxy_balancer
{
my ($d, $balancer) = @_;
my $p = &domain_has_website($d);
if ($p && $p ne 'web') {
        return &plugin_call($p, "feature_delete_web_balancer", $d, $balancer);
        }
&require_apache();
my ($virt, $vconf) = &get_apache_virtual($d->{'dom'}, $d->{'web_port'});
return "Failed to find Apache config for $d->{'dom'}" if (!$virt);

my @ports = ( $d->{'web_port'},
		 $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
my $done = 0;
foreach my $port (@ports) {
	my ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'}, $port);
	next if (!$virt);

	# Remove regular directives
	foreach my $dir ("ProxyPass", "ProxyPassReverse") {
		my @oldpp = &apache::find_directive($dir, $vconf);
		my @pp = grep { !/^(\/\S*)\s+/ ||
			        $1 ne $balancer->{'path'} } @oldpp;
		$done++ if (@pp != @oldpp);
		&apache::save_directive($dir, \@pp, $vconf, $conf);
		}

	if ($balancer->{'balancer'}) {
		# Remove the Proxy block
		my @proxy = &apache::find_directive_struct("Proxy", $vconf);
		my ($proxy) = grep {
			$_->{'value'} =~ /balancer:\/\/([^\/ ]+)/ &&
			$1 eq $balancer->{'balancer'} } @proxy;
		if ($proxy) {
			&apache::save_directive_struct(
				$proxy, undef, $vconf, $conf);
			$done++;
			}
		}

	# Remove any rewrite directives for websockets
	my @rwc = &apache::find_directive("RewriteCond", $vconf);
	my @rwr = &apache::find_directive("RewriteRule", $vconf);
	my ($rwr) = grep { /^\Q^$balancer->{'path'}?(.*)\E\s+"ws?s:/ } @rwr;
	if ($rwr) {
		# There is one, delete it
		@rwr = grep { $_ ne $rwr } @rwr;
		&apache::save_directive("RewriteRule", \@rwr, $vconf, $conf);
		@rwc = grep { &indexof($_, &websockets_rewriteconds(0)) < 0 } @rwc;
		&apache::save_directive("RewriteCond", \@rwc, $vconf, $conf);
		}

	&flush_file_lines($virt->{'file'});
	}

&register_post_action(\&restart_apache);
return $done ? undef : "No proxy directives for $balancer->{'path'} found";
}

# modify_proxy_balancer(&domain, &balancer, &oldbalancer)
# Updates a balancer block - the name of which cannot change
sub modify_proxy_balancer
{
my ($d, $b, $oldb) = @_;
my $p = &domain_has_website($d);
if ($p && $p ne 'web') {
        return &plugin_call($p, "feature_modify_web_balancer", $d, $b, $oldb);
        }
&require_apache();
my $bn = $b->{'balancer'};

my $done = 0;
my @ports = ( $d->{'web_port'},
		 $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
foreach my $port (@ports) {
	my ($virt, $vconf, $conf) = &get_apache_virtual($d->{'dom'}, $port);
	next if (!$virt);

	# Find and fix the ProxyPass and ProxyPassReverse
	my $slash = $b->{'path'} eq '/' || $b->{'path'} =~ /\/$/ ? '/' : undef;
	foreach my $dir ("ProxyPass", "ProxyPassReverse") {
		my @npp;
		foreach my $pp (&apache::find_directive($dir, $vconf)) {
			my ($dirpath, $dirurl) = split(/\s+/, $pp);
			if ($dirpath eq $oldb->{'path'} &&
			    $dirurl =~ /^(balancer:\/\/\Q$bn\E)/) {
				# Balancer
				$pp = "$b->{'path'} $1$slash";
				$done++;
				}
			elsif ($dirpath eq $oldb->{'path'} &&
			       $dirurl =~ /^((http|https|ajp|fcgi|scgi):\/\/\S+|unix:(\/\S+)\|\S+:\/\/\S+)|\!/) {
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
		my ($proxy) = grep
			{ $_->{'value'} =~ /^balancer:\/\/\Q$bn\E/ }
			&apache::find_directive_struct("Proxy", $vconf);
		if ($proxy) {
			&apache::save_directive("BalancerMember", $b->{'urls'},
						$proxy->{'members'}, $conf);
			$done++;
			}
		}

	# Fix any RewriteRule for websockets
	my @rwc = &apache::find_directive("RewriteCond", $vconf);
	my @rwr = &apache::find_directive("RewriteRule", $vconf);
	my ($rwr) = grep { /^\Q^$oldb->{'path'}?(.*)\E\s+"ws?s:/ } @rwr;
	my $wsurl;
	my $wsprot;
	if (!$b->{'none'} && $b->{'websockets'}) {
		$wsurl = $b->{'urls'}->[0];
		$wsprot = $wsurl =~ /^https:/i ? "wss" : "ws";
		$wsurl =~ s/^(http|https):\/\///;
		$wsurl =~ s/\/$//;
		$wsurl = "$wsprot://$wsurl/\$1";
		}
	if (($b->{'none'} || !$b->{'websockets'}) && $rwr) {
		# Need to remove entirely
		@rwr = grep { $_ ne $rwr } @rwr;
                &apache::save_directive("RewriteRule", \@rwr, $vconf, $conf);
		@rwc = grep { &indexof($_, &websockets_rewriteconds(0)) < 0 } @rwc;
		&apache::save_directive("RewriteCond", \@rwc, $vconf, $conf);
		}
	elsif (!$b->{'none'} && $b->{'websockets'} && $rwr) {
		# Need to update path
		my $idx = &indexof($rwr, @rwr);
		$rwr[$idx] = "^$b->{'path'}?(.*) \"$wsurl\" [P]";
		&apache::save_directive("RewriteRule", \@rwr, $vconf, $conf);
		}
	elsif (!$b->{'none'} && $b->{'websockets'} && !$rwr) {
		# Need to add
		push(@rwc, &websockets_rewriteconds(1));
		&apache::save_directive("RewriteCond", \@rwc, $vconf, $conf, 1);
		push(@rwr, "^$b->{'path'}?(.*) \"$wsurl\" [P]");
		&apache::save_directive("RewriteRule", \@rwr, $vconf, $conf, 1);
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

# get_balancer_usage(&domain, &scripts-used, &plugin-used)
# Fill in two hashes with maps from paths to script into and plugin usage of
# balancers
sub get_balancer_usage
{
my ($d, $used, $pused) = @_;
foreach $sinfo (&list_domain_scripts($d)) {
	$used->{$sinfo->{'opts'}->{'path'}} = $sinfo;
	}
foreach my $p (&list_feature_plugins(1)) {
	if (&plugin_defined($p, "feature_path_desc")) {
		foreach my $pd (&plugin_call($p, "feature_path_desc", $d)) {
			$pd->{'plugin'} = $p;
			$pused->{$pd->{'path'}} = $pd;
			}
		}
	}
}

# allocate_proxy_port([base], [number])
# Finds ports that are not in use by any domain's script
# or server and returns a space-separated list of them
sub allocate_proxy_port
{
my ($base, $ports) = @_;
$base ||= 3000;
my %used;
foreach my $d (&list_domains()) {
	foreach my $ds (&list_domain_scripts($d)) {
		foreach my $p (split(/\s+/, $ds->{'opts'}->{'port'})) {
			$used{$p} = 1;
			}
		}
	}
my @rv;
while(scalar(@rv) < $ports) {
	my $rport = &allocate_free_tcp_port(\%used, $base);
	$rport || &error("Failed to allocate port starting from $base");
	$used{$rport}++;
	push(@rv, $rport);
	}
return join(" ", @rv);
}

# setup_proxy(&domain, path, [port], [proxy-path], [protocol])
# Adds webserver config entries to proxy some path to a local server
sub setup_proxy
{
my ($d, $path, $rport, $ppath, $proto) = @_;
$rport ||= &allocate_proxy_port(undef, 1);
my @ports = split(/\s+/, $rport);
$proto ||= "http";
my $has = &has_proxy_balancer($d);
my $balancer = { 'path' => $path };
if ($has == 2) {
	# Multiple-destination balancer
	$balancer->{'balancer'} = "proxy".$ports[0];
	}
$balancer->{'urls'} = [ map { "$proto://127.0.0.1:$_$ppath" } @ports ];
&create_proxy_balancer($d, $balancer);
}

# delete_proxy(&domain, path)
# Delete the webserver config entries that proxy on some port
sub delete_proxy
{
my ($d, $path) = @_;
my ($balancer) = grep { $_->{'path'} eq $path } &list_proxy_balancers($d);
&delete_proxy_balancer($d, $balancer) if ($balancer);
}

# add_unix_localhost(&balancer)
# If a balancer URL is missing the |http:// suffix, add it
sub add_unix_localhost
{
my ($b) = @_;
foreach my $u (@{$b->{'urls'}}) {
	if ($u =~ /^unix:/ && $u !~ /\|/) {
		# Need to append localhost URL
		$u .= "|http://127.0.0.1";
		}
	}
}

# remove_unix_localhost(&balancer, always-remove-suffix)
# If a balancer URL has the |http://127.0.0.1 suffix, remove it (for display)
sub remove_unix_localhost
{
my ($b, $always) = @_;
foreach my $u (@{$b->{'urls'}}) {
	if ($u =~ /^unix:/) {
		if ($always) {
			$u =~ s/\|.*$//;
			}
		else {
			$u =~ s/\|http:\/\/127.0.0.1\/?//;
			}
		}
	}
}

1;

