#!/usr/bin/perl
# licence-offline-live.pl runs the installed API against private fixture files.
# The host's license, repository configuration and package state are not changed.
package virtual_server;
use strict;
use warnings;
no warnings 'once';
use File::Temp qw(tempdir);
use Digest::SHA qw(sha256_hex);
our ($module_name, $virtualmin_license_file, $licence_status, %text,
     $virtualmin_apt_auth_file, $virtualmin_yum_repo, $virtualmin_apt_repo);
my ($root) = grep { -f "$_/virtual-server/virtual-server-lib.pl" }
    qw(/usr/share/webmin /usr/libexec/webmin);
die "Virtualmin is missing\n" if (!$root);
$ENV{'WEBMIN_CONFIG'} = '/etc/webmin';
$ENV{'WEBMIN_VAR'} = '/var/webmin';
$ENV{'REMOTE_USER'} = 'root';
$main::no_acl_check = 1;
$0 = "$root/virtual-server/licence-offline-live.pl";
chdir("$root/virtual-server") or die $!;
require './virtual-server-lib.pl';
require './virtualmin-licence.pl';
foreign_require('webmin');
set_all_null_print();

# Record only hashes, never real credentials or authenticated repository URLs.
my @original = grep { $_ && -f $_ } ($virtualmin_license_file, $virtualmin_apt_auth_file,
    $virtualmin_yum_repo, $virtualmin_apt_repo, $webmin::module_config_file);
my %before = map { $_ => sha256_hex(read_file_contents($_)) } @original;
my $dir = tempdir('virtualmin-offline-test-XXXXXX', DIR => '/var/tmp', CLEANUP => 1);
local $virtualmin_license_file = "$dir/license";
local $licence_status = "$dir/status";
local $webmin::module_config_file = "$dir/webmin";
local %webmin::config = (upsource => 'https://123456789:SOURCE_FIXTURE_KEY@software.virtualmin.com/wbm',
    upuser => '123456789', uppass => 'SOURCE_FIXTURE_KEY', password => 'unrelated');
local $virtualmin_apt_auth_file = "$dir/apt-auth";
local $virtualmin_yum_repo = "$dir/rpm";
local $virtualmin_apt_repo;
write_env_file($virtualmin_license_file, { SerialNumber => '123456789', LicenseKey => 'SOURCE_FIXTURE_KEY' });
write_file($licence_status, { status => 0, expiry => '2099-01-01', subscription => 'source' });
write_file_contents("$dir/webmin", "upsource=https://123456789:SOURCE_FIXTURE_KEY\@software.virtualmin.com/wbm\npassword=unrelated\n");
write_file_contents("$dir/apt-auth", "machine download.virtualmin.com/virtualmin login 123456789 password SOURCE_FIXTURE_KEY\nmachine unrelated.example login other password keep\n");
write_file_contents("$dir/rpm", "[virtualmin]\nbaseurl=https://123456789:SOURCE_FIXTURE_KEY\@download.virtualmin.com/pro/rpm\nenabled=0\n");
chmod(0600, "$dir/apt-auth");
my %cached;
read_file_cached($licence_status, \%cached);
{
    no warnings 'redefine';
    # Keep the shared Webmin configuration writer pointed at this fixture.
    local *webmin::save_module_config = sub { write_file($webmin::module_config_file, \%webmin::config); };
    local *require_licence = sub { die "Online loading attempted\n" };
    local *http_post = sub { die "Network attempted\n" };
    local *http_download = sub { die "Network attempted\n" };
    local *setup_virtualmin_repos = sub { die "Repository setup attempted\n" };
    my ($err) = change_licence('CLONE_REQUIRES_LICENSE', 'CLONE_REQUIRES_LICENSE', 0, 0, 0, 1);
    die "Offline change failed\n" if ($err);
}
for my $file ($virtualmin_license_file, "$dir/webmin", "$dir/apt-auth", "$dir/rpm") {
    my $value = read_file_contents($file);
    die "Source fixture credentials retained\n" if ($value =~ /SOURCE_FIXTURE_KEY|123456789/);
    die "Placeholder missing in $file\n" unless $value =~ /CLONE_REQUIRES_LICENSE/;
}
die "APT permissions changed\n" unless ((stat("$dir/apt-auth"))[2] & 0777) == 0600;
die "Repository channel changed\n" unless read_file_contents("$dir/rpm") eq
    "[virtualmin]\nbaseurl=https://CLONE_REQUIRES_LICENSE:CLONE_REQUIRES_LICENSE\@download.virtualmin.com/pro/rpm\nenabled=0\n";
my %after;
read_file_cached($licence_status, \%after);
die "Cached source status retained\n" unless $after{'status'} == 1 && !$after{'subscription'};
for my $file (@original) {
    die "Host configuration changed\n" unless sha256_hex(read_file_contents($file)) eq $before{$file};
}
print "PASS: offline API, real Webmin writes, APT/RPM credentials, cache invalidation, permissions and host preservation\n";
