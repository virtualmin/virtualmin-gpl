# Functions for the post-install wizard

# If the wizard should be invoked, returns a URL for it. For calling by themes
sub wizard_redirect
{
if (&master_admin() &&
    ($config{'wizard_run'} eq '' && $config{'first_version'} >= 3.69 ||
     $config{'wizard_run'} eq '0')) {
	return "/$module_name/wizard.cgi";
	}
return undef;
}

sub get_wizard_steps
{
return ( "intro",
	 $config{'spam'} ? ( "memory" ) : ( ),
	 $config{'spam'} && !$config{'provision_spam_host'} ?
		( "spam" ) : ( ),
	 # Virus scanning depends on spam filtering, which sets up the
	 # procmail configuration used to run the scanner. Provisioned
	 # services are managed outside this local-daemon wizard.
	 $config{'spam'} && $config{'virus'} &&
		!$config{'provision_virus_host'} ? ( "virus" ) : ( ),
	 "db",
	 $config{'mysql'} ? ( "mysql" ) : ( ),
	 $config{'dns'} ? ( "dns" ) : ( ),
	 $mail_system == 99 ? ( ) : "email",
	 "done" );
}

# get_wizard_next_step(step, &old-steps)
# Returns the index of the step to show after the given one in the re-computed
# step list, or undef if the wizard is complete. Parsing a step can enable or
# disable features, which changes the list of remaining steps.
sub get_wizard_next_step
{
my ($current, $oldsteps) = @_;
my @steps = &get_wizard_steps();
my %index = map { $steps[$_] => $_ } (0 .. $#steps);
if (defined($index{$current})) {
	# Step is still in the flow, so move to the one following it
	my $next = $index{$current} + 1;
	return $next < scalar(@steps) ? $next : undef;
	}
# The step removed itself from the flow, so find the first of the steps
# that followed it which still exists
my $oldidx = 0;
foreach my $i (0 .. $#$oldsteps) {
	$oldidx = $i if ($oldsteps->[$i] eq $current);
	}
foreach my $s (@$oldsteps[$oldidx+1 .. $#$oldsteps]) {
	return $index{$s} if (defined($index{$s}));
	}
return undef;
}

sub wizard_show_intro
{
print &ui_table_row(undef,
	$text{'wizard_intro'}, 2);
}

# Show a form to enable or disable lookup-domain-daemon
sub wizard_show_memory
{
print &ui_table_row(undef, $text{'wizard_memory2'}. "<p></p>", 2);

my $mem = &get_uname_arch() =~ /64/ ? "70M" : "35M";
print &ui_table_row($text{'wizard_memory_lookup'},
	&ui_radio("lookup", &check_lookup_domain_daemon(),
		  [ [ 1, &text('wizard_memory_lookup1', $mem)."<br>" ],
		    [ 0, $text{'wizard_memory_lookup0'} ] ]));
}

# Enable or disable pre-loading and lookup-domain-daemon
sub wizard_parse_memory
{
my ($in) = @_;
&push_all_print();
&set_all_null_print();

my $lud = &check_lookup_domain_daemon();
if ($in->{'lookup'} && !$lud) {
	# Startup lookup daemon
	&setup_lookup_domain_daemon();
	}
elsif (!$in->{'lookup'} && $lud) {
	# Stop lookup daemon
	&delete_lookup_domain_daemon();
	}
&save_module_config_keys(
	{ 'no_lookup_domain_daemon' => !$in->{'lookup'} });

&pop_all_print();
return undef;
}

# Show a form asking the user if he wants to run clamd
sub wizard_show_virus
{
print &ui_table_row(undef, $text{'wizard_virusnew'} . "<p></p>", 2);
my $cs = &check_clamd_status();
if ($cs != -1) {
	print &ui_table_row($text{'wizard_virusmsg'},
		&ui_radio("clamd", $cs ? 1 : 0,
		  [ [ 1, $text{'wizard_virus1'}."<br>" ],
		    [ 0, $text{'wizard_virus0'} ] ]));
	}
else {
	print &ui_table_row(undef, $text{'wizard_clamdnone'});
	print &ui_hidden("clamd", 0);
	}
}

# Parse the clamd form, and enable or disable clamd
sub wizard_parse_virus
{
my ($in) = @_;
if (defined($in->{'clamd'})) {
	my $cs = &check_clamd_status();
	if ($in->{'clamd'}) {
		# Virus scanning cannot be enabled without spam filtering or a
		# manageable local clamd service
		return $text{'check_evirusspam'} if (!$config{'spam'});
		return $text{'wizard_eclamdenable'} if ($cs == -1);
		if (!$cs) {
			# Start and test clamd before selecting its client program
			&push_all_print();
			&set_all_null_print();
			my $ok = &enable_clamd();
			&pop_all_print();
			return $text{'wizard_eclamdenable'} if (!$ok);
			my $last_err;
			&foreign_require("init");
			for(my $try=0; $try<20; $try++) {
				$last_err = &test_virus_scanner("clamdscan");
				last if (!$last_err);
				if ($try == 0 && &has_command("freshclam") &&
					!init::action_status('clamav-freshclam')) {
					# First time around, try running
					# freshclam
					&backquote_with_timeout("freshclam", 60);
					}
				else {
					sleep($try);
					}
				}
			return &text('wizard_eclamdtest', $last_err)
				if ($last_err);
			}
		# Yes always means the daemonized scanner, even when clamd was
		# already running before the wizard
		&save_global_virus_scanner("clamdscan");
		&save_module_config_keys({ 'virus' => $config{'virus'} || 1 });
		}
	else {
		# Disable clamd and virus feature, unless some domains are
		# using it
		my @doms = grep { $_->{'virus'} } &list_domains();
		if (@doms) {
			return &text('wizard_eclaminuse', scalar(@doms));
		}
		&push_all_print();
		&set_all_null_print();
		&disable_clamd() if ($cs >= 0);
		&pop_all_print();
		&save_global_virus_scanner("clamscan");
		&save_module_config_keys({ 'virus' => 0 });
		}
	}
return undef;
}

# Show a form asking the user if he wants to run spamd
sub wizard_show_spam
{
print &ui_table_row(undef, $text{'wizard_spam'} . "<p></p>", 2);
my $cs = &check_spamd_status();
if ($cs != -1) {
	print &ui_table_row($text{'wizard_spamd'},
		&ui_radio("spamd", $cs ? 1 : 0,
			  [ [ 1, $text{'wizard_spamd1'}."<br>" ],
			    [ 0, $text{'wizard_spamd0'} ] ]));
	}
else {
	print &ui_table_row($text{'wizard_spamdnone'});
	print &ui_hidden("spamd", 0);
	}
}

# Parse the spamd form, and enable or disable spamd
sub wizard_parse_spam
{
my ($in) = @_;
if (defined($in->{'spamd'})) {
	my $cs = &check_spamd_status();
	if ($in->{'spamd'}) {
		# Yes always enables the feature with the daemonized client
		return $text{'wizard_espamdenable'} if ($cs == -1);
		if (!$cs) {
			&push_all_print();
			&set_all_null_print();
			my $ok = &enable_spamd();
			&pop_all_print();
			return $text{'wizard_espamdenable'} if (!$ok);
			}
		&save_global_spam_client("spamc");
		&save_module_config_keys({ 'spam' => $config{'spam'} || 1 });
		}
	else {
		# Spam owns the mail-filtering chain used by virus scanning, so
		# neither feature can be disabled while a domain uses either one
		my @doms = grep { $_->{'spam'} || $_->{'virus'} } &list_domains();
		if (@doms) {
			return &text('wizard_espaminuse', scalar(@doms));
			}
		my $virus_enabled = $config{'virus'};

		# Stop all daemons used only by the disabled filtering features
		&push_all_print();
		&set_all_null_print();
		&disable_spamd() if ($cs >= 0);
		&disable_clamd()
			if ($virus_enabled && !$config{'provision_virus_host'} &&
			    &check_clamd_status() >= 0);
		&delete_lookup_domain_daemon();
		&pop_all_print();

		# Keep safe dormant clients so the features can be re-enabled and
		# configured later without referring to stopped daemon services
		&save_global_spam_client("spamassassin")
			if (!$config{'provision_spam_host'});
		&save_global_virus_scanner("clamscan")
			if ($virus_enabled && !$config{'provision_virus_host'});
		&save_module_config_keys({
			'spam' => 0,
			'virus' => 0,
			'no_lookup_domain_daemon' => 1,
			});
		}
	}
return undef;
}

# get_wizard_postgres_default()
# Returns the PostgreSQL choice to show initially. Detect an existing usable
# installation without changing the Virtualmin feature configuration.
sub get_wizard_postgres_default
{
return 1 if ($config{'postgres'});
return 0 if (!&foreign_installed("postgresql", 0));
&require_postgres();

# A discovered local cluster may be configured but currently stopped
return 1 if ($postgresql::hba_conf_file);

# A reachable server also covers configured remote PostgreSQL instances
return &postgresql::is_postgresql_running() == 1 ? 1 : 0;
}

# Ask the user if he wants to run MySQL and/or PostgreSQL
sub wizard_show_db
{
print &ui_table_row(undef, $text{'wizard_db'}. "<p></p>", 2);
print &ui_table_row($text{'wizard_db_mysql'},
                    &ui_yesno_radio("mysql", $config{'mysql'} ? 1 : 0));
print &ui_table_row($text{'wizard_db_postgres'},
                    &ui_yesno_radio("postgres",
				    &get_wizard_postgres_default()));
}

# Enable or disable MySQL and PostgreSQL, depending on user's selections
sub wizard_parse_db
{
my ($in) = @_;
&foreign_require("init");

&require_mysql();
if ($in->{'mysql'}) {
	# Enable and start MySQL, if possible
	if (!&foreign_installed("mysql", 0)) {
		return $text{'wizard_emysqlinst'};
		}
	$config{'mysql'} ||= 1;
	if (&mysql::is_mysql_running() == 0) {
		my $err = &mysql::start_mysql();
		return &text('wizard_emysqlstart', $err) if ($err);
		}
	if (&init::action_status("mysql")) {
		&init::enable_at_boot("mysql");
		}

	# Make sure MySQL can be used
	if (&foreign_installed("mysql", 1) == 0) {
		return &text('wizard_emysqlconf', '../mysql/');
		}
	}
else {
	# Disable and shut down MySQL
	$config{'mysql'} = 0;
	&mysql::stop_mysql();
	&init::disable_at_boot("mysql");
	}

if ($in->{'postgres'}) {
	# Enable and start PostgreSQL
	if (!&foreign_installed("postgresql", 0)) {
		return &text('wizard_epostgresinst', $virtualmin_docs_link.
			"installation/automated/#postgresql");
		}
	&require_postgres();
	$config{'postgres'} ||= 1;
	my $postgres_status = &postgresql::is_postgresql_running();
	my $postgres_setup;
	my $postgres_service_status;
	if ($postgres_status == 0 && !$postgresql::hba_conf_file &&
	    &postgresql::is_postgresql_local()) {
		# Check the service when one is registered with Webmin
		my $postgres_action = &init::action_status("postgresql");
		$postgres_service_status = $postgres_action ?
			&init::status_action("postgresql") : undef;
		if (!$postgres_action || $postgres_service_status == 0) {
			# Fall back to module setup when no service action exists
			my $err = &postgresql::setup_postgresql();
			return &text('wizard_epostgressetup', $err) if ($err);
			$postgres_setup = 1;
			$postgres_service_status = &init::status_action("postgresql")
				if ($postgres_action);
			}
		elsif ($postgres_service_status != 1) {
			# Don't initialize or start when service status is unknown
			return &text('wizard_epostgresconf', '../postgresql/');
			}
		}
	if ($postgres_status == 0 &&
	    (!defined($postgres_service_status) ||
	     $postgres_service_status != 1)) {
		my $err = &postgresql::start_postgresql();
		return &text('wizard_epostgresstart', $err) if ($err);
		# The service command can return before the server is ready,
		# so wait for it to start accepting connections
		for (my $try = 0; $try < 5; $try++) {
			last if (&postgresql::is_postgresql_running() != 0);
			sleep(1);
			}
		}
	if (&init::action_status("postgresql")) {
		&init::enable_at_boot("postgresql");
		}

	# Make sure PostgreSQL can be used
	# A newly initialized module still has its old state cached, and setup
	# and startup errors for it have already been checked above
	if (!$postgres_setup && &foreign_installed("postgresql", 1) != 2) {
		return &text('wizard_epostgresconf', '../postgresql/');
		}
	}
elsif (&foreign_available("postgresql")) {
	# Disable and shut down PostgreSQL
	&require_postgres();
	$config{'postgres'} = 0;
	&postgresql::stop_postgresql();
	&init::disable_at_boot("postgresql");
	}
my %feature_config = map { $_ => $config{$_} }
			 grep { exists($config{$_}) } qw(mysql postgres);
&save_module_config_keys(\%feature_config);

return undef;
}

# Show a form to set the MySQL root password
sub wizard_show_mysql
{
&require_mysql();
if (&mysql::is_mysql_running() == -1) {
	# Cannot even login with the current password
	print &ui_table_row(undef, $text{'wizard_mysql4'}, 2);
	print &ui_hidden("needchange", 1);

	print &ui_table_row($text{'wizard_mysql_empty'},
		&ui_textbox("mypass", undef, 20)."<br>\n".
		&ui_checkbox("forcepass", 1, $text{'wizard_mysql_forcepass'}, 0));
	}
else {
	# Offer to change the password
	print &ui_hidden("needchange", 0);
	print &ui_table_row(undef, $text{'wizard_mysql'} . " " .
			   ($mysql::mysql_pass ? $text{'wizard_mysql3'}
					       : $text{'wizard_mysql2'}) . "<p></p>", 2);
	if ($mysql::mysql_pass) {
		print &ui_table_row($text{'wizard_mysql_pass'},
			&ui_opt_textbox("mypass", undef, 20,
					$text{'wizard_mysql_pass1'}."<br>",
					$text{'wizard_mysql_pass0'}));
		}
	else {
		# Do we have socket authentication plugin?
		my $plugins = &mysql::list_authentication_plugins();
		my $has_unix_socket = grep { $_ eq 'unix_socket' } @$plugins;
		if ($has_unix_socket && defined(&mysql::mysql_login_type) &&
		    &mysql::mysql_login_type($mysql::mysql_login || 'root')) {
			# Using socket authentication
			my $text_mysql_def = $text{'wizard_mysql_pass2'} .
				"&nbsp;".&ui_help($text{'wizard_mysql5'});
			print &ui_hidden("socket", 1);
			print &ui_table_row($text{'wizard_mysql_pass'},
			&ui_opt_textbox("mypass", &random_password(16), 20,
					$text_mysql_def."<br>",
					$text{'wizard_mysql_pass0'}));
			}
		else {
			print &ui_table_row($text{'wizard_mysql_empty'},
			&ui_textbox("mypass", &random_password(16), 20));
			}
		}

	# Offer to clean up test/anonymous DB and user, if they exist
	my @dbs = &list_dom_mysql_databases(undef);
	if (&indexof("test", @dbs) >= 0) {
		my @tables = &list_dom_mysql_tables(undef, "test", 1);
		print &ui_table_row($text{'wizard_mysql_deltest'}.
			(@tables ? " ".&text('wizard_mysql_delc',
					     scalar(@tables)) : ""),
			&ui_yesno_radio("deltest", @tables ? 0 : 1));
		}
	my $rv = &execute_dom_sql(undef, $mysql::master_db,
		"select * from user where user = ''");
	if (@{$rv->{'data'}}) {
		print &ui_table_row($text{'wizard_mysql_delanon'},
			&ui_yesno_radio("delanon", 1));
		}
	}
}

# Set the MySQL password, if changed
sub wizard_parse_mysql
{
my ($in) = @_;
&require_mysql();
my $user = $mysql::mysql_login || 'root';
if ($in->{'socket'} && !$in->{'mypass'}) {
	# Socket auth with no password. Check if we actually have socket plugin,
	# and not just empty password
	my $mode = &mysql::mysql_login_type($user);
	if ($mode ne 'socket') {
		&mysql::change_user_password('', $user, 'localhost',
					     'unix_socket');
		}
	return undef;
	}
my $pass = $in->{'mypass_def'} ? $mysql::mysql_pass : $in->{'mypass'};
if ($in->{'needchange'}) {
	# Change the password used by subsequent code to validate that it works
	$mysql::mysql_pass = $pass;
	$mysql::authstr = &mysql::make_authstr();
	}
if (&mysql::is_mysql_running() == -1) {
	# Forcibly change the mysql password
	if ($in->{'forcepass'}) {
		&push_all_print();
		&set_all_null_print();
		my $err = &force_set_mysql_password($user, $pass);
		&pop_all_print();
		return $err if ($err);
		}

	if (&mysql::is_mysql_running() <= 0) {
		return $text{'wizard_mysql_epass'};
		}
	}
else {
	if (!$in{'mypass_def'}) {
		# Change in DB
		eval {
			local $main::error_must_die = 1;
			&execute_password_change_sql(undef, $user, undef, $pass);
			};
		# Update the password used by subsequent code if
		# changing it worked
		&update_webmin_mysql_pass($user, $pass);
		$mysql::mysql_pass = $pass;
		$mysql::authstr = &mysql::make_authstr();
		}
	}

# Remove test database if requested
if ($in->{'deltest'}) {
	&execute_dom_sql(undef, $mysql::master_db, "drop database test");
	&execute_dom_sql(undef, $mysql::master_db,
		"delete from db where db = 'test' or db = 'test_%'");
	}
if ($in->{'delanon'}) {
	&execute_dom_sql(undef, $mysql::master_db,
		"delete from user where user = ''");
	}

return undef;
}

# Show a form to set the primary nameservers
sub wizard_show_dns
{
&require_bind();
print &ui_table_row(undef, $text{'wizard_dns'} . "<p></p>", 2);

# Primary nameserver
my $tmpl = &get_template(0);
my $tmaster = $tmpl->{'dns_master'} eq 'none' ? undef
						 : $tmpl->{'dns_master'};
my $master = $tmaster ||
		$bconfig{'default_prins'} ||
		&get_system_hostname();
print &ui_table_row($text{'wizard_dns_prins'},
		    &ui_textbox("prins", $master, 40)." ".
		    &ui_checkbox("prins_skip", 1, $text{'wizard_dns_skip'},
				 $config{'prins_skip'}));

# Secondaries (optional)
my @secns = split(/\s+/, $tmpl->{'dns_ns'});
print &ui_table_row($text{'wizard_dns_secns'},
		    &ui_textarea("secns", join("", map { "$_\n" } @secns),
				 4, 40));
}

sub wizard_parse_dns
{
my ($in) = @_;
&require_bind();
my @tmpls = &list_templates();
my ($tmpl) = grep { $_->{'id'} eq '0' } @tmpls;
$tmpl || return $text{'wizard_etmpl0'};

# Validate primary NS
$in->{'prins'} =~ /^[a-z0-9\.\_\-]+$/i || return $text{'wizard_dns_eprins'};
if (!$in->{'prins_skip'}) {
	&to_ipaddress($in->{'prins'}) || return $text{'wizard_dns_eprins2'};
	my ($ok, $msg) = &check_resolvability($in->{'prins'});
	if (!$ok) {
		return &text('wizard_dns_eprins3', $msg);
		}
	}
$tmpl->{'dns_master'} = $in->{'prins'};
$tmpl->{'dns_master_skip'} = $in->{'prins_skip'};
&save_template($tmpl);

# Validate any secondary NSs
my @secns;
foreach my $ns (split(/\s+/, $in->{'secns'})) {
	$ns =~ /^[a-z0-9\.\_\-]+$/i || return &text('wizard_dns_esecns', $ns);
	if (!$in->{'prins_skip'}) {
		&to_ipaddress($ns) || return &text('wizard_dns_esecns2', $ns);
		my ($ok, $msg) = &check_resolvability($ns);
		if (!$ok) {
			return &text('wizard_dns_esecns3', $ns, $msg);
			}
		}
	push(@secns, $ns);
	}
$tmpl->{'dns_ns'} = join(" ", @secns);
&save_template($tmpl);

# Save skip option
&save_module_config_keys({ 'prins_skip' => $in{'prins_skip'} });
}

sub wizard_show_email
{
&foreign_require("mailboxes");
print &ui_table_row(undef, $text{'wizard_email_desc'}, 2);

# From address for email notifications
print &ui_table_row($text{'wizard_from_addr'},
	&ui_opt_textbox("from_addr", $config{'from_addr'}, 50,
		$text{'default'}." (".&mailboxes::get_from_address().")<br>",
		$text{'wizard_from_addr2'}));

# Default to address for notifications
print &ui_table_row($text{'wizard_to_addr'},
	&ui_opt_textbox("to_addr", $gconfig{'webmin_email_to'}, 50,
			$text{'wizard_to_addr_none'}));
}

sub wizard_parse_email
{
my ($in) = @_;

if ($in->{'from_addr_def'}) {
	&save_module_config_keys({ }, [ 'from_addr' ]);
	}
else {
	$in->{'from_addr'} =~ /\S+\@\S+/ || return $text{'wizard_efrom_addr'};
	&save_module_config_keys({ 'from_addr' => $in->{'from_addr'} });
	}

&lock_file("$config_directory/config");
if ($in->{'to_addr_def'}) {
	delete($gconfig{'webmin_email_to'});
	}
else {
	$in->{'to_addr'} =~ /\S+\@\S+/ || return $text{'wizard_efrom_addr'};
	$gconfig{'webmin_email_to'} = $in->{'to_addr'};
	}
&write_file("$config_directory/config", \%gconfig);
&unlock_file("$config_directory/config");
}

sub wizard_show_done
{
print &ui_table_row(undef, &text('wizard_done'), 2);
}

# get_real_memory_size()
# Returns the amount of RAM in bytes, or undef if we can't get it
sub get_real_memory_size
{
return undef if (!&foreign_check("proc"));
&foreign_require("proc");
return undef if (!defined(&proc::get_memory_info));
my ($real) = &proc::get_memory_info();
return $real * 1024;
}

# get_uname_arch()
# Returns the architecture, like x86_64 or i386
sub get_uname_arch
{
my $out = &backquote_command("uname -m");
$out =~ s/\s+//g;
return $out;
}

1;
