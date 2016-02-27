# Functions for collecting general system info

# collect_system_info()
# Returns a hash reference containing system information
sub collect_system_info
{
&foreign_require("system-status");
local $info = &system_status::get_collected_info();

# Memory may come from a custom command
if ($config{'mem_cmd'}) {
	# Get from custom command
	local $out = &backquote_command($config{'mem_cmd'});
	local @lines = split(/\r?\n/, $out);
	$info->{'mem'} = [ map { $_/1024 } @lines ];
	}

# Available Virtualmin package updates
if (&foreign_check("security-updates")) {
	&foreign_require("security-updates");
	local @poss = &security_updates::list_possible_updates(2);
	local %doneposs;
	@poss = grep { !$doneposs{$_->{'name'},$_->{'version'}}++ } @poss;
	$info->{'poss'} = \@poss;
	if (!$config{'collect_noall'}) {
		local @allposs = &security_updates::list_possible_updates(2, 1);
		local %doneposs;
		@allposs = grep { !$doneposs{$_->{'name'},$_->{'version'}}++ } @allposs;
		$info->{'allposs'} = \@allposs;
		}
	}

# System status
$info->{'startstop'} = [ &get_startstop_links() ];

# Counts for domains
local $dusers = &count_domain_users();
local $daliases = &count_domain_aliases(1);
local @doms = &list_domains();
local %fcount = map { $_, 0 } @features;
$fcount{'doms'} = 0;
foreach my $d (@doms) {
	$fcount{'doms'}++;
	foreach my $f (@features) {
		$fcount{$f}++ if ($d->{$f});
		}
	my @dbs = &domain_databases($d);
	$fcount{'dbs'} += scalar(@dbs);
	$fcount{'users'} += $dusers->{$d->{'id'}};
	$fcount{'aliases'} += $daliases->{$d->{'id'}};
	}
$info->{'fcount'} = \%fcount;
$info->{'ftypes'} = [ "doms", "dns", "web", "ssl", "mail", "dbs",
		      "users", "aliases" ];
local (%fmax, %fextra, %fhide);
foreach my $f (@{$info->{'ftypes'}}) {
	local ($extra, $reason, $max, $hide) =
		&count_feature($f);
	$fmax{$f} = $max;
	$fextra{$f} = $extra;
	$fhide{$f} = $hide;
	}
$info->{'fmax'} = \%fmax;
$info->{'fextra'} = \%fextra;
$info->{'fhide'} = \%fhide;

# Quota use for domains
if (&has_home_quotas()) {
	local @quota;
	local $homesize = &quota_bsize("home");
	local $mailsize = &quota_bsize("mail");
	local $maxquota = 0;

	# Work out quotas
	foreach my $d (@doms) {
		# If this is a parent domain, sum up quotas
		if (!$d->{'parent'}) {
			local ($home, $mail, $dbusage, $quota);
			if ($config{'show_uquotas'} == 0) {
				# Domain group quotas
				($home, $mail, $dbusage) =
					&get_domain_quota($d, 1);
				$quota = $d->{'quota'};
				}
			else {
				# Just the domain owner
				local $duser = &get_domain_owner($d, 1, 0, 1);
				$home = $duser->{'uquota'};
				$mail = $duser->{'umquota'};
				$dbusage = 0;
				$quota = $duser->{'quota'} + $duser->{'mquota'};
				}
			local $usage = $home*$homesize +
				       $mail*$mailsize;
			$maxquota = $usage+$dbusage
				if ($usage+$dbusage > $maxquota);
			local $limit = $quota * $homesize;
			$maxquota = $limit if ($limit > $maxquota);
			push(@quota, [ $d, $usage, $limit, $dbusage ]);
			}
		}
	$info->{'quota'} = \@quota;
	$info->{'maxquota'} = $maxquota;
	}

# IP addresses used
local (%ipcount, %ipdom);
foreach my $d (@doms) {
	next if ($d->{'alias'});
	$ipcount{$d->{'ip'}}++;
	$ipdom{$d->{'ip'}} ||= $d;
	if ($d->{'ip6'}) {
		$ipcount{$d->{'ip6'}}++;
		$ipdom{$d->{'ip6'}} ||= $d;
		}
	}
local %doneip;
if (keys %ipdom > 1) {
	local $defip = &get_default_ip();
	local $defip6 = &get_default_ip6();
	if (defined(&list_resellers)) {
		foreach my $r (&list_resellers()) {
			if ($r->{'acl'}->{'defip'}) {
				$reselip{
				  $r->{'acl'}->{'defip'}} = $r;
				}
			}
		}
	if (defined(&list_shared_ips)) {
		foreach my $ip (&list_shared_ips()) {
			$sharedip{$ip}++;
			}
		}
	if (defined(&list_shared_ip6s)) {
		foreach my $ip6 (&list_shared_ip6s()) {
			$sharedip{$ip6}++;
			}
		}
	local @ips;
	foreach my $ip ($defip,
		     (sort { $a cmp $b } keys %reselip),
		     (sort { $a cmp $b } keys %ipcount)) {
		next if ($doneip{$ip}++);
		push(@ips, [ $ip, $ip eq $defip ? ('def', undef) :
				  $ip eq $defip6 ? ('def', undef) :
			          $reselip{$ip} ? ('reseller',
						   $reselip{$ip}->{'name'}) :
			          $sharedip{$ip} ? ('shared', undef) :
						   ('virt', undef),
			     $ipcount{$ip}, $ipdom{$ip}->{'dom'} ]);
		}
	$info->{'ips'} = [ grep { &check_ipaddress($_->[0]) } @ips ];
	$info->{'ips6'} = [ grep { &check_ip6address($_->[0]) } @ips ];
	}

# IP ranges available
local $tmpl = &get_template(0);
local @ranges = split(/\s+/, $tmpl->{'ranges'});
local @ipranges;
local %taken = &interface_ip_addresses();
foreach my $r (@ranges) {
	$r =~ /^(\d+\.\d+\.\d+)\.(\d+)\-(\d+)$/ || next;
        local ($base, $s, $e) = ($1, $2, $3);
	local ($ipcount, $usedcount) = (0, 0);
	for(my $j=$s; $j<=$e; $j++) {
		local $try = "$base.$j";
		if ($doneip{$try} || $taken{$try}) {
			$usedcount++;
			}
		$ipcount++;
		}
	push(@ipranges, [ $r, $ipcount, $usedcount ]);
	}
if (@ipranges) {
	$info->{'ipranges'} = \@ipranges;
	}

# Program information
local @progs;
foreach my $f ("virtualmin", @features) {
	if ($config{$f} || $f eq "virtualmin") {
		local $ifunc = "sysinfo_$f";
		if (defined(&$ifunc)) {
			push(@progs, &$ifunc());
			}
		}
	}
$info->{'progs'} = \@progs;

return $info;
}

