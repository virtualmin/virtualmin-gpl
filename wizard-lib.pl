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
	 $config{'virus'} ? ( "virus" ) : ( ),
	 $config{'spam'} ? ( "spam" ) : ( ),
	 "db",
	 $config{'mysql'} ? ( "mysql" ) : ( ),
	 $config{'dns'} ? ( "dns" ) : ( ),
	 "email",
	 "done",
	 "hashpass",
	 "ssldir",
	 "alldone" );
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

local $mem = &get_uname_arch() =~ /64/ ? "70M" : "35M";
print &ui_table_row($text{'wizard_memory_lookup'},
	&ui_radio("lookup", &check_lookup_domain_daemon(),
		  [ [ 1, &text('wizard_memory_lookup1', $mem)."<br>" ],
		    [ 0, $text{'wizard_memory_lookup0'} ] ]));
}

# Enable or disable pre-loading and lookup-domain-daemon
sub wizard_parse_memory
{
local ($in) = @_;
&push_all_print();
&set_all_null_print();

local $lud = &check_lookup_domain_daemon();
if ($in->{'lookup'} && !$lud) {
	# Startup lookup daemon
	&setup_lookup_domain_daemon();
	}
elsif (!$in->{'lookup'} && $lud) {
	# Stop lookup daemon
	&delete_lookup_domain_daemon();
	}
$config{'no_lookup_domain_daemon'} = !$in->{'lookup'};
&save_module_config();

&pop_all_print();
return undef;
}

# Show a form asking the user if he wants to run clamd
sub wizard_show_virus
{
print &ui_table_row(undef, $text{'wizard_virusnew'} . "<p></p>", 2);
local $cs = &check_clamd_status();
if ($cs != -1) {
	$cs = 2 if (!$cs && &get_global_virus_scanner() eq 'clamscan');
	print &ui_table_row($text{'wizard_virusmsg'},
		&ui_radio("clamd", $cs,
		  [ [ 1, $text{'wizard_virus1'}."<br>" ],
		    $cs == 2 ? ( [ 2, $text{'wizard_virus2'}."<br>" ] ) : ( ),
		    [ 0, $text{'wizard_virus0'} ] ]));
	}
else {
	print &ui_table_row(undef, "<b>$text{'wizard_clamdnone'}</b>");
	}
}

# Parse the clamd form, and enable or disable clamd
sub wizard_parse_virus
{
local ($in) = @_;
if (defined($in->{'clamd'})) {
	local $cs = &check_clamd_status();
	if ($in->{'clamd'} == 1 && !$cs) {
		# Enable if needed
		&push_all_print();
		&set_all_null_print();
		local $ok = &enable_clamd();
		&pop_all_print();
		if ($ok) {
			# Switch to clamdscan, after testing
			local $last_err;
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
			&save_global_virus_scanner("clamdscan");
			}
		else {
			return $text{'wizard_eclamdenable'};
			}
		$config{'virus'} = 1;
		&save_module_config();
		}
	elsif ($in->{'clamd'} == 0) {
		# Disable clamd and virus feature, unless some domains are
		# using it
		my @doms = grep { $_->{'virus'} } &list_domains();
		if (@doms) {
			return &text('wizard_eclaminuse', scalar(@doms));
			}
		&push_all_print();
		&set_all_null_print();
		&disable_clamd();
		&pop_all_print();
		&save_global_virus_scanner("clamscan");
		$config{'virus'} = 0;
		&save_module_config();
		}
	elsif ($in->{'clamd'} == 2) {
		# Must have been on clamscan mode, so leave it
		&push_all_print();
		&set_all_null_print();
		&disable_clamd();
		&pop_all_print();
		&save_global_virus_scanner("clamscan");
		$config{'virus'} = 1;
		&save_module_config();
		}
	}
return undef;
}

# Show a form asking the user if he wants to run spamd
sub wizard_show_spam
{
print &ui_table_row(undef, $text{'wizard_spam'} . "<p></p>", 2);
local $cs = &check_spamd_status();
if ($cs != -1) {
	print &ui_table_row($text{'wizard_spamd'},
		&ui_radio("spamd", $cs ? 1 : 0,
			  [ [ 1, $text{'wizard_spamd1'}."<br>" ],
			    [ 0, $text{'wizard_spamd0'} ] ]));
	}
else {
	print &ui_table_row($text{'wizard_spamdnone'});
	}
}

