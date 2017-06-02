# Functions for managing Postgrey and Postfix

@postgrey_data_types = ( 'clients', 'recipients' );
use Socket;

# check_postgrey()
# Returns undef if Postgrey is installed, or an error message if not
sub check_postgrey
{
if ($config{'mail_system'} != 0) {
	return $text{'postgrey_epostfix'};
	}
elsif (!&has_command("postgrey")) {
	return &text('postgrey_ecmd', "<tt>postgrey</tt>");
	}
elsif (!defined(getpwnam("postgrey"))) {
	return &text('postgrey_euser', "<tt>postgrey</tt>");
	}
else {
	return undef;
	}
}

# can_install_postgrey()
# Returns 1 if Postgrey can possibly be installed on this OS
sub can_install_postgrey
{
if ($gconfig{'os_type'} eq 'debian-linux' ||
    $gconfig{'os_type'} eq 'redhat-linux') {
	&foreign_require("software");
	return defined(&software::update_system_install);
	}
return 0;
}

# install_postgrey_package()
# Attempt to install Postgrey, outputting progress messages
sub install_postgrey_package
{
&foreign_require("software");
local @inst = &software::update_system_install("postgrey");
return scalar(@inst) || !&check_postgrey();
}

# Returns the init script name for postgrey's daemon
sub get_postgrey_init
{
return "postgrey";
}

# get_postgrey_args()
# Returns the Postgrey command-line arguments
sub get_postgrey_args
{
local $ofile = "/etc/default/postgrey";
local $postgrey = &has_command("postgrey");

# First try running process
&foreign_require("proc");
foreach my $p (&proc::list_processes()) {
	if ($p->{'args'} =~ /^(postgrey|\Q$postgrey\E|\/\S+\/postgrey)\s+(.*)/) {
		return $2;
		}
	}

if (-r $ofile) {
	# Get from options file on Debian
	my $lref = &read_file_lines($ofile, 1);
	foreach my $l (@$lref) {
		if ($l =~ /^\s*POSTGREY_OPTS="(.*)"/) {
			return $1;
			}
		}
	}

&foreign_require("init");
if ($init::init_mode eq 'init') {
	# Last try checking the init script
	local $ifile = &init::action_filename(&get_postgrey_init());
	my $lref = &read_file_lines($ifile, 1);
	foreach my $l (@$lref) {
		if ($l =~ /\Q$postgrey\E\s+(.*)/i) {
			return $1;
			}
		}
	}
return undef;
}

# get_postgrey_port()
# Returns the port on which postgrey listens
sub get_postgrey_port
{
local $args = &get_postgrey_args();
if ($args =~ /--inet=(\S+)/) {
	# TCP port
	local $opts = $1;
	if ($opts =~ /^(\S+):(\d+)$/) {
		return $2;
		}
	elsif ($opts =~ /^\d+$/) {
		return $opts;
		}
	}
elsif ($args =~ /--unix=(\/\S+)/) {
	# Unix socket file
	return $1;
	}
return undef;
}

# is_postgrey_enabled()
# Returns 1 if so, 0 if not. Checks if the daemon is running, and Postfix is
# configured to use it.
sub is_postgrey_enabled
{
if (!&find_byname("postgrey")) {
	# Not running
	return 0;
	}
&foreign_require("init");
if (&init::action_status(&get_postgrey_init()) != 2) {
	# Not enabled at boot
	return 0;
	}
local $port = &get_postgrey_port();
if (!$port) {
	# No port, so we can't tell!
	return 0;
	}
&require_mail();
local $rr = &postfix::get_real_value("smtpd_recipient_restrictions");
if ($rr =~ /check_policy_service\s+inet:\S+:\Q$port\E/ ||
    $rr =~ /check_policy_service\s+unix:\Q$port\E/) {
	return 1;
	}
return 0;
}