# get_collected_info()
# Returns the most recently collected system information, or the current info
sub get_collected_info
{
local $infostr = $config{'collect_interval'} eq 'none' ? undef :
			&read_file_contents($collected_info_file);
if ($infostr) {
	local $info = &unserialise_variable($infostr);
	if (ref($info) eq 'HASH' && keys(%$info) > 0) {
		return $info;
		}
	}
return &collect_system_info();
}

# save_collected_info(&info)
# Save information collected on schedule
sub save_collected_info
{
local ($info) = @_;
&open_tempfile(INFO, ">$collected_info_file");
&print_tempfile(INFO, &serialise_variable($info));
&close_tempfile(INFO);
}

# refresh_startstop_status()
# Refresh regularly collected info on status of services
sub refresh_startstop_status
{
local $info = &get_collected_info();
$info->{'startstop'} = [ &get_startstop_links() ];
&save_collected_info($info);
}

# refresh_possible_packages(&newpackages)
# Refresh regularly collected info on available packages
sub refresh_possible_packages
{
local ($pkgs) = @_;
local %pkgs = map { $_, 1 } @$pkgs;
local $info = &get_collected_info();
if ($info->{'poss'} && &foreign_check("security-updates")) {
	&foreign_require("security-updates");
	local @poss = &security_updates::list_possible_updates(1);
	$info->{'poss'} = \@poss;
	local @allposs = &security_updates::list_possible_updates(1, 1);
	$info->{'allposs'} = \@allposs;
	}
&save_collected_info($info);
}

