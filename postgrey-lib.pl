# Functions for managing Postgrey and Postfix
# XXX centos support

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
if (-r $ofile) {
	# Get from options file on Debian
	my $lref = &read_file_lines($ofile, 1);
	foreach my $l (@$lref) {
		if ($l =~ /^\s*POSTGREY_OPTS="(.*)"/) {
			return $1;
			}
		}
	}
&foreign_require("init", "init-lib.pl");
if ($init::init_mode eq 'init') {
	# Next try checking the init script
	local $ifile = &init::action_filename(&get_postgrey_init());
	foreach my $l (@$lref) {
		if ($l =~ /\Q$postgrey\E\s+(.*)/i) {
			return $1;
			}
		}
	}
# Fall back to running process
&foreign_require("proc", "proc-lib.pl");
foreach my $p (&proc::list_processes()) {
	if ($p->{'args'} =~ /^(postgrey|\Q$postgrey\E)\s+(.*)/) {
		return $2;
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
	local $opts = $1;
	if ($opts =~ /^(\S+):(\d+)$/) {
		return $2;
		}
	elsif ($opts =~ /^\d+$/) {
		return $opts;
		}
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
&foreign_require("init", "init-lib.pl");
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
if ($rr =~ /check_policy_service\s+inet:\S+:(\d+)/ && $1 == $port) {
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
&foreign_require("init", "init-lib.pl");
local $init = &get_postgrey_init();
local $port = &get_postgrey_port();
&$first_print($text{'postgrey_init'});
if (&init::action_status($init) != 2) {
	if (!$port) {
		# Pick a random port now
		$port = &allocate_random_port(60000);
		}
	local $postgrey = &has_command("postgrey");
	&init::enable_at_boot($init, 'Start the Postgrey greylisting server',
			      "$postgrey --inet=$port -d",
			      "killall -9 postgrey");
	&$second_print(&text('postgrey_initdone', $port));
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

# Configure Postfix and restart
&$first_print($text{'postgrey_postfix'});
&require_mail();
local $rr = &postfix::get_real_value("smtpd_recipient_restrictions");
if ($rr =~ /check_policy_service\s+inet:\S+:(\d+)/ && $1 == $port) {
	# Already OK
	&$second_print($text{'postgrey_postfixalready'});
	}
else {
	if ($rr =~ /(.*)check_policy_service\s+inet:\S+:(\d+)(.*)/) {
		# Wrong port?!
		$rr = $1."check_policy_service inet:127.0.0.1:$port".$3;
		}
	else {
		# Need to setup
		$rr .= " check_policy_service inet:127.0.0.1:$port";
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
if ($rr =~ /^(.*)\s*check_policy_service\s+inet:\S+:(\d+)(.*)/ && $2 == $port) {
	$rr = $1.$3;
	&postfix::set_current_value("smtpd_recipient_restrictions", $rr);
	&postfix::reload_postfix();
	&$second_print($text{'postgrey_nopostfixdone'});
	}
else {
	&$second_print($text{'postgrey_nopostfixalready'});
	}

# Kill the process
&foreign_require("init", "init-lib.pl");
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
	last if (bind($fh, sockaddr_in($port, INADDR_ANY)));
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
			    'cmts' => [ @cmts ] });
		@cmts = ( );
		}
	else {
		# Blank line (end of comments)
		@cmts = ( );
		}
	$lnum++;
	}
close(POSTGREY);
return \@rv;
}

sub create_postgrey_data
{
}

sub modify_postgrey_data
{
}

sub delete_postgrey_data
{
}

1;

