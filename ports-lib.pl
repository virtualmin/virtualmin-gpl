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
my %donepid;
@rv = grep { !$donepid{$_->{'proc'}->{'pid'}}++ } @rv;
return @rv;
}

# disallowed_domain_server_ports(&domain)
# Returns active ports that should not be in use
sub disallowed_domain_server_ports
{
my ($d) = @_;
my %canports = map { $_->{'lport'}, $_ } &allowed_domain_server_ports($d);
my @usedports = &active_domain_server_ports($d);
return grep { !$canports{$_->{'lport'}} } @usedports;
}

# kill_disallowed_domain_server_ports(&domain)
# Terminate server processes that shouldn't be running
sub kill_disallowed_domain_server_ports
{
my ($d) = @_;
my @ports = &disallowed_domain_server_ports($d);
return 0 if (!@ports);

# Kill the processes
foreach my $p (@ports) {
	next if ($p->{'proc'}->{'pid'} <= 0);
	next if (!$p->{'proc'}->{'user'} ||
		 $p->{'proc'}->{'user'} eq 'root');
	$p->{'msg'} = "Killing $p->{'proc'}->{'pid'}";
	my $ok = &kill_logged('TERM', $p->{'proc'}->{'pid'});
	my $msg;
	if (!$ok || kill(0, $p->{'proc'}->{'pid'})) {
		# Maybe a KILL is needed?
		sleep(2);
		if (kill(0, $p->{'proc'}->{'pid'})) {
			$ok = &kill_logged('KILL', $p->{'proc'}->{'pid'});
			}
		else {
			# It shut down in the 2 seconds
			$ok = 1;
			}
		}
	if (!$ok) {
		# Kill failed?!
		$msg = &text('kill_failed', "$!");
		}
	elsif (kill(0, $p->{'proc'}->{'pid'})) {
		# Somehow it is still running
		$msg = $text{'kill_still'};
		}
	else {
		# Worked!
		$msg = $text{'kill_done'};
		}
	$p->{'msg'} = $msg;
	}

# Email the master admin, if configured
if ($config{'bw_email'}) {
	$fmt = "%-20.20s %-6.6s %-30.30s %-20.20s\n";
	my $body = $text{'kill_header'}."\n\n";
	$body .= sprintf($fmt, $text{'kill_user'},
			       $text{'kill_port'},
			       $text{'kill_cmd'},
			       $text{'kill_result'});
	$body .= sprintf($fmt, "-" x 20, "-" x 6, "-" x 30, "-" x 20);
	foreach my $p (@ports) {
		$body .= sprintf($fmt, $p->{'user'}->{'user'},
				       $p->{'lport'},
				       $p->{'proc'}->{'args'},
				       $p->{'msg'});
		}
	&foreign_require("mailboxes");
	&mailboxes::send_text_mail(
		&get_global_from_address(),
		$config{'bw_email'},
		undef,
		$text{'kill_subject'},
		$body);
	}
}

1;
