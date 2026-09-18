#!/usr/local/bin/perl

=head1 configure-ai.pl

Save AI provider settings for virtualmin-ai and remote-ai.cgi

This command saves the provider, model, API URL and API key used by the
natural-language planner. The master administrator can use C<--user> to
configure any Webmin user. Other users can configure only their own settings
and must have remote API access.

The provider is one of C<openai>, C<anthropic>, C<gemini>, C<xai>, C<deepseek>
or C<custom>. C<--model> selects the model and defaults to the provider's own
default. C<--api-url> is required for a custom OpenAI-compatible server and is
otherwise overrides the built-in URL. Only the master administrator may set
an API URL or assign a custom provider. Other users must use a built-in URL or
a custom endpoint already assigned to them.

The master administrator can read the key from a root-only file with
C<--api-key-file> or from standard input with C<--api-key-stdin>. A remote API
POST request can send it with C<--api-key>, which keeps the key out of the URL
and process list. The provider verifies the key before it is saved unless
C<--no-verify> is given. If the provider does not change, omitting the key
keeps the saved one. An Anthropic key not scoped to a workspace also needs
C<--workspace>.

C<--show> prints the saved settings with the key masked, C<--remove> deletes
them, and C<--list> shows the master administrator every configured user.

Examples:

  virtualmin configure-ai --provider openai \
    --api-key-file /root/openai.key
  virtualmin configure-ai --user artists --provider anthropic \
    --api-key-file /root/artists-anthropic.key

=cut

package virtual_server;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*)\/[^\/]+$/) {
		chdir($pwd = $1);
		}
	else {
		chop($pwd = `pwd`);
		}
	$0 = "$pwd/configure-ai.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "configure-ai.pl must be run as root";
	}
&require_remote_api_command();

