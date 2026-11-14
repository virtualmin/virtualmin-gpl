#!/usr/bin/perl
# Exercise single and bulk API account deletion without a Webmin installation.

use strict;
use warnings;
use Test::More;
use FindBin;
our (%in, %text, @accounts, @deleted, @logged, $admin, $locked,
     $reloads, $redirect);
$INC{'./virtual-server-lib.pl'} = __FILE__;
do "$FindBin::Bin/../api-access-lib.pl" or die $@ || $!;
{
    no warnings qw(redefine once);
    # list_api_access_users([name]): filter the in-memory account fixtures.
    *list_api_access_users = sub {
        return grep { !@_ || $_->{name} eq $_[0] } @accounts;
    };
}
%text = map { $_ => $_ } qw(apiaccess_ecannot apiaccess_epost
    apiaccess_egone apiaccess_enone);

# ReadParse(): use the request supplied by run_request instead of CGI input.
sub ReadParse { }
# master_admin(): return the current fixture's administrator status.
sub master_admin { return $admin; }
# require_acl(): account operations are provided by the stubs below.
sub require_acl { }
# error_setup(message): omit the prefix; this fixture renders no UI.
sub error_setup { }
# error(message): stop the request before any later mutation.
sub error { die "$_[0]\n"; }
# obtain_lock_webmin(): track whether account operations run under the lock.
sub obtain_lock_webmin { $locked = 1; }
# release_lock_webmin(): release the simulated account lock.
sub release_lock_webmin { $locked = 0; }
# unique(values...): collapse repeated checkbox values, preserving their order.
sub unique { my %seen; return grep { !$seen{$_}++ } @_; }
# acl::delete_user(name): remove only an in-memory account while locked.
sub acl::delete_user {
    die "Deletion without lock\n" unless $locked;
    push(@deleted, $_[0]);
    @accounts = grep { $_->{name} ne $_[0] } @accounts;
}
# webmin_log(action, type, name, details): record the deletion's audit target.
sub webmin_log { push(@logged, [@_]); }
# reload_miniserv(): count authentication reloads without touching the host.
sub reload_miniserv { $reloads++; }
# redirect(url): record the destination without printing CGI headers.
sub redirect { $redirect = $_[0]; return 1; }

# run_request(&params, [admin], [method]): run the save CGI; return any error.
# params is a parsed form hashref. The optional arguments default to a master
# administrator making a POST.
sub run_request {
    my ($params, $is_admin, $method) = @_;
    %in = %$params;
    $admin = defined($is_admin) ? $is_admin : 1;
    local $ENV{REQUEST_METHOD} = $method || 'POST';
    # Each request starts with three accounts and a fresh mutation log.
    @accounts = map { { name => "api$_", policy => { api_id => "id$_" } } } 1..3;
    @deleted = @logged = ();
    $locked = $reloads = 0;
    $redirect = '';
    # Capture CGI errors so tests can inspect both the denial and its effects.
    my $result = do "$FindBin::Bin/../save_api_access.cgi";
    return $@ || (!$result ? $! : '');
}

# A valid bulk request deletes only checked accounts and logs each deletion.
is(run_request({ bulk => 1, delete => 1, d => "id1\0id2" }), '',
    'bulk deletion succeeds');
is_deeply(\@deleted, [qw(api1 api2)], 'only checked accounts are deleted');
is_deeply([map { $_->{name} } @accounts], ['api3'], 'unchecked account survives');
is_deeply([map { [@$_[0..2]] } @logged],
    [['delete', 'apiaccount', 'api1'], ['delete', 'apiaccount', 'api2']],
    'each deleted account is logged');
is($reloads, 1, 'bulk deletion reloads authentication once');
ok(!$locked, 'successful deletion releases the lock');
is($redirect, 'api_access.cgi', 'returns to the account list');

# Duplicate checkbox values must not repeat account deletion.
is(run_request({ bulk => 1, delete => 1, d => "id1\0id1" }), '',
    'duplicate selections are accepted');
is_deeply(\@deleted, ['api1'], 'duplicate selection deletes only once');

# Reject the whole selection before changing anything, including stale lists.
for my $selection ('', 'root', 'old-id1', "id1\0missing", "id1\0root") {
    like(run_request({ bulk => 1, delete => 1, d => $selection }),
        qr/apiaccess_(?:enone|egone)/, 'reject empty, stale or invalid selection');
    is_deeply(\@deleted, [], 'invalid selection deletes no accounts');
    ok(!$locked, 'rejected selection releases the shared account lock');
    is($reloads, 0, 'invalid selection does not reload authentication');
}
# A selection alone cannot authorize deletion or double as account creation.
for my $request ({ bulk => 1, d => 'id1' },
                 { bulk => 1, delete => 1, new => 1, d => 'id1' }) {
    like(run_request($request), qr/apiaccess_egone/, 'reject invalid bulk action');
    is_deeply(\@deleted, [], 'invalid bulk action changes nothing');
}

# The editor keeps its name-and-ID check and the same deletion path.
is(run_request({ old => 'api1', id => 'id1', delete => 1 }), '',
    'single-account editor deletion still works');
is_deeply(\@deleted, ['api1'], 'editor deletes only its account');
like(run_request({ old => 'api1', id => 'old-id1', delete => 1 }),
    qr/apiaccess_egone/, 'stale editor cannot delete a replacement account');
is_deeply(\@deleted, [], 'replacement account survives');

# Bulk requests must pass the same role and HTTP-method checks as edits.
my $bulk = { bulk => 1, delete => 1, d => 'id1' };
like(run_request($bulk, 0), qr/apiaccess_ecannot/, 'non-admin cannot bulk delete');
is_deeply(\@deleted, [], 'non-admin request deletes nothing');
like(run_request($bulk, 1, 'GET'), qr/apiaccess_epost/, 'GET cannot bulk delete');
is_deeply(\@deleted, [], 'GET request deletes nothing');

done_testing();
