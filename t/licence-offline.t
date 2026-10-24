use strict;
use warnings;
no warnings 'once';
use Test::More;
use FindBin;
use File::Temp qw(tempdir);

# Exercise the real API with fixture files and forbidden online operations.
package virtual_server;
our ($virtualmin_license_file, $licence_status, $virtualmin_shop_link,
     $virtualmin_apt_auth_file, $virtualmin_yum_repo, $virtualmin_apt_repo,
     $upgrade_virtualmin_host_all, $first_print, $second_print, %config, %text);
$first_print = $second_print = sub {};
$upgrade_virtualmin_host_all = join('|', map { quotemeta($_) }
    qw(software.virtualmin.com download.virtualmin.com rc.download.virtualmin.dev));
sub require_licence { die "Online license loading is forbidden\n"; }
sub setup_virtualmin_repos { die "Repository setup is forbidden\n"; }
sub http_post { die "Network access is forbidden\n"; }
sub http_download { die "Network access is forbidden\n"; }
sub lock_file { }
sub unlock_file { }
sub foreign_require { die 'Unexpected module' unless $_[0] eq 'webmin'; }
sub text { $_[0] }
sub read_file_contents {
    open(my $fh, '<', $_[0]) or die "Cannot read fixture\n";
    local $/; return <$fh>;
}
sub write_file_contents {
    open(my $fh, '>', $_[0]) or die "Cannot write fixture\n";
    print $fh $_[1]; close($fh) or die "Cannot close fixture\n";
}
sub read_env_file {
    my ($path, $out) = @_;
    %$out = map { split(/=/, $_, 2) } split(/\n/, read_file_contents($path));
}
sub write_env_file { write_file_contents($_[0], join('', map { "$_=$_[1]->{$_}\n" } sort keys %{$_[1]})); }
sub write_file { write_env_file(@_); }
sub webmin::save_module_config { write_env_file($webmin::module_config_file, \%webmin::config); }
require "$FindBin::Bin/../virtualmin-licence.pl";

