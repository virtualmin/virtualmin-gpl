# Functions for managing Postgrey and Postfix

@postgrey_data_types = ( 'clients', 'recipients' );
use Socket;

# get_postgrey_type()
# Returns the greylisting backend type : postgrey or milter
sub get_postgrey_type
{
return 'postgrey' if (&has_command("postgrey"));
return 'milter' if (&should_use_milter_postgrey());
return 'milter' if (&get_milter_greylist_path() && &get_ratelimit_config_file());
return 'postgrey';
}

# should_use_milter_postgrey()
# Returns 1 if this OS should use milter-greylist instead of postgrey
sub should_use_milter_postgrey
{
return 0 if ($gconfig{'os_type'} ne 'redhat-linux');
my $real_type = $gconfig{'real_os_type'} || '';
my $real_version = $gconfig{'real_os_version'} || '';
my %el_like = map { $_, 1 } (
	'redhat enterprise linux',
	'red hat enterprise linux',
	'centos linux',
	'centos stream linux',
	'rocky linux',
	'almalinux',
	'cloudlinux',
	'oracle enterprise linux',
	'oracle linux',
	);
return 0 if (!$el_like{lc($real_type)});
if ($real_version =~ /^(\d+)/) {
	return $1 >= 10 ? 1 : 0;
	}

# Webmin maps EL-derived distributions to a Redhat-compatible version by
# adding 8 to the real major version, so Rocky 10 appears as 18.0 here.
return $gconfig{'os_version'} >= 18 ? 1 : 0;
}

# get_postgrey_package()
# Returns the package name to install for greylisting
sub get_postgrey_package
{
return &get_postgrey_type() eq 'milter' ||
       &should_use_milter_postgrey() ? "milter-greylist" : "postgrey";
}

