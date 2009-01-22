#!/usr/local/bin/perl

=head1 info.pl

Show general information about this Virtualmin system.

XXX

=cut

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*\/)[^\/]+$/) {
		chdir($1);
		}
	chop($pwd = `pwd`);
	$0 = "$pwd/info.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "info.pl must be run as root";
	}

foreach $a (@ARGV) {
	if ($a eq "--help") {
		&usage();
		}
	elsif ($a eq "--search") {
		push(@searches, shift(@ARGV));
		}
	else {
		push(@searches, $a);
		}
	}

$info = &get_collected_info();
%tinfo = &get_theme_info($current_theme);
$info->{'host'} = { 'hostname', &get_system_hostname(),
		    'os' => $gconfig{'real_os_type'}.' '.
			    $gconfig{'real_os_version'},
		    'webmin version' => &get_webmin_version(),
		    'virtualmin version' => $module_info{'version'},
		    'theme version' => $tinfo{'version'},
		    'root' => $root_directory,
		    'module root' => $module_root_directory,
		  };
delete($info->{'startstop'});
delete($info->{'quota'});
delete($info->{'inst'}) if (!@{$info->{'inst'}});
delete($info->{'poss'}) if (!@{$info->{'poss'}});
delete($info->{'fextra'});
delete($info->{'fhide'});
delete($info->{'fmax'});
foreach my $k (keys %$info) {
	delete($info->{$k}) if (!&info_search_match($k));
	}
&recursive_info_dump($info, "");

sub recursive_info_dump
{
local ($info, $indent) = @_;

# Dump object, depending on type
if (ref($info) eq "ARRAY") {
	foreach $k (@$info) {
		print $indent,"* ";
		if (ref($k)) {
			print "\n";
			&recursive_info_dump($k, $indent."    ");
			}
		else {
			print $k,"\n";
			}
		}
	}
elsif (ref($info) eq "HASH") {
	foreach $k (sort { $a cmp $b } keys %$info) {
		print $indent,$k,": ";
		if (ref($info->{$k})) {
			print "\n";
			&recursive_info_dump($info->{$k}, $indent."    ");
			}
		else {
			print $info->{$k},"\n";
			}
		}
	}
else {
	print $indent,$info,"\n";
	}
}

sub info_search_match
{
local ($i) = @_;
if (@searches && !ref($i)) {
	foreach my $s (@searches) {
		return 1 if ($i =~ /\Q$s\E/i);
		}
	return 0;
	}
return 1;
}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Displays information about this Virtualmin system.\n";
print "\n";
print "usage: info.pl\n";
exit(1);
}

