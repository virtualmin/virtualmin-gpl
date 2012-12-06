# Functions for the post-install wizard

# If the wizard should be invoked, returns a URL for it. For calling by themes
sub wizard_redirect
{
if (&master_admin() &&
    ($config{'wizard_run'} eq '' && $config{'first_version'} >= 3.69 ||
     $config{'wizard_run'} eq '0')) {
	return "$gconfig{'webprefix'}/$module_name/wizard.cgi";
	}
return undef;
}

sub get_wizard_steps
{
return ( "intro",
	 "memory",
	 $config{'virus'} ? ( "virus" ) : ( ),
	 $config{'spam'} ? ( "spam" ) : ( ),
	 "db",
	 $config{'mysql'} ? ( "mysql", "mysize" ) : ( ),
	 $config{'dns'} ? ( "dns" ) : ( ),
	 "hashpass",
	 "done" );
}

sub wizard_show_intro
{
print &ui_table_row(undef,
	$text{'wizard_intro'}, 2);
}

# Show a form to enable or disable pre-loading and lookup-domain-daemon
sub wizard_show_memory
{
print &ui_table_row(undef, $text{'wizard_memory'}, 2);

local $mem = &get_uname_arch() =~ /64/ ? "40M" : "20M";
print &ui_table_row($text{'wizard_memory_preload'},
	&ui_radio("preload", $config{'preload_mode'} ? 1 : 0,
		  [ [ 1, &text('wizard_memory_preload1', $mem)."<br>" ],
		    [ 0, $text{'wizard_memory_preload0'} ] ]));

if ($config{'spam'}) {
	local $mem = &get_uname_arch() =~ /64/ ? "70M" : "35M";
	print &ui_table_row($text{'wizard_memory_lookup'},
		&ui_radio("lookup", &check_lookup_domain_daemon(),
			  [ [ 1, &text('wizard_memory_lookup1', $mem)."<br>" ],
			    [ 0, $text{'wizard_memory_lookup0'} ] ]));
	}
}

# Enable or disable pre-loading and lookup-domain-daemon
sub wizard_parse_memory
{
local ($in) = @_;
&push_all_print();
&set_all_null_print();

if ($in->{'preload'} && !$config{'preload_mode'}) {
	# Turn on preloading
	$config{'preload_mode'} = 2;
	&save_module_config();
	&update_miniserv_preloads(2);
	&restart_miniserv();
	}
elsif (!$in->{'preload'} && $config{'preload_mode'}) {
	# Turn off preloading
	$config{'preload_mode'} = 0;
	&save_module_config();
	&update_miniserv_preloads(0);
	&restart_miniserv();
	}

if ($config{'spam'}) {
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
	}

&pop_all_print();
return undef;
}

# Show a form asking the user if he wants to run clamd
sub wizard_show_virus
{
print &ui_table_row(undef, $text{'wizard_virus'}, 2);
local $cs = &check_clamd_status();
if ($cs != -1) {
	print &ui_table_row($text{'wizard_clamd'},
		&ui_radio("clamd", $cs ? 1 : 0,
			  [ [ 1, $text{'wizard_clamd1'}."<br>" ],
			    [ 0, $text{'wizard_clamd0'} ] ]));
	}
else {
	print &ui_table_row($text{'wizard_clamdnone'});
	}
}

