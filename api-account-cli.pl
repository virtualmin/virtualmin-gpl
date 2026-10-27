# Shared entry point for root-only API account commands. Load before Webmin.
package virtual_server;
use Cwd ();
use File::Basename ();
use File::Spec ();

# Reject HTTP and in-process dispatch before reading configuration or passwords.
# Both UIDs must be root; Webmin initialization must not promote a setuid caller.
if ($< != 0 || $> != 0 || $module_name ||
    $main::virtualmin_remote_api || $ENV{'VIRTUALMIN_REMOTE_API'} ||
    $ENV{'REQUEST_METHOD'} || $ENV{'GATEWAY_INTERFACE'} ||
    $ENV{'SCRIPT_NAME'} || $main::webmin_script_type eq 'web') {
	die "API account management is available only to root on the command line\n";
	}
# Keep the caller's directory so relative password paths still work.
my $api_account_cli_cwd = $ENV{'WRAPPER_ORIGINAL_PWD'} || Cwd::getcwd();
$main::no_acl_check++;
$ENV{'WEBMIN_CONFIG'} ||= '/etc/webmin';
$ENV{'WEBMIN_VAR'} ||= '/var/webmin';
chdir(File::Basename::dirname(__FILE__)) || die "Cannot enter module directory: $!\n";
# Webmin needs an absolute script path even when Perl was given a relative one.
$0 = Cwd::getcwd().'/'.File::Basename::basename($0);
require './virtual-server-lib.pl';

# api_account_cli(action, &args)
# Runs create, modify, delete or list. args is an argv arrayref.
# Returns after success or help; exits with status 1 on operation errors.
sub api_account_cli
{
my ($action, $args) = @_;
# Require root and a master role after Webmin loads, including for help.
$< == 0 && $> == 0 && !&is_remote_api_request() && &master_admin() ||
	die "API account management is available only to root on the command line\n";
if (grep { $_ eq '--help' } @$args) {
	# Show help before validating other options or reading a password.
	&api_account_cli_usage($action);
	return;
	}
eval {
	my $opts = &parse_api_account_cli($action, $args);
	if ($action eq 'list') {
		# Listing never returns password hashes or session data.
		&list_api_accounts_cli($opts);
		}
	else {
		# Changes use the same validation and account lock as the UI.
		if ($opts->{'passfile'} || $opts->{'pass_stdin'}) {
			# Read the password before taking the account lock.
			local *PASSFILE;
			my $fh = \*PASSFILE;
			if ($opts->{'pass_stdin'}) {
				# Pipes support automation without putting passwords in argv.
				$fh = \*STDIN;
				}
			else {
				# Relative files are relative to the shell, not the module root.
				my $file = File::Spec->rel2abs($opts->{'passfile'}, $api_account_cli_cwd);
				&open_readfile($fh, $file) || die "Cannot read password file: $!\n";
				}
			local $/;
			$opts->{'password'} = <$fh>;
			# Keep stdin open for the caller.
			close($fh) if (!$opts->{'pass_stdin'});
			# Treat an empty file or pipe as an empty password for validation.
			$opts->{'password'} = '' if (!defined($opts->{'password'}));
			# Accept one final line ending; embedded newlines remain invalid.
			$opts->{'password'} =~ s/\r?\n\z//;
			}
		# Callback(): merge changes under the account lock.
		my @changed = &save_api_access_accounts(sub {
			return &api_account_cli_params($action, $opts);
			});
		my %verbs = (create => 'created', modify => 'updated', delete => 'deleted');
		print "API account $_ $verbs{$action} successfully\n" foreach @changed;
		}
	};
if ($@) {
	# Return a nonzero status for scripts; never print the submitted options.
	print STDERR "ERROR: $@\n";
	exit(1);
	}
}

