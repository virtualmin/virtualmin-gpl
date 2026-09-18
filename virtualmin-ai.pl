#!/usr/local/bin/perl

=head1 virtualmin-ai.pl

Plan and run Virtualmin commands from a natural-language request

This command sends a natural-language request and current Virtualmin command
help to an AI provider. The provider returns a structured plan. Virtualmin
rejects any command or option that is not installed and allowed on the local
system. Model output is never passed to a shell.

GPL installations can create and list virtual servers and users. Virtualmin Pro
also enables commands that have already been audited for use through the remote
API. The exact commands still depend on what is installed on the system.

Supported providers are OpenAI, Anthropic Claude, Google Gemini, xAI Grok,
DeepSeek and OpenAI-compatible servers such as Ollama and LM Studio. Run
C<--configure> to choose a provider, API key and model. Virtualmin saves these
settings in files readable only by root. Use C<--user> to save settings for
another Webmin user so C<remote-ai.cgi> can plan for that user.

Interactive configuration shows numbered provider and model lists. A model can
also be entered by name. Before saving, Virtualmin checks the key and sends a
small structured request to the model. C<--no-verify> skips both checks. For
scripts, pass C<--provider>, C<--model>, C<--api-url> and C<--workspace>
directly, and read the key from C<--api-key-file> or C<--api-key-stdin>.
C<--show> displays saved settings with the key masked. C<--remove> deletes the
settings.

For a single run, C<--provider>, C<--model>, C<--api-url> and C<--api-key-file>
override the saved settings, as do the C<VIRTUALMIN_AI_PROVIDER>,
C<VIRTUALMIN_AI_MODEL>, C<VIRTUALMIN_AI_API_URL> and provider key environment
variables such as C<OPENAI_API_KEY>. A key file must be owned by root and
inaccessible to group and other users. An Anthropic key not scoped to a
workspace also needs C<--workspace> or C<ANTHROPIC_WORKSPACE_ID>.

Virtualmin displays the plan and asks for confirmation before running it.
C<--plan> displays the plan without running it. C<--yes> runs it without asking.

C<--yes> is only for trusted automation. It skips human review and runs the
validated plan as root. Although command and option names are restricted,
documented Virtualmin options may read or modify any file path available to
root. Do not use C<--yes> with requests copied from an untrusted source.

A request does not need to include passwords for new virtual servers or users.
Virtualmin generates a separate random password for each new account and shows
it once after execution. C<--password-file> instead uses one password from a
root-owned file readable only by root for every new account in the plan. A
password written in the request is used exactly as written and is sent to the
provider with the rest of the request. Passwords are passed to Virtualmin
commands through private files, never as command-line values.

For example:

  virtualmin-ai --configure
  virtualmin-ai "Create artists.example with a 512 MB owner quota"
  virtualmin-ai --password-file /root/new-domain.pass \
    "Create artists.example and a mailbox for joe"

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
	$0 = "$pwd/virtualmin-ai.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "virtualmin-ai must be run as root\n";
	}
use Text::Wrap ();

