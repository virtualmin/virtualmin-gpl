# Helpers for the system ProFTPd service.  The old per-domain virtual FTP
# feature has been retired, but authenticated FTP and global ProFTPd settings
# still use a few shared helpers here.

sub require_proftpd
{
return if ($require_proftpd++);
&foreign_require("proftpd");
}

# has_proftpd_support()
# Returns true if the Webmin ProFTPd module is installed and configured.
sub has_proftpd_support
{
return 0 if (!&foreign_check("proftpd"));
my $installed = eval { &foreign_installed("proftpd", 1) };
return 0 if ($@ || $installed != 2);
&require_proftpd();
my $conf = eval { &proftpd::get_config() };
return !$@ && ref($conf) ? 1 : 0;
}

# restart_proftpd()
# Tell ProFTPd to re-read its config file. Does nothing if run from inetd.
sub restart_proftpd
{
return 1 if (!&has_proftpd_support());
&require_proftpd();
my $conf = &proftpd::get_config();
my $st = &proftpd::find_directive("ServerType", $conf);
if (lc($st) ne "inetd") {
	&$first_print($text{'setup_proftpdpid'});
	my $proftpdlock = "$module_config_directory/proftpd-restart";
	&lock_file($proftpdlock);
	my $err = &proftpd::apply_configuration();
	&unlock_file($proftpdlock);
	&$second_print($err ? &text('setup_proftpdfailed', $err)
			    : $text{'setup_done'});
	return $err ? 0 : 1;
	}
return 1;
}

# get_proftpd_log([&domain])
# Returns the global ProFTPd transfer log path. Per-domain virtual FTP logs are
# no longer managed by Virtualmin, so a domain argument returns undef.
sub get_proftpd_log
{
my ($d) = @_;
return undef if ($d);
return undef if (!&has_proftpd_support());
&require_proftpd();
my $conf = &proftpd::get_config();
my $global = &proftpd::find_directive_struct("Global", $conf);
my $gconf = $global ? $global->{'members'} : undef;
return ($gconf ? &proftpd::find_directive("TransferLog", $gconf) : undef) ||
       ($gconf ? &proftpd::find_directive("ExtendedLog", $gconf) : undef) ||
       &proftpd::find_directive("TransferLog", $conf) ||
       &proftpd::find_directive("ExtendedLog", $conf) ||
       "/var/log/xferlog";
}

# sysinfo_ftp()
# Returns the ProFTPd version if it is installed.
sub sysinfo_ftp
{
return () if (!&has_proftpd_support());
&require_proftpd();
$proftpd::site{'version'} ||= &proftpd::get_proftpd_version();
return ( [ $text{'sysinfo_proftpd'}, $proftpd::site{'version'} ] );
}

sub startstop_ftp
{
my ($typestatus) = @_;
$typestatus ||= { };
return () if (!&has_proftpd_support());
&require_proftpd();
my $conf = &proftpd::get_config();
my $st = &proftpd::find_directive("ServerType", $conf);
if ($st eq 'inetd') {
	return ( );
	}
my $status;
if (defined($typestatus->{'proftpd'})) {
	$status = $typestatus->{'proftpd'} == 1;
	}
else {
	$status = &proftpd::get_proftpd_pid();
	}
my @links = ( { 'link' => '/proftpd/',
	       'desc' => $text{'index_fmanage'},
	       'manage' => 1 } );
if ($status) {
	return ( { 'status' => 1,
		   'name' => $text{'index_fname'},
		   'desc' => $text{'index_fstop'},
		   'restartdesc' => $text{'index_frestart'},
		   'longdesc' => $text{'index_fstopdesc'},
		   'links' => \@links } );
	}
else {
	return ( { 'status' => 0,
		   'name' => $text{'index_fname'},
		   'desc' => $text{'index_fstart'},
		   'longdesc' => $text{'index_fstartdesc'},
		   'links' => \@links } );
	}
}

sub stop_service_ftp
{
return 0 if (!&has_proftpd_support());
&require_proftpd();
return &proftpd::stop_proftpd();
}

sub start_service_ftp
{
return 0 if (!&has_proftpd_support());
&require_proftpd();
return &proftpd::start_proftpd();
}

# has_ftp_chroot()
# Returns 1 if we can configure ProFTPd chroot directories.
sub has_ftp_chroot
{
return &has_proftpd_support();
}

# list_ftp_chroots()
# Returns a list of chroot directories. Each is a hash ref with keys :
#  group - A group to restrict, or undef for all
#  neg - Negative if to apply to everyone except that group
#  dir - The chroot directory, or ~ for users' homes
sub list_ftp_chroots
{
my @rv;
return @rv if (!&has_ftp_chroot());
&require_proftpd();
my $conf = &proftpd::get_config();
$proftpd::conf = $conf;		# get_or_create is broken in Webmin 1.410
my $gconf = &proftpd::get_or_create_global($conf);
foreach my $dr (&proftpd::find_directive_struct("DefaultRoot", $gconf)) {
	my $chroot = { 'dr' => $dr,
			  'dir' => $dr->{'words'}->[0] };
	if ($dr->{'words'}->[1] eq '') {
		# Applies to all groups
		}
	elsif ($dr->{'words'}->[1] =~ /,/) {
		# Applies to many .. too complex to support
		next;
		}
	elsif ($dr->{'words'}->[1] =~ /^(\!?)(\S+)$/) {
		$chroot->{'neg'} = $1;
		$chroot->{'group'} = $2;
		}
	push(@rv, $chroot);
	}
return @rv;
}

# save_ftp_chroots(&chroots)
# Updates the list of chroot'd directories.
sub save_ftp_chroots
{
my ($chroots) = @_;
return 0 if (!&has_ftp_chroot());
&require_proftpd();
my $conf = &proftpd::get_config();
$proftpd::conf = $conf;
my $gconf = &proftpd::get_or_create_global($conf);

# Find old directives that we can't configure yet
my @old = &proftpd::find_directive_struct("DefaultRoot", $gconf);
my @keep = grep { $_->{'words'}->[1] =~ /,/ } @old;
my @newv = map { $_->{'value'} } @keep;

# Add new ones
foreach my $chroot (@$chroots) {
	my @w = ( $chroot->{'dir'} );
	if ($chroot->{'group'}) {
		push(@w, ($chroot->{'neg'} ? "!" : "").$chroot->{'group'});
		}
	push(@newv, join(" ", @w));
	}
&proftpd::save_directive("DefaultRoot", \@newv, $gconf, $conf);
&flush_file_lines();

&register_post_action(\&restart_proftpd);
return 1;
}

# Lock the ProFTPd config file
sub obtain_lock_ftp
{
return if (!&has_proftpd_support());
&obtain_lock_anything();
if ($main::got_lock_ftp == 0) {
	&require_proftpd();
	&lock_file($proftpd::config{'proftpd_conf'});
	&lock_file($proftpd::config{'add_file'})
		if ($proftpd::config{'add_file'});
	undef(@proftpd::get_config_cache);
	}
$main::got_lock_ftp++;
}

# Unlock the ProFTPd config file
sub release_lock_ftp
{
return if (!$main::got_lock_ftp);
if ($main::got_lock_ftp == 1) {
	&require_proftpd();
	&unlock_file($proftpd::config{'proftpd_conf'});
	&unlock_file($proftpd::config{'add_file'})
		if ($proftpd::config{'add_file'});
	}
$main::got_lock_ftp-- if ($main::got_lock_ftp);
&release_lock_anything();
}

1;
