# Functions for finding which ports users are using

# allowed_domain_server_ports(&domain)
# Returns the list of ports that a parent server and all sub-servers is
# supposed to be using
sub allowed_domain_server_ports
{
my ($d) = @_;
my @rv;

# FPM port
if (&domain_has_website($d)) {
	my $mode = &get_domain_php_mode($d);
	if ($mode eq "fpm") {
		my $port = &get_php_fpm_config_value($d, "listen");
		if ($port =~ /^\d+$/) {
			push(@rv, { 'lport' => $port,
				    'type' => 'fpm' });
			}
		}
	}

# Script ports
foreach my $sinfo (&list_domain_scripts($d)) {
	foreach my $p (split(/\s+/, $sinfo->{'opts'}->{'port'})) {
		push(@rv, { 'lport' => $p,
			    'type' => 'script',
			    'script' => $sinfo->{'type'},
			    'sid' => $sinfo->{'id'} });
		}
	}

# FCGId ports?
# XXX

# Ports belonging to sub-servers
foreach my $pd (&get_domain_by("parent", $d->{'id'})) {
	push(@rv, &allowed_domain_server_ports($pd));
	}
return @rv;
}

# active_domain_server_ports(&domain)
# Returns the list of ports belonging to a domain's user that are in use
sub active_domain_server_ports
{
my ($d) = @_;
return ( ) if (!&foreign_check("proc"));
&foreign_require("proc");
my @rv;
my %umap = map { $_->{'user'}, $_ } &list_domain_users($d, 0, 1, 1, 1);
foreach my $p (&proc::list_processes()) {
	my $u = $umap{$p->{'user'}};
	next if (!$u);
	foreach my $s (&proc::find_process_sockets($p->{'pid'})) {
		next if (!$s->{'listen'});
		if ($s->{'lport'} !~ /^\d+$/) {
			$s->{'lport'} = getservbyname(
				$s->{'lport'}, lc($s->{'proto'}));
			}
		$s->{'user'} = $u;
		$s->{'proc'} = $p;
		push(@rv, $s);
		}
	}
return @rv;
}

1;
