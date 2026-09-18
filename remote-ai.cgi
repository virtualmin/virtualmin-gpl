#!/usr/local/bin/perl
# Builds a remote.cgi plan from a natural-language request. This CGI never
# executes commands. The caller reviews the plan, then sends each step to
# remote.cgi using its own credentials. The usual remote API permission checks
# still apply when those steps run.
#
# Parameters:
#   request        The natural-language request (required)
#   have-password  Set to 1 if the caller will replace the password placeholder
#                  before running each affected step. Otherwise, this endpoint
#                  generates a password for each new account and returns it in
#                  generated.
#
# The response is always JSON with a status of plan, clarification or error.

$main::allow_rpc_only = 1;
package virtual_server;
use JSON::PP;
$trust_unknown_referers = 1;
require './virtual-server-lib.pl';
&ReadParse();
print "Content-type: application/json\n\n";
my $json = JSON::PP->new->canonical->pretty;
my $settings;

&can_use_virtualmin_ai() ||
	&ai_error("You are not allowed to use the AI planner", 'not-allowed');
my $master = &master_admin();
my $owner = $master ? undef : ($base_remote_user || $remote_user);
$master || defined($owner) ||
	&ai_error("The current user could not be determined", 'not-allowed');
my $who = $master ? 'the master administrator' : "Webmin user $owner";

# Validate the request text
my $prompt = $in{'request'};
$prompt = '' if (!defined($prompt));
$prompt =~ s/^\s+|\s+$//g;
$prompt ne '' || &ai_error("Missing request parameter", 'no-request');
length($prompt) <= 32768 ||
	&ai_error("The request is too long", 'request-too-long');
my $have_password = $in{'have-password'} ? 1 : 0;

# Load only this user's saved provider settings; never use environment keys
my $settings_error;
($settings, $settings_error) = &resolve_ai_settings($owner, { }, 0);
$settings_error && &ai_error($settings_error, 'settings');
if (!$settings->{'key'} && !$settings->{'optional_key'}) {
	&ai_error("No AI provider is configured for $who. ".
		  ($master ? "Run virtualmin-ai --configure first" :
		   "Run the configure-ai API command, or ask the master ".
		   "administrator to run virtualmin-ai --configure --user $owner"),
		  'no-api-key');
	}

# Allow only one provider request per account. Keeping this handle open holds
# the non-blocking lock until planning ends.
my ($request_lock, $lock_error) = &virtualmin_ai_request_lock($owner);
if ($lock_error) {
	my $code = $lock_error =~ /^Another / ? 'busy' : 'request-lock';
	&ai_error($lock_error, $code);
	}
my $curl = &has_command('curl');
$curl || &ai_error("curl is not installed on this system", 'no-curl');

# Show the planner only commands registered for non-master remote use.
# remote.cgi still checks the target domain and the user's exact permissions
# when the client runs each step.
my $command_info = &list_ai_command_info(
	$master ? undef : sub { &can_remote($_[0]) });
%$command_info ||
	&ai_error("No Virtualmin commands are available to plan for $who",
		  'no-commands');

my ($result, $plan_error) = &virtualmin_ai_plan($settings, $command_info,
	$prompt, { 'remote' => 1, 'placeholder' => $have_password }, $curl);
$plan_error && &ai_error($plan_error, 'provider');
if ($result->{'clarification'}) {
	print $json->encode({ 'status' => 'clarification',
			      'question' => $result->{'clarification'} });
	exit(0);
	}

# Convert each password slot to a remote.cgi --pass value. Use either the
# caller's placeholder or a generated password returned with the plan.
my $plan = $result->{'plan'};
my @generated;
foreach my $slot (@{$plan->{'passwords'}}) {
	my $arguments = $plan->{'commands'}->[$slot->{'step'}]->{'arguments'};
	my $position = $slot->{'position'};
	$arguments->[$position] = '--pass' if ($slot->{'option'} eq '--passfile');
	if ($slot->{'source'} eq 'placeholder') {
		$arguments->[$position + 1] = $virtualmin_ai_password_placeholder;
		}
	elsif ($slot->{'source'} eq 'generated') {
		$arguments->[$position + 1] = $slot->{'value'};
		push(@generated, { 'step' => $slot->{'step'} + 1,
				   'account' => $slot->{'account'},
				   'password' => $slot->{'value'} });
		}
	}

# Convert every validated argument array to remote.cgi parameters
my @steps;
foreach my $step (@{$plan->{'commands'}}) {
	my ($params, $error) = &virtualmin_ai_step_params($step->{'arguments'});
	$error && &ai_error("The plan cannot be expressed as remote.cgi ".
			    "parameters: $error", 'provider');
	push(@steps, {
		'program' => $step->{'command'},
		'params' => $params,
		'reason' => $step->{'reason'},
		'destructive' => &virtualmin_ai_destructive_command(
			$step->{'command'}, $step->{'arguments'}) ?
			JSON::PP::true : JSON::PP::false,
		});
	}
my $output = { 'status' => 'plan',
	       'summary' => $plan->{'summary'},
	       'steps' => \@steps };
$output->{'placeholder'} = $virtualmin_ai_password_placeholder
	if ($have_password);
$output->{'generated'} = \@generated if (@generated);
print $json->encode($output);

# ai_error(message, code)
# Prints a JSON error, redacts the configured key and exits.
sub ai_error
{
my ($message, $code) = @_;
$message ||= 'Unknown error';
if ($settings && $settings->{'key'}) {
	$message =~ s/\Q$settings->{'key'}\E/[redacted]/g;
	}
$message =~ s/[\x00-\x1f\x7f]+/ /g;
print $json->encode({ 'status' => 'error', 'code' => $code || 'error',
		      'error' => $message });
exit(0);
}