# add_historic_collected_info(&info, time)
# Add to the collected info log files the current CPU load, memory uses, swap
# use, disk use and other info we might want to graph
sub add_historic_collected_info
{
local ($info, $time) = @_;
if (!-d $historic_info_dir) {
	&make_dir($historic_info_dir, 0700);
	}
local @stats;
push(@stats, [ "load", $info->{'load'}->[0] ]) if ($info->{'load'});
push(@stats, [ "load5", $info->{'load'}->[1] ]) if ($info->{'load'});
push(@stats, [ "load15", $info->{'load'}->[2] ]) if ($info->{'load'});
push(@stats, [ "procs", $info->{'procs'} ]) if ($info->{'procs'});
if ($info->{'mem'}) {
	push(@stats, [ "memused",
		       ($info->{'mem'}->[0]-$info->{'mem'}->[1])*1024 ]);
	push(@stats, [ "memtotal",
		       $info->{'mem'}->[0]*1024 ]);
	if ($info->{'mem'}->[2]) {
		push(@stats, [ "swapused",
			      ($info->{'mem'}->[2]-$info->{'mem'}->[3])*1024 ]);
		push(@stats, [ "swaptotal",
			       $info->{'mem'}->[2]*1024 ]);
		}
	if ($info->{'mem'}->[4] ne '') {
		push(@stats, [ "memcached",
			       $info->{'mem'}->[4]*1024 ]);
		}
	if ($info->{'mem'}->[5] ne '') {
		push(@stats, [ "memburst",
			       $info->{'mem'}->[5]*1024 ]);
		}
	}
if ($info->{'disk_total'}) {
	push(@stats, [ "diskused",
		       $info->{'disk_total'}-$info->{'disk_free'},
		       $info->{'disk_total'} ]);
	}
push(@stats, [ "doms", $info->{'fcount'}->{'doms'} ]);
push(@stats, [ "users", $info->{'fcount'}->{'users'} ]);
push(@stats, [ "aliases", $info->{'fcount'}->{'aliases'} ]);
local $qlimit = 0;
local $qused = 0;
foreach my $q (@{$info->{'quota'}}) {
	$qlimit += $q->[2];
	$qused += $q->[1]+$q->[3];
	}
push(@stats, [ "quotalimit", $qlimit ]);
push(@stats, [ "quotaused", $qused ]);

# Get messages processed by procmail since the last collection time
local $now = time();
my $hasprocmail = &mail_system_has_procmail();
if (-r $procmail_log_file && $hasprocmail) {
	# Get last seek position
	local $lastinfo = &read_file_contents("$historic_info_dir/procmailpos");
	local @st = stat($procmail_log_file);
	local ($lastpos, $lastinode, $lasttime);
	if (defined($lastinfo)) {
		($lastpos, $lastinode, $lasttime) = split(/\s+/, $lastinfo);
		}
	else {
		# For the first run, start at the end of the file
		$lastpos = $st[7];
		$lastinode = $st[1];
		$lasttime = time();
		}

	open(PROCMAILLOG, $procmail_log_file);
	if ($st[1] == $lastinode && $lastpos) {
		seek(PROCMAILLOG, $lastpos, 0);
		}
	else {
		$lastpos = 0;
		}
	local ($mailcount, $spamcount, $viruscount) = (0, 0, 0);
	while(<PROCMAILLOG>) {
		$lastpos += length($_);
		s/\r|\n//g;
		local %log = map { split(/:/, $_, 2) } split(/\s+/, $_);
		if ($log{'User'}) {
			$mailcount++;
			if ($log{'Mode'} eq 'Spam') {
				$spamcount++;
				}
			elsif ($log{'Mode'} eq 'Virus') {
				$viruscount++;
				}
			}
		}
	close(PROCMAILLOG);
	local $mins = ($now - $lasttime) / 60.0;
	push(@stats, [ "mailcount", $mins ? $mailcount / $mins : 0 ]);
	push(@stats, [ "spamcount", $mins ? $spamcount / $mins : 0 ]);
	push(@stats, [ "viruscount", $mins ? $viruscount / $mins : 0 ]);

	# Save last seek
	&open_tempfile(PROCMAILPOS, ">$historic_info_dir/procmailpos");
	&print_tempfile(PROCMAILPOS, $lastpos," ",$st[1]," ",$now."\n");
	&close_tempfile(PROCMAILPOS);
	}

# Read mail server log to count messages since the last run
local $mail_log_file = $config{'bw_maillog'};
$mail_log_file = &get_mail_log() if ($mail_log_file eq "auto");
if ($mail_log_file) {
	# Get last seek position
	local ($spamcount, $mailcount) = (0, 0);
	local $lastinfo = &read_file_contents("$historic_info_dir/maillogpos");
	local @st = stat($mail_log_file);
	local ($lastpos, $lastinode, $lasttime);
	if (defined($lastinfo)) {
		($lastpos, $lastinode, $lasttime) = split(/\s+/, $lastinfo);
		}
	else {
		# For the first run, start at the end of the file
		$lastpos = $st[7];
		$lastinode = $st[1];
		$lasttime = time();
		}

	# Read the log, finding number of messages recived, bounced and
	# greylisted
	local ($recvcount, $bouncecount, $greycount, $ratecount) = (0, 0, 0);
	open(MAILLOG, $mail_log_file);
	if ($st[1] == $lastinode && $lastpos) {
		seek(MAILLOG, $lastpos, 0);
		}
	else {
		$lastpos = 0;
		}
	while(<MAILLOG>) {
		if (/^(\S+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\S+)\s+(\S+):\s+(\S+):\s+from=(\S+),\s+size=(\d+)/) {
			# Sendmail or postfix from= line for a new message
			$recvcount++;
			}
		elsif (/^(\S+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\S+)\s+(\S+):\s+(\S+):\s+<(\S+)>\.*\s*(.*)/i) {
			# Sendmail bounce message
			$recvcount++;
			$bouncecount++;
			}
		elsif (/^(\S+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\S+)\s+(\S+):\s+(NOQUEUE):\s+(\S+):.*from=(\S+)\s+to=(\S+)/) {
			# Postfix bounce message
			$recvcount++;
			if (/Greylisted/) {
				$greycount++;
				}
			else {
				$bouncecount++;
				}
			}
		elsif (/^(\S+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\S+).*ratelimit overflow for class/) {
			# Rate limiting message
			$ratecount++;
			}
		elsif (/^(\S+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\S+).*spam:\s*identified\s+spam/ && !$hasprocmail) {
			# Classified as spam when procmail delivery isn't used
			$spamcount++;
			$mailcount++;
			}
		elsif (/^(\S+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\S+).*spam:\s*clean\s+message/ && !$hasprocmail) {
			# Deliverted normally when procmail delivery isn't used
			$mailcount++;
			}
		}
	$lastpos = tell(MAILLOG);
	close(MAILLOG);
	if ($lastpos <= 0) {
		$lastpos = $st[7];
		}
	local $mins = ($now - $lasttime) / 60.0;
	push(@stats, [ "recvcount", $mins ? $recvcount / $mins : 0 ]);
	push(@stats, [ "bouncecount", $mins ? $bouncecount / $mins : 0 ]);
	if ($greycount || !&check_postgrey()) {
		push(@stats, [ "greycount", $mins ? $greycount / $mins : 0 ]);
		}
	if ($ratecount) {
		push(@stats, [ "ratecount", $mins ? $ratecount / $mins : 0 ]);
		}
	if ($spamcount) {
		push(@stats, [ "spamcount", $mins ? $spamcount / $mins : 0 ]);
		}
	if ($mailcount) {
		push(@stats, [ "mailcount", $mins ? $mailcount / $mins : 0 ]);
		}

	# Save last seek
	&open_tempfile(MAILPOS, ">$historic_info_dir/maillogpos");
	&print_tempfile(MAILPOS, $lastpos," ",$st[1]," ",$now."\n");
	&close_tempfile(MAILPOS);
	}

# Get network traffic counts since last run
if (&foreign_check("net") && $gconfig{'os_type'} =~ /-linux$/) {
	# Get the current byte count
	local $rxtotal = 0;
	local $txtotal = 0;
	if ($config{'collect_ifaces'}) {
		# From module config
		@ifaces = split(/\s+/, $config{'collect_ifaces'});
		}
	else {
		# Get list from net module
		&foreign_require("net");
		if (defined(&net::active_interfaces)) {
			foreach my $i (&net::active_interfaces()) {
				if ($i->{'virtual'} eq '' &&
				    $i->{'name'} =~ /^(eth|em|eno|ens|enp|enx|ppp|wlan|ath|wlan)/) {
					push(@ifaces, $i->{'name'});
					}
				}
			}
		else {
			# Not available on this OS?
			@ifaces = ( "eth0" );
			}
		}
	@ifaces = &unique(@ifaces);
	local $ifaces = join(" ", @ifaces);
	if (&has_command("ifconfig")) {
		# Get traffic from old ifconfig command
		foreach my $iname (@ifaces) {
			local $out = &backquote_command(
				"LC_ALL='' LANG='' ifconfig ".
				quotemeta($iname)." 2>/dev/null");
			local $rx = $out =~ /RX\s+bytes:\s*(\d+)/i ? $1 : undef;
			local $tx = $out =~ /TX\s+bytes:\s*(\d+)/i ? $1 : undef;
			$rxtotal += $rx;
			$txtotal += $tx;
			}
		}
	else {
		# Get traffic from /proc/net/dev
		local $out = &read_file_contents("/proc/net/dev");
		foreach my $l (split(/\r?\n/, $out)) {
			$l =~ s/^\s+//;
			my @w = split(/[ \t:]+/, $l);
			if (&indexof($w[0], @ifaces) >= 0) {
				$rxtotal += $w[1];
				$txtotal += $w[9];
				}
			}
		}

	# Work out the diff since the last run, if we have it
	local %netcounts;
	if (&read_file("$historic_info_dir/netcounts", \%netcounts) &&
	    $netcounts{'rx'} && $netcounts{'tx'} &&
	    $netcounts{'ifaces'} eq $ifaces &&
	    $rxtotal >= $netcounts{'rx'} && $txtotal >= $netcounts{'tx'}) {
		local $secs = ($now - $netcounts{'now'}) * 1.0;
		local $rxscaled = ($rxtotal - $netcounts{'rx'}) / $secs;
		local $txscaled = ($txtotal - $netcounts{'tx'}) / $secs;
		if ($rxscaled >= $netcounts{'rx_max'}) {
			$netcounts{'rx_max'} = $rxscaled;
			}
		if ($txscaled >= $netcounts{'tx_max'}) {
			$netcounts{'tx_max'} = $txscaled;
			}
		push(@stats, [ "rx", $rxscaled, $netcounts{'rx_max'} ]);
		push(@stats, [ "tx", $txscaled, $netcounts{'tx_max'} ]);
		}

	# Save the last counts
	$netcounts{'rx'} = $rxtotal;
	$netcounts{'tx'} = $txtotal;
	$netcounts{'now'} = $now;
	$netcounts{'ifaces'} = $ifaces;
	&write_file("$historic_info_dir/netcounts", \%netcounts);
	}

# Get drive temperatures
local ($temptotal, $tempcount);
foreach my $t (@{$info->{'drivetemps'}}) {
	$temptotal += $t->{'temp'};
	$tempcount++;
	}
if ($temptotal) {
	push(@stats, [ "drivetemp", $temptotal / $tempcount ]);
	}

# Get CPU temperature
local ($temptotal, $tempcount);
foreach my $t (@{$info->{'cputemps'}}) {
	$temptotal += $t->{'temp'};
	$tempcount++;
	}
if ($temptotal) {
	push(@stats, [ "cputemp", $temptotal / $tempcount ]);
	}

# Get IO blocks
if ($info->{'io'}) {
	push(@stats, [ "bin", $info->{'io'}->[0] ]);
	push(@stats, [ "bout", $info->{'io'}->[1] ]);
	}

# Get CPU user and IO time
if ($info->{'cpu'}) {
	push(@stats, [ "cpuuser", $info->{'cpu'}->[0] ]);
	push(@stats, [ "cpukernel", $info->{'cpu'}->[1] ]);
	push(@stats, [ "cpuidle", $info->{'cpu'}->[2] ]);
	push(@stats, [ "cpuio", $info->{'cpu'}->[3] ]);
	}

# Write to the file
foreach my $stat (@stats) {
	open(HISTORY, ">>$historic_info_dir/$stat->[0]");
	print HISTORY $time," ",$stat->[1],"\n";
	close(HISTORY);
	}

# Update the file storing the max possible value for each variable
local %maxpossible;
&read_file("$historic_info_dir/maxes", \%maxpossible);
foreach my $stat (@stats) {
	if ($stat->[2] && $stat->[2] > $maxpossible{$stat->[0]}) {
		$maxpossible{$stat->[0]} = $stat->[2];
		}
	}
&write_file("$historic_info_dir/maxes", \%maxpossible);
}

