# API accounts have Webmin credentials but no Unix account or master role.
# Their module ACL stores permissions; a random ID links new domains to them.

# is_api_access_user()
# Returns true for a dedicated API account, including a disabled account.
sub is_api_access_user
{
return $access{'api_id'} ne '';
}

# api_access_contains(list, value)
# Checks value against a whitespace-separated API permission list.
# A * entry allows any nonempty value, even alongside explicit IDs.
sub api_access_contains
{
my ($list, $value) = @_;
return &acl_list_contains($list, $value, 1);
}

# default_api_access_policy()
# Returns a new policy hashref using the configured template and plan defaults.
# UI and CLI accounts start with no command grants; saving assigns their ID.
sub default_api_access_policy
{
my $plan = &get_default_plan();
return { 'api_created' => 1, 'api_disabled' => 0,
	 'api_domains' => '*', 'api_templates' => '*', 'api_plans' => '*',
	 'api_template' => &get_init_template(0),
	 'api_plan' => $plan ? $plan->{'id'} : '' };
}

# list_api_access_resources(kind)
# Returns resource hashrefs for kind: domain, template or plan.
# Uses the same choices for UI fields, CLI lookups and save validation.
sub list_api_access_resources
{
my ($kind) = @_;
# Domain grants may name any existing server, including child servers.
return &list_domains() if ($kind eq 'domain');
# Exclude deleted templates; list_templates() includes them.
return grep { !$_->{'deleted'} } &list_templates() if ($kind eq 'template');
# list_plans() already excludes deleted plans.
return &list_plans() if ($kind eq 'plan');
# Reject unsupported kinds instead of returning an empty list.
die "Unknown API resource type: $kind\n";
}

