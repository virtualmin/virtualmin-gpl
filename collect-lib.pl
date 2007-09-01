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
local $infostr = &read_file_contents($collected_info_file);
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
push(@stats, [ "procs", $info->{'procs'} ]) if ($info->{'procs'});
if ($info->{'mem'}) {
	push(@stats, [ "memused",
		       ($info->{'mem'}->[0]-$info->{'mem'}->[1])*1024 ]);
	if ($info->{'mem'}->[2]) {
		push(@stats, [ "swapused",
			      ($info->{'mem'}->[2]-$info->{'mem'}->[3])*1024 ]);
		}
	}
if ($info->{'disk_total'}) {
	push(@stats, [ "diskused",
		       $info->{'disk_total'}-$info->{'disk_free'} ]);
	}
# XXX more?
# XXX total quota allocated
foreach my $stat (@stats) {
	open(HISTORY, ">>$historic_info_dir/$stat->[0]");
	print HISTORY $time," ",$stat->[1],"\n";
	close(HISTORY);
	}
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
opendir(HISTDIR, $historic_info_dir);
foreach my $f (readdir(HISTDIR)) {
	if ($f =~ /^[a-z]$/) {
		local @rv = &list_historic_collected_info($f, $start, $end);
		$all{$f} = \@rv;
		}
	}
closedir(HISTDIR);
return \%all;
}

1;

