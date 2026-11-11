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
# Returns command and option grants with provider keys, scope, and aliases.
# Virtual option grants have a parent command instead of an executable path.
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
	# Database import can claim a source outside every permitted domain.
	$scoped = 0 if ($core && $canonical eq 'import-database');
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
# Extra option permissions are selectable grants, never executable scripts.
# Bind them to the core provider so a plugin replacement cannot inherit them.
# Rows contain the base command, suffix, domain scope, flags, optional help
# key and warning flag. Empty flag lists are checked inside the command.
# Server-wide entries always warn; domain-scoped entries can warn too.
foreach my $option (
	[ 'modify-domain', 'quotas', 1, [ '--quota', '--uquota' ] ],
	[ 'modify-domain', 'quotas-reapply', 1, [ '--apply-all-quotas' ] ],
	[ 'modify-domain', 'bandwidth', 1,
	  [ '--bw', '--bw-disable', '--bw-no-disable' ] ],
	[ 'modify-domain', 'protection', 1, [ '--protected', '--unprotected' ] ],
	[ 'modify-domain', '2fa', 1, [ '--disable-2fa' ], '2fa', 1 ],
	[ 'modify-domain', 'home', 0, [ '--home' ] ],
	[ 'modify-domain', 'hooks', 0, [ '--pre-command', '--post-command' ] ],
	[ 'rename-domain', 'user', 1, [ '--new-user', '--auto-user' ] ],
	[ 'create-user', 'encpass', 1, [ '--encpass' ], 'encpass', 1 ],
	# Provisioning overrides can change ownership, isolation or placement.
	[ 'create-domain', 'reseller', 0, [ '--reseller' ],
	  'reseller', 1 ],
	[ 'create-domain', 'jail', 1, [ '--enable-jail', '--disable-jail' ],
	  'jail', 1 ],
	[ 'create-domain', 'database-server', 0, [ '--mysql-server', '--postgres-server' ],
	  'database_server', 1 ],
	[ 'create-domain', 'passfile', 0, [ '--passfile' ],
	  'passfile', 1 ],
	# Existing domains need separate grants for the same privileged changes.
	[ 'modify-domain', 'reseller', 0, [
	  '--reseller', '--add-reseller', '--delete-reseller' ],
	  'reseller', 1 ],
	[ 'modify-domain', 'jail', 1, [
	  '--enable-jail', '--disable-jail', '--copy-jail' ],
	  'jail', 1 ],
	[ 'modify-domain', 'database-server', 0, [ '--mysql-server' ],
	  'database_server', 1 ],
	[ 'modify-domain', 'passfile', 0, [ '--passfile' ],
	  'passfile', 1 ],
	# Password file inputs read as root, regardless of the target account.
	[ 'create-user', 'passfile', 0, [ '--passfile' ],
	  'passfile', 1 ],
	[ 'modify-user', 'passfile', 0, [ '--passfile' ],
	  'passfile', 1 ],
	[ 'create-admin', 'passfile', 0, [ '--passfile' ],
	  'passfile', 1 ],
	[ 'modify-admin', 'passfile', 0, [ '--passfile' ],
	  'passfile', 1 ],
	# File paths and stored key selection need privileged read access.
	[ 'create-domain', 'ssh-key-file', 0, [ ],
	  'ssh_key_file', 1 ],
	[ 'create-user', 'ssh-key-file', 0, [ '--ssh-pubkey-id' ],
	  'ssh_key_file', 1 ],
	[ 'modify-user', 'ssh-key-file', 0, [ '--ssh-pubkey-id' ],
	  'ssh_key_file', 1 ],
	# Hooks and home paths can give access beyond the selected domain.
	[ 'create-domain', 'hooks', 0, [ '--pre-command', '--post-command' ],
	  'hooks', 1 ],
	[ 'delete-domain', 'hooks', 0, [ '--pre-command', '--post-command' ],
	  'hooks', 1 ],
	[ 'rename-domain', 'home', 0, [ '--new-home' ],
	  'home', 1 ],
	# Username changes retain validation and existing-account clash checks.
	[ 'modify-domain', 'user', 1, [ '--user' ],
	  'user', 0 ],
	[ 'create-user', 'noappend', 1, [ '--noappend' ],
	  'create_user_noappend', 1 ],
	# DNS placement and custom fields may affect shared server settings.
	[ 'create-domain', 'dns-placement', 0, [
	  '--no-slaves', '--no-secondaries', '--separate-dns-subdomain',
	  '--any-dns-subdomain' ],
	  'create_domain_dns_placement', 1 ],
	[ 'create-domain', 'admin-fields', 0, [ ],
	  'create_domain_admin_fields', 1 ],
	[ 'modify-custom', 'admin-fields', 0, [ '--allow-missing' ],
	  'modify_custom_admin_fields', 1 ],
	# Mail behavior and private-key file access are independent permissions.
	[ 'modify-mail', 'autoconfig', 1, [ '--autoconfig', '--no-autoconfig' ],
	  'modify_mail_autoconfig', 0 ],
	[ 'modify-mail', 'dkim-file', 0, [ '--dkim-key' ],
	  'modify_mail_dkim_file', 1 ],
	# Secondary servers and parent zones can serve other domains as well.
	[ 'modify-dns', 'slaves', 0, [
	  '--add-slave', '--remove-slave', '--add-all-slaves',
	  '--sync-all-slaves' ],
	  'modify_dns_slaves', 1 ],
	[ 'modify-dns', 'subdomain', 0, [ '--enable-subdomain', '--disable-subdomain' ],
	  'modify_dns_subdomain', 1 ],
	# Scanner and notification choices stay limited to selected domains.
	[ 'modify-spam', 'scanners', 1, [
	  '--use-spamc', '--use-spamassassin', '--use-clamscan',
	  '--use-clamdscan', '--use-clamd-stream-client', '--use-clamdscan-remote' ],
	  'modify_spam_scanners', 1 ],
	[ 'generate-acme-cert', 'email-master', 1, [ '--email-master', '--no-email-master' ],
	  'generate_acme_cert_email_master', 0 ],
	# These options cross file, PHP or database administrator boundaries.
	[ 'install-cert', 'files', 0, [ ],
	  'install_cert_files', 1 ],
	[ 'modify-php-ini', 'admin', 1, [ '--fpm-admin-value' ],
	  'modify_php_ini_admin', 1 ],
	[ 'create-database', 'options', 0, [ '--opt' ],
	  'create_database_options', 1 ],
	# Keep each privileged web-server effect independently selectable.
	[ 'modify-web', 'logs', 0, [
	  '--access-log', '--error-log', '--php-log' ],
	  'modify_web_logs', 1 ],
	[ 'modify-web', 'cert-paths', 0, [
	  '--ssl-cert', '--ssl-key', '--ssl-ca',
	  '--default-ssl-cert', '--default-ssl-key', '--default-ssl-ca',
	  '--default-ssl-paths' ],
	  'modify_web_cert_paths', 1 ],
	# Directives and ports can affect the shared web-server process.
	[ 'modify-web', 'directives', 0, [ '--add-directive', '--remove-directive' ],
	  'modify_web_directives', 1 ],
	[ 'modify-web', 'ports', 0, [
	  '--port', '--ssl-port', '--url-port',
	  '--ssl-url-port' ],
	  'modify_web_ports', 1 ],
	# Repairs and process limits can disrupt the selected domain.
	[ 'modify-web', 'repair', 1, [
	  '--fix-document-dir', '--fix-options', '--cleanup-mod-php' ],
	  'modify_web_repair', 1 ],
	[ 'modify-web', 'php-limits', 1, [ '--php-children-no-check' ],
	  'modify_web_php_limits', 1 ],
	# Resource association changes what Virtualmin manages or leaves behind.
	[ 'enable-feature', 'associate', 0, [ '--associate' ],
	  'enable_feature_associate', 1 ],
	[ 'disable-feature', 'disassociate', 0, [ '--disassociate' ],
	  'disable_feature_disassociate', 1 ],
	[ 'delete-domain', 'only', 0, [ '--only' ],
	  'delete_domain_only', 1 ],
	# Version overrides and registration can bypass normal installer checks.
	[ 'install-script', 'unsupported', 1, [ '--unsupported' ],
	  'install_script_unsupported', 1 ],
	[ 'install-script', 'log-only', 1, [ '--log-only' ],
	  'install_script_log_only', 1 ],
	# Global applications can serve domains outside the target list.
	[ 'install-script', 'global', 0, [ ],
	  'global_scripts', 1 ],
	[ 'delete-script', 'global', 0, [ ],
	  'global_scripts', 1 ],
	[ 'start-stop-script', 'global', 0, [ ],
	  'global_scripts', 1 ],
	# TLS keys may be shared; other secret output follows domain selection.
	[ 'list-certs', 'private-keys', 0, [ '--key', '--newkey' ],
	  'list_certs_private_keys', 1 ],
	[ 'list-domains', 'secrets', 1, [ ],
	  'secrets', 1 ],
	[ 'list-users', 'secrets', 1, [ ],
	  'secrets', 1 ],
	[ 'list-admins', 'secrets', 1, [ ],
	  'secrets', 1 ],
	[ 'list-scripts', 'secrets', 1, [ ],
	  'secrets', 1 ]) {
	my ($base, $suffix, $scoped, $args, $label, $warning) = @$option;
	my $parent = $commands{$base};
	# Replaced or unavailable base commands cannot expose core option grants.
	next if (!$parent || $parent->{'provider'} ne $module_name);
	my $name = "$base-$suffix";
	$label ||= $suffix;
	$label =~ tr/-/_/;
	# Inherit edition requirements and keep risk separate from domain scope.
	$commands{$name} = { 'name' => $name,
		'provider' => $module_name, 'key' => "$module_name:$name",
		'parent' => $parent->{'key'}, 'virtual' => 1,
		'options' => $args, 'scoped' => $scoped,
		'pro' => $parent->{'pro'},
		'warning' => !$scoped || $warning ? 1 : 0,
		'desc' => &text('apiaccess_option_'.$label, $base) };
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
return $command && !$command->{'virtual'} &&
	!&api_account_pro_message($command->{'name'}) &&
	&api_access_contains($access{'api_commands'}, $command->{'key'});
}