# Parse the spamd form, and enable or disable spamd
sub wizard_parse_spam
{
local ($in) = @_;
if (defined($in->{'spamd'})) {
	local $cs = &check_spamd_status();
	if ($in->{'spamd'} && !$cs) {
		# Enable if needed
		&push_all_print();
		&set_all_null_print();
		local $ok = &enable_spamd();
		&pop_all_print();
		if ($ok) {
			# Switch to spamc
			&save_global_spam_client("spamc");
			}
		else {
			return $text{'wizard_espamdenable'};
			}
		}
	elsif (!$in->{'spamd'} && $cs) {
		# Disable if needed
		&push_all_print();
		&set_all_null_print();
		&disable_spamd();
		&pop_all_print();
		&save_global_spam_client("spamassassin");
		}
	}
return undef;
}

# Ask the user if he wants to run MySQL and/or PostgreSQL
sub wizard_show_db
{
print &ui_table_row(undef, $text{'wizard_db'}. "<p></p>", 2);
print &ui_table_row($text{'wizard_db_mysql'},
                    &ui_yesno_radio("mysql", $config{'mysql'} ? 1 : 0));
print &ui_table_row($text{'wizard_db_postgres'},
                    &ui_yesno_radio("postgres", $config{'postgres'} ? 1 : 0));
}