# Parse command-line arguments
&parse_common_cli_flags(\@ARGV);
my ($show, $remove, $list, $no_verify, $key_file, $key_stdin, $key, $target_user);
my %given;
while(@ARGV > 0) {
	my $a = shift(@ARGV);
	if ($a eq "--provider") {
		$given{'provider'} = shift(@ARGV);
		}
	elsif ($a eq "--model") {
		$given{'model'} = shift(@ARGV);
		}
	elsif ($a eq "--api-url") {
		$given{'url'} = shift(@ARGV);
		}
	elsif ($a eq "--workspace") {
		$given{'workspace'} = shift(@ARGV);
		}
	elsif ($a eq "--api-key") {
		$key = shift(@ARGV);
		}
	elsif ($a eq "--api-key-file") {
		$key_file = shift(@ARGV);
		}
	elsif ($a eq "--api-key-stdin") {
		$key_stdin = 1;
		}
	elsif ($a eq "--user") {
		$target_user = shift(@ARGV);
		}
	elsif ($a eq "--show") {
		$show = 1;
		}
	elsif ($a eq "--remove") {
		$remove = 1;
		}
	elsif ($a eq "--list") {
		$list = 1;
		}
	elsif ($a eq "--no-verify") {
		$no_verify = 1;
		}
	elsif ($a eq "--help") {
		&usage();
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Only the master administrator can configure other users or read key files
my $master = &master_admin();
my $remote_api = $main::virtualmin_remote_api || $ENV{'VIRTUALMIN_REMOTE_API'};
if (defined($target_user)) {
	$master || &usage("--user is only available to the master administrator");
	&virtualmin_ai_webmin_user_exists($target_user) ||
		&usage("Webmin user $target_user does not exist");
	}
$key_file && !$master &&
	&usage("--api-key-file is only available to the master administrator");
defined($key) && (!$remote_api || uc($ENV{'REQUEST_METHOD'} || '') ne 'POST') &&
	&usage("--api-key is only available in a remote API POST request");
$list && !$master &&
	&usage("--list is only available to the master administrator");
my $user = $master ? $target_user : ($base_remote_user || $remote_user);
$master || defined($user) || &usage("The current user could not be determined");
my $who = defined($user) ? "Webmin user $user" : "the master administrator";

if ($list) {
	# List every configured user without revealing any key
	my @accounts = &list_ai_accounts();
	@accounts || print "No AI settings are saved\n";
	foreach my $account (@accounts) {
		my $info = &get_ai_provider($account->{'provider'});
		print $account->{'user'} eq '' ? "master" : $account->{'user'}, "\n";
		print "    Provider: $account->{'provider'}\n";
		print "    Model: ", ($account->{'model'} || $info->{'model'} || ''), "\n";
		print "    API URL: ", ($account->{'url'} || $info->{'url'} || ''), "\n";
		print "    API key: ", &mask_ai_key($account->{'key'}), "\n";
		}
	exit(0);
	}
if ($remove) {
	print &delete_ai_account($user) ?
		"Removed the AI settings for $who\n" :
		"No AI settings were saved for $who\n";
	exit(0);
	}
if ($show) {
	&show_ai_account($user, $who);
	exit(0);
	}

# Reuse saved values only when the provider stays the same
my $existing = &get_ai_account($user);
my $provider = $given{'provider'} ||
	       ($existing ? $existing->{'provider'} : undef);
$provider || &usage("Missing --provider; choose one of ".
		    join(', ', &list_ai_providers()));
my $info = &get_ai_provider($provider) ||
	&usage("Unknown AI provider $provider; choose one of ".
	       join(', ', &list_ai_providers()));
my $same = $existing && $existing->{'provider'} eq $provider;
if (!$master) {
	my $access_error = &virtualmin_ai_nonmaster_provider_error(
		$provider, exists($given{'url'}), $existing);
	$access_error && &usage($access_error);
	}
my $url = defined($given{'url'}) ? $given{'url'} :
	  $same ? $existing->{'url'} : '';
my $model = defined($given{'model'}) ? $given{'model'} :
	    $same ? $existing->{'model'} : '';
my $workspace = defined($given{'workspace'}) ? $given{'workspace'} :
		$same ? $existing->{'workspace'} : '';
if ($key_file) {
	my $error;
	($key, $error) = &virtualmin_ai_read_secret_file($key_file, 'API key');
	$error && &usage($error);
	}
elsif ($key_stdin) {
	# Read one key from standard input without echoing it
	$key = <STDIN>;
	defined($key) || &usage("No API key was given on standard input");
	$key =~ s/[\r\n]+$//;
	$key =~ s/^\s+|\s+$//g;
	}
elsif (!defined($key)) {
	$key = $same ? $existing->{'key'} : undef;
	}
if (!$key && !$info->{'optional_key'}) {
	&usage("Missing --api-key, --api-key-file or --api-key-stdin for the ".
	       "$provider provider");
	}
my $account = { 'provider' => $provider, 'model' => $model,
		'url' => $url, 'workspace' => $workspace, 'key' => $key };
my $error = &validate_ai_account($account);
$error && &usage($error);

# Verify the key and URL by requesting the provider's model list
if (!$no_verify) {
	my $curl = &has_command('curl');
	$curl || &usage("curl is required to verify the AI provider; ".
			"use --no-verify to skip");
	my ($models, $verify_error) = &virtualmin_ai_list_models(
		{ 'format' => $info->{'format'},
		  'url' => $url || $info->{'url'},
		  'model' => $model || $info->{'model'},
		  'workspace' => $workspace,
		  'key' => $key }, $curl);
	if ($verify_error) {
		$verify_error =~ s/\Q$key\E/[redacted]/g if ($key);
		$verify_error =~ s/[\x00-\x1f\x7f]+/ /g;
		print "Verification failed: $verify_error\n";
		exit(1);
		}
	my $chosen = $model || $info->{'model'};
	if (@$models && !grep { $_ eq $chosen } @$models) {
		print "Warning: the provider did not list the selected model $chosen\n";
		}
	}
$error = &save_ai_account($user, $account);
if ($error) {
	print "$error\n";
	exit(1);
	}
print "Saved the AI settings for $who\n";
&show_ai_account($user, $who);

# show_ai_account(user, who)
# Prints the saved settings with the key masked.
sub show_ai_account
{
my ($user, $who) = @_;
my $account = &get_ai_account($user);
if (!$account) {
	print "No AI settings are saved for $who\n";
	return;
	}
my $info = &get_ai_provider($account->{'provider'});
print "Provider: $account->{'provider'} ($info->{'desc'})\n";
print "Model: ", ($account->{'model'} || $info->{'model'} || ''), "\n";
print "API URL: ", ($account->{'url'} || $info->{'url'} || ''), "\n";
print "Workspace: $account->{'workspace'}\n" if ($account->{'workspace'});
print "API key: ", ($account->{'key'} ? &mask_ai_key($account->{'key'}) :
					 'none'), "\n";
}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Save AI provider settings for virtualmin-ai and remote-ai.cgi.\n";
print "\n";
print "virtualmin configure-ai [--user name]\n";
print "                        [--provider openai|anthropic|gemini|xai|deepseek|custom]\n";
print "                        [--model name]\n";
print "                        [--api-url url]\n";
print "                        [--api-key key (remote POST only) |\n";
print "                         --api-key-file file |\n";
print "                         --api-key-stdin]\n";
print "                        [--workspace id]\n";
print "                        [--no-verify]\n";
print "virtualmin configure-ai --show [--user name]\n";
print "virtualmin configure-ai --remove [--user name]\n";
print "virtualmin configure-ai --list\n";
exit(1);
}