my ($plan_only, $assume_yes, $configure, $show, $remove, $no_verify);
my ($api_key_file, $api_key_stdin, $password_file, $target_user);
my %overrides;
my @prompt;
while (@ARGV) {
	my $arg = shift(@ARGV);
	if ($arg eq '--plan') {
		$plan_only = 1;
		}
	elsif ($arg eq '--yes') {
		$assume_yes = 1;
		}
	elsif ($arg eq '--configure') {
		$configure = 1;
		}
	elsif ($arg eq '--show') {
		$show = 1;
		}
	elsif ($arg eq '--remove') {
		$remove = 1;
		}
	elsif ($arg eq '--no-verify') {
		$no_verify = 1;
		}
	elsif ($arg eq '--user') {
		$target_user = shift(@ARGV);
		defined($target_user) || &usage("Missing value for --user");
		}
	elsif ($arg eq '--provider') {
		$overrides{'provider'} = shift(@ARGV);
		defined($overrides{'provider'}) ||
			&usage("Missing value for --provider");
		}
	elsif ($arg eq '--api-key-file') {
		$api_key_file = shift(@ARGV);
		defined($api_key_file) || &usage("Missing value for --api-key-file");
		}
	elsif ($arg eq '--api-key-stdin') {
		$api_key_stdin = 1;
		}
	elsif ($arg eq '--password-file') {
		$password_file = shift(@ARGV);
		defined($password_file) || &usage("Missing value for --password-file");
		}
	elsif ($arg eq '--api-url') {
		$overrides{'url'} = shift(@ARGV);
		defined($overrides{'url'}) || &usage("Missing value for --api-url");
		}
	elsif ($arg eq '--model') {
		$overrides{'model'} = shift(@ARGV);
		defined($overrides{'model'}) || &usage("Missing value for --model");
		}
	elsif ($arg eq '--workspace') {
		$overrides{'workspace'} = shift(@ARGV);
		defined($overrides{'workspace'}) ||
			&usage("Missing value for --workspace");
		}
	elsif ($arg eq '--help') {
		&usage();
		}
	else {
		push(@prompt, $arg, @ARGV);
		last;
		}
	}
$plan_only && $assume_yes && &usage("--plan and --yes cannot be used together");
if ($overrides{'provider'} && !&get_ai_provider($overrides{'provider'})) {
	&usage("Unknown AI provider $overrides{'provider'}; choose one of ".
	       join(', ', &list_ai_providers()));
	}
if (defined($overrides{'url'})) {
	my $url_error = &virtualmin_ai_validate_api_url($overrides{'url'});
	$url_error && &usage($url_error);
	}
if (defined($overrides{'model'}) && !&valid_model_name($overrides{'model'})) {
	&usage("Invalid model name");
	}
if (defined($overrides{'workspace'}) && $overrides{'workspace'} ne '' &&
    $overrides{'workspace'} !~ /^[a-zA-Z0-9_\-]{1,128}$/) {
	&usage("Invalid workspace ID");
	}
$api_key_file && $api_key_stdin &&
	&usage("--api-key-file and --api-key-stdin cannot be used together");

# Manage the root-only settings shared with configure-ai and remote-ai.cgi
if ($configure || $show || $remove) {
	@prompt && &usage("A request cannot be combined with a settings action");
	$password_file && &usage("--password-file is only used when running a request");
	($configure && $remove) && &usage("--configure and --remove cannot be used together");
	&check_webmin_user($target_user) if (defined($target_user));
	my $who = defined($target_user) ? "Webmin user $target_user" :
					  "the master administrator (root)";
	if ($remove) {
		print &delete_ai_account($target_user) ?
			"Removed the AI settings for $who\n" :
			"No AI settings were saved for $who\n";
		exit(0);
		}
	if ($show) {
		&show_ai_account($target_user, $who);
		exit(0);
		}
	&configure_ai_account($target_user, $who, \%overrides, $api_key_file,
			      $api_key_stdin, $no_verify);
	exit(0);
	}
defined($target_user) && &usage("--user is only used with --configure, --show or --remove");
$no_verify && &usage("--no-verify is only used with --configure");
$api_key_stdin && &usage("--api-key-stdin is only used with --configure");

my $prompt = join(' ', @prompt);
if (!$prompt) {
	-t STDIN && &usage("Missing natural-language request");
	local $/;
	$prompt = <STDIN>;
	}
$prompt =~ s/^\s+|\s+$//g;
$prompt || &usage("Missing natural-language request");
length($prompt) <= 32768 || &usage("The request is too long");

# Command-line flags win over environment variables, which win over the saved
# master settings and the provider defaults.
if ($api_key_file) {
	$overrides{'key'} = &read_secret_file($api_key_file, 'API key');
	}
