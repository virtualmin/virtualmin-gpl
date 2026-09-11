use strict;
use warnings;
no warnings qw(once redefine);
use File::Temp qw(tempdir);
use POSIX ();
use Test::More;
use FindBin;

plan skip_all => 'Set VIRTUALMIN_PROFTPD_VM_TEST=1 on a disposable Webmin VM'
    unless $ENV{'VIRTUALMIN_PROFTPD_VM_TEST'};

$ENV{'WEBMIN_CONFIG'} = '/etc/webmin';
$ENV{'WEBMIN_VAR'} = '/var/webmin';
open(my $mc, '<', '/etc/webmin/miniserv.conf') or die $!;
my ($root) = map { /^root=(.*)/ ? $1 : () } <$mc>;
close($mc);
chdir("$root/virtual-server") or die $!;
$0 = "$root/virtual-server/proftpd-logrotate-test.pl";
unshift(@INC, $root);
require WebminCore;
WebminCore->import();
init_config();
foreign_require('virtual-server');
foreign_require('logrotate');

my $source = "$FindBin::Bin/../proftpd-lib.pl";
{
    package virtual_server;
    do $source or die $@ || $!;
}

# Use the VM's real parser and complete configuration in a temporary copy.
my $tmp = tempdir('proftpd-logrotate-XXXXXX', TMPDIR => 1, CLEANUP => 1);
mkdir("$tmp/conf.d") or die $!;
my %original;
foreach my $file (glob('/etc/logrotate.d/*')) {
    next unless -f $file;
    (my $name = $file) =~ s{.*/}{};
    open(my $fh, '<', $file) or die $!;
    $original{$name} = do { local $/; <$fh> };
    close($fh);
}
open(my $main, '<', '/etc/logrotate.conf') or die $!;
my $maintext = do { local $/; <$main> };
close($main);
$maintext =~ s{/etc/logrotate.d}{$tmp/conf.d}g;
write_text("$tmp/main.conf", $maintext);
$logrotate::config{'logrotate_conf'} = "$tmp/main.conf";
$logrotate::config{'add_file'} = "$tmp/conf.d";
$virtual_server::config{'logrotate'} = 1;

my $debian = exists($original{'proftpd-core'});
my $rule = $debian ? 'proftpd-core' : 'proftpd';