# Enable or disable MySQL and PostgreSQL, depending on user's selections
sub wizard_parse_db
{
local ($in) = @_;
&foreign_require("init");

&require_mysql();
if ($in->{'mysql'}) {
	# Enable and start MySQL, if possible
	if (!&foreign_installed("mysql", 0)) {
		return $text{'wizard_emysqlinst'};
		}
	$config{'mysql'} ||= 1;
	if (&mysql::is_mysql_running() == 0) {
		local $err = &mysql::start_mysql();
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

&require_postgres();
if ($in->{'postgres'}) {
	# Enable and start PostgreSQL
	if (!&foreign_installed("postgresql", 0)) {
		return $text{'wizard_epostgresinst'};
		}
	$config{'postgres'} ||= 1;
	if (&postgresql::is_postgresql_running() == 0) {
		local $err = &postgresql::start_postgresql();
		return &text('wizard_epostgresstart', $err) if ($err);
		}
	if (&init::action_status("postgresql")) {
		&init::enable_at_boot("postgresql");
		}

	# Make sure PostgreSQL can be used
	if (&foreign_installed("postgresql", 1) != 2) {
		return &text('wizard_epostgresconf', '../postgresql/');
		}
	}
else {
	# Disable and shut down PostgreSQL
	$config{'postgres'} = 0;
	&postgresql::stop_postgresql();
	&init::disable_at_boot("postgresql");
	}
&save_module_config();

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
		if (defined(&mysql::mysql_login_type) &&
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
local ($in) = @_;
&require_mysql();
if ($in->{'socket'} && !$in->{'mypass'}) {
	# No password needed
	return undef;
	}
local $pass = $in->{'mypass_def'} ? $mysql::mysql_pass : $in->{'mypass'};
local $user = $mysql::mysql_login || 'root';
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

# Work out the max mysql username length, but only for new installs
if ($config{'mysql_user_size_auto'} != 2) {
	eval {
		local $main::error_must_die = 1;
		my @str = &mysql::table_structure($mysql::master_db, "user");
		my ($ufield) = grep { lc($_->{'field'}) eq 'user' } @str;
		if ($ufield && $ufield->{'type'} =~ /\((\d+)\)/) {
			&lock_file($module_config_file);
			$config{'mysql_user_size'} = $1;
			$config{'mysql_user_size_auto'} = 2;
			&save_module_config();
			&unlock_file($module_config_file);
			}
		};
	}

return undef;
}

# Show a form to set the primary nameservers
sub wizard_show_dns
{
&require_bind();
print &ui_table_row(undef, $text{'wizard_dns'} . "<p></p>", 2);

# Primary nameserver
local $tmpl = &get_template(0);
local $tmaster = $tmpl->{'dns_master'} eq 'none' ? undef
						 : $tmpl->{'dns_master'};
local $master = $tmaster ||
		$bconfig{'default_prins'} ||
		&get_system_hostname();
print &ui_table_row($text{'wizard_dns_prins'},
		    &ui_textbox("prins", $master, 40)." ".
		    &ui_checkbox("prins_skip", 1, $text{'wizard_dns_skip'},
				 $config{'prins_skip'}));

# Secondaries (optional)
local @secns = split(/\s+/, $tmpl->{'dns_ns'});
print &ui_table_row($text{'wizard_dns_secns'},
		    &ui_textarea("secns", join("", map { "$_\n" } @secns),
				 4, 40));
}

sub wizard_parse_dns
{
local ($in) = @_;
&require_bind();
local @tmpls = &list_templates();
local ($tmpl) = grep { $_->{'id'} eq '0' } @tmpls;
$tmpl || return $text{'wizard_etmpl0'};

# Validate primary NS
$in->{'prins'} =~ /^[a-z0-9\.\_\-]+$/i || return $text{'wizard_dns_eprins'};
if (!$in->{'prins_skip'}) {
	&to_ipaddress($in->{'prins'}) || return $text{'wizard_dns_eprins2'};
	local ($ok, $msg) = &check_resolvability($in->{'prins'});
	if (!$ok) {
		return &text('wizard_dns_eprins3', $msg);
		}
	}
$tmpl->{'dns_master'} = $in->{'prins'};
&save_template($tmpl);

# Validate any secondary NSs
local @secns;
foreach my $ns (split(/\s+/, $in->{'secns'})) {
	$ns =~ /^[a-z0-9\.\_\-]+$/i || return &text('wizard_dns_esecns', $ns);
	if (!$in->{'prins_skip'}) {
		&to_ipaddress($ns) || return &text('wizard_dns_esecns2', $ns);
		local ($ok, $msg) = &check_resolvability($ns);
		if (!$ok) {
			return &text('wizard_dns_esecns3', $ns, $msg);
			}
		}
	push(@secns, $ns);
	}
$tmpl->{'dns_ns'} = join(" ", @secns);
&save_template($tmpl);

# Save skip option
$config{'prins_skip'} = $in{'prins_skip'};
&save_module_config();
}

sub wizard_show_email
{
&foreign_require("mailboxes");
print &ui_table_row(undef, $text{'wizard_email_desc'}, 2);

print &ui_table_row($text{'wizard_from_addr'},
	&ui_opt_textbox("from_addr", $config{'from_addr'}, 50,
		$text{'default'}." (".&mailboxes::get_from_address().")<br>",
		$text{'wizard_from_addr2'}));
}

sub wizard_parse_email
{
local ($in) = @_;
if ($in->{'from_addr_def'}) {
	delete($config{'from_addr'});
	}
else {
	$in->{'from_addr'} =~ /\S+\@\S+/ || return $text{'wizard_efrom_addr'};
	$config{'from_addr'} = $in->{'from_addr'};
	&save_module_config();
	}
}

sub wizard_show_done
{
print &ui_table_row(undef, $text{'wizard_done'}, 2);

print &ui_table_row(undef, $text{'wizard_done2'}, 2);
}

sub wizard_show_alldone
{
print &ui_table_row(undef, &text('wizard_alldone'), 2);
}

sub wizard_parse_alldone
{
return undef;	# Always works
}

# wizard_show_hashpass()
# Ask the user if he wants to enable storage of hashed passwords only
sub wizard_show_hashpass
{
print &ui_table_row(undef, "$text{'wizard_hashpass'} $text{'wizard_hashpass_warn'}<br>", 2);

local $tmpl = &get_template(0);
print &ui_table_row($text{'wizard_hashpass_mode'},
	&ui_radio("hashpass", $tmpl->{'hashpass'} ? 1 : 0,
		  [ [ 0, $text{'wizard_hashpass_mode0'}."<br>" ],
		    [ 1, $text{'wizard_hashpass_mode1'} ] ]));
}

# wizard_parse_hashpass(&in)
# Parse the hashed password setting
sub wizard_parse_hashpass
{
local ($in) = @_;

# Update default template
local @tmpls = &list_templates();
local ($tmpl) = grep { $_->{'id'} eq '0' } @tmpls;
$tmpl || return $text{'wizard_etmpl0'};
$tmpl->{'hashpass'} = $in->{'hashpass'};
&save_template($tmpl);

# If not storing hashed passwords, need to have Usermin read mail files directly
if ($in->{'hashpass'} && &foreign_check("usermin")) {
	# Make sure read mail module is installed, and setup to use local
	# mail files
	&foreign_require("usermin");
	return undef if (!&usermin::get_usermin_module_info("mailbox"));
	my %mconfig;
	my $cfile = "$usermin::config{'usermin_dir'}/mailbox/config";
	&lock_file($cfile);
	&read_file($cfile, \%mconfig);
	return undef if ($mconfig{'mail_system'} != 4);

	# Force use of local mail files instead
	my ($mail_base, $mail_style, $mail_file, $mail_dir) = &get_mail_style();
	if ($mail_dir) {
		$mconfig{'mail_system'} = 1;
		$mconfig{'mail_qmail'} = $mail_base;
		$mconfig{'mail_style'} = $mail_style;
		$mconfig{'mail_dir_qmail'} = $mail_dir;
		}
	else {
		$mconfig{'mail_system'} = 0;
		$mconfig{'mail_dir'} = $mail_base;
		$mconfig{'mail_style'} = $mail_style;
		$mconfig{'mail_file'} = $mail_file;
		}
	&write_file($cfile, \%mconfig);
	&unlock_file($cfile);
	}

return undef;
}

sub wizard_show_ssldir
{
print &ui_table_row(undef, $text{'wizard_ssldir'} . "<p></p>", 2);

my $tmpl = &get_template(0);
my $mode;
if ($tmpl->{'cert_key_tmpl'} &&
    $tmpl->{'cert_cert_tmpl'} eq 'auto' &&
    $tmpl->{'cert_ca_tmpl'} eq 'auto' &&
    $tmpl->{'cert_combined_tmpl'} eq 'auto' &&
    $tmpl->{'cert_everything_tmpl'} eq 'auto') {
	# Some custom dir
	if ($tmpl->{'cert_key_tmpl'} eq $ssl_certificate_dir."/ssl.key") {
		# Standard dir
		$mode = 1;
		}
	else {
		$mode = 2;
		}
	}
elsif (!$tmpl->{'cert_key_tmpl'} &&
       !$tmpl->{'cert_cert_tmpl'} &&
       !$tmpl->{'cert_ca_tmpl'} &&
       !$tmpl->{'cert_combined_tmpl'} &&
       !$tmpl->{'cert_everything_tmpl'}) {
	# Default which uses home dir
	$mode = 0;
	}
else {
	# Some other setting
	$mode = 3;
	}
my @opts = ( [ 0, $text{'wizard_ssldir_mode0'} ],
	     [ 1, &text('wizard_ssldir_mode1',
			"<tt>$ssl_certificate_parent</tt>&nbsp;") ] );
if ($mode == 2) {
	push(@opts, [ 2, $text{'wizard_ssldir_mode2'},
			 &ui_textbox("ssldir_custom",
				$tmpl->{'cert_key_tmpl'}, 40) ]);
	}
if ($mode == 3) {
	push(@opts, [ 3, $text{'wizard_ssldir_mode3'} ]);
	}
print &ui_table_row($text{'wizard_ssldir_mode'},
	&ui_radio_table("ssldir", $mode, \@opts));
}

# wizard_parse_ssldir(&in)
# Save SSL cert directory options
sub wizard_parse_ssldir
{
my ($in) = @_;
my @tmpls = &list_templates();
my ($tmpl) = grep { $_->{'id'} eq '0' } @tmpls;
$tmpl || return $text{'wizard_etmpl0'};
if ($in->{'ssldir'} == 0) {
	# Fall back to the default
	delete($tmpl->{'cert_key_tmpl'});
	delete($tmpl->{'cert_cert_tmpl'});
	delete($tmpl->{'cert_ca_tmpl'});
	delete($tmpl->{'cert_combined_tmpl'});
	delete($tmpl->{'cert_everything_tmpl'});
	}
elsif ($in->{'ssldir'} == 1 || $in->{'ssldir'} == 2) {
	if ($in->{'ssldir'} == 1) {
		# Standard key dir
		$tmpl->{'cert_key_tmpl'} = $ssl_certificate_dir."/ssl.key";
		}
	else {
		# Custom key template
		$in{'ssldir_custom'} =~ /\S/ || &error($text{'wizard_essldir'});
		}
	$tmpl->{'cert_cert_tmpl'} = 'auto';
	$tmpl->{'cert_ca_tmpl'} = 'auto';
	$tmpl->{'cert_combined_tmpl'} = 'auto';
	$tmpl->{'cert_everything_tmpl'} = 'auto';
	}
if ($in->{'ssldir'} != 3) {
	&save_template($tmpl);
	}
}

# get_real_memory_size()
# Returns the amount of RAM in bytes, or undef if we can't get it
sub get_real_memory_size
{
return undef if (!&foreign_check("proc"));
&foreign_require("proc");
return undef if (!defined(&proc::get_memory_info));
local ($real) = &proc::get_memory_info();
return $real * 1024;
}

# get_uname_arch()
# Returns the architecture, like x86_64 or i386
sub get_uname_arch
{
local $out = &backquote_command("uname -m");
$out =~ s/\s+//g;
return $out;
}

1;