# api_access_can_option(name)
# Checks an extra grant for the current command without granting a master role.
# The base command must still be authorized by the same provider.
# Domain batches deny server-wide grants, including checks made at runtime.
sub api_access_can_option
{
my ($name) = @_;
my $option = &get_api_access_command($name);
# Batch children may never acquire effects outside their target domains.
return 0 if ($option && !$option->{'scoped'} &&
	     $api_access_domain_batch);
return $option && $option->{'virtual'} && $api_access_command &&
	$option->{'parent'} eq $api_access_command->{'key'} &&
	&api_access_can_command($api_access_command->{'name'}) &&
	&api_access_contains($access{'api_commands'}, $option->{'key'});
}

# api_access_command_options(&command, &args)
# Returns extra permissions required by options in an API argv arrayref.
sub api_access_command_options
{
my ($command, $args) = @_;
my %args = map { $_ => 1 } @$args;
return grep { $_->{'virtual'} && $_->{'parent'} eq $command->{'key'} &&
	      grep { $args{$_} } @{$_->{'options'}} }
	&list_api_access_commands();
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
{
	# Validate option grants against this command, not a previous batch target.
	local $api_access_command = $command;
	foreach my $option (&api_access_command_options($command, $args)) {
		&api_access_can_option($option->{'name'}) ||
			die "API option requires permission $option->{'name'}\n";
		}
	}
if ($command->{'name'} =~ /^(create|modify)-domain$/) {
	# Only explicit quota grants may override plan limits on existing domains.
	local $api_access_command = $command;
	foreach my $arg (@$args) {
		next if ($command->{'name'} eq 'modify-domain' &&
			 $arg =~ /^--(quota|uquota)$/ &&
			 &api_access_can_option('modify-domain-quotas'));
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
# A domain command's server-wide options must not enter the batch wrapper.
foreach my $option (&api_access_command_options($command, \@args)) {
	$option->{'scoped'} ||
		die "Batch commands cannot use server-wide option permissions\n";
	}
foreach my $d (@domains) {
	my @childargs = ('--domain', $d->{'dom'}, @args);
	if ($test) {
		# Report the validated target without starting a child process.
		print "Would run $name for $d->{'dom'}\n";
		next;
		}
	# The fork retains this flag even when it clears the environment.
	# Runtime checks then reject file inputs and global applications too.
	local $api_access_domain_batch = 1;
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
foreach my $user (@_ ? &acl::get_user($_[0]) : &acl::list_users(undef, 1)) {
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
	    $hash, %global, %acl);
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
		# Extra permissions need their parent in the resolved command selection.
		my %chosen = map { $_ => 1 } @chosen;
		foreach my $key (@chosen) {
			my $parent = $known{$key}->{'parent'};
			if ($parent && !$chosen{$parent}) {
				# Reject incomplete grants before writing any account changes.
				die &text('apiaccess_edependency', $known{$key}->{'name'},
					$known{$parent}->{'name'})."\n";
				}
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
		# All includes future resources; selected IDs must still exist.
		foreach my $kind ('domain', 'template', 'plan') {
			$in{$kind.'_mode'} =~ /^(all|selected)$/ ||
				die($text{'apiaccess_escope'}."\n");
			my @items = &list_api_access_resources($kind);
			my %ids = map { $_->{'id'} => 1 } @items;
			my @ids = split(/\s+/, $in{$kind.'s'});
			if ($in{$kind.'_mode'} eq 'selected') {
				# Reject missing or deleted resources.
				(grep { !$ids{$_} } @ids) && die($text{'apiaccess_escope'}."\n");
				}
			$policy{"api_${kind}s"} = $in{$kind.'_mode'} eq 'all' ? '*' : join(' ', @ids);
			# Only templates and plans have creation defaults to validate.
			next if ($kind eq 'domain');
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
			$desc = &trim($desc);
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