# check_postgrey()
# Returns undef if Postgrey is installed, or an error message if not
sub check_postgrey
{
if (!$config{'mail'}) {
	}
elsif ($mail_system != 0) {
	return $text{'postgrey_epostfix'};
	}
elsif (&get_postgrey_type() eq 'milter') {
	if (!&get_milter_greylist_path()) {
		return &text('postgrey_ecmd', "<tt>milter-greylist</tt>");
		}
	my $cfile = &get_ratelimit_config_file();
	return &text('ratelimit_econfig', "<tt>$cfile</tt>")
		if (!$cfile || !-r $cfile);
	&foreign_require("init");
	my $init = &get_postgrey_init();
	return &text('ratelimit_einit', "<tt>$init</tt>")
		if (&get_ratelimit_type() ne 'source' &&
		    !&init::action_status($init));
	return undef;
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
my $pkg = &get_postgrey_package();
my @inst = &software::update_system_install($pkg);
return scalar(@inst) || !&check_postgrey();
}

# Returns the init script name for postgrey's daemon
sub get_postgrey_init
{
return &get_postgrey_type() eq 'milter' ? &get_ratelimit_init_name() :
					  "postgrey";
}

# get_postgrey_args()
# Returns the Postgrey command-line arguments
sub get_postgrey_args
{
return undef if (&get_postgrey_type() eq 'milter');
my $postgrey = &has_command("postgrey");

# First try running process
&foreign_require("proc");
foreach my $p (&proc::list_processes()) {
	if ($p->{'args'} =~ /^(postgrey|\Q$postgrey\E|\/\S+\/postgrey)\s+(.*)/) {
		return $2;
		}
	}

# Get from options file on Debian
my $ofile = "/etc/default/postgrey";
if (-r $ofile) {
	my $lref = &read_file_lines($ofile, 1);
	foreach my $l (@$lref) {
		if ($l =~ /^\s*POSTGREY_OPTS="(.*)"/) {
			return $1;
			}
		}
	}

# Get from options file on CentOS / Rocky 9
my $sfile = "/etc/sysconfig/postgrey";
if (-r $sfile) {
	my $lref = &read_file_lines($sfile, 1);
	foreach my $l (@$lref) {
		if ($l =~ /^\s*POSTGREY_TYPE="(.*)"/) {
			return $1;
			}
		}
	}

&foreign_require("init");
if ($init::init_mode eq 'init') {
	# Last try checking the init script
	my $ifile = &init::action_filename(&get_postgrey_init());
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
my $args = &get_postgrey_args();
if ($args =~ /--inet=(\S+)/) {
	# TCP port
	my $opts = $1;
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
return 0 if (!&is_postgrey_running());
&foreign_require("init");
if (&init::action_status(&get_postgrey_init()) != 2) {
	# Not enabled at boot
	return 0;
	}
if (&get_postgrey_type() eq 'milter') {
	return &is_postgrey_configured() &&
	       &is_postgrey_milter_greylisting_enabled();
	}
return &is_postgrey_configured();
}

# is_postgrey_running()
# Returns 1 if the postgrey server is running
sub is_postgrey_running
{
if (&get_postgrey_type() eq 'milter') {
	return &find_byname("milter-greylist") ? 1 : 0;
	}
return &find_byname("postgrey") ? 1 : 0;
}

# is_postgrey_service_expected()
# Returns 1 if the greylisting service should be running
sub is_postgrey_service_expected
{
&foreign_require("init");
return 1 if (&init::action_status(&get_postgrey_init()) == 2);
return &is_postgrey_configured();
}

# get_postgrey_service_status()
# Returns service status output for display when greylisting is not running
sub get_postgrey_service_status
{
&foreign_require("init");
my $init = &get_postgrey_init();
if ($init::init_mode eq "systemd" && &has_command("systemctl")) {
	my $unit = eval { &init::action_unit($init) };
	$unit ||= $init;
	return &backquote_command(
		"systemctl --no-pager status ".quotemeta($unit)." 2>&1");
	}
return undef;
}

# is_postgrey_configured()
# Returns 1 if Postfix is confgured to use Postgrey, 0 if not
sub is_postgrey_configured
{
if (&get_postgrey_type() eq 'milter') {
	my $socketfile = &get_postgrey_milter_socket();
	return 0 if (!$socketfile);
	return 0 if (!&is_postgrey_milter_greylisting_enabled());
	my $wantmilter = "local:$socketfile";
	&require_mail();
	my $milters = &postfix::get_real_value("smtpd_milters");
	return $milters =~ /\Q$wantmilter\E/ ? 1 : 0;
	}
my $port = &get_postgrey_port();
return 0 if (!$port);
&require_mail();
my $rr = &postfix::get_real_value("smtpd_recipient_restrictions");
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
if (&get_postgrey_type() eq 'milter') {
	return &enable_postgrey_milter();
	}

# Enable at boot
&foreign_require("init");
my $init = &get_postgrey_init();
my $port = &get_postgrey_port();
&$first_print($text{'postgrey_init'});
if (&init::action_status($init) != 2) {
	if (!$port) {
		# Pick a random port now
		$port = &allocate_random_port(60000);
		}
	my $postgrey = &has_command("postgrey");
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
	my ($ok, $out) = &init::start_action($init);
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
my $rr = &postfix::get_real_value("smtpd_recipient_restrictions");
if ($rr =~ /check_policy_service\s+inet:\S+:\Q$port\E/ ||
    $rr =~ /check_policy_service\s+unix:\Q$port\E/) {
	# Already OK
	&$second_print($text{'postgrey_postfixalready'});
	}
else {
	my $wantport = $port =~ /^\// ? "unix:$port"
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
	my $donetext = ($port =~ /^\//) ?
		'postgrey_postfixdone2' : 'postgrey_postfixdone';
	&$second_print(&text($donetext, "<tt>$port</tt>"));
	}

return 1;
}

# disable_postgrey()
# Turns off greylisting by stopping the daemon and configuring Postfix. May
# print stuff.
sub disable_postgrey
{
if (&get_postgrey_type() eq 'milter') {
	return &disable_postgrey_milter();
	}

# Remove from Postfix configuration
&$first_print($text{'postgrey_nopostfix'});
my $port = &get_postgrey_port();
my $init = &get_postgrey_init();
&require_mail();
my $rr = &postfix::get_real_value("smtpd_recipient_restrictions");
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
my $init = &get_postgrey_init();
&$first_print($text{'postgrey_noproc'});
if (&find_byname("postgrey")) {
	my ($ok, $out) = &init::stop_action($init);
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
my ($port) = @_;
my $proto = getprotobyname('tcp');
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

# get_postgrey_milter_socket()
# Returns the socket used by milter-greylist, relative to the mail chroot
sub get_postgrey_milter_socket
{
my $cfile = &get_ratelimit_config_file();
return undef if (!$cfile || !-r $cfile);
my $conf = &get_ratelimit_config();
my ($socket) = grep { $_->{'name'} eq 'socket' } @$conf;
return undef if (!$socket);
my $socketfile = $socket->{'value'};
my $chroot = &get_mailserver_chroot();
if ($chroot) {
	$socketfile =~ s/^\Q$chroot\E//;
	}
return $socketfile;
}

# get_postgrey_milter_acl_action_index(&directive)
# Returns the values index containing the ACL action, like greylist
sub get_postgrey_milter_acl_action_index
{
my ($dir) = @_;
return undef if ($dir->{'name'} ne 'racl' && $dir->{'name'} ne 'acl');
return undef if (!@{$dir->{'values'}});
return $dir->{'values'}->[0] =~ /^"/ && $dir->{'values'}->[1] ? 1 : 0;
}

# postgrey_milter_acl_is_default(&directive, action-index)
# Returns 1 if an ACL applies to the default rule
sub postgrey_milter_acl_is_default
{
my ($dir, $idx) = @_;
return $dir->{'values'}->[$idx+1] &&
       &postgrey_milter_unquote($dir->{'values'}->[$idx+1]) eq 'default';
}

# postgrey_milter_unquote(value)
# Removes milter-greylist quoting from a value
sub postgrey_milter_unquote
{
my ($value) = @_;
$value =~ s/^'(.*)'$/$1/;
$value =~ s/^"(.*)"$/$1/;
return $value;
}

# postgrey_milter_decode_value(value)
# Returns the value without regexp wrappers, and a regexp flag
sub postgrey_milter_decode_value
{
my ($value, $clause) = @_;
$value = &postgrey_milter_unquote($value);
if ($value =~ /^\/(.*)\/$/) {
	my $inner = $1;
	return ($inner, 0)
		if ($clause eq 'addr' && &postgrey_milter_is_ip_cidr($inner));
	return ($inner, 1);
	}
return ($value, 0);
}

# postgrey_milter_is_ip_cidr(value)
# Returns 1 if a value looks like an IPv4 or IPv6 address/network
sub postgrey_milter_is_ip_cidr
{
my ($value) = @_;
return 1 if ($value =~ /^(\d{1,3}\.){3}\d{1,3}(\/\d+)?$/);
return 1 if ($value =~ /^[0-9a-f:]+(\/\d+)?$/i && $value =~ /:/);
return 0;
}

# postgrey_milter_encode_value(&data)
# Converts a UI whitelist value into milter-greylist syntax
sub postgrey_milter_encode_value
{
my ($data) = @_;
return $data->{'re'} ? "/".$data->{'value'}."/" : $data->{'value'};
}

# get_postgrey_milter_data_clauses(type)
# Returns milter-greylist clauses that match a Postgrey data type
sub get_postgrey_milter_data_clauses
{
my ($type) = @_;
return $type eq 'clients' ? ( 'addr', 'domain' ) :
       $type eq 'recipients' ? ( 'rcpt' ) : ( );
}

# get_postgrey_milter_data_clause(type, &data)
# Returns the milter-greylist clause to use for a new whitelist entry
sub get_postgrey_milter_data_clause
{
my ($type, $data) = @_;
if ($type eq 'clients') {
	return &postgrey_milter_is_ip_cidr($data->{'value'}) ? 'addr' :
							       'domain';
	}
return $type eq 'recipients' ? 'rcpt' : undef;
}

# postgrey_milter_list_line_tokens(line)
# Returns member values from a physical list line
sub postgrey_milter_list_line_tokens
{
my ($line) = @_;
my $work = $line;
$work =~ s/#.*$//;
$work =~ s/\\\s*$//;
$work =~ s/^.*?\{// if ($work =~ /\{/);
$work =~ s/\}.*$//;
$work =~ s/^\s+//;
$work =~ s/\s+$//;
my $tokens = &wsplit_with_quotes($work);
return grep { /\S/ } @$tokens;
}

# list_postgrey_milter_list_members(&directive, clause)
# Returns list members while preserving source line details
sub list_postgrey_milter_list_members
{
my ($dir, $clause) = @_;
my $lref = &read_file_lines($dir->{'file'}, 1);
my @rv;
for(my $i=$dir->{'line'}; $i<=$dir->{'eline'}; $i++) {
	my $line = $lref->[$i];
	next if (!defined($line));
	my @tokens = &postgrey_milter_list_line_tokens($line);
	next if (!@tokens);
	my @cmts;
	if ($line =~ /#\s*(\S.*)$/) {
		@cmts = ( $1 );
		}
	foreach my $token (@tokens) {
		my ($value, $re) =
			&postgrey_milter_decode_value($token, $clause);
		push(@rv, {
			'raw_value' => $token,
			'line' => $dir->{'line'},
			'eline' => $dir->{'eline'},
			'file' => $dir->{'file'},
			'member_line' => $i,
			'line_tokens' => scalar(@tokens),
			'value' => $value,
			're' => $re,
			'cmts' => [ @cmts ],
			});
		}
	}
return @rv;
}

# postgrey_milter_comment_lines(&data)
# Returns config comment lines for a whitelist entry
sub postgrey_milter_comment_lines
{
my ($data) = @_;
return map { "# ".$_ } grep { /\S/ } @{$data->{'cmts'} || []};
}

# postgrey_milter_comment_is_description(comment)
# Returns 1 if a comment looks like a user description, not disabled config
sub postgrey_milter_comment_is_description
{
my ($comment) = @_;
$comment =~ s/^\s+//;
$comment =~ s/\s+$//;
return 0 if ($comment eq "");
my %config_words = map { $_, 1 } qw(
	racl acl dacl list addr domain from rawfrom rcpt ratelimit socket
	pidfile dumpfile dumpfreq geoipdb geoip2db geoipv6db dnsrbl
	urlcheck sm_macro peer syncaddr syncsrcaddr report domainexact
	greylist whitelist blacklist continue msg delay autowhite
	);
return 0 if ($comment =~ /^(\S+)/ && $config_words{lc($1)});
return 1;
}

# postgrey_milter_directive_comment_start(&directive)
# Returns the first contiguous comment line immediately above a directive
sub postgrey_milter_directive_comment_start
{
my ($dir) = @_;
my $lref = &read_file_lines($dir->{'file'}, 1);
my $start = $dir->{'line'};
while($start > 0) {
	my $line = $lref->[$start-1];
	last if (!defined($line) || $line !~ /^\s*#\s*(\S.*)$/ ||
		 !&postgrey_milter_comment_is_description($1));
	$start--;
	}
return $start;
}

# postgrey_milter_directive_comments(&directive)
# Returns comments immediately above a directive
sub postgrey_milter_directive_comments
{
my ($dir) = @_;
my $lref = &read_file_lines($dir->{'file'}, 1);
my $start = &postgrey_milter_directive_comment_start($dir);
my @rv;
for(my $i=$start; $i<$dir->{'line'}; $i++) {
	my $line = $lref->[$i];
	if ($line =~ /^\s*#\s*(\S.*)$/) {
		push(@rv, $1) if (&postgrey_milter_comment_is_description($1));
		}
	}
my $line = $lref->[$dir->{'line'}];
if ($line =~ /#\s*(\S.*)$/) {
	push(@rv, $1) if (&postgrey_milter_comment_is_description($1));
	}
return @rv;
}

# delete_postgrey_milter_directive(&directive)
# Deletes a directive and its immediately preceding comments
sub delete_postgrey_milter_directive
{
my ($dir) = @_;
my $lref = &read_file_lines($dir->{'file'});
my $start = &postgrey_milter_directive_comment_start($dir);
splice(@$lref, $start, $dir->{'eline'} - $start + 1);
&flush_file_lines($dir->{'file'});
}

# postgrey_milter_update_list_member_comment(line, &old-data, &new-data)
# Updates a one-entry list line with user comments
sub postgrey_milter_update_list_member_comment
{
my ($line, $old, $new) = @_;
return $line if (!$old || !$new || $old->{'line_tokens'} > 1);
my @cmts = grep { /\S/ } @{$new->{'cmts'} || []};
my $comment = join(" ", @cmts);
$line =~ s/\s*#.*$//;
$line =~ s/\s+$//;
$line .= " # ".$comment if ($comment ne "");
return $line;
}

# postgrey_milter_acl_action(&directive)
# Returns the action index and action name for a milter-greylist ACL
sub postgrey_milter_acl_action
{
my ($dir) = @_;
my $idx = &get_postgrey_milter_acl_action_index($dir);
return (undef, undef) if (!defined($idx));
return ($idx, $dir->{'values'}->[$idx]);
}

# replace_postgrey_milter_acl_action(&directive, action)
# Updates an ACL action in-place without reformatting the directive
sub replace_postgrey_milter_acl_action
{
my ($dir, $action) = @_;
my ($idx, $oldaction) = &postgrey_milter_acl_action($dir);
return 0 if (!defined($idx) || $oldaction eq $action);
my $file = $dir->{'file'};
my $lref = &read_file_lines($file);
my $line = $lref->[$dir->{'line'}];
return 0 if (!defined($line));
my $changed;
if ($idx == 0) {
	$changed = $line =~
		s/^(\s*(?:racl|acl)\s+)\Q$oldaction\E\b/$1$action/;
	}
else {
	my $tag = $dir->{'values'}->[0];
	$changed = $line =~
		s/^(\s*(?:racl|acl)\s+\Q$tag\E\s+)\Q$oldaction\E\b/$1$action/;
	}
return 0 if (!$changed);
$lref->[$dir->{'line'}] = $line;
&flush_file_lines($file);
return 1;
}

# update_postgrey_milter_default_action(action)
# Sets the first default ACL to the requested action, removing duplicate
# default ACLs that would otherwise be ignored by milter-greylist.
sub update_postgrey_milter_default_action
{
my ($action) = @_;
my $cfile = &get_ratelimit_config_file();
return 0 if (!$cfile || !-r $cfile);
&lock_file($cfile);
my $conf = &get_ratelimit_config();
my @defaults;
foreach my $c (@$conf) {
	my ($idx, $act) = &postgrey_milter_acl_action($c);
	next if (!defined($idx) || !&postgrey_milter_acl_is_default($c, $idx));
	push(@defaults, $c);
	}
my $changed = 0;
if (@defaults) {
	$changed += &replace_postgrey_milter_acl_action($defaults[0],
						       $action);
	if (@defaults > 1) {
		my @dups = reverse @defaults[1 .. $#defaults];
		foreach my $dup (@dups) {
			my ($current) = grep { $_->{'line'} == $dup->{'line'} }
					     @$conf;
			if ($current) {
				&save_ratelimit_directive($conf, $current,
							  undef);
				$changed++;
				}
			}
		&flush_file_lines($cfile) if ($changed);
		}
	}
else {
	&save_ratelimit_directive($conf, undef,
		{ 'name' => 'racl',
		  'values' => [ $action, 'default' ] },
		undef);
	&flush_file_lines($cfile);
	$changed++;
	}
&unlock_file($cfile);
return $changed;
}

# is_postgrey_milter_greylisting_enabled()
# Returns 1 if milter-greylist has a greylisting ACL
sub is_postgrey_milter_greylisting_enabled
{
my $cfile = &get_ratelimit_config_file();
return 0 if (!$cfile || !-r $cfile);
my $conf = &get_ratelimit_config();
foreach my $c (@$conf) {
	my ($idx, $action) = &postgrey_milter_acl_action($c);
	next if (!defined($idx) || !&postgrey_milter_acl_is_default($c, $idx));
	return $action eq 'greylist' ? 1 : 0;
	}
return 0;
}

# enable_postgrey_milter_greylisting()
# Enables the global milter-greylist ACL
sub enable_postgrey_milter_greylisting
{
return &update_postgrey_milter_default_action('greylist');
}

# disable_postgrey_milter_greylisting()
# Disables the global milter-greylist ACL
sub disable_postgrey_milter_greylisting
{
return &update_postgrey_milter_default_action('whitelist');
}

# postgrey_milter_has_ratelimits()
# Returns 1 if the milter-greylist config has rate-limit rules
sub postgrey_milter_has_ratelimits
{
my $cfile = &get_ratelimit_config_file();
return 0 if (!$cfile || !-r $cfile);
my $conf = &get_ratelimit_config();
foreach my $c (@$conf) {
	return 1 if ($c->{'name'} eq 'ratelimit');
	foreach my $v (@{$c->{'values'}}) {
		return 1 if ($v eq 'ratelimit');
		}
	}
return 0;
}

# update_postgrey_milter_socket()
# Adjusts the milter-greylist socket for Postfix and returns the socket file
sub update_postgrey_milter_socket
{
my $conf = &get_ratelimit_config();
my $chroot = &get_mailserver_chroot();
my $init = &get_postgrey_init();
my ($oldsocket) = grep { $_->{'name'} eq 'socket' } @$conf;
return undef if (!$oldsocket);
my $socketfile = $oldsocket->{'value'};
if ($chroot) {
	# Adjust the socket to ensure it is under the chroot
	if (!&is_under_directory($chroot, $socketfile) &&
	    $socketfile !~ /^\Q$chroot\E/) {
		my $newsocket = { 'name' => 'socket',
				  'values' => [ "\"$chroot$socketfile\"",
						'666' ] };
		&save_ratelimit_directive($conf, $oldsocket, $newsocket);
		&flush_file_lines($oldsocket->{'file'});
		}
	else {
		# Already under the chroot, so remove the chroot prefix
		$socketfile =~ s/^\Q$chroot\E//;
		}

	# Change path in init script and defaults file if needed
	foreach my $ifile (&init::action_filename($init),
			   "/etc/default/milter-greylist") {
		if ($ifile && -r $ifile) {
			my $lref = &read_file_lines($ifile);
			foreach my $l (@$lref) {
				if ($l =~ /^SOCKET\s*=/) {
					$l = "SOCKET=$chroot$socketfile";
					}
				}
			&flush_file_lines($ifile);
			&init::restart_systemd();
			}
		}

	# Make sure the socket file directory exists
	my $socketdir = "$chroot$socketfile";
	$socketdir =~ s/\/[^\/]+$//;
	if (!-d $socketdir) {
		&make_dir($socketdir, 0775, 1);
		my $user = &get_ratelimit_user();
		if ($user) {
			&set_ownership_permissions($user, undef, undef,
						   $socketdir);
			}
		}
	}

# Set socket to 666 permissions
my ($socket) = grep { $_->{'name'} eq 'socket' } @$conf;
if ($socket && $socket->{'values'}->[1] ne '666') {
	$socket->{'values'}->[1] = '666';
	&save_ratelimit_directive($conf, $socket, $socket);
	&flush_file_lines($socket->{'file'});
	}

return &get_postgrey_milter_socket();
}

# get_postgrey_milter_insert_before(&config)
# Returns the directive before which new whitelist ACLs should be inserted
sub get_postgrey_milter_insert_before
{
my ($conf) = @_;
foreach my $c (@$conf) {
	my ($idx, $action) = &postgrey_milter_acl_action($c);
	next if (!defined($idx));
	if ($action eq 'greylist') {
		return $c;
		}
	}
foreach my $c (@$conf) {
	my ($idx, $action) = &postgrey_milter_acl_action($c);
	next if (!defined($idx));
	if ($action eq 'whitelist' && &postgrey_milter_acl_is_default($c, $idx)) {
		return $c;
		}
	}
return undef;
}

# list_postgrey_milter_data(type)
# Returns milter-greylist whitelist entries matching a Postgrey data type
sub list_postgrey_milter_data
{
my ($type) = @_;
my $cfile = &get_ratelimit_config_file();
return undef if (!$cfile || !-r $cfile);
my $conf = &get_ratelimit_config();
my %clauses = map { $_, 1 } &get_postgrey_milter_data_clauses($type);
my %whitelists;
my @rv;

# First collect actively whitelisted list names
foreach my $c (@$conf) {
	my ($idx, $action) = &postgrey_milter_acl_action($c);
	next if (!defined($idx) || $action ne 'whitelist');
	for(my $i=$idx+1; $i<@{$c->{'values'}}; $i++) {
		if ($c->{'values'}->[$i] eq 'list' && $c->{'values'}->[$i+1]) {
			$whitelists{&postgrey_milter_unquote(
				$c->{'values'}->[$i+1])} = 1;
			}
		}
	}

foreach my $c (@$conf) {
	if ($c->{'name'} eq 'list') {
		my $name = &postgrey_milter_unquote($c->{'values'}->[0]);
		my $clause = $c->{'values'}->[1];
		next if (!$whitelists{$name} || !$clauses{$clause});
		foreach my $member (&list_postgrey_milter_list_members(
				    $c, $clause)) {
			$member->{'milter'} = 1;
			$member->{'source'} = 'list';
			$member->{'clause'} = $clause;
			$member->{'index'} = scalar(@rv);
			push(@rv, $member);
			}
		next;
		}

	my ($idx, $action) = &postgrey_milter_acl_action($c);
	next if (!defined($idx) || $action ne 'whitelist');
	my @matches;
	for(my $i=$idx+1; $i<@{$c->{'values'}}; $i++) {
		my $clause = $c->{'values'}->[$i];
		next if (!$clauses{$clause} || !$c->{'values'}->[$i+1]);
		my ($value, $re) =
			&postgrey_milter_decode_value($c->{'values'}->[$i+1],
						      $clause);
		push(@matches, [ $i, $clause, $value, $re ]);
		$i++;
		}
	next if (@matches != 1 || @{$c->{'values'}} != $idx+3);
	my ($i, $clause, $value, $re) = @{$matches[0]};
	push(@rv, {
		'milter' => 1,
		'source' => 'acl',
		'line' => $c->{'line'},
		'file' => $c->{'file'},
		'clause' => $clause,
		'vindex' => $i+1,
		'value' => $value,
		're' => $re,
		'cmts' => [ &postgrey_milter_directive_comments($c) ],
		'index' => scalar(@rv),
		});
	}
return \@rv;
}

# create_postgrey_milter_data(type, &data)
# Adds a milter-greylist whitelist ACL entry
sub create_postgrey_milter_data
{
my ($type, $data) = @_;
$data = { %$data };
if ($type eq 'clients' && &postgrey_milter_is_ip_cidr($data->{'value'})) {
	$data->{'re'} = 0;
	}
my $cfile = &get_ratelimit_config_file();
$cfile || &error("No milter-greylist configuration file found");
my $clause = &get_postgrey_milter_data_clause($type, $data);
$clause || &error("No milter-greylist clause for $type");
&lock_file($cfile);
my $conf = &get_ratelimit_config();
my $before = &get_postgrey_milter_insert_before($conf);
my $comment_line = $before ? $before->{'line'} :
		   scalar(@{&read_file_lines($cfile, 1)});
my $new = { 'name' => 'racl',
	    'values' => [ 'whitelist', $clause,
			  &postgrey_milter_encode_value($data) ] };
&save_ratelimit_directive($conf, undef, $new, $before);
my @cmts = &postgrey_milter_comment_lines($data);
if (@cmts) {
	my $lref = &read_file_lines($cfile);
	splice(@$lref, $comment_line, 0, @cmts);
	}
&flush_file_lines($cfile);
&unlock_file($cfile);
}

# normalize_postgrey_milter_whitelist_acls()
# Repairs whitelist ACLs that look like IP/CIDR values stored as domain regexps
sub normalize_postgrey_milter_whitelist_acls
{
my $cfile = &get_ratelimit_config_file();
return 0 if (!$cfile || !-r $cfile);
&lock_file($cfile);
my $conf = &get_ratelimit_config();
my $changed = 0;
foreach my $c (@$conf) {
	my ($idx, $action) = &postgrey_milter_acl_action($c);
	next if (!defined($idx) || $action ne 'whitelist');
	my $new;
	for(my $i=$idx+1; $i<@{$c->{'values'}}; $i++) {
		next if ($c->{'values'}->[$i] ne 'domain' ||
			 !$c->{'values'}->[$i+1]);
		my $raw = &postgrey_milter_unquote($c->{'values'}->[$i+1]);
		next if ($raw !~ /^\/(.*)\/$/ ||
			 !&postgrey_milter_is_ip_cidr($1));
		$new ||= { %$c, 'values' => [ @{$c->{'values'}} ] };
		$new->{'values'}->[$i] = 'addr';
		$new->{'values'}->[$i+1] = $1;
		$i++;
		}
	if ($new) {
		&save_ratelimit_directive($conf, $c, $new);
		$changed++;
		}
	}
&flush_file_lines($cfile) if ($changed);
&unlock_file($cfile);
return $changed;
}

# replace_postgrey_milter_list_member(&data, [new-value], [&new-data])
# Replaces or removes one list member without reformatting the whole list
sub replace_postgrey_milter_list_member
{
my ($data, $newvalue, $newdata) = @_;
my $lref = &read_file_lines($data->{'file'});
my $line = $lref->[$data->{'member_line'}];
return 0 if (!defined($line));
my $oldvalue = $data->{'raw_value'} || &postgrey_milter_encode_value($data);
if (defined($newvalue)) {
	$line =~ s/(\A|[\s\{])\Q$oldvalue\E(?=([\s\\\}]|$))/$1$newvalue/;
	$line = &postgrey_milter_update_list_member_comment(
		$line, $data, $newdata);
	$lref->[$data->{'member_line'}] = $line;
	}
elsif ($data->{'line_tokens'} <= 1 && $line !~ /\{.*\}/) {
	splice(@$lref, $data->{'member_line'}, 1);
	}
else {
	$line =~ s/(\A|[\s\{])\Q$oldvalue\E(?=([\s\\\}]|$))/$1/;
	$lref->[$data->{'member_line'}] = $line;
	}
&flush_file_lines($data->{'file'});
return 1;
}

# postgrey_milter_acl_data_matches(&directive, &data)
# Returns 1 if a parsed ACL still matches a UI whitelist entry
sub postgrey_milter_acl_data_matches
{
my ($dir, $data) = @_;
return 0 if ($data->{'source'} ne 'acl' || !defined($data->{'vindex'}));
my ($idx, $action) = &postgrey_milter_acl_action($dir);
return 0 if (!defined($idx) || $action ne 'whitelist');
return 0 if (@{$dir->{'values'}} != $idx+3);
return 0 if ($data->{'vindex'} <= $idx ||
	     $data->{'vindex'} >= @{$dir->{'values'}});
return 0 if ($dir->{'values'}->[$data->{'vindex'}-1] ne $data->{'clause'});
my ($value, $re) = &postgrey_milter_decode_value(
	$dir->{'values'}->[$data->{'vindex'}], $data->{'clause'});
return $value eq $data->{'value'} &&
       ($re ? 1 : 0) == ($data->{'re'} ? 1 : 0);
}

# delete_postgrey_milter_data(type, &data)
# Removes a milter-greylist whitelist entry
sub delete_postgrey_milter_data
{
my ($type, $data) = @_;
my $cfile = &get_ratelimit_config_file();
$cfile || &error("No milter-greylist configuration file found");
&lock_file($cfile);
if ($data->{'source'} eq 'list' && defined($data->{'member_line'})) {
	&replace_postgrey_milter_list_member($data, undef);
	}
else {
	my $conf = &get_ratelimit_config();
	my ($old) = grep { $_->{'line'} == $data->{'line'} } @$conf;
	if ($old && &postgrey_milter_acl_data_matches($old, $data)) {
		&delete_postgrey_milter_directive($old);
		}
	}
&unlock_file($cfile);
}

# modify_postgrey_milter_data(type, &old-data, &new-data)
# Modifies a milter-greylist whitelist entry
sub modify_postgrey_milter_data
{
my ($type, $old, $new) = @_;
$new = { %$new };
if ($type eq 'clients' && &postgrey_milter_is_ip_cidr($new->{'value'})) {
	$new->{'re'} = 0;
	}
my $newclause = &get_postgrey_milter_data_clause($type, $new);
if ($old->{'source'} eq 'list' &&
    defined($old->{'member_line'}) &&
    $old->{'clause'} eq $newclause) {
	&lock_file($old->{'file'});
	&replace_postgrey_milter_list_member(
		$old, &postgrey_milter_encode_value($new), $new);
	&unlock_file($old->{'file'});
	}
else {
	&delete_postgrey_milter_data($type, $old);
	&create_postgrey_milter_data($type, $new);
	}
}

# enable_postgrey_milter()
# Turns on greylisting using milter-greylist
sub enable_postgrey_milter
{
&foreign_require("init");
my $init = &get_postgrey_init();
my ($startcmd, $stopcmd);
if (&get_ratelimit_type() eq 'source') {
	my $conf = &get_ratelimit_config();
	my ($pidfile) = grep { $_->{'name'} eq 'pidfile' } @$conf;
	if (!$pidfile) {
		$pidfile = { 'name' => 'pidfile',
			     'value' => '/var/run/milter-greylist.pid',
			     'values' => [ '"/var/run/milter-greylist.pid"' ] };
		&save_ratelimit_directive($conf, undef, $pidfile);
		&flush_file_lines($pidfile->{'file'});
		}
	$stopcmd = "kill `cat $pidfile->{'value'}` && sleep 5";
	$startcmd = &get_milter_greylist_path().
		    " -f ".&get_ratelimit_config_file();
	}

# Enable at boot
&$first_print($text{'postgrey_init'});
if (&init::action_status($init) != 2) {
	if (&get_ratelimit_type() eq 'source') {
		&init::enable_at_boot($init,
			"Start milter-greylist",
			$startcmd, $stopcmd, undef,
			{ 'fork' => 1 });
		}
	else {
		&init::enable_at_boot($init);
		}
	&$second_print($text{'postgrey_initdone'});
	}
else {
	&$second_print($text{'postgrey_initalready'});
	}

my $dfile = "/etc/default/milter-greylist";
if (&get_ratelimit_type() eq 'debian' && -r $dfile) {
	my $lref = &read_file_lines($dfile);
	my $changed = 0;
	foreach my $l (@$lref) {
		if ($l =~ /^\s*ENABLED=/ && $l ne "ENABLED=1") {
			$l = "ENABLED=1";
			$changed++;
			}
		}
	&flush_file_lines($dfile) if ($changed);
	}

# Ensure milter-greylist actually performs greylisting
&normalize_postgrey_milter_whitelist_acls();
&enable_postgrey_milter_greylisting();

# Adjust the socket file
&$first_print($text{'ratelimit_socket'});
my $socketfile = &update_postgrey_milter_socket();
if (!$socketfile) {
	&$second_print($text{'ratelimit_esocket'});
	return 0;
	}
&$second_print($text{'setup_done'});

# Start process
&$first_print($text{'postgrey_proc'});
if (&find_byname("milter-greylist")) {
	my ($ok, $out) = &init::restart_action($init);
	if (!$ok) {
		&$second_print(&text('postgrey_procfailed',
				     "<tt>".&html_escape($out)."</tt>"));
		return 0;
		}
	&$second_print($text{'postgrey_procdone'});
	}
else {
	&init::stop_action($init);
	sleep(5);
	my ($ok, $out) = &init::start_action($init);
	if (!$ok) {
		&$second_print(&text('postgrey_procfailed',
				     "<tt>".&html_escape($out)."</tt>"));
		return 0;
		}
	&$second_print($text{'postgrey_procdone'});
	}

# Configure Postfix and restart
&$first_print($text{'postgrey_postfix'});
&require_mail();
my $newmilter = "local:$socketfile";
&lock_file($postfix::config{'postfix_config_file'});
&postfix::set_current_value("milter_default_action", "accept");
if (!&postfix::get_current_value("milter_protocol")) {
	&postfix::set_current_value("milter_protocol", 2);
	}
my $milters = &postfix::get_current_value("smtpd_milters");
if ($milters !~ /\Q$newmilter\E/) {
	$milters = $milters ? $milters.",".$newmilter : $newmilter;
	&postfix::set_current_value("smtpd_milters", $milters);
	&postfix::set_current_value("non_smtpd_milters", $milters);
	&unlock_file($postfix::config{'postfix_config_file'});
	&postfix::reload_postfix();
	&$second_print(&text('postgrey_postfixdone2',
			     "<tt>$socketfile</tt>"));
	}
else {
	&unlock_file($postfix::config{'postfix_config_file'});
	&$second_print($text{'postgrey_postfixalready'});
	}

return 1;
}

# disable_postgrey_milter()
# Turns off greylisting using milter-greylist
sub disable_postgrey_milter
{
&foreign_require("init");
my $init = &get_postgrey_init();
my $keep_milter = &postgrey_milter_has_ratelimits();

# Remove greylisting ACLs
&disable_postgrey_milter_greylisting();

# Remove from Postfix if not needed by rate limiting
&$first_print($text{'postgrey_nopostfix'});
my $socketfile = &get_postgrey_milter_socket();
my $oldmilter = $socketfile ? "local:".$socketfile : undef;
&require_mail();
if (!$keep_milter && $oldmilter) {
	&lock_file($postfix::config{'postfix_config_file'});
	my $milters = &postfix::get_current_value("smtpd_milters");
	if ($milters =~ /\Q$oldmilter\E/) {
		$milters = join(",", grep { $_ ne $oldmilter }
				split(/\s*,\s*/, $milters));
		&postfix::set_current_value("smtpd_milters", $milters);
		&postfix::set_current_value("non_smtpd_milters", $milters);
		&unlock_file($postfix::config{'postfix_config_file'});
		&postfix::reload_postfix();
		&$second_print($text{'postgrey_nopostfixdone'});
		}
	else {
		&unlock_file($postfix::config{'postfix_config_file'});
		&$second_print($text{'postgrey_nopostfixalready'});
		}
	}
else {
	&$second_print($text{'setup_done'});
	}

# Stop or restart the process
&$first_print($text{'postgrey_noproc'});
if ($keep_milter) {
	my ($ok, $out) = &init::restart_action($init);
	if (!$ok) {
		&$second_print(&text('postgrey_noprocfailed',
				     "<tt>".&html_escape($out)."</tt>"));
		}
	else {
		&$second_print($text{'setup_done'});
		}
	}
elsif (&find_byname("milter-greylist")) {
	my ($ok, $out) = &init::stop_action($init);
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

# Disable at boot if not needed by rate limiting
&$first_print($text{'postgrey_noinit'});
if (!$keep_milter && &init::action_status($init) == 2) {
	&init::disable_at_boot($init);
	&$second_print($text{'postgrey_noinitdone'});
	}
else {
	&$second_print($text{'postgrey_noinitalready'});
	}
}

# get_postgrey_data_file("clients"|"recipients")
# Returns the full path to the file containing some Postgrey data, like
# whitelisted clients or senders
sub get_postgrey_data_file
{
return undef if (&get_postgrey_type() eq 'milter');
my ($type) = @_;
my $args = &get_postgrey_args();
if ($args =~ /--whitelist-\Q$type\E=(\S+)/) {
	return $1;
	}
my $out = &backquote_command("postgrey -h 2>&1");
if ($out =~ /--whitelist-\Q$type\E=.*default:\s+(\S+)/) {
	return $1;
	}
return undef;
}

# list_postgrey_data(type)
# Returns a list of Postgrey configuration entries of some type, as an array ref
sub list_postgrey_data
{
my ($type) = @_;
if (&get_postgrey_type() eq 'milter') {
	if (!$postgrey_data_cache{$type}) {
		$postgrey_data_cache{$type} =
			&list_postgrey_milter_data($type);
		}
	return $postgrey_data_cache{$type};
	}
my $file = &get_postgrey_data_file($type);
return undef if (!$file);
if (!$postgrey_data_cache{$type}) {
	local $_;
	my (@rv, @cmts);
	my $lnum = 0;
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

# find_duplicate_postgrey_data(type, &data, [skip-index])
# Returns an existing whitelist entry with the same value and match type
sub find_duplicate_postgrey_data
{
my ($type, $data, $skip) = @_;
my $list = &list_postgrey_data($type);
return undef if (!$list);
my $re = $data->{'re'} ? 1 : 0;
my $clause;
if (&get_postgrey_type() eq 'milter') {
	$clause = &get_postgrey_milter_data_clause($type, $data);
	}
foreach my $d (@$list) {
	next if (defined($skip) && defined($d->{'index'}) &&
		 $d->{'index'} == $skip);
	next if ($d->{'value'} ne $data->{'value'});
	next if (($d->{'re'} ? 1 : 0) != $re);
	if (defined($clause)) {
		next if (($d->{'clause'} || '') ne $clause);
		}
	return $d;
	}
return undef;
}

# create_postgrey_data(type, &data)
# Add an entry to a Postgrey whitelist file, and in-memory cache
sub create_postgrey_data
{
my ($type, $data) = @_;
if (&get_postgrey_type() eq 'milter') {
	&create_postgrey_milter_data($type, $data);
	return;
	}
my $file = &get_postgrey_data_file($type);
$file || &error("Failed to find file for $type");
my @newlines = &postgrey_data_lines($data);
my $lref = &read_file_lines($file);
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
my ($type, $data) = @_;
if (&get_postgrey_type() eq 'milter') {
	my $old = &list_postgrey_data($type)->[$data->{'index'}];
	&modify_postgrey_milter_data($type, $old, $data);
	return;
	}
my $file = &get_postgrey_data_file($type);
$file || &error("Failed to find file for $type");
my @newlines = &postgrey_data_lines($data);
my $oldlines = $data->{'eline'} - $data->{'line'} + 1;
my $lref = &read_file_lines($file);
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
my ($type, $data) = @_;
if (&get_postgrey_type() eq 'milter') {
	&delete_postgrey_milter_data($type, $data);
	return;
	}
my $file = &get_postgrey_data_file($type);
$file || &error("Failed to find file for $type");
my $lref = &read_file_lines($file);
my $oldlines = $data->{'eline'} - $data->{'line'} + 1;
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
my ($data) = @_;
my @rv;
push(@rv, map { "# $_" } @{$data->{'cmts'}});
push(@rv, $data->{'re'} ? "/".$data->{'value'}."/" : $data->{'value'});
return @rv;
}

# apply_postgrey_data()
# Apply whitelist data changes to the running greylisting service
sub apply_postgrey_data
{
if (&get_postgrey_type() eq 'milter') {
	return 0 if (!&find_byname("milter-greylist"));
	&foreign_require("init");
	my ($ok, $out) = &init::restart_action(&get_postgrey_init());
	return $ok ? 1 : 0;
	}
my $args = &get_postgrey_args();
my $pid;
if ($args =~ /--pidfile=(\S+)/) {
	my $pidfile = $1;
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