my ($settings, $settings_error) = &resolve_ai_settings(undef, \%overrides, 1);
$settings_error && &usage($settings_error);
my $provider_info = &get_ai_provider($settings->{'provider'});
if (!$settings->{'key'} && !$settings->{'optional_key'}) {
	&usage("No API key is available for the $settings->{'provider'} provider. ".
	       "Run virtualmin-ai --configure, set $provider_info->{'env'}, ".
	       "or use --api-key-file");
	}
my $api_key = $settings->{'key'};
# Read a supplied password before contacting the provider. One bad file then
# stops the request early, and one valid value applies to every new account.
my $password = $password_file ?
	&read_secret_file($password_file, 'password') : undef;
my $curl = &has_command('curl');
$curl || &usage("curl is required to contact the AI provider");

# Give the model only commands allowed by this edition and installed locally
my $command_info = &list_ai_command_info();
%$command_info || die "No commands are available to virtualmin-ai\n";
my ($result, $plan_error) = &virtualmin_ai_plan($settings, $command_info,
	$prompt, { 'password' => $password }, $curl);
$plan_error && &provider_error($plan_error, $api_key);
if ($result->{'clarification'}) {
	print "Clarification needed: $result->{'clarification'}\n";
	exit(2);
	}
my $plan = $result->{'plan'};

print $plan->{'summary'}, "\n" if ($plan->{'summary'});
for (my $i = 0; $i < @{$plan->{'commands'}}; $i++) {
	my $step = $plan->{'commands'}->[$i];
	my $number = $i + 1;
	print "$number. ".&virtualmin_ai_display_step($plan, $i, $password_file)."\n";
	print "   $step->{'reason'}\n" if ($step->{'reason'});
	}
my @generated = grep { $_->{'source'} eq 'generated' } @{$plan->{'passwords'}};
print "Virtualmin will generate a password for each new account and show it ".
      "once after execution.\n" if (@generated);
exit(0) if ($plan_only);

print STDERR &virtualmin_ai_unattended_warning(), "\n" if ($assume_yes);

if (!$assume_yes) {
	-t STDIN || die "Refusing to execute without a terminal; use --yes or --plan\n";
	print "Run these commands? [y/N] ";
	my $answer = <STDIN>;
	$answer =~ /^y(?:es)?\s*$/i || do {
		print "No commands were run.\n";
		exit(0);
		};
	}

# Provider credentials must not be inherited by Virtualmin API commands.
delete($ENV{$_}) foreach (&virtualmin_ai_provider_env_names(),
			  'VIRTUALMIN_AI_API_KEY');
my $api_helper = &get_api_helper_command() || 'virtualmin';
my ($status, $failed_index, $failed_step, $run_error) =
	&virtualmin_ai_execute_plan($plan, $api_helper);
# Show passwords for attempted steps even after a partial failure
my @ran = grep { !defined($failed_index) || $_->{'step'} < $failed_index }
	       @generated;
if (@ran) {
	print "\nGenerated passwords, shown once:\n";
	foreach my $slot (@ran) {
		printf "  %-40s %s\n", $slot->{'account'} ||
			$plan->{'commands'}->[$slot->{'step'}]->{'command'},
			$slot->{'value'};
		}
	}
if ($status) {
	die "Command $failed_index ($failed_step->{'command'}) failed".
	    ($run_error ? ": $run_error" : " with status $status")."\n";
	}
print "All Virtualmin commands completed successfully.\n";
exit(0);