# enable_postgrey()
# Turns on greylisting by starting the daemon and configuring Postfix. May
# print stuff. Returns 1 on success or 0 on failure.
sub enable_postgrey
{
# Enable at boot
&foreign_require("init");
local $init = &get_postgrey_init();
local $port = &get_postgrey_port();
&$first_print($text{'postgrey_init'});
if (&init::action_status($init) != 2) {
	if (!$port) {
		# Pick a random port now
		$port = &allocate_random_port(60000);
		}
	local $postgrey = &has_command("postgrey");
	&init::enable_at_boot(
		$init,
		'Start the Postgrey greylisting server',
		$postgrey." -d ".($port =~ /^\// ? "--unix=$port"
					         : "--inet=$port"),
		"killall -9 postgrey");
	&$second_print($text{'postgrey_initdone'});
	}
else {
	&$second_print($text{'postgrey_initalready'});
	}

# Start process
&$first_print($text{'postgrey_proc'});
if (!&find_byname("postgrey")) {
	local ($ok, $out) = &init::start_action($init);
	if (!$ok) {
		&$second_print(&text('postgrey_procfailed',
				     "<tt>".&html_escape($out)."</tt>"));
		return 0;
		}
	&$second_print($text{'postgrey_procdone'});
	}
else {
	&$second_print($text{'postgrey_procalready'});
	}
$port = &get_postgrey_port();	# In case we got it from the running
				# process after the init script started

# Configure Postfix and restart
&$first_print($text{'postgrey_postfix'});
&require_mail();
local $rr = &postfix::get_real_value("smtpd_recipient_restrictions");
if ($rr =~ /check_policy_service\s+inet:\S+:\Q$port\E/ ||
    $rr =~ /check_policy_service\s+unix:\Q$port\E/) {
	# Already OK
	&$second_print($text{'postgrey_postfixalready'});
	}
else {
	local $wantport = $port =~ /^\// ? "unix:$port"
					 : "inet:127.0.0.1:$port";
	if ($rr =~ /(.*)check_policy_service\s+(inet|unix):[^, ]+(.*)/) {
		# Wrong port?!
		$rr = $1."check_policy_service ".$wantport.$3;
		}
	else {
		# Need to setup
		$rr .= " check_policy_service ".$wantport;
		}
	&postfix::set_current_value("smtpd_recipient_restrictions", $rr);
	&postfix::reload_postfix();
	&$second_print(&text('postgrey_postfixdone', $port));
	}

return 1;
}

# disable_postgrey()
# Turns off greylisting by stopping the daemon and configuring Postfix. May
# print stuff.
sub disable_postgrey
{
# Remove from Postfix configuration
&$first_print($text{'postgrey_nopostfix'});
local $port = &get_postgrey_port();
local $init = &get_postgrey_init();
&require_mail();
local $rr = &postfix::get_real_value("smtpd_recipient_restrictions");
if ($rr =~ /^(.*)\s*check_policy_service\s+inet:\S+:\Q$port\E(.*)/ ||
    $rr =~ /^(.*)\s*check_policy_service\s+unix:\Q$port\E(.*)/) {
	$rr = $1.$2;
	&postfix::set_current_value("smtpd_recipient_restrictions", $rr);
	&postfix::reload_postfix();
	&$second_print($text{'postgrey_nopostfixdone'});
	}
else {
	&$second_print($text{'postgrey_nopostfixalready'});
	}

# Kill the process
&foreign_require("init");
local $init = &get_postgrey_init();
&$first_print($text{'postgrey_noproc'});
if (&find_byname("postgrey")) {
	local ($ok, $out) = &init::stop_action($init);
	if (!$ok) {
		&$second_print(&text('postgrey_noprocfailed',
				     "<tt>".&html_escape($out)."</tt>"));
		}
	else {
		&$second_print($text{'postgrey_noprocdone'});
		}
	}
else {
	&$second_print($text{'postgrey_noprocalready'});
	}

# Disable at boot
&$first_print($text{'postgrey_noinit'});
if (&init::action_status($init) == 2) {
	&init::disable_at_boot($init);
	&$second_print($text{'postgrey_noinitdone'});
	}
else {
	&$second_print($text{'postgrey_noinitalready'});
	}
}

# allocate_random_port(base)
# Find a socket that isn't currently in use
sub allocate_random_port
{
local ($port) = @_;
local $proto = getprotobyname('tcp');
if (!socket(RANDOMSOCK, PF_INET, SOCK_STREAM, $proto)) {
	&error("socket failed : $!");
	}
setsockopt(RANDOMSOCK, SOL_SOCKET, SO_REUSEADDR, pack("l", 1));
while(1) {
	$port++;
	last if (bind(RANDOMSOCK, sockaddr_in($port, INADDR_ANY)));
	}
close(RANDOMSOCK);
return $port;
}

# get_postgrey_data_file("clients"|"recipients")
# Returns the full path to the file containing some Postgrey data, like
# whitelisted clients or senders
sub get_postgrey_data_file
{
local ($type) = @_;
local $args = &get_postgrey_args();
if ($args =~ /--whitelist-\Q$type\E=(\S+)/) {
	return $1;
	}
local $out = &backquote_command("postgrey -h 2>&1");
if ($out =~ /--whitelist-\Q$type\E=.*default:\s+(\S+)/) {
	return $1;
	}
return undef;
}