# list_historic_collected_info(stat, [start], [end])
# Returns an array of times and values for some stat, within the given
# time period
sub list_historic_collected_info
{
local ($stat, $start, $end) = @_;
local @rv;
local $last_time;
local $now = time();
open(HISTORY, "$historic_info_dir/$stat");
while(<HISTORY>) {
	chop;
	local ($time, $value) = split(" ", $_);
	next if ($time < $last_time ||	# No time travel or future data
		 $time > $now);
	if ((!defined($start) || $time >= $start) &&
	    (!defined($end) || $time <= $end)) {
		push(@rv, [ $time, $value ]);
		}
	if (defined($end) && $time > $end) {
		last;	# Past the end point
		}
	$last_time = $time;
	}
close(HISTORY);
return @rv;
}

# list_all_historic_collected_info([start], [end])
# Returns a hash mapping stats to data within some time period
sub list_all_historic_collected_info
{
local ($start, $end) = @_;
foreach my $f (&list_historic_stats()) {
	local @rv = &list_historic_collected_info($f, $start, $end);
	$all{$f} = \@rv;
	}
closedir(HISTDIR);
return \%all;
}

# get_historic_maxes()
# Returns a hash reference from stats to the max possible values ever seen
sub get_historic_maxes
{
local %maxpossible;
&read_file("$historic_info_dir/maxes", \%maxpossible);
return \%maxpossible;
}