# configure_ai_account(user, who, &overrides, key-file, key-stdin, no-verify)
# Selects and verifies a provider, API key and model, then saves them for the
# master administrator or another Webmin user. Command-line values skip their
# matching interactive step.
sub configure_ai_account
{
my ($user, $who, $overrides, $key_file, $key_stdin, $no_verify) = @_;
my $interactive = -t STDIN && -t STDOUT ? 1 : 0;
my $existing = &get_ai_account($user) || { };
my $curl = &has_command('curl');
$no_verify || $curl || &usage("curl is required to check the AI provider; ".
			      "use --no-verify to skip");
local $| = 1;
local $SIG{'INT'} = \&cancelled;

# Show the account being configured and its current settings
print "Virtualmin AI - settings for $who\n";
if ($existing->{'provider'}) {
	print "Current: ".&account_summary($existing)."\n";
	}
else {
	print "No settings are saved yet.\n";
	}

# Step 1: choose the provider and any custom server URL
my $provider = $overrides->{'provider'};
if (!$provider) {
	$interactive || &usage("Missing --provider; choose one of ".
			       join(', ', &list_ai_providers()));
	print "\nStep 1 of 3: Provider\n";
	$provider = &ask_ai_provider($existing->{'provider'});
	}
my $info = &get_ai_provider($provider);
my $same = ($existing->{'provider'} || '') eq $provider;
my $url = $overrides->{'url'};
if (!defined($url)) {
	my $default = $same && $existing->{'url'} ? $existing->{'url'} :
						    $info->{'url'};
	if ($info->{'url'}) {
		$url = $default;
		}
	elsif ($interactive) {
		&say("Enter the server's chat completions endpoint, for example ".
		     "http://localhost:11434/v1/chat/completions.");
		while (1) {
			$url = &ask("API URL", $default);
			my $url_error = &virtualmin_ai_validate_api_url($url);
			last if (!$url_error);
			print "[failed] $url_error\n";
			}
		}
	else {
		&usage("Missing --api-url for the $provider provider");
		}
	}
my $url_error = &virtualmin_ai_validate_api_url($url);
$url_error && &usage($url_error);

# Step 2: verify the API key and load the model list for the next step
my $saved_key = $same ? $existing->{'key'} : undef;
my $workspace = defined($overrides->{'workspace'}) ? $overrides->{'workspace'} :
		$same ? ($existing->{'workspace'} || '') : '';
my $key;
my $given;
if ($key_file) {
	$key = &read_secret_file($key_file, 'API key');
	$given = 1;
	}
elsif ($key_stdin) {
	$key = &read_key_stdin();
	$given = 1;
	}
elsif (!$interactive) {
	$key = $saved_key;
	$given = 1;
	}
$given && !$key && !$info->{'optional_key'} &&
	&usage("An API key is required; use --api-key-file or --api-key-stdin");
print "\nStep 2 of 3: API key\n" if ($interactive);
my $models = [ ];
while (1) {
	if (!$given) {
		if ($saved_key) {
			&say("A saved key ".&mask_ai_key($saved_key)." exists. Press Enter ".
			     "to keep it, or enter a new key. Your input is hidden.");
			}
		elsif ($info->{'optional_key'}) {
			&say("This local server does not require a key. Press Enter to ".
			     "continue without one. Your input is hidden.");
			}
		else {
			&say("Enter the key from your $info->{'desc'} account. ".
			     "Your input is hidden.");
			}
		my $typed = &ask_hidden("Key");
		$typed =~ /[\x00-\x1f\x7f]/ &&
			&usage("The API key contains invalid characters");
		$key = $typed ne '' ? $typed : $saved_key;
		if (!$key && !$info->{'optional_key'}) {
			print "[failed] An API key is required.\n";
			next;
			}
		}
	if ($no_verify) {
		print "[skipped] The key was not checked.\n" if ($interactive);
		last;
		}
	my $error;
	print "Checking the key with $info->{'desc'} ... " if ($interactive);
	($models, $error) = &virtualmin_ai_list_models(
		{ 'format' => $info->{'format'}, 'url' => $url, 'key' => $key,
		  'workspace' => $workspace }, $curl);
	if (!$error) {
		print "[ok] Key accepted. Models available: ".scalar(@$models).".\n"
			if ($interactive);
		last;
		}
	$error = &clean_error($error, $key);
	$interactive || die "Verification failed: $error\n";
	print "[failed] $error\n";
	if ($provider eq 'anthropic' && !$workspace && $error =~ /workspace/i) {
		# Ask for the workspace required by this Anthropic key
		&say("This Anthropic key requires a workspace ID.");
		$workspace = &ask("Workspace ID", '');
		$workspace =~ /^[a-zA-Z0-9_\-]{1,128}$/ ||
			&usage("Invalid workspace ID");
		next;
		}
	$given && exit(1);
	}

# Step 3: choose a model from the provider's list or enter its name
my $default = $same && $existing->{'model'} ? $existing->{'model'} :
						$info->{'model'};
my $model = $overrides->{'model'};
print "\nStep 3 of 3: Model\n" if ($interactive && !defined($model));
while (1) {
	if (!defined($model) || $model eq '') {
		if ($interactive && @$models) {
			$model = &ask_ai_model($provider, $models, $default);
			}
		elsif ($interactive) {
			$model = &ask("Model", $default);
			}
		elsif ($default) {
			$model = $default;
			}
		else {
			&usage("Missing --model for the $provider provider");
			}
		}
	if (!&valid_model_name($model)) {
		$interactive || &usage("Invalid model name");
		print "[failed] Invalid model name.\n";
		$overrides->{'model'} && exit(1);
		$model = undef;
		next;
		}
	if (@$models && !grep { $_ eq $model } @$models) {
		print "[warning] The provider did not list the selected model $model.\n";
		}
	last if ($no_verify);
	# A small structured request checks that the model answers in the expected
	# format before the settings are saved
	print "\nTesting $model ... " if ($interactive);
	my ($seconds, $error) = &virtualmin_ai_test_model(
		{ 'format' => $info->{'format'}, 'url' => $url, 'key' => $key,
		  'workspace' => $workspace, 'model' => $model,
		  'request_options' => $info->{'request_options'} }, $curl);
	if (!$error) {
		printf "[ok] Replied in %.1f s\n", $seconds if ($interactive);
		last;
		}
	$error = &clean_error($error, $key);
	$interactive || die "Test request to $model failed: $error\n";
	print "[failed] $error\n";
	$overrides->{'model'} && exit(1);
	$model = undef;
	}

# Show the new settings, then save them
my $account = {
	'provider' => $provider,
	'model' => $model,
	'url' => $info->{'url'} && $url eq $info->{'url'} ? '' : $url,
	'workspace' => $workspace,
	'key' => $key,
	};
my $error = &validate_ai_account($account);
$error && &usage($error);
print "\nSummary\n";
&print_account_rows($account, $existing);
my $file = &ai_account_file($user);
if ($interactive) {
	print "\n";
	my $answer = &ask("Save to $file? [Y/n]");
	if ($answer !~ /^(y(?:es)?)?$/i) {
		print "Not saved.\n";
		exit(0);
		}
	}
$error = &save_ai_account($user, $account);
$error && die "$error\n";
print "[ok] Saved.\n";
return if (!$interactive);

# Show one next command and the equivalent non-interactive configuration
my $flags = "--provider $provider --model $model";
$flags .= " --api-url $url" if ($account->{'url'});
$flags .= " --workspace $workspace" if ($workspace);
$flags = "--user $user $flags" if (defined($user));
print "\nTry it:      virtualmin-ai ".(defined($user) ?
	"--show --user $user" : "\"Create example.com with a 1 GB quota\"")."\n";
print "Scriptable:  virtualmin-ai --configure $flags".
      ($key ? " \\\n               --api-key-stdin" : '')."\n";
}

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
print "Virtualmin AI - settings for $who\n";
&print_account_rows($account);
}