# Parse the clamd form, and enable or disable clamd
sub wizard_parse_virus
{
local ($in) = @_;
if (defined($in->{'clamd'})) {
	local $cs = &check_clamd_status();
	if ($in->{'clamd'} && !$cs) {
		# Enable if needed
		&push_all_print();
		&set_all_null_print();
		local $ok = &enable_clamd();
		&pop_all_print();
		if ($ok) {
			# Switch to clamdscan, after testing
			local $last_err;
			for(my $try=0; $try<10; $try++) {
				$last_err = &test_virus_scanner("clamdscan");
				last if (!$last_err);
				if ($try == 0 && &has_command("freshclam")) {
					# First time around, try running
					# freshclam
					&backquote_with_timeout("freshclam",60);
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
		}
	elsif (!$in->{'clamd'} && $cs) {
		# Disable if needed
		&push_all_print();
		&set_all_null_print();
		&disable_clamd();
		&pop_all_print();
		&save_global_virus_scanner("clamscan");
		}
	}
return undef;
}

# Show a form asking the user if he wants to run spamd
sub wizard_show_spam
{
print &ui_table_row(undef, $text{'wizard_spam'}, 2);
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
print &ui_table_row(undef, $text{'wizard_db'}, 2);
print &ui_table_row($text{'wizard_db_mysql'},
	&ui_radio("mysql", $config{'mysql'} ? 1 : 0,
		  [ [ 1, $text{'wizard_db_mysql1'}."<br>" ],
		    [ 0, $text{'wizard_db_mysql0'} ] ]));
print &ui_table_row($text{'wizard_db_postgres'},
	&ui_radio("postgres", $config{'postgres'} ? 1 : 0,
		  [ [ 1, $text{'wizard_db_postgres1'}."<br>" ],
		    [ 0, $text{'wizard_db_postgres0'} ] ]));
}

# Enable or disable MySQL and PostgreSQL, depending on user's selections
sub wizard_parse_db
{
local ($in) = @_;
&foreign_require("init", "init-lib.pl");

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
	if (&foreign_installed("mysql", 1) != 2) {
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
print &ui_table_row(undef, $text{'wizard_mysql'}.
		   ($mysql::mysql_pass ? $text{'wizard_mysql3'}
				       : $text{'wizard_mysql2'}), 2);
if ($mysql::mysql_pass) {
	print &ui_table_row($text{'wizard_mysql_pass'},
		&ui_opt_textbox("mypass", undef, 20,
				$text{'wizard_mysql_pass1'}."<br>",
				$text{'wizard_mysql_pass0'}));
	}
else {
	print &ui_table_row($text{'wizard_mysql_empty'},
		&ui_textbox("mypass", undef, 20));
	}
}

# Set the MySQL password, if changed
sub wizard_parse_mysql
{
local ($in) = @_;
&require_mysql();
if (!$in{'mypass_def'}) {
	# Change in DB
	local $esc = &mysql::escapestr($in->{'mypass'});
	local $user = $mysql::mysql_login || "root";
	&mysql::execute_sql_logged($mysql::master_db,
	    "update user set password = $mysql::password_func('$esc') ".
	    "where user = '$user'");
	&mysql::execute_sql_logged($mysql::master_db, 'flush privileges');

	# Update Webmin
	$mysql::config{'pass'} = $in->{'mypass'};
	&mysql::save_module_config(\%mysql::config, "mysql");
	}
return undef;
}

# Show a form to select the MySQL size configuration
sub wizard_show_mysize
{
print &ui_table_row(undef, $text{'wizard_mysize'}, 2);

local $mem = &get_real_memory_size();
local $mysize = $config{'mysql_size'};
if ($mem && !$mysize) {
	$mysize = $mem <= 256*1024*1024 ? "small" :
		  $mem <= 512*1024*1024 ? "medium" :
		  $mem <= 1024*1024*1024 ? "large" : "huge";
	}
print &ui_table_row($text{'wizard_mysize_type'},
	    &ui_radio("mysize", $mysize,
		      [ [ "", $text{'wizard_mysize_def'}."<br>" ],
			[ "small", $text{'wizard_mysize_small'}."<br>" ],
			[ "medium", $text{'wizard_mysize_medium'}."<br>" ],
			[ "large", $text{'wizard_mysize_large'}."<br>" ],
			[ "huge", $text{'wizard_mysize_huge'}."<br>" ] ]));
}

sub wizard_parse_mysize
{
local ($in) = @_;
&require_mysql();
if ($in->{'mysize'}) {
	# Stop MySQL
	local $running = &mysql::is_mysql_running();
	if ($running) {
		&mysql::stop_mysql();
		}

	# Adjust my.cnf
	my $temp = &transname();
	&copy_source_dest($mysql::config{'my_cnf'}, $temp);
	&lock_file($mysql::config{'my_cnf'});
	my $conf = &mysql::get_mysql_config();
	foreach my $s (&list_mysql_size_settings($in->{'mysize'})) {
		my $sname = $s->[2] || "mysqld";
		my ($sect) = grep { $_->{'name'} eq $sname &&
				    $_->{'members'} } @$conf;
		if ($sect) {
			&mysql::save_directive($conf, $sect, $s->[0],
					       $s->[1] ? [ $s->[1] ] : [ ]);
			}
		}
	&flush_file_lines($mysql::config{'my_cnf'});
	&unlock_file($mysql::config{'my_cnf'});
	$config{'mysql_size'} = $in->{'mysize'};

	# Start it up again
	if ($running) {
		&mysql::stop_mysql();
		my $err = &mysql::start_mysql();
		if ($err) {
			# Panic! MySQL couldn't start with the new config ..
			# try to roll it back
			&copy_source_dest($temp, $mysql::config{'my_cnf'});
			&mysql::start_mysql();
			return &text('wizard_emysizestart', $err);
			}
		}
	}
&lock_file($module_config_file);
&save_module_config();
&unlock_file($module_config_file);
return undef;
}

# Show a form to set the primary nameservers
sub wizard_show_dns
{
&require_bind();
print &ui_table_row(undef, $text{'wizard_dns'}, 2);

# Primary nameserver
local $tmpl = &get_template(0);
local $tmaster = $tmpl->{'dns_master'} eq 'none' ? undef
						 : $tmpl->{'dns_master'};
local $master = $tmaster ||
		$bconfig{'default_prins'} ||
		&get_system_hostname();
print &ui_table_row($text{'wizard_dns_prins'},
		    &ui_textbox("prins", $master, 40)." ".
		    &ui_checkbox("prins_skip", 1, $text{'wizard_dns_skip'}, 0));

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
}

sub wizard_show_done
{
print &ui_table_row(undef,
	&text('wizard_done', 'edit_newfeatures.cgi', 'edit_newsv.cgi'), 2);
}

sub wizard_parse_done
{
return undef;	# Always works
}

sub wizard_show_hashpass
{
print &ui_table_row(undef, $text{'wizard_hashpass'}, 2);

local $tmpl = &get_template(0);
print &ui_table_row($text{'wizard_hashpass_mode'},
	&ui_radio("hashpass", $tmpl->{'hashpass'} ? 1 : 0,
		  [ [ 0, $text{'wizard_hashpass_mode0'}."<br>" ],
		    [ 1, $text{'wizard_hashpass_mode1'} ] ]));
print &ui_table_row(undef, "<b>$text{'wizard_hashpass_warn'}</b>", 2);
}

sub wizard_parse_hashpass
{
local ($in) = @_;

# Update default template
local @tmpls = &list_templates();
local ($tmpl) = grep { $_->{'id'} eq '0' } @tmpls;
$tmpl->{'hashpass'} = $in->{'hashpass'};
&save_template($tmpl);

# If not storing hashed passwords, need to have Usermin read mail files directly
if ($in->{'hashpass'} && &foreign_check("usermin")) {
	# Make sure read mail module is installed, and setup to use local
	# mail files
	&foreign_require("usermin", "usermin-lib.pl");
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