# Run the actual postinstall section with real Webmin locks. Other upgrade
# migrations are outside this test's scope.
my $postinstall = read_text("$FindBin::Bin/../postinstall.pl");
my ($hook_source) = $postinstall =~ /(# Unlock config now we're done with it\n.*?)\nif \(!defined\(\$gconfig\{'forgot_pass'\}\)\)/s;
die 'Cannot locate postinstall repair section' unless $hook_source;
my $hook = eval "package virtual_server; no strict 'vars'; sub { $hook_source }";
die $@ unless $hook;
reset_config();
{
    local $virtual_server::module_config_file = "$tmp/virtualmin-config";
    write_text($virtual_server::module_config_file, "fixture=1\n");
    my $repair = \&virtual_server::setup_proftpd_logrotate;
    my @repairs;
    local *virtual_server::setup_proftpd_logrotate = sub {
        ok(!defined($main::locked_file_list{$virtual_server::module_config_file}),
            'postinstall releases the module configuration lock before repair');
        push(@repairs, $repair->());
        return $repairs[-1];
    };
    for (1 .. 2) {
        lock_file($virtual_server::module_config_file);
        $hook->();
        ok(!-e "$tmp/conf.d.lock" && !-e "$tmp/main.conf.lock" &&
            !$main::got_lock_logrotate, 'postinstall repair releases its logrotate locks');
    }
    is_deeply(\@repairs, [$debian ? 2 : 0, 0], 'postinstall repairs once and is safe to repeat');
    check_config('configuration repaired by postinstall remains valid');

    # A competing process holds the logrotate lock, then needs the module
    # configuration lock. Postinstall must release its lock before waiting.
    reset_config();
    pipe(my $ready, my $notify) or die $!;
    lock_file($virtual_server::module_config_file);
    my $child = fork();
    die "fork: $!" unless defined($child);
    if (!$child) {
        close($ready);
        # The child must not inherit ownership of its parent's locks.
        %main::locked_file_list = ();
        @main::temporary_files = ();
        my $error;
        {
            local $SIG{'ALRM'} = sub { die "competing lock timeout\n" };
            eval {
                alarm(15);
                lock_file("$tmp/conf.d", 0, 0, 1);
                die 'Competing lock was not created' unless -e "$tmp/conf.d.lock";
                syswrite($notify, "ready\n");
                lock_file($virtual_server::module_config_file, 0, 0, 1);
                unlock_file($virtual_server::module_config_file);
                unlock_file("$tmp/conf.d");
                alarm(0);
            };
            $error = $@;
            alarm(0);
        }
        unlock_all_files();
        print STDERR $error if $error;
        close($notify);
        POSIX::_exit($error ? 1 : 0);
    }
    close($notify);
    my ($completed, $waited);
    {
        local $SIG{'ALRM'} = sub { die "postinstall lock timeout\n" };
        eval {
            alarm(20);
            my $signal = <$ready>;
            die 'Competing process did not acquire its lock' unless $signal && $signal eq "ready\n";
            $hook->();
            waitpid($child, 0);
            $waited = 1;
            $completed = $? == 0;
            alarm(0);
        };
        alarm(0);
        diag($@) if $@;
    }
    close($ready);
    if (!$waited) {
        kill('KILL', $child);
        waitpid($child, 0);
    }
    ok($completed, 'postinstall and a competing configuration editor both finish without deadlock');
    ok(!-e "$tmp/virtualmin-config.lock" && !-e "$tmp/conf.d.lock" &&
        !-e "$tmp/main.conf.lock" && !$main::got_lock_logrotate,
        'competing processes leave no configuration locks behind');
}

reset_config();
my $before = read_text("$tmp/conf.d/$rule");
my $count = virtual_server::setup_proftpd_logrotate();
is($count, $debian ? 2 : 0, 'adds only logs absent from the package rules');
my $after = read_text("$tmp/conf.d/$rule");
if (!$debian) {
    is($after, $before, 'package wildcard remains byte-for-byte unchanged');
}
is(virtual_server::setup_proftpd_logrotate(), 0, 'second call makes no changes');
is(read_text("$tmp/conf.d/$rule"), $after, 'second call preserves file contents');
check_config('complete configuration remains valid');

if ($debian) {
    # A configuration parsed before locking must not hide an administrator's
    # new rule when the repair checks for existing coverage.
    reset_config();
    logrotate::get_config_parent();
    write_text("$tmp/conf.d/custom", "/var/log/proftpd/sftp.log {\n missingok\n daily\n rotate 7\n}\n");
    is(virtual_server::setup_proftpd_logrotate(), 1, 'reloads coverage after acquiring the lock');
    check_config('a rule added after caching does not cause a duplicate');

    # Adding filenames must not rewrite custom scripts or their heredocs.
    reset_config();
    my $custom = $original{$rule};
    $custom =~ s{(\tpostrotate\n)}{$1cat <<EOF > $tmp/heredoc-result\nkeep this script intact\nEOF\n};
    write_text("$tmp/conf.d/$rule", $custom);
    clear_cache();
    is(virtual_server::setup_proftpd_logrotate(), 2, 'adds logs to a block with a custom script');
    my $updated = read_text("$tmp/conf.d/$rule");
    my ($oldbody) = $custom =~ /(\{.*)/s;
    my ($newbody) = $updated =~ /(\{.*)/s;
    is($newbody, $oldbody, 'preserves scripts, comments, and all existing directives exactly');
    check_config('configuration with a heredoc remains valid');
    reset_config();
    virtual_server::setup_proftpd_logrotate();

    # The saved block retains its existing policy and postrotate command.
    my ($block) = grep { ref($_->{'name'}) && grep { $_ eq '/var/log/proftpd/sftp.log' } @{$_->{'name'}} } @{logrotate::get_config()};
    is(logrotate::find_value('create', $block->{'members'}), '640 root adm', 'keeps package ownership and permissions');
    like(logrotate::find_value('postrotate', $block->{'members'}), qr/invoke-rc.d proftpd restart/, 'keeps package restart command');
    ok(logrotate::find('missingok', $block->{'members'}), 'absent logs remain permitted');

    # Force real logrotate on isolated files, recording the postrotate call.
    # The actual service restart command was checked above.
    mkdir("$tmp/logs") or die $!;
    my @members = map { +{ %$_ } } @{$block->{'members'}};
    my ($post) = grep { $_->{'name'} eq 'postrotate' } @members;
    $post->{'script'} = "echo rotated >> $tmp/postrotate-count\n";
    my @paths = map { "$tmp/logs/$_.log" } qw(sftp tls);
    my $fixture = { name => \@paths, members => \@members };
    write_text("$tmp/rotation.conf", join("\n", logrotate::directive_lines($fixture, ''))."\n");
    write_text($_, "rotation test\n") foreach @paths;
    my $out = `logrotate --force --state $tmp/state $tmp/rotation.conf 2>&1`;
    is($? >> 8, 0, 'forced rotation succeeds') or diag($out);
    foreach my $path (@paths) {
        ok(-s "$path.1" && -f $path && !-s $path, "$path rotates and is recreated");
        is((stat($path))[2] & 07777, 0640, 'recreated log has package permissions');
    }
    is(read_text("$tmp/postrotate-count"), "rotated\n", 'shared postrotate runs once for both logs');

    foreach my $case (
        ['explicit SFTP rule', '/var/log/proftpd/sftp.log', 1],
        ['wildcard SFTP rule', '/var/log/proftpd/s*.log', 1],
        ['wildcard for both missing logs', '/var/log/proftpd/[st]*.log', 0],
        ['wildcard in a different directory', '/var/log/*ftp*.log', 2],
    ) {
        reset_config();
        write_text("$tmp/conf.d/custom", "$case->[1] {\n missingok\n daily\n rotate 7\n}\n");
        clear_cache();
        is(virtual_server::setup_proftpd_logrotate(), $case->[2], $case->[0]);
        check_config("$case->[0]: no duplicate entries");
    }
    reset_config();
    my $nomissing = $original{$rule};
    $nomissing =~ s/\bmissingok\b/nomissingok/g;
    write_text("$tmp/conf.d/$rule", $nomissing);
    is(virtual_server::setup_proftpd_logrotate(), 0, 'does not add absent logs to a block requiring them');
    is(read_text("$tmp/conf.d/$rule"), $nomissing, 'custom missing-file policy remains unchanged');
    reset_config();
    unlink("$tmp/conf.d/$rule") or die $!;
    is(virtual_server::setup_proftpd_logrotate(), 0, 'does not invent a rule when the package block is absent');
}
done_testing();

sub write_text {
    my ($file, $text) = @_;
    open(my $fh, '>', $file) or die "$file: $!";
    print $fh $text;
    close($fh) or die $!;
}
sub read_text {
    open(my $fh, '<', $_[0]) or die "$_[0]: $!";
    return do { local $/; <$fh> };
}
sub clear_cache {
    %logrotate::get_config_cache = ();
    %logrotate::get_config_lnum_cache = ();
    %logrotate::get_config_files_cache = ();
    $logrotate::get_config_parent_cache = undef;
}
sub reset_config {
    unlink("$tmp/conf.d/custom") if -e "$tmp/conf.d/custom";
    write_text("$tmp/conf.d/$_", $original{$_}) foreach keys %original;
    clear_cache();
}
sub check_config {
    my ($name) = @_;
    my $out = `logrotate --debug --state /dev/null $tmp/main.conf 2>&1`;
    is($? >> 8, 0, $name) or diag($out);
}