# print_account_rows(&account, [&previous])
# Prints aligned settings and notes changes from the previous values.
sub print_account_rows
{
my ($account, $previous) = @_;
my $info = &get_ai_provider($account->{'provider'});
my $previous_info = $previous && $previous->{'provider'} ?
	&get_ai_provider($previous->{'provider'}) : undef;
my @rows = (
	[ 'Provider', $info->{'desc'},
	  $previous_info ? $previous_info->{'desc'} : undef ],
	[ 'Model', $account->{'model'} || $info->{'model'},
	  $previous_info ? $previous->{'model'} || $previous_info->{'model'} : undef ],
	[ 'API URL', $account->{'url'} || $info->{'url'},
	  $previous_info ? $previous->{'url'} || $previous_info->{'url'} : undef ],
	);
push(@rows, [ 'Workspace', $account->{'workspace'},
	      $previous ? $previous->{'workspace'} : undef ])
	if ($account->{'workspace'} || ($previous && $previous->{'workspace'}));
push(@rows, [ 'API key', $account->{'key'} ? &mask_ai_key($account->{'key'}) : 'none',
	      $previous_info ? ($previous->{'key'} ? &mask_ai_key($previous->{'key'}) : 'none')
			     : undef ]);
my $width = 0;
foreach my $row (@rows) {
	$width = length($row->[1]) if (length($row->[1] || '') > $width);
	}
$width = 40 if ($width > 40);
foreach my $row (@rows) {
	my ($label, $value, $old) = @$row;
	$value = '' if (!defined($value));
	my $note = '';
	if ($previous_info) {
		$old = '' if (!defined($old));
		$note = $old eq $value ? '(unchanged)' :
			$old ne '' ? "(was $old)" : '(new)';
		}
	my $line = sprintf("  %-10s %s", $label, $value);
	$line .= (' ' x ($width - length($value)))."  $note" if ($note ne '');
	print "$line\n";
	}
}

