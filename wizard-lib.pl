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
	 "defdom",
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
print &ui_table_row(undef, $text{'wizard_virusnew'}, 2);
local $cs = &check_clamd_status();
if ($cs != -1) {
	$cs = 2 if (!$cs && $config{'virus'});
	print &ui_table_row($text{'wizard_virusmsg'},
		&ui_radio("clamd", $cs,
			  [ [ 1, $text{'wizard_virus1'}."<br>" ],
			    $cs == 2 ? ( [ 2, $text{'wizard_virus2'} ] ) : ( ),
			    [ 0, $text{'wizard_virus0'} ] ]));
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
	if ($in->{'clamd'} == 1 && !$cs) {
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

	print &ui_table_row($text{'wizard_mysql_empty'},
		&ui_textbox("mypass", undef, 20)."<br>\n".
		&ui_checkbox("forcepass", 1, $text{'wizard_mysql_forcepass'}, 0));
	}
else {
	# Offer to change the password
	print &ui_table_row(undef, $text{'wizard_mysql'} . " " .
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
			&ui_textbox("mypass", &random_password(16), 20));
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
local $pass = $in->{'mypass'};
local $user = $mysql::mysql_login || 'root';
&require_mysql();
$mysql::mysql_pass = $pass;
$mysql::authstr = &mysql::make_authstr();
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
			&execute_password_change_sql(undef, $user, undef, $pass);
			};
		&update_webmin_mysql_pass($user, $pass) if (!$@);
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
if (!&list_domains() && !$config{'mysql_user_size'}) {
	eval {
		local $main::error_must_die = 1;
		my @str = &mysql::table_structure($mysql::master_db, "user");
		my ($ufield) = grep { lc($_->{'field'}) eq 'user' } @str;
		if ($ufield && $ufield->{'type'} =~ /\((\d+)\)/) {
			$config{'mysql_user_size'} = $1;
			&save_module_config();
			}
		};
	}

return undef;
}

# Show a form to select the MySQL size configuration
sub wizard_show_mysize
{
print &ui_table_row(undef, $text{'wizard_mysize'}, 2);

&require_mysql();
if (-r $mysql::config{'my_cnf'}) {
	local $mem = &get_real_memory_size();
	local $mysize = $config{'mysql_size'} || "";
	local $recsize;
	if ($mem) {
		$recsize = $mem <= 256*1024*1024 ? "small" :
			   $mem <= 512*1024*1024 ? "medium" :
			   $mem <= 1024*1024*1024 ? "large" : "huge";
		}
	my @types = &list_mysql_size_setting_types();
	my $conf = &mysql::get_mysql_config();
	my $currt;
	foreach my $t (@types) {
		my ($oneset) = &list_mysql_size_settings($t);
		my $sname = $oneset->[2] || "mysqld";
		my ($sect) = grep { $_->{'name'} eq $sname &&
				    $_->{'members'} } @$conf;
		if ($sect) {
			my $v = &mysql::find_value($oneset->[0], $sect->{'members'});
			if ($v && $v eq $oneset->[1]) {
				$currt = $t;
				}
			}
		}
	my $def_msg;
	if ($currt) {
		$def_msg = $text{"wizard_mysize_$currt"};
		($def_msg) = $def_msg =~ /(.*?\(\d+.+?\S*\))/;
		}
	print &ui_table_row($text{'wizard_mysize_type'},
		    &ui_radio_table("mysize", $mysize,
		      [ [ "", $text{'wizard_mysize_def'}.
			      ($def_msg ? " - $def_msg" : "") ],
			map { [ $_, $text{'wizard_mysize_'.$_}.
			        ($_ eq $recsize ? " $text{'wizard_myrec'}" : "")
			      ] } @types ]));
	}
else {
	print &ui_table_row(&text('wizard_mysize_ecnf',
				  "<tt>$mysql::config{'my_cnf'}</tt>"));
	}
}