# parse_api_account_cli(action, &args)
# Parses an argv arrayref for create, modify, delete or list into a hashref.
# Rejects unknown flags and repeated scalar options; list options may repeat.
sub parse_api_account_cli
{
my ($action, $args) = @_;
# Map value options to the fields used when building the saved policy.
my %values = (name => 'name', desc => 'desc', passfile => 'passfile',
	command => 'commands', 'command-mode' => 'command_mode',
	domain => 'domains', 'domain-mode' => 'domain_mode',
	'allowed-template' => 'templates', 'template-mode' => 'template_mode',
	'default-template' => 'template', 'allowed-plan' => 'plans',
	'plan-mode' => 'plan_mode', 'default-plan' => 'plan');
# Opposite flags share a field so the parser can detect conflicting choices.
my %flags = (enable => ['enabled', 1], disable => ['enabled', 0],
	created => ['created', 1], 'no-created' => ['created', 0],
	'pass-stdin' => ['pass_stdin', 1], 'name-only' => ['nameonly', 1],
	multiline => ['multiline', 1]);
my %repeated = map { $_ => 1 } qw(commands domains templates plans);
my %opts;
# Copy the argument list so parsing does not consume the caller's argv.
my @args = @$args;
while (@args) {
	my $arg = shift(@args);
	$arg =~ s/^--// || die "Expected an option beginning with --\n";
	my ($key, $value);
	if ($values{$arg}) {
		# Values cannot consume the next switch accidentally.
		$key = $values{$arg};
		@args && $args[0] !~ /^--/ || die "Missing value for --$arg\n";
		$value = shift(@args);
		}
	elsif ($flags{$arg}) {
		# Opposite switches share a key so conflicting settings are rejected.
		($key, $value) = @{$flags{$arg}};
		}
	else {
		# Unknown flags must not silently leave a permission unchanged.
		die "Unknown option --$arg\n";
		}
	if ($action eq 'list' || $action eq 'delete') {
		# Listing and deletion accept no account-setting options.
		($key eq 'name' || $action eq 'list' &&
		 $key =~ /^(nameonly|multiline)$/) || die "--$arg is not valid for $action\n";
		}
	else {
		# Output-format flags apply only to listings.
		$key !~ /^(nameonly|multiline)$/ || die "--$arg is only valid for list\n";
		}
	if ($repeated{$key}) {
		# Each occurrence adds a selection; edits replace the saved list.
		push(@{$opts{$key}}, $value);
		}
	else {
		# Repeated scalar options usually indicate a scripting mistake.
		!exists($opts{$key}) || die "Repeated or conflicting option --$arg\n";
		$opts{$key} = $value;
		}
	}
# Check requirements that depend on the complete set of supplied options.
($action eq 'list' || $opts{'name'}) || die "Missing --name\n";
!($opts{'nameonly'} && $opts{'multiline'}) || die "Choose --name-only or --multiline\n";
!(exists($opts{'passfile'}) && $opts{'pass_stdin'}) ||
	die "Choose --passfile or --pass-stdin\n";
if (exists($opts{'passfile'})) {
	# Reject an empty path instead of silently keeping the old password.
	length($opts{'passfile'}) || die "Missing password filename\n";
	}
$action ne 'create' || $opts{'passfile'} || $opts{'pass_stdin'} ||
	die "Creating an account requires --passfile or --pass-stdin\n";
return \%opts;
}

# api_account_cli_params(action, &options)
# Builds complete form parameters under the account lock. Unspecified edit
# settings are preserved; names and IDs are resolved before shared validation.
# action is create, modify or delete. options is the parsed CLI hashref,
# with a password value added only when the caller supplied one.
sub api_account_cli_params
{
my ($action, $opts) = @_;
my ($user) = grep { $_->{'name'} eq $opts->{'name'} } &list_api_access_users();
my $p;
if ($action eq 'create') {
	# Match the UI defaults, with no commands granted until explicitly selected.
	$p = &default_api_access_policy();
	}
else {
	# Modify and delete only API accounts, never ordinary Webmin users.
	$user || die $text{'apiaccess_egone'}."\n";
	$p = $user->{'policy'};
	}
# Start with saved settings or creation defaults, then apply explicit options.
my %in = (new => $action eq 'create' ? 1 : 0, name => $opts->{'name'},
	old => $opts->{'name'}, id => $p->{'api_id'},
	delete => $action eq 'delete' ? 1 : 0,
	enabled => !$p->{'api_disabled'}, created => $p->{'api_created'},
	command_mode => 'include', commands => $p->{'api_commands'},
	template => $p->{'api_template'}, plan => $p->{'api_plan'},
	password_def => exists($opts->{'password'}) ? 0 : 1);
# Preserve omitted password, description and toggle settings.
foreach my $key (qw(password desc enabled created)) {
	$in{$key} = $opts->{$key} if (exists($opts->{$key}));
	}
# Deletion needs the account identity, not a valid command or resource list.
return \%in if ($action eq 'delete');
if (exists($opts->{'commands'}) || exists($opts->{'command_mode'})) {
	# A supplied mode uses only the new command list, even when it is empty.
	$in{'command_mode'} = exists($opts->{'command_mode'}) ? $opts->{'command_mode'} : 'include';
	my %keys = map { $_->{'key'} => 1 } &list_api_access_commands();
	my @keys;
	# Resolve names or provider keys to canonical command grants.
	foreach my $name (@{$opts->{'commands'} || []}) {
		my $entry = &get_api_access_command($name);
		my $key = $keys{$name} ? $name : $entry ? $entry->{'key'} : undef;
		$key || die "Unknown or terminal-only command: $name\n";
		push(@keys, $key);
		}
	$in{'commands'} = join(' ', @keys);
	}
# Resolve each scope independently. A supplied selection replaces its old list.
foreach my $kind ('domain', 'template', 'plan') {
	my $field = $kind.'s';
	my $mode = $kind.'_mode';
	my @items = &list_api_access_resources($kind);
	my $label = $kind eq 'domain' ? 'dom' : 'name';
	$in{$mode} = $p->{'api_'.$field} eq '*' ? 'all' : 'selected';
	$in{$field} = $p->{'api_'.$field} eq '*' ? '' : $p->{'api_'.$field};
	if (exists($opts->{$field}) || exists($opts->{$mode})) {
		# Lists select resources; mode-only requests allow all or select none.
		$in{$mode} = exists($opts->{$mode}) ? $opts->{$mode} : 'selected';
		$in{$mode} ne 'all' || !@{$opts->{$field} || []} ||
			die "Do not combine --$kind-mode all with a selection\n";
		$in{$field} = join(' ', map {
			&api_account_cli_resource($_, \@items, $label, $kind)
			} @{$opts->{$field} || []});
		}
	if ($kind ne 'domain' && exists($opts->{$kind})) {
		# Defaults use the same name-or-ID resolution as their allowed lists.
		$in{$kind} = &api_account_cli_resource($opts->{$kind}, \@items, $label, $kind);
		}
	}
return \%in;
}