# account_summary(&account)
# Returns the provider, model and masked key on one line.
sub account_summary
{
my ($account) = @_;
my $info = &get_ai_provider($account->{'provider'});
return join(' / ', $info->{'desc'},
	    $account->{'model'} || $info->{'model'} || 'default model',
	    $account->{'key'} ? "key ".&mask_ai_key($account->{'key'}) : 'no key');
}

# check_webmin_user(name)
# Exits unless the name is an existing Webmin user.
sub check_webmin_user
{
my ($name) = @_;
&virtualmin_ai_webmin_user_exists($name) ||
	&usage("Webmin user $name does not exist");
}

# ask_ai_provider(current)
# Lists providers by number and returns the chosen ID. Enter keeps the current
# provider.
sub ask_ai_provider
{
my ($current) = @_;
my @ids = &list_ai_providers();
my @labels;
my $width = 0;
foreach my $id (@ids) {
	my $info = &get_ai_provider($id);
	my $label = $info->{'desc'}.
		    ($info->{'hint'} ? " ($info->{'hint'})" : '');
	push(@labels, $label);
	$width = length($label) if (length($label) > $width);
	}
my $default_number = 1;
for (my $i = 0; $i < @ids; $i++) {
	my $current_here = $ids[$i] eq ($current || '');
	$default_number = $i + 1 if ($current_here);
	print &menu_line($i + 1, 1, $labels[$i], $width,
			 $current_here ? "* current" : '');
	}
while (1) {
	my $answer = &ask("Choose", $default_number);
	return $ids[$answer - 1] if ($answer =~ /^\d+$/ && $answer >= 1 &&
				     $answer <= @ids);
	# Also accept a provider ID directly
	return $answer if (&get_ai_provider($answer));
	print "[failed] Enter a number from 1 to ".scalar(@ids).".\n";
	}
}