# get_historic_first_last(stat)
# Returns the Unix time for the first and last stats recorded
sub get_historic_first_last
{
local ($stat) = @_;
open(HISTORY, "$historic_info_dir/$stat") || return (undef, undef);
local $first = <HISTORY>;
$first || return (undef, undef);
chop($first);
local ($firsttime, $firstvalue) = split(" ", $first);
seek(HISTORY, 2, -256) || seek(HISTORY, 0, 0);
while(<HISTORY>) {
	$last = $_;
	}
close(HISTORY);
chop($last);
local ($lasttime, $lastvalue) = split(" ", $last);
return ($firsttime, $lasttime);
}

# list_historic_stats()
# Returns a list of variables on which we have stats
sub list_historic_stats
{
local @rv;
opendir(HISTDIR, $historic_info_dir);
foreach my $f (readdir(HISTDIR)) {
	if ($f =~ /^[a-z]+[0-9]*$/ && $f ne "maxes" && $f ne "procmailpos" &&
	    $f ne "netcounts" && $f ne "maillogpos") {
		push(@rv, $f);
		}
	}
closedir(HISTDIR);
return @rv;
}

# setup_collectinfo_job()
# Creates or updates the collectinfo.pl cron job, based on the schedule
# set in the module config.
sub setup_collectinfo_job
{
# Work out correct steps
local $step = $config{'collect_interval'};
$step = 5 if (!$step || $step eq 'none');
$step = 60 if ($step > 60);
local $offset = int(rand()*$step);
local @mins;
for(my $i=$offset; $i<60; $i+= $step) {
	push(@mins, $i);
	}
local $job = &find_cron_script($collect_cron_cmd);
if (!$job && $config{'collect_interval'} ne 'none') {
	# Create, and run for the first time
	$job = { 'mins' => join(',', @mins),
		 'hours' => '*',
		 'days' => '*',
		 'months' => '*',
		 'weekdays' => '*',
		 'user' => 'root',
		 'active' => 1,
		 'command' => $collect_cron_cmd };
	&setup_cron_script($job);
	}
elsif ($job && $config{'collect_interval'} ne 'none') {
	# Update existing job, if step has changed
	local @oldmins = split(/,/, $job->{'mins'});
	local $oldstep = $oldmins[0] eq '*' ? 1 :
			 @oldmins == 1 ? 60 :
			 $oldmins[1]-$oldmins[0];
	if ($step != $oldstep) {
		$job->{'mins'} = join(',', @mins);
		&setup_cron_script($job);
		}
	}
elsif ($job && $config{'collect_interval'} eq 'none') {
	# No longer wanted, so delete
	&delete_cron_script($job->{'command'});
	}
}