# api_account_cli_resource(value, &items, label-key, kind)
# Resolves an exact ID or a unique display name, rejecting missing or ambiguous
# names. items is an arrayref of resource hashrefs; label-key names their
# display-name field. kind identifies the resource type in errors.
sub api_account_cli_resource
{
my ($value, $items, $label, $kind) = @_;
my @found = grep { $_->{'id'} eq $value } @$items;
# Prefer IDs so a numeric display name cannot shadow an existing resource ID.
@found = grep { $_->{$label} eq $value } @$items if (!@found);
@found == 1 || die "Unknown or ambiguous $kind: $value\n";
return $found[0]->{'id'};
}

# list_api_accounts_cli(&options)
# Prints account names, a summary table or policy details, without credentials.
# options is a hashref with optional name, nameonly and multiline fields.
# Without a name, lists all API accounts; without a format flag, prints a table.
sub list_api_accounts_cli
{
my ($opts) = @_;
my @users = sort { $a->{'name'} cmp $b->{'name'} } &list_api_access_users();
if (exists($opts->{'name'})) {
	# Report a missing account rather than returning an empty listing.
	@users = grep { $_->{'name'} eq $opts->{'name'} } @users;
	@users || die $text{'apiaccess_egone'}."\n";
	}
# Headings belong only to the default table, not script-friendly output.
printf "%-24s %-10s %s\n", 'Username', 'Status', 'Description'
	if (!$opts->{'nameonly'} && !$opts->{'multiline'});
foreach my $user (@users) {
	my $p = $user->{'policy'};
	my $status = $p->{'api_disabled'} ? 'Disabled' : 'Enabled';
	if ($opts->{'nameonly'}) {
		# Name-only output is suitable for shell loops.
		print "$user->{'name'}\n";
		}
	elsif ($opts->{'multiline'}) {
		# Include provider keys and resource IDs so policies can be inspected.
		print "$user->{'name'}\n";
		print "    Description: $user->{'real'}\n    Status: $status\n";
		foreach my $field (qw(id commands domains templates plans template plan created)) {
			print "    $field: $p->{'api_'.$field}\n";
			}
		}
	else {
		# Show full usernames; do not truncate identifiers in terminal output.
		printf "%-24s %-10s %s\n", $user->{'name'}, $status, $user->{'real'};
		}
	}
}

# api_account_cli_usage(action)
# Prints help for create, modify, delete or list, including applicable options.
sub api_account_cli_usage
{
my ($action) = @_;
my $command = $action eq 'list' ? 'list-api-accounts' : "$action-api-account";
# Align continuation lines with the first option, as in other CLI help.
my $indent = ' ' x length("virtualmin $command ");
print "Manage API accounts as root from the command line only.\n\n";
print "virtualmin $command ", $action eq 'list' ? '[--name username]' : '--name username', "\n";
if ($action eq 'list') {
	# Lists have no account-setting options.
	print $indent, "[--name-only | --multiline]\n";
	}
elsif ($action ne 'delete') {
	# Create and modify share the same permission and password options.
	print $indent, "[--desc text]\n";
	print $indent, "[--enable | --disable]\n";
	print $indent, "[--passfile path | --pass-stdin]\n";
	# Keep command and virtual server selection modes independent.
	print $indent, "[--command name]*\n";
	print $indent, "[--command-mode include|exclude|all]\n";
	print $indent, "[--domain name|id]*\n";
	print $indent, "[--domain-mode selected|all]\n";
	print $indent, "[--created | --no-created]\n";
	# Limit creation defaults to the allowed templates and plans.
	print $indent, "[--allowed-template name|id]*\n";
	print $indent, "[--template-mode selected|all]\n";
	print $indent, "[--default-template name|id]\n";
	print $indent, "[--allowed-plan name|id]*\n";
	print $indent, "[--plan-mode selected|all]\n";
	print $indent, "[--default-plan name|id]\n\n";
	# Explain creation defaults and how omitted options behave during edits.
	print "Creating an account requires --passfile or --pass-stdin.\n\n";
	print "New accounts use the API Access page defaults, with no commands allowed.\n\n";
	print "When editing, settings you leave out stay unchanged. Lists you supply\n";
	print "replace the saved lists. Repeat options marked with * to select more items.\n\n";
	print "A mode without its list does not reuse the saved selection. For example:\n";
	print "--command-mode include without --command removes all command permissions.\n";
	print "--domain-mode selected without --domain selects no existing servers.";
	}
print "\n";
}

1;