# ask_ai_model(provider, &models, current)
# Lists the provider's recommended and chat models, then returns the selected
# name. Part of a name filters the list, "all" includes hidden models and
# "more" shows the next page.
sub ask_ai_model
{
my ($provider, $models, $current) = @_;
my ($entries, $hidden_note) = &virtualmin_ai_model_groups($provider, $models);
my %state = ( 'all' => 0, 'filter' => '', 'offset' => 0, 'limit' => 10 );
while (1) {
	my $page = &virtualmin_ai_model_page($entries, \%state);
	my @shown = @{$page->{'shown'}};

	# Describe the current list and the available filters
	my $what = $state{'all'} ? 'models' : 'chat models';
	my $intro = $state{'filter'} ne '' ?
		"Showing $page->{'total'} $what matching \"$state{'filter'}\"." :
		"Showing $page->{'total'} $what.";
	if ($page->{'hidden'}) {
		my $noun = $page->{'hidden'} == 1 ? 'model' : 'models';
		$intro .= " $page->{'hidden'} $noun hidden".
			  ($hidden_note ? " ($hidden_note)" : '').".";
		}
	my @can;
	push(@can, "\"all\" to include hidden models") if ($page->{'hidden'});
	push(@can, "part of a model name to filter");
	push(@can, "\"clear\" to remove the filter") if ($state{'filter'} ne '');
	&say("$intro Type ".join(', or ', @can).".");
	if (!@shown) {
		# Offer to use an unmatched filter as an exact model name
		my $answer = &ask("Use \"$state{'filter'}\" as the model name anyway? [y/N]");
		return $state{'filter'} if ($answer =~ /^y(?:es)?$/i);
		$state{'filter'} = '';
		next;
		}

	# Keep model numbers stable across pages
	print "\n";
	my $width = 0;
	foreach my $entry (@shown) {
		$width = length($entry->{'id'}) if (length($entry->{'id'}) > $width);
		}
	$width = 40 if ($width > 40);
	my ($group, $default_number) = ('', undef);
	my $digits = length($page->{'offset'} + @shown);
	for (my $i = 0; $i < @shown; $i++) {
		my $entry = $shown[$i];
		if ($entry->{'group'} ne $group) {
			$group = $entry->{'group'};
			print "  $group\n";
			}
		my $number = $page->{'offset'} + $i + 1;
		my $current_here = $entry->{'id'} eq ($current || '');
		$default_number = $number if ($current_here);
		print &menu_line($number, $digits, $entry->{'id'}, $width,
				 $entry->{'note'} ? $entry->{'note'} :
				 $current_here ? '* current' : '');
		}
	print "  ... $page->{'remaining'} more, type \"more\" to see them\n"
		if ($page->{'remaining'} > 0);

	# Keep the current model as the default even when it is off this page
	my $default = defined($default_number) ? $default_number :
		      $current && &valid_model_name($current) ? $current :
		      $page->{'offset'} + 1;
	my $answer = &ask("Choose a number or name", $default);
	if ($answer =~ /^\d+$/) {
		my $all = &virtualmin_ai_model_page($entries,
			{ %state, 'offset' => 0, 'limit' => $page->{'total'} });
		return $all->{'shown'}->[$answer - 1]->{'id'}
			if ($answer >= 1 && $answer <= $page->{'total'});
		print "[failed] Enter a number from 1 to $page->{'total'}.\n";
		}
	elsif (lc($answer) eq 'all') {
		$state{'all'} = 1;
		$state{'offset'} = 0;
		}
	elsif (lc($answer) eq 'more') {
		$state{'offset'} += $state{'limit'} if ($page->{'remaining'} > 0);
		}
	elsif (lc($answer) eq 'clear') {
		$state{'filter'} = '';
		$state{'offset'} = 0;
		}
	elsif (grep { $_->{'id'} eq $answer } @$entries) {
		return $answer;
		}
	else {
		$state{'filter'} = $answer;
		$state{'offset'} = 0;
		}
	print "\n";
	}
}

# menu_line(number, digits, label, width, note)
# Formats one numbered entry, with the note in a column after the label.
sub menu_line
{
my ($number, $digits, $label, $width, $note) = @_;
my $line = sprintf("  %*d) %s", $digits, $number, $label);
$line .= (' ' x ($width - length($label)))."  $note"
	if (defined($note) && $note ne '');
return "$line\n";
}