# list_postgrey_data(type)
# Returns a list of Postgrey configuration entries of some type, as an array ref
sub list_postgrey_data
{
local ($type) = @_;
local $file = &get_postgrey_data_file($type);
return undef if (!$file);
if (!$postgrey_data_cache{$type}) {
	local ($_, @rv, @cmts);
	local $lnum = 0;
	&open_readfile(POSTGREY, $file);
	while(<POSTGREY>) {
		s/\r|\n//g;
		if (/^\s*#+\s*(\S.*)$/) {
			# Comment line
			push(@cmts, $1);
			}
		elsif (/\S/ && !/^\s*#/) {
			# Actual line
			push(@rv, { 'line' => $lnum - scalar(@cmts),
				    'eline' => $lnum,
				    'file' => $file,
				    'value' => $_,
				    'index' => scalar(@rv),
				    'cmts' => [ @cmts ] });
			if ($rv[$#rv]->{'value'} =~ /^\/(.*)\/$/) {
				# Regular expression
				$rv[$#rv]->{'value'} = $1;
				$rv[$#rv]->{'re'} = 1;
				}
			@cmts = ( );
			}
		else {
			# Blank line (end of comments)
			@cmts = ( );
			}
		$lnum++;
		}
	close(POSTGREY);
	$postgrey_data_cache{$type} = \@rv;
	}
return $postgrey_data_cache{$type};
}

# create_postgrey_data(type, &data)
# Add an entry to a Postgrey whitelist file, and in-memory cache
sub create_postgrey_data
{
local ($type, $data) = @_;
local $file = &get_postgrey_data_file($type);
$file || &error("Failed to find file for $type");
local @newlines = &postgrey_data_lines($data);
local $lref = &read_file_lines($file);
if ($postgrey_data_cache{$type}) {
	# Add to cache and set lines and index
	$data->{'line'} = scalar(@$lref);
	$data->{'eline'} = scalar(@$lref) + scalar(@newlines) - 1;
	$data->{'file'} = $file;
	$data->{'index'} = scalar(@{$postgrey_data_cache{$type}});
	push(@{$postgrey_data_cache{$type}}, $data);
	}
push(@$lref, @newlines);
&flush_file_lines($file);
}

# modify_postgrey_data(type, &data)
# Modify an entry in a Postgrey whitelist file
sub modify_postgrey_data
{
local ($type, $data) = @_;
local $file = &get_postgrey_data_file($type);
$file || &error("Failed to find file for $type");
local @newlines = &postgrey_data_lines($data);
local $oldlines = $data->{'eline'} - $data->{'line'} + 1;
local $lref = &read_file_lines($file);
splice(@$lref, $data->{'line'}, $oldlines, @newlines);
$data->{'eline'} = $data->{'line'} + scalar(@newlines) - 1;
if ($postgrey_data_cache{$type} && scalar(@newlines) != $oldlines) {
	# Fix lines in cache
	foreach my $c (@{$postgrey_data_cache{$type}}) {
		if ($c->{'line'} > $data->{'line'}) {
			$c->{'line'} += scalar(@newlines) - $oldlines;
			$c->{'eline'} += scalar(@newlines) - $oldlines;
			}
		}
	}
&flush_file_lines($file);
}

# delete_postgrey_data(type, &data)
# Remove an entry from a Postgrey whitelist file, and in-memory cache
sub delete_postgrey_data
{
local ($type, $data) = @_;
local $file = &get_postgrey_data_file($type);
$file || &error("Failed to find file for $type");
local $lref = &read_file_lines($file);
local $oldlines = $data->{'eline'} - $data->{'line'} + 1;
splice(@$lref, $data->{'line'}, $oldlines);
if ($postgrey_data_cache{$type}) {
	# Remove from cache and shift other lines and indexes down
	splice(@{$postgrey_data_cache{$type}}, $data->{'index'}, 1);
	foreach my $c (@{$postgrey_data_cache{$type}}) {
		if ($c->{'index'} > $data->{'index'}) {
			$c->{'index'}--;
			}
		if ($c->{'line'} > $data->{'line'}) {
			$c->{'line'} -= $oldlines;
			$c->{'eline'} -= $oldlines;
			}
		}
	}
&flush_file_lines($file);
}

sub postgrey_data_lines
{
local ($data) = @_;
local @rv;
push(@rv, map { "# $_" } @{$data->{'cmts'}});
push(@rv, $data->{'re'} ? "/".$data->{'value'}."/" : $data->{'value'});
return @rv;
}

# apply_postgrey_data()
# Send a HUP signal to have postgrey re-read it's data files
sub apply_postgrey_data
{
local $args = &get_postgrey_args();
local $pid;
if ($args =~ /--pidfile=(\S+)/) {
	local $pidfile = $1;
	$pid = &check_pid_file($pidfile);
	}
($pid) = &find_byname("postgrey") if (!$pid);
if ($pid) {
	return &kill_logged('HUP', $pid) ? 1 : 0;
	}
return 0;
}

# Lock all Postgrey configuration files
sub obtain_lock_postgrey
{
&obtain_lock_anything();
if ($main::got_lock_postgrey == 0) {
	foreach my $t (@postgrey_data_types) {
		my $file = &get_postgrey_data_file($t);
		&lock_file($file) if ($file);
		}
	}
$main::got_lock_postgrey++;
}

# Un-lock all Postgrey configuration files
sub release_lock_postgrey
{
if ($main::got_lock_postgrey == 1) {
	foreach my $t (@postgrey_data_types) {
		my $file = &get_postgrey_data_file($t);
		&unlock_file($file) if ($file);
		}
	}
$main::got_lock_postgrey-- if ($main::got_lock_postgrey);
&release_lock_anything();
}

1;

