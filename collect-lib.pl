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
		&foreign_require("mount", "mount-lib.pl");
		local @mounted = &mount::list_mounted();
		local $total = 0;
		local $free = 0;
		foreach my $m (@mounted) {
			if ($m->[2] eq "ext2" || $m->[2] eq "ext3" ||
			    $m->[2] eq "reiserfs" || $m->[2] eq "ufs" ||
			    $m->[1] =~ /^\/dev\//) {
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
	local @poss = &security_updates::list_possible_updates(1);
	$info->{'poss'} = \@poss;
	}

# System status
$info->{'startstop'} = [ &get_startstop_links() ];

# Counts for domains
local @doms = &virtual_server::list_domains();
local %fcount = map { $_, 0 } @virtual_server::features;
$fcount{'doms'} = 0;
foreach my $d (@doms) {
	$fcount{'doms'}++;
	foreach my $f (@virtual_server::features) {
		$fcount{$f}++ if ($d->{$f});
		}
	my @dbs = &virtual_server::domain_databases($d);
	$fcount{'dbs'} += scalar(@dbs);
	my @users = &virtual_server::list_domain_users($d, 0, 1, 1, 1);
	$fcount{'users'} += scalar(@users);
	my @aliases = &virtual_server::list_domain_aliases($d, 1);
	$fcount{'aliases'} += scalar(@aliases);
	}
$info->{'fcount'} = \%fcount;
$info->{'ftypes'} = [ "doms", "dns", "web", "ssl", "mail", "dbs",
		      "users", "aliases" ];
local (%fmax, %fextra, %fhide);
foreach my $f (@{$info->{'ftypes'}}) {
	local ($extra, $reason, $max, $hide) =
		&virtual_server::count_feature($f);
	$fmax{$f} = $max;
	$fextra{$f} = $extra;
	$fhide{$f} = $hide;
	}
$info->{'fmax'} = \%fmax;
$info->{'fextra'} = \%fextra;
$info->{'fhide'} = \%fhide;

# Quota use for domains
if (&virtual_server::has_home_quotas()) {
	local @quota;
	local $homesize = &virtual_server::quota_bsize("home");
	local $mailsize = &virtual_server::quota_bsize("mail");
	local $maxquota = 0;

	# Work out quotas
	foreach my $d (@doms) {
		# If this is a parent domain, sum up quotas
		if (!$d->{'parent'} && &virtual_server::has_home_quotas()) {
			local ($home, $mail, $dbusage) =
				&virtual_server::get_domain_quota($d, 1);
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
	local $defip = &virtual_server::get_default_ip();
	if (defined(&virtual_server::list_resellers)) {
		foreach my $r (&virtual_server::list_resellers()) {
			if ($r->{'acl'}->{'defip'}) {
				$reselip{
				  $r->{'acl'}->{'defip'}} = $r;
				}
			}
		}
	if (defined(&virtual_server::list_shared_ips)) {
		foreach my $ip (&virtual_server::list_shared_ips()) {
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
foreach my $f ("virtualmin", @virtual_server::features) {
	if ($virtual_server::config{$f} || $f eq "virtualmin") {
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

1;