package main;
my $marker = 'CLONE_REQUIRES_LICENSE';
my $dir = tempdir(DIR => '/tmp', CLEANUP => 1);
$virtual_server::virtualmin_license_file = "$dir/license";
$virtual_server::licence_status = "$dir/status";
$virtual_server::text{'licence_offline_changed'} = 'License changed offline';
$webmin::module_config_file = "$dir/webmin";
$webmin::config{'upsource'} = 'https://123456:oldkey@download.virtualmin.com/wbm';
$webmin::config{'password'} = 'unrelated';
$webmin::config{'upuser'} = '123456';
$webmin::config{'uppass'} = 'oldkey';
virtual_server::write_env_file("$dir/license", {SerialNumber=>'123456', LicenseKey=>'oldkey'});
virtual_server::write_file_contents("$dir/unrelated.repo", 'https://123456:oldkey@download.virtualmin.com/other');
my @cases = (
    ['RPM URL', 'virtualmin_yum_repo', "[virtualmin]\nbaseurl=https://123456:oldkey\@software.virtualmin.com/pro/rpm\nenabled=0\n",
     "[virtualmin]\nbaseurl=https://$marker:$marker\@software.virtualmin.com/pro/rpm\nenabled=0\n"],
    ['APT URL', 'virtualmin_apt_repo', 'deb https://123456:oldkey@download.virtualmin.com/pro/apt virtualmin main',
     "deb https://$marker:$marker\@download.virtualmin.com/pro/apt virtualmin main"],
    ['APT auth', 'virtualmin_apt_auth_file', "machine download.virtualmin.com\nlogin 123456\npassword oldkey\nmachine unrelated.example login other password keep\n",
     "machine download.virtualmin.com\nlogin $marker\npassword $marker\nmachine unrelated.example login other password keep\n"],
    ['APT auth path', 'virtualmin_apt_auth_file', "machine https://rc.download.virtualmin.dev/virtualmin login 123456 password oldkey\n",
     "machine https://rc.download.virtualmin.dev/virtualmin login $marker password $marker\n"],
    ['Unrelated host', 'virtualmin_yum_repo', 'https://other:keep@software.virtualmin.com.example/pro',
     'https://other:keep@software.virtualmin.com.example/pro'],
);
for my $case (@cases) {
    my ($name, $field, $input, $expected) = @$case;
    no strict 'refs';
    local ${"virtual_server::$field"} = "$dir/repo";
    virtual_server::write_file_contents("$dir/repo", $input);
    virtual_server::write_file_contents("$dir/status", "status=0\nsubscription=source\n");
    my ($err) = virtual_server::change_licence($marker, $marker, 0, 0, 0, 1);
    ok(!$err, "$name: offline path bypasses loading, validation and setup");
    is(virtual_server::read_file_contents("$dir/repo"), $expected, "$name: credentials only");
    virtual_server::change_licence($marker, $marker, 0, 0, 0, 1);
    is(virtual_server::read_file_contents("$dir/repo"), $expected, "$name: repeat is harmless");
}
like(virtual_server::read_file_contents("$dir/license"), qr/^LicenseKey=$marker$/m, 'shared license write replaces key');
like(virtual_server::read_file_contents("$dir/license"), qr/^SerialNumber=$marker$/m, 'shared license write replaces serial');
is($webmin::config{'upsource'}, "https://$marker:$marker\@download.virtualmin.com/wbm", 'shared Webmin update changes credentials');
like(virtual_server::read_file_contents("$dir/webmin"), qr/^password=unrelated$/m, 'other Webmin settings retained');
is($webmin::config{'upuser'}, $marker, 'Webmin update user holding the old serial replaced');
like(virtual_server::read_file_contents("$dir/webmin"), qr/^uppass=$marker$/m, 'Webmin update password replaced');
unlike(virtual_server::read_file_contents("$dir/status"), qr/subscription|status=0/, 'cached license state cleared');
like(virtual_server::read_file_contents("$dir/unrelated.repo"), qr/123456:oldkey/, 'no scan of unrelated files');
my ($bad) = virtual_server::change_licence("bad\nvalue", $marker, 1, 1, 0, 1);
ok($bad, 'unsafe credentials rejected');
like(virtual_server::read_file_contents("$dir/license"), qr/^SerialNumber=$marker$/m, 'invalid input makes no writes');
# Webmin update credentials change only when they hold the previous serial.
$webmin::config{'upuser'} = 'other-user';
$webmin::config{'uppass'} = 'other-pass';
virtual_server::change_licence('NEWSERIAL', 'NEWKEY', 0, 0, 0, 1);
is($webmin::config{'upuser'}, 'other-user', 'unrelated Webmin update user retained');
is($webmin::config{'uppass'}, 'other-pass', 'unrelated Webmin update password retained');
virtual_server::change_licence($marker, $marker, 0, 0, 0, 1);
{
    no warnings 'redefine';
    local *virtual_server::write_file_contents = sub { die "Simulated write failure\n"; };
    ok(!eval { virtual_server::change_licence('NEW', 'NEW', 1, 1, 0, 1); 1 }, 'write failure cannot report success');
}
# Online calls still load and validate licenses before any file changes.
{
    no warnings 'redefine';
    local *virtual_server::require_licence = sub { 1 };
    local *virtual_server::get_licence_hostid = sub { 'fixture' };
    local *virtual_server::licence_scheduled = sub { (1, undef, 'Invalid fixture license') };
    my ($error) = virtual_server::change_licence('INVALID', 'INVALID', 0, 1);
    ok($error, 'online validation still rejects invalid licenses');
    like(virtual_server::read_file_contents("$dir/license"), qr/^SerialNumber=$marker$/m, 'online validation failure makes no writes');
}
# The CLI selects the offline API and skips its post-change hooks.
{
    no warnings 'redefine';
    local $virtual_server::module_name = 'virtual-server';
    local *virtual_server::set_all_text_print = sub {};
    local *virtual_server::virtualmin_api_log = sub {};
    for my $offline (0, 1) {
        my (@call, $hooks);
        local *virtual_server::change_licence = sub { @call = @_; return (0, undef); };
        local *virtual_server::run_post_actions_silently = sub { $hooks++; };
        local $virtual_server::offline;
        local @ARGV = ('--serial', $marker, '--key', $marker, $offline ? ('--offline') : ());
        do "$FindBin::Bin/../change-licence.pl";
        is($@, '', "CLI mode $offline completes");
        is($call[5] || 0, $offline, "CLI mode $offline selects the API path");
        is($hooks || 0, $offline ? 0 : 1, "CLI mode $offline handles hooks");
    }
}
done_testing();