# list_api_access_commands()
# Returns command hashrefs with provider keys, script paths, scope, and aliases.
# The pro flag marks commands that need Pro when run by a dedicated API account.
# Scoped commands enforce account permissions themselves. Other commands may
# affect resources outside the account's domain list.
sub list_api_access_commands
{
# Reuse the catalog only within this process. New requests rescan providers.
return @api_access_commands if ($api_access_commands_loaded);
# Use the shared command catalog in dispatcher order; later providers win.
my (%commands, %plugin_scoped);
foreach my $entry (&list_api_commands()) {
	my ($name, $canonical, $provider) =
		@$entry{ 'name', 'canonical', 'provider' };
	# Only executable command names can be granted, never account-management CLI.
	next if ($name !~ /^[a-z0-9][a-z0-9-]*$/ || !-x $entry->{'path'} ||
		&is_api_account_command($name) || &is_api_account_command($canonical));
	my $core = $provider eq $module_name || $provider eq "$module_name/pro";
	if (!$core && !exists($plugin_scoped{$provider})) {
		# Ask each plugin once which commands enforce domain permissions.
		my @scoped = &plugin_defined($provider, 'feature_remote_api_commands') ?
			&plugin_call($provider, 'feature_remote_api_commands') : ();
		$plugin_scoped{$provider} = {
			map { my $name = $_; $name =~ s/\.pl$//; ($name, 1) } @scoped };
		}
	# Core reuses the owner command registry, plus filtered listings and batches.
	my $scoped = $core ? (&get_user_remote_api_command($canonical) ||
		$canonical =~ /^(list-templates|list-plans|run-api-command)$/) :
		$plugin_scoped{$provider}->{$canonical};
	# Tooltips use the full opening paragraph and end with a period.
	my $desc = $entry->{'desc'};
	$desc =~ s/\s+/ /g;
	$desc =~ s/^ | $//g;
	$desc .= '.' if ($desc ne '' && $desc !~ /\.$/);
	# Keep provider-bound grants and canonical execution paths for all aliases.
	my $dir = &module_root_directory($provider);
	$commands{$name} = { 'name' => $canonical, 'provider' => $provider,
		'key' => "$provider:$canonical", 'path' => "$dir/$canonical.pl",
		'desc' => $desc, 'scoped' => $scoped ? 1 : 0,
		'pro' => exists($api_account_pro_features{$canonical}) ? 1 : 0 };
	}
# Present aliases as one permission while retaining each accepted spelling.
my %grants;
foreach my $name (sort keys %commands) {
	my $command = $commands{$name};
	$grants{$command->{'key'}} ||= $command;
	push(@{$grants{$command->{'key'}}->{'aliases'}}, $name);
	}
@api_access_commands = map { $grants{$_} } sort keys %grants;
$api_access_commands_loaded = 1;
return @api_access_commands;
}

# get_api_access_command(name)
# Resolves a name or script path to its provider entry, or returns undef.
sub get_api_access_command
{
my ($name) = @_;
# Match the dispatcher's script spelling, including registered aliases.
$name = &normalize_api_command_name($name);
$name =~ s/\.pl$//;
my ($command) = grep {
	my $entry = $_;
	grep { $_ eq $name } @{$entry->{'aliases'} || [ $entry->{'name'} ]}
	} &list_api_access_commands();
return $command;
}

# api_access_can_command(name)
# Checks a command name or script path against saved grants and the edition.
# Unknown and newly installed commands are denied.
sub api_access_can_command
{
my ($name) = @_;
# An account must be active before any saved grant can authorize a command.
return 0 if (!&is_api_access_user() || $access{'api_disabled'});
# Reject terminal-only commands even if an old catalog or ACL contains one.
return 0 if (&is_api_account_command($name));
# Both scoped and server-wide commands need a saved grant for this provider
# and must be available in this edition.
my $command = &get_api_access_command($name);
return $command &&
	!&api_account_pro_message($command->{'name'}) &&
	&api_access_contains($access{'api_commands'}, $command->{'key'});
}

# api_access_can_domain(&domain)
# Checks a domain hashref against the current API account's domain policy.
# Callers must first establish that this is an API account.
# Grants cover descendants; api_created also grants this account's creations.
# This checks target access only; command grants are checked separately.
sub api_access_can_domain
{
my ($d) = @_;
# Missing targets and disabled accounts cannot satisfy a domain grant.
return 0 if (!$d || $access{'api_disabled'});
# A parent grant covers descendants; stop if stored ancestry contains a cycle.
my %seen;
while ($d && !$seen{$d->{'id'}}++) {
	# An explicit grant or the all-domains setting authorizes this ancestor.
	return 1 if (&api_access_contains($access{'api_domains'}, $d->{'id'}));
	# The account ID prevents a reused username inheriting old creations.
	return 1 if ($access{'api_created'} &&
		    $d->{'api_owner'} eq $access{'api_id'});
	$d = $d->{'parent'} ? &get_domain($d->{'parent'}) : undef;
	}
return 0;
}

# api_access_system_command()
# True only while executing an explicitly granted server-wide command.
# This is not a master login and must not be used to authorize scoped commands.
sub api_access_system_command
{
return &is_api_access_user() && $api_access_command &&
	!$api_access_command->{'scoped'} &&
	&api_access_can_command($api_access_command->{'name'});
}

# api_access_request_args(&raw-parameters, [format])
# Builds argv without letting a parameter value introduce additional options.
# raw-parameters contains URL-encoded name=value pairs. format, if supplied,
# names the output selector to omit; no selector is omitted by default.
# Repeated values remain separate arguments. Invalid input raises an error.
sub api_access_request_args
{
my ($raw, $format) = @_;
my @args;
my $programs = 0;
foreach my $pair (@$raw) {
	my ($name, $value) = split(/=/, $pair, 2);
	# Decode names and values once, keeping each value in one argument.
	foreach ($name, $value) {
		# A parameter without '=' is a flag with an empty value.
		$_ = '' if (!defined($_));
		tr/+/ /;
		s/%([a-f0-9]{2})/chr(hex($1))/egi;
		}
	if ($name eq 'program') {
		# Count dispatch selectors separately from command options.
		$programs++;
		next;
		}
	# The dispatcher consumes this selector; it is not a command option.
	next if (defined($format) && $name eq $format);
	# Names become switches; allow lowercase letters, digits, and hyphens.
	$name =~ /^[a-z][a-z0-9-]*$/ || die "Invalid API parameter name\n";
	# Even optional-value parsers must not interpret values as switches.
	$value !~ /\0/ && $value !~ /^--/ || die "Invalid API parameter value\n";
	# Empty values are flags; other values remain one argument.
	push(@args, "--$name");
	push(@args, $value) if ($value ne '');
	}
# Reject missing or repeated selectors instead of choosing one implicitly.
$programs == 1 || die "Supply exactly one program parameter\n";
return @args;
}

# prepare_api_access_command(name, &args)
# Checks a command name or path and its argv arrayref, returning its catalog
# entry and setting the current command's permission context. Raises an error
# on denial. Wrappers must call this before executing a nested command too.
sub prepare_api_access_command
{
my ($name, $args) = @_;
# Resolve aliases before checking the edition, including nested batch calls.
my $command = &get_api_access_command($name);
if ($command && (my $err = &api_account_pro_message($command->{'name'}))) {
	# Retained grants cannot authorize these operations after a downgrade.
	die $err."\n";
	}
# Check the saved grant before recording any command as authorized.
&api_access_can_command($name) || die "API command is not permitted\n";
if ($command->{'name'} =~ /^(create|modify)-domain$/) {
	# Resource limits must come from an allowed plan, not caller overrides.
	foreach my $arg (@$args) {
		$arg !~ /^--(quota|uquota|bandwidth|mailboxlimit|dbslimit|domslimit|aliaslimit|aliasdomslimit|realdomslimit|max-mailboxes|max-dbs|max-doms|max-aliases|max-aliasdoms|max-realdoms)$/ ||
			die "API accounts must use the limits from a plan\n";
		}
	}
# Record the authorized command for checks inside its implementation.
$api_access_command = $command;
return $command;
}

# run_api_access_batch(&args)
# Parses an argv arrayref and runs an allowed command for selected domains.
# Repeated --domain options choose targets; omitting them selects all allowed
# domains. --test checks permissions without executing. --command is required
# and consumes the remaining arguments as options for the child command.
# --help alone describes these options without running a command.
# Forked children retain API permissions instead of starting the root CLI.
# Lexical parser state prevents wrapper variables leaking into child scripts.
sub run_api_access_batch
{
my ($argv) = @_;
my @args = @$argv;
my (@names, $name, $test);
if (@args == 1 && $args[0] eq '--help') {
	# get-command also uses this help to discover supported API parameters.
	print "Executes another API command over multiple servers.\n\n";
	print "virtualmin run-api-command [--domain name]* [--test]\n";
	print "                           --command name\n\n";
	print "Pass the command's options after --command name.\n";
	return;
	}
# Wrapper options end at --command; all following arguments belong to the child.
while (@args) {
	my $arg = shift(@args);
	if ($arg eq '--domain') {
		# Repeated domain options select the batch targets.
		push(@names, shift(@args));
		}
	elsif ($arg eq '--test') {
		# Dry runs check grants and targets without running the child.
		$test = 1;
		}
	elsif ($arg eq '--command') {
		# Preserve the remaining arguments for the selected command.
		$name = shift(@args);
		last;
		}
	else {
		# Reject wrapper flags not supported for API accounts.
		die "Use --domain, --test and --command for API batch requests\n";
		}
	}
# Reject a missing command before resolving targets and canonical aliases.
$name && $name ne 'run-api-command' || die "Missing or recursive command\n";
my @domains;
if (@names) {
	# Validate every target before doing any work.
	foreach my $domain (@names) {
		my $d = &get_domain_by('dom', $domain);
		$d && &api_access_can_domain($d) || die "Domain is not permitted\n";
		push(@domains, $d);
		}
	}
else {
	# An omitted domain list means all domains visible to this API account.
	@domains = grep { &api_access_can_domain($_) } &list_domains();
	}
# Reauthorize the child and reject recursive aliases or system commands.
my $command = &prepare_api_access_command($name, \@args);
$name = $command->{'name'};
$name ne 'run-api-command' || die "Recursive batch command is not permitted\n";
$command->{'scoped'} || die "Batch commands must support domain access checks\n";
foreach my $d (@domains) {
	my @childargs = ('--domain', $d->{'dom'}, @args);
	if ($test) {
		# Report the validated target without starting a child process.
		print "Would run $name for $d->{'dom'}\n";
		next;
		}
	# Child execution preserves the ACL and the caller's identity.
	pipe(my $read, my $write) || die "Cannot open command pipe: $!\n";
	my $pid = &execute_webmin_script($command->{'path'},
		$command->{'provider'}, \@childargs, $write);
	# Forward output and stop the batch when a child fails.
	print while (<$read>);
	close($read);
	waitpid($pid, 0);
	die "Command failed for $d->{'dom'}\n" if ($?);
	}
}

# api_access_module_acl(&policy)
# Builds module ACL key/value pairs from a policy hashref without a master role.
# Dispatch checks command grants; scoped commands apply their domain checks.
sub api_access_module_acl
{
my ($policy) = @_;
# Retain only recognized policy fields; never import a caller-supplied role.
my %acl = map { $_ => $policy->{$_} }
	qw(api_id api_commands api_domains api_templates api_plans api_created
	   api_disabled api_template api_plan);
# Enable capabilities that commands check after their saved grant is verified.
$acl{'noconfig'} = 1;
$acl{'domains'} = '';
$acl{'create'} = 1;
$acl{'edit'} = 1;
$acl{'import'} = 1;
$acl{'edit_remote_api'} = 1;
# Command and domain grants control access to these editing capabilities.
foreach my $edit (@edit_limits) {
	$acl{"edit_$edit"} = 1;
	}
# Feature checks also consult the customer's plan when a target domain is set.
foreach my $feature (@features, &list_feature_plugins()) {
	$acl{"feature_$feature"} = 1;
	}
return %acl;
}

# list_api_access_users([name])
# Returns Webmin user hashrefs with their API policy in a policy hashref.
# Includes disabled accounts so administrators can enable or delete them.
# When name is supplied, looks up only that login through Webmin.
sub list_api_access_users
{
&require_acl();
my @rv;
# Module access and an API account ID distinguish these from ordinary users.
foreach my $user (@_ ? &acl::get_user($_[0]) : &acl::list_users()) {
	next if (!$user || !grep { $_ eq $module_name } @{$user->{'modules'}});
	my %acl = &get_module_acl($user->{'name'}, $module_name);
	push(@rv, { %$user, 'policy' => \%acl }) if ($acl{'api_id'});
	}
return @rv;
}

# save_api_access_accounts(&params-or-builder)
# Creates, updates or deletes API accounts and returns the affected usernames.
# Accepts a form hashref or a no-argument callback returning one under the lock.
# Raises an error on failure and always releases the account lock.
sub save_api_access_accounts
{
my ($params) = @_;
# Authorize both entry points before locking or changing Webmin accounts.
&master_admin() || die $text{'apiaccess_ecannot'}."\n";
&require_acl();
&obtain_lock_webmin();
my @changed;
# Turn Webmin write errors into exceptions so the lock is released on failure.
local $main::error_must_die = 1;
eval {
	# The UI supplies form fields directly. The CLI callback reads the latest
	# account settings under this lock, then applies its requested changes.
	# Reading before the lock could overwrite an edit made while waiting.
	my %in = %{ ref($params) eq 'CODE' ? &$params() : $params };
	my (@delete_users, $user, $name, %policy, @catalog, %known, @chosen,
	    %domains, $hash, %global, %acl);
	@delete_users = ( );
	if ($in{'bulk'}) {
		# Validate the entire selection under the lock before deleting any account.
		$in{'delete'} && !$in{'new'} || die($text{'apiaccess_egone'}."\n");
		my @ids = &unique(split(/\0/, $in{'d'}));
		@ids || die($text{'apiaccess_enone'}."\n");
		my %by_id = map { $_->{'policy'}->{'api_id'} => $_ }
			&list_api_access_users();
		foreach my $id (@ids) {
			# A missing ID may belong to a deleted or replaced login.
			$by_id{$id} || die($text{'apiaccess_egone'}."\n");
			push(@delete_users, $by_id{$id});
			}
		}
	elsif (!$in{'new'}) {
		# Recheck both the name and immutable ID under the account lock.
		($user) = &list_api_access_users($in{'old'});
		$user && $in{'id'} eq $user->{'policy'}->{'api_id'} ||
			die($text{'apiaccess_egone'}."\n");
		$name = $user->{'name'};
		# Delete a single account through the same path as a bulk deletion.
		@delete_users = ($user) if ($in{'delete'});
		}
	else {
		# Reject reserved names and existing Webmin or Unix accounts.
		$name = $in{'name'};
		$name =~ /^[a-z][a-z0-9_-]{0,63}$/ &&
			$name !~ /^(root|admin|sysadm|webmin)$/ ||
			die($text{'apiaccess_ename'}."\n");
		&acl::get_user($name) &&
			die($text{'apiaccess_eexists'}."\n");
		defined(getpwnam($name)) && die($text{'apiaccess_eexists'}."\n");
		}

	if ($in{'delete'}) {
		# Only existing accounts that passed the ID checks may be deleted.
		$in{'new'} && die($text{'apiaccess_egone'}."\n");
		# Deleting an account revokes access but keeps its virtual servers.
		foreach my $selected (@delete_users) {
			&acl::delete_user($selected->{'name'});
			push(@changed, $selected->{'name'});
			&webmin_log('delete', 'apiaccount', $selected->{'name'}, { });
			}
		}
	else {
		# Validate the complete policy before changing any account files.
		%policy = ( 'api_id' => $user ? $user->{'policy'}->{'api_id'} :
			&acl::generate_random_id(), 'api_disabled' => !$in{'enabled'} ? 1 : 0,
			'api_created' => $in{'created'} ? 1 : 0 );
		$policy{'api_id'} || die($text{'apiaccess_erandom'}."\n");
		# Validate command keys before applying the selection mode.
		@catalog = &list_api_access_commands();
		%known = map { $_->{'key'} => $_ } @catalog;
		@chosen = split(/\s+/, $in{'commands'});
		foreach my $key (@chosen) {
			$known{$key} || die($text{'apiaccess_ecommand'}."\n");
			}
		$in{'command_mode'} =~ /^(include|exclude|all)$/ ||
			die($text{'apiaccess_ecommand'}."\n");
		# Broad selection modes include only commands available in this edition.
		my @available = grep {
			!&api_account_pro_message($known{$_}->{'name'}) } sort keys %known;
		if ($in{'command_mode'} eq 'all') {
			# Store a fixed list; upgrading later does not expand this grant.
			@chosen = @available;
			}
		elsif ($in{'command_mode'} eq 'exclude') {
			# Resolve exclusions now; future commands are never implicitly allowed.
			my %excluded = map { $_ => 1 } @chosen;
			@chosen = grep { !$excluded{$_} } @available;
			}
		# Include mode may resubmit existing Pro grants on GPL.
		# All/exclude replace them with this edition's commands.
		my %previous = $user ? map { $_ => 1 }
			split(/\s+/, $user->{'policy'}->{'api_commands'}) : ( );
		foreach my $key (@chosen) {
			# Only a newly added grant must pass the current edition check.
			next if ($previous{$key});
			my $err = &api_account_pro_message($known{$key}->{'name'});
			die $err."\n" if ($err);
			}
		$policy{'api_commands'} = join(' ', &unique(@chosen));
		# All-domain access includes future domains; selected IDs must exist.
		$in{'domain_mode'} =~ /^(all|selected)$/ || die($text{'apiaccess_escope'}."\n");
		%domains = map { $_->{'id'} => 1 } &list_api_access_resources('domain');
		@chosen = split(/\s+/, $in{'domains'});
		if ($in{'domain_mode'} eq 'selected') {
			# Reject grants for removed or unknown domains.
			(grep { !$domains{$_} } @chosen) && die($text{'apiaccess_escope'}."\n");
			}
		$policy{'api_domains'} = $in{'domain_mode'} eq 'all' ? '*' : join(' ', @chosen);
		# Validate template and plan grants separately from their defaults.
		foreach my $kind ('template', 'plan') {
			my @items = &list_api_access_resources($kind);
			my %ids = map { $_->{'id'} => 1 } @items;
			my @ids = split(/\s+/, $in{$kind.'s'});
			$in{$kind.'_mode'} =~ /^(all|selected)$/ ||
				die($text{'apiaccess_escope'}."\n");
			if ($in{$kind.'_mode'} eq 'selected') {
				# Reject missing or deleted templates and plans.
				(grep { !$ids{$_} } @ids) && die($text{'apiaccess_escope'}."\n");
				}
			$policy{"api_${kind}s"} = $in{$kind.'_mode'} eq 'all' ? '*' : join(' ', @ids);
			$policy{'api_'.$kind} = $in{$kind};
			if ($in{$kind} ne '') {
				# Defaults must be allowed; template ID 0 is valid.
				$ids{$in{$kind}} && &api_access_contains(
					$policy{"api_${kind}s"}, $in{$kind}) ||
					die($text{'apiaccess_edefault'}."\n");
				}
			}
		if (grep { $known{$_}->{'name'} eq 'create-domain' }
		    split(/\s+/, $policy{'api_commands'})) {
			# Creation needs defaults for requests that omit these options.
			$policy{'api_template'} ne '' && $policy{'api_plan'} ne '' ||
				die($text{'apiaccess_edefault'}."\n");
			}
		if ($in{'new'} || !$in{'password_def'}) {
			# Require a valid password when creating or explicitly replacing it.
			length($in{'password'}) >= 24 && $in{'password'} !~ /[\0\r\n]/ ||
				die($text{'apiaccess_epassword'}."\n");
			my $err = &acl::check_password_restrictions($name, $in{'password'});
			# Apply Webmin's password rules as well as the API minimum.
			die($err."\n") if ($err);
			# Use SHA-512 password hashing even on installations using DES.
			# Reject the result if crypt lacks SHA-512 support.
			my $salt = &acl::generate_random_id();
			$salt || die($text{'apiaccess_erandom'}."\n");
			$hash = &acl::encrypt_password($in{'password'}, '$6$'.substr($salt, 0, 16).'$');
			$hash =~ /^\$6\$/ || die($text{'apiaccess_ehash'}."\n");
			}

		if (!$user) {
			# Keep a new login locked until both ACLs are saved.
			# A failed write must not leave a usable, unrestricted account.
			$user = { 'name' => $name, 'pass' => '!',
				'modules' => [ $module_name ], 'nochange' => 1 };
			&acl::create_user($user);
			}
		# Store endpoint and command restrictions before unlocking a new login.
		%global = ( 'rpc' => 0, 'api_only' => 'virtual-server/remote.cgi',
			'fileunix' => 'nobody' );
		&save_module_acl(\%global, $name, '', 1);
		%acl = &api_access_module_acl(\%policy);
		&save_module_acl(\%acl, $name, $module_name, 1);
		# Change the hash only for a new password; block other modules and
		# self-service password changes.
		$user->{'pass'} = $hash if (defined($hash));
		$user->{'modules'} = [ $module_name ];
		$user->{'nochange'} = 1;
		if (exists($in{'desc'})) {
			# Share Webmin's real-name field. Omitted input preserves it.
			# Keep the value on one config line. An empty field clears it.
			my $desc = $in{'desc'};
			$desc =~ s/[\r\n\0]+/ /g;
			$desc =~ s/^\s+|\s+$//g;
			$user->{'real'} = length($desc) ? $desc : undef;
			}
		&acl::modify_user($name, $user);
		push(@changed, $name);
		# Revoke any sessions issued before a policy or password change.
		my %miniserv;
		&get_miniserv_config(\%miniserv);
		&acl::delete_session_user(\%miniserv, $name) if ($miniserv{'session'});
		# Log commands and account status without including the password.
		&webmin_log($in{'new'} ? 'create' : 'modify', 'apiaccount', $name,
			{ 'commands' => $policy{'api_commands'},
			  'disabled' => $policy{'api_disabled'} });
		}
	};
# Save the failure before cleanup, then report it after releasing the lock.
my $err = $@;
&release_lock_webmin();
die $err if ($err);
# Reload only after all requested changes have completed.
&reload_miniserv();
return @changed;
}

1;
