# Functions for collecting general system info

# collect_system_info()
# Returns a hash reference containing system information
sub collect_system_info
{
local $info = { };

# System information
if (&foreign_check("proc")) {
	&foreign_require("proc", "proc-lib.pl");
	if (defined(&proc::get_cpu_info)) {
		local @c = &proc::get_cpu_info();
		$info->{'load'} = \@c;
		}
	local @procs = &proc::list_processes();
	$info->{'procs'} = scalar(@procs);
	if (defined(&proc::get_memory_info)) {
		local @m = &proc::get_memory_info();
		$info->{'mem'} = \@m;
		}
	if (&foreign_check("mount")) {
		&require_useradmin();
		&foreign_require("mount", "mount-lib.pl");
		local @mounted = &mount::list_mounted();
		local $total = 0;
		local $free = 0;
		foreach my $m (@mounted) {
			if ($m->[2] eq "ext2" || $m->[2] eq "ext3" ||
			    $m->[2] eq "reiserfs" || $m->[2] eq "ufs" ||
			    $m->[2] eq "zfs" || $m->[2] eq "simfs" ||
			    $m->[2] eq "xfs" ||
			    $m->[1] =~ /^\/dev\// || $m->[1] eq $home_base) {
				local ($t, $f) =
					&mount::disk_space($m->[2], $m->[0]);
				$total += $t*1024;
				$free += $f*1024;
				}
			}
		$info->{'disk_total'} = $total;
		$info->{'disk_free'} = $free;
		}
	}

# Available package updates
if (&foreign_check("security-updates")) {
	&foreign_require("security-updates", "security-updates-lib.pl");
	local @poss = &security_updates::list_possible_updates(2);
	$info->{'poss'} = \@poss;
	if (defined(&security_updates::list_possible_installs)) {
		local @inst = &security_updates::list_possible_installs(2);
		$info->{'inst'} = \@inst;
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
			local ($home, $mail, $dbusage) =
				&get_domain_quota($d, 1);
			local $usage = $home*$homesize +
				       $mail*$mailsize;
			$maxquota = $usage+$dbusage if ($usage+$dbusage > $maxquota);
			local $limit = $d->{'quota'}*$homesize;
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
	}
if (keys %ipdom > 1) {
	local $defip = &get_default_ip();
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
	local @ips;
	foreach my $ip ($defip,
		     (sort { $a cmp $b } keys %reselip),
		     (sort { $a cmp $b } keys %ipcount)) {
		next if ($doneip{$ip}++);
		push(@ips, [ $ip, $ip eq $defip ? ('def', undef) :
			          $reselip{$ip} ? ('reseller',
						   $reselip{$ip}->{'name'}) :
			          $sharedip{$ip} ? ('shared', undef) :
						   ('virt', undef),
			     $ipcount{$ip}, $ipdom{$ip}->{'dom'} ]);
		}
	$info->{'ips'} = \@ips;
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
	&foreign_require("security-updates", "security-updates-lib.pl");
	local @poss = &security_updates::list_possible_updates(2);
	$info->{'poss'} = \@poss;
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
		       ($info->{'mem'}->[0]-$info->{'mem'}->[1])*1024,
		       $info->{'mem'}->[0]*1024 ]);
	if ($info->{'mem'}->[2]) {
		push(@stats, [ "swapused",
			      ($info->{'mem'}->[2]-$info->{'mem'}->[3])*1024,
			      $info->{'mem'}->[2]*1024 ]);
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

# Get mail since the last collection time
if (-r $procmail_log_file) {
	# Get last seek position
	local $lastinfo = &read_file_contents("$historic_info_dir/procmailpos");
	local @st = stat($procmail_log_file);
	local $now = time();
	local ($lastpos, $lastinode, $lasttime);
	if (defined($lastinfo)) {
		($lastpos, $lastinode, $lasttime) = split(/\s+/, $lastinfo);
		}
	else {
		# For the first run, start at the end of the file
		$lastpos = $st[7];
		$lastinode = $st[1];
		$lasttime = now();
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
	push(@stats, [ "mailcount", $mailcount / $mins ]);
	push(@stats, [ "spamcount", $spamcount / $mins ]);
	push(@stats, [ "viruscount", $viruscount / $mins ]);

	# Save last seek
	&open_tempfile(PROCMAILPOS, ">$historic_info_dir/procmailpos");
	&print_tempfile(PROCMAILPOS, $lastpos," ",$st[1]," ",$now."\n");
	&close_tempfile(PROCMAILPOS);
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
open(HISTORY, "$historic_info_dir/$stat");
while(<HISTORY>) {
	chop;
	local ($time, $value) = split(" ", $_);
	if ((!defined($start) || $time >= $start) &&
	    (!defined($end) || $time <= $end)) {
		push(@rv, [ $time, $value ]);
		}
	if (defined($end) && $time > $end) {
		last;	# Past the end point
		}
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
	if ($f =~ /^[a-z]+[0-9]*$/ && $f ne "maxes" && $f ne "procmailpos") {
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
local $offset = int(rand()*$step);
local @mins;
for(my $i=$offset; $i<60; $i+= $step) {
	push(@mins, $i);
	}
local $job = &find_virtualmin_cron_job($collect_cron_cmd);
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
	&cron::create_cron_job($job);
	}
elsif ($job && $config{'collect_interval'} ne 'none') {
	# Update existing job, if step has changed
	local @oldmins = split(/,/, $job->{'mins'});
	local $oldstep = $oldmins[0] eq '*' ? 1 :
			 @oldmins == 1 ? 60 :
			 $oldmins[1]-$oldmins[0];
	if ($step != $oldstep) {
		$job->{'mins'} = join(',', @mins);
		&cron::change_cron_job($job);
		}
	}
elsif ($job && $config{'collect_interval'} eq 'none') {
	# No longer wanted, so delete
	&cron::delete_cron_job($job);
	}
&cron::create_wrapper($collect_cron_cmd, $module_name, "collectinfo.pl");
}

1;