sub wizard_parse_mysize
{
local ($in) = @_;
&require_mysql();
if ($in->{'mysize'} && -r $mysql::config{'my_cnf'}) {
	# Stop MySQL
	local $running = &mysql::is_mysql_running();
	my ($myver, $variant);
	if ($running) {

		# Get MySQL/MariaDB version and variant before stopping it
		($myver, $variant) = &get_dom_remote_mysql_version();
		&mysql::stop_mysql();
		}

	# Adjust my.cnf
	my $temp = &transname();
	my $conf = &mysql::get_mysql_config();
	my @files = &unique(map { $_->{'file'} } @$conf);
	foreach my $file (@files) {
		my $bf = $file;
		$bf =~ s/.*\///;
		&copy_source_dest($file, $temp."_".$bf);
		&lock_file($file);
		}
	foreach my $s (&list_mysql_size_settings($in->{'mysize'}, $myver, $variant)) {
		my $sname = $s->[2] || "mysqld";
		my ($sect) = grep { $_->{'name'} eq $sname &&
				    $_->{'members'} } @$conf;
		if ($sect) {
			&mysql::save_directive($conf, $sect, $s->[0],
					       $s->[1] ? [ $s->[1] ] : [ ]);
			}
		}
	foreach my $file (@files) {
		&flush_file_lines($file, undef, 1);
		&unlock_file($file);
		}
	$config{'mysql_size'} = $in->{'mysize'};

	# Start it up again
	if ($running) {
		&mysql::stop_mysql();
		my $err = &mysql::start_mysql();
		if ($err) {
			# Panic! MySQL couldn't start with the new config ..
			# try to roll it back
			foreach my $file (@files) {
				my $bf = $file;
				$bf =~ s/.*\///;
				&copy_source_dest($temp."_".$bf, $file);
				}
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
print &ui_table_row(undef, &text('wizard_done'), 2);

# If user sets up a default domain, refresh navigation menu with it
if (defined(&theme_post_save_domain) && $in{'refresh'}) {
	my $dom = get_domain_by("dom", $in{'refresh'});
	&theme_post_save_domain($dom, 'create');
	}
}

sub wizard_parse_done
{
return undef;	# Always works
}

# wizard_show_hashpass()
# Ask the user if he wants to enable storage of hashed passwords only
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

# wizard_parse_hashpass(&in)
# Parse the hashed password setting
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

# wizard_show_defdom()
# Show a form asking if the user wants to create a default virtual server
sub wizard_show_defdom
{
my $already = &get_domain_by("defaultdomain", 1);
if ($already) {
	print &ui_hidden("defdom", 0);
	print &ui_table_row(undef,
		&text('wizard_defdom_exists', "<b><tt>@{[show_domain_name($already)]}</tt></b>"), 2);
	}
else {
	print &ui_table_row(undef, $text{'wizard_defdom'}, 2);
	my $def = $ENV{'SERVER_NAME'};
	if (&check_ipaddress($def) || &check_ip6address($def)) {
		# Try hostname instead
		$def = &get_system_hostname();
		if ($def !~ /\./) {
			my $def2 = &get_system_hostname(0, 1);
			$def = $def2 if ($def2 =~ /\./);
			}
		}
	print &ui_table_row($text{'wizard_defdom_mode'},
		&ui_radio("defdom", 1,
			  [ [ 0, $text{'wizard_defdom0'} ],
			    [ 1, $text{'wizard_defdom1'}." ".
				 &ui_textbox("defhost", $def, 20) ] ]));

	print &ui_table_row($text{'wizard_defdom_ssl'},
		&ui_radio("defssl", 2,
			  [ [ 0, $text{'wizard_defssl0'} ],
			    [ 1, $text{'wizard_defssl1'} ],
			    [ 2, $text{'wizard_defssl2'} ] ]));
	}
}

# wizard_parse_defdom(&in)
# Create a default virtual server, if requested
sub wizard_parse_defdom
{
my ($in) = @_;
return undef if (!$in->{'defdom'});

# Validate the domain name
my $dname = $in->{'defhost'};
my $err = &valid_domain_name($dname);
return $err if ($err);
my $clash = &get_domain_by("dom", $dname);
return &text('wizard_defdom_clash', $dname) if ($clash);
my $already = &get_domain_by("defaultdomain", 1);
return &text('wizard_defdom_already', $already->{'dom'}) if ($already);
&lock_domain_name($dname);

# Work out username / etc
my ($user, $try1, $try2) = &unixuser_name($dname);
$user || return &text('setup_eauto', $try1, $try2);
my ($group, $gtry1, $gtry2) = &unixgroup_name($dname, $user);
$group || return &text('setup_eauto2', $try1, $try2);
my $defip = &get_default_ip();
my $defip6 = &get_default_ip6();
my $template = &get_init_template();
my $plan = &get_default_plan();

# Work out prefix if needed, and check it
my $prefix ||= &compute_prefix($dname, $group, undef, 1);
$prefix =~ /^[a-z0-9\.\-]+$/i || return $text{'setup_eprefix'};
my $pclash = &get_domain_by("prefix", $prefix);
$pclash && return &text('setup_eprefix3', $prefix, $pclash->{'dom'});

# Create the virtual server object
my %dom;
%dom = ('id', &domain_id(),
		'dom', $dname,
		'user', $user,
		'group', $group,
		'ugroup', $group,
		'owner', $text{'wizard_defdom_desc'},
		'name', 1,
		'name6', 1,
		'ip', $defip,
		'dns_ip', &get_dns_ip(),
		'virt', 0,
		'virtalready', 0,
		'ip6', $ip6,
		'virt6', 0,
		'virt6already', 0,
		'pass', &random_password(),
		'quota', 0,
		'uquota', 0,
		'source', 'wizard.cgi',
		'template', $template,
		'plan', $plan->{'id'},
		'prefix', $prefix,
		'nocreationmail', 1,
		'hashpass', 0,
		'defaultdomain', 1,
        );

# Set initial features
$dom{'dir'} = 1;
$dom{'unix'} = 1;
$dom{'dns'} = 1;
my $webf = &domain_has_website();
my $sslf = &domain_has_ssl();
$dom{$webf} = 1;
if ($in->{'defssl'}) {
	$dom{$sslf} = 1;
	if ($in->{'defssl'} == 2) {
		$dom{'auto_letsencrypt'} = 1;
		}
	else {
		$dom{'auto_letsencrypt'} = 0;
		}
	}

# Fill in other default fields
&set_limits_from_plan(\%dom, $plan);
&set_capabilities_from_plan(\%dom, $plan);
$dom{'emailto'} = $dom{'user'}.'@'.&get_system_hostname();
$dom{'db'} = &database_name(\%dom);
&set_featurelimits_from_plan(\%dom, $plan);
&set_chained_features(\%dom, undef);
&set_provision_features(\%dom);
&generate_domain_password_hashes(\%dom, 1);
$dom{'home'} = &server_home_directory(\%dom, undef);
&complete_domain(\%dom);

# Check for various clashes
$derr = &virtual_server_depends(\%dom);
return $derr if ($derr);
$cerr = &virtual_server_clashes(\%dom);
return $cerr if ($cerr);
my @warns = &virtual_server_warnings(\%dom);
return join(" ", @warns) if (@warns);

# Create the server
&push_all_print();
&set_all_null_print();
my $err = &create_virtual_server(
	\%dom, undef, undef, 0, 0, $pass, $dom{'owner'});
&pop_all_print();
return $err if ($err);

&run_post_actions_silently();
&unlock_domain_name($dname);

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