# say(text)
# Prints one paragraph wrapped to the usual terminal width.
sub say
{
my ($text) = @_;
local $Text::Wrap::columns = 72;
print Text::Wrap::wrap('', '', $text), "\n";
}

# ask(prompt, [default])
# Asks for one visible value on the terminal. Enter returns the default.
sub ask
{
my ($prompt, $default) = @_;
print $prompt.(defined($default) && $default ne '' ? " [$default]" : '').
      ($prompt =~ /\]$/ ? ' ' : ': ');
my $answer = <STDIN>;
defined($answer) || &cancelled();
$answer =~ s/^\s+|\s+$//g;
return $answer eq '' && defined($default) ? $default : $answer;
}

# ask_hidden(prompt)
# Asks for one value with terminal echo disabled.
my $echo_off;
sub ask_hidden
{
my ($prompt) = @_;
my $stty = &has_command('stty');
print "$prompt: ";
if ($stty) {
	system($stty, '-echo');
	$echo_off = $stty;
	}
my $answer = <STDIN>;
if ($stty) {
	system($stty, 'echo');
	$echo_off = undef;
	}
print "\n";
defined($answer) || &cancelled();
$answer =~ s/[\r\n]+$//;
$answer =~ s/^\s+|\s+$//g;
return $answer;
}

# cancelled()
# Restores terminal echo and exits without saving.
sub cancelled
{
system($echo_off, 'echo') if ($echo_off);
print "\nCancelled, nothing was saved.\n";
exit(1);
}

# valid_model_name(name)
# Returns 1 for a model name that is safe to save and send.
sub valid_model_name
{
my ($name) = @_;
return defined($name) && $name =~ /^[a-z0-9][a-z0-9._:\/\-]{0,127}$/i ? 1 : 0;
}

# read_key_stdin()
# Reads an API key piped on standard input.
sub read_key_stdin
{
my $line = <STDIN>;
defined($line) || &usage("No API key was given on standard input");
$line =~ s/[\r\n]+$//;
$line =~ s/^\s+|\s+$//g;
$line !~ /[\x00-\x1f\x7f]/ || &usage("The API key contains invalid characters");
return $line;
}

# read_secret_file(path, label)
# Reads one bounded, non-empty secret without printing it, or exits.
sub read_secret_file
{
my ($path, $label) = @_;
my ($value, $error) = &virtualmin_ai_read_secret_file($path, $label);
$error && &usage($error);
return $value;
}

# clean_error(message, key)
# Makes a provider error safe to print, with the key redacted.
sub clean_error
{
my ($message, $key) = @_;
$message ||= 'Unknown AI provider error';
$message =~ s/\Q$key\E/[redacted]/g if ($key);
$message =~ s/[\x00-\x1f\x7f]+/ /g;
$message =~ s/^\s+|\s+$//g;
return $message;
}

# provider_error(message, key)
# Exits with a provider error, redacting the configured key if a provider
# happens to echo it.
sub provider_error
{
my ($message, $key) = @_;
die &clean_error($message, $key)."\n";
}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
print "Build and run a Virtualmin command plan from a natural-language request.\n\n";
print "virtualmin-ai [--plan | --yes]\n";
print "              [--provider name] [--model name] [--api-url url]\n";
print "              [--api-key-file file] [--workspace id]\n";
print "              [--password-file file]\n";
print "              \"request\"\n\n";
print "virtualmin-ai --configure [--user name]\n";
print "              [--provider name] [--model name] [--api-url url]\n";
print "              [--api-key-file file | --api-key-stdin] [--workspace id]\n";
print "              [--no-verify]\n";
print "virtualmin-ai --show [--user name]\n";
print "virtualmin-ai --remove [--user name]\n\n";
print "Providers: ", join(', ', &list_ai_providers()), "\n";
exit(1);
}
