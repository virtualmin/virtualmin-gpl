#!/usr/bin/perl
# Exercise remote.cgi authorization without loading Webmin or running commands.
use strict;
use warnings;
use Test::More;
use FindBin;
use File::Temp qw(tempdir);
use JSON::PP qw(decode_json);

my $command_dir = tempdir(DIR => '/tmp', CLEANUP => 1);
my $command_path = "$command_dir/list-domains.pl";
open(my $command, '>', $command_path) or die $!;
close($command);
chmod(0700, $command_path) or die $!;

{
    package virtual_server;
    our (%access, %in, @in, %text, $endpoint, $admin, $command_dir,
         $module_name, @api_access_commands, $api_access_commands_loaded,
         $virtualmin_pro);
    # Load the real authorization helpers without module initialization.
    do "$FindBin::Bin/../security-lib.pl" or die $@ || $!;
    do "$FindBin::Bin/../commands-lib.pl" or die $@ || $!;
    do "$FindBin::Bin/../api-access-lib.pl" or die $@ || $!;
    $module_name = 'virtual-server';
    $virtualmin_pro = 1;

    # ReadParse(): request parameters are supplied by run_request.
    sub ReadParse { }
    # webmin_user_api_only(): return the fixture's authenticated endpoint.
    sub webmin_user_api_only { return $endpoint; }
    # master_admin(): select whether ordinary role checks would grant access.
    sub master_admin { return $admin; }
    # reseller_admin(): these fixtures cover master, owner, and API accounts.
    sub reseller_admin { return 0; }
    # module_root_directory(module): resolve scripts only inside the fixture.
    sub module_root_directory { return $command_dir; }
    # un_urlize(value): fixture parameters contain no URL escapes.
    sub un_urlize { return $_[0]; }
    # text(key, [values...]): expand the actual remote API messages.
    sub text {
        my ($key, @values) = @_;
        my $message = $text{$key};
        $message =~ s/\$(\d+)/$values[$1-1]/ge;
        return $message;
    }
    # create_json_format(&data): encode errors without Webmin dependencies.
    sub create_json_format { return JSON::PP::encode_json($_[0]); }
    # execute_webmin_script(path, module, &args, output): record dispatch only.
    sub execute_webmin_script {
        print "DISPATCHED $_[0]\n";
        CORE::exit(0);
    }
}

# Use a fixed catalog and shipped messages for the real request dispatcher.
$virtual_server::command_dir = $command_dir;
@virtual_server::api_access_commands = ({ name => 'list-domains',
    key => 'virtual-server:list-domains', provider => 'virtual-server',
    path => $command_path, scoped => 1 });
$virtual_server::api_access_commands_loaded = 1;
open(my $lang, '<', "$FindBin::Bin/../lang/en") or die $!;
while (<$lang>) {
    chomp;
    $virtual_server::text{$1} = $2 if /^(remote_\w+)=(.*)$/;
}
close($lang);

# run_request(endpoint, &policy, admin, [json])
# Run the CGI in a child; return its exit status and captured response.
sub run_request {
    my ($endpoint, $policy, $admin, $json) = @_;
    pipe(my $reader, my $writer) or die $!;
    my $pid = fork();
    defined($pid) or die $!;
    if (!$pid) {
        # Replace only Webmin initialization; the CGI and policy checks run.
        close($reader);
        open(STDOUT, '>&', $writer) or die $!;
        close($writer);
        $INC{'./virtual-server-lib.pl'} = __FILE__;
        $virtual_server::endpoint = $endpoint;
        $virtual_server::admin = $admin;
        %virtual_server::access = %$policy;
        %virtual_server::in = (program => 'list-domains');
        $virtual_server::in{json} = 1 if $json;
        @virtual_server::in = ('program=list-domains');
        do "$FindBin::Bin/../remote.cgi";
        print "CGI failed: $@\n";
        CORE::exit(1);
    }
    # Read until the CGI exits, without letting it change the parent fixture.
    close($writer);
    local $/;
    my $output = <$reader>;
    close($reader);
    waitpid($pid, 0);
    return ($?, $output);
}

my $endpoint = 'virtual-server/remote.cgi';
my %granted = (api_id => 'fixture', noconfig => 1,
    api_commands => 'virtual-server:list-domains');
for my $case (
    ['granted API account', $endpoint, { %granted }, 0, 1],
    ['disabled API account', $endpoint, { %granted, api_disabled => 1 }, 0, 0],
    ['ungranted command', $endpoint, { %granted, api_commands => '' }, 0, 0],
    ['missing API policy', $endpoint, {}, 1, 0],
    ['ordinary master', '', {}, 1, 1],
    ['permitted domain owner', '', { edit_remote_api => 1 }, 0, 1],
    ['domain owner without API access', '', {}, 0, 0]) {
    # Exercise both dedicated accounts and the unchanged ordinary role path.
    my ($label, $path, $policy, $admin, $allowed) = @$case;
    my ($status, $output) = run_request($path, $policy, $admin);
    is($status, 0, "$label returns a normal API response");
    if ($allowed) {
        # Only an authorized request may reach command execution.
        like($output, qr/^DISPATCHED \Q$command_path\E$/m, "$label dispatches");
    }
    else {
        # Rejections must use the API response and never reach execution.
        like($output, qr/^ERROR: You are not allowed to run /m, "$label denied");
        unlike($output, qr/DISPATCHED/, "$label executes nothing");
    }
}

# Missing policy errors must honor the requested output format too.
my ($status, $output) = run_request($endpoint, {}, 1, 1);
is($status, 0, 'missing policy returns a normal JSON response');
like($output, qr/^Content-type: application\/json\n\n/, 'JSON content type');
my (undef, $body) = split(/\n\n/, $output, 2);
is_deeply(decode_json($body), { status => 'error',
    error => $virtual_server::text{remote_ecannot} }, 'missing policy JSON error');

done_testing();