# restart_collected_services(&info)
# If any services are detected as down, try to restart them. Re-check the status
# afterwards, and update the info hash.
sub restart_collected_services
{
local ($info) = @_;
my $count = 0;
foreach my $ss (@{$info->{'startstop'}}) {
	if (!$ss->{'status'}) {
		# Down .. need to restart
		my $err;
		if (&indexof($ss->{'feature'}, @plugins) < 0) {
			# Core feature
			my $sfunc = "start_service_".$ss->{'feature'};
			$err = &$sfunc();
			}
		else {
			# From plugin
			$err = &plugin_call($ss->{'feature'},
					    "feature_start_service");
			}
		$count++;
		}
	}
if ($count) {
	$info->{'startstop'} = [ &get_startstop_links() ];
	}
return $count;
}

# get_current_drive_temps()
# Returns a list of hashes, containing device and temp keys
sub get_current_drive_temps
{
local @rv;
if (!$config{'collect_notemp'} && $virtualmin_pro &&
    &foreign_installed("smart-status")) {
	&foreign_require("smart-status");
	foreach my $d (&smart_status::list_smart_disks_partitions()) {
		local $st = &smart_status::get_drive_status($d->{'device'}, $d);
		foreach my $a (@{$st->{'attribs'}}) {
			if ($a->[0] =~ /^Temperature\s+Celsius$/i &&
			    $a->[1] > 0) {
				push(@rv, { 'device' => $d->{'device'},
					    'temp' => int($a->[1]) });
				}
			}
		}
	}
return @rv;
}

# get_current_cpu_temps()
# Returns a list of hashes containing core and temp keys
sub get_current_cpu_temps
{
local @rv;
if (!$config{'collect_notemp'} && $virtualmin_pro &&
    $gconfig{'os_type'} =~ /-linux$/ && &has_command("sensors")) {
	&open_execute_command(SENSORS, "sensors </dev/null 2>/dev/null", 1);
	while(<SENSORS>) {
		if (/Core\s+(\d+):\s+([\+\-][0-9\.]+)/) {
			push(@rv, { 'core' => $1,
				    'temp' => $2 });
			}
		elsif (/CPU:\s+([\+\-][0-9\.]+)/) {
			push(@rv, { 'core' => 0,
				    'temp' => $1 });
			}
		}
	close(SENSORS);
	}
return @rv;
}

1;

