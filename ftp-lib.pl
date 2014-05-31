# Functions for talking to an FTP server

# ftp_tryload(host, file, srcfile, [&error], [&callback], [user, pass],
# 	      [port], [attempts])
# Download data from a local file to an FTP site
sub ftp_tryload
{
local $tries = $_[8] || 1;
for(my $i=0; $i<$tries; $i++) {
	&ftp_upload(@_);
	return 1 if (!${$_[3]});
	}
return 0;
}

# ftp_onecommand(host, command, [&error], [user, pass], [port])
# Executes one command on an FTP server, after logging in, and returns its
# exit status.
sub ftp_onecommand
{
local($buf, @n);

$main::download_timed_out = undef;
local $SIG{ALRM} = \&download_timeout;
alarm(60);

# connect to host and login
&open_socket($_[0], $_[5] || 21, "SOCK", $_[2]) || return 0;
alarm(0);
if ($main::download_timed_out) {
	if ($_[2]) { ${$_[2]} = $main::download_timed_out; return 0; }
	else { &error($main::download_timed_out); }
	}
&ftp_command("", 2, $_[2]) || return 0;
if ($_[3]) {
	# Login as supplied user
	local @urv = &ftp_command("USER $_[3]", [ 2, 3 ], $_[2]);
	@urv || return 0;
	if (int($urv[1]/100) == 3) {
		&ftp_command("PASS $_[4]", 2, $_[2]) || return 0;
		}
	}
else {
	# Login as anonymous
	local @urv = &ftp_command("USER anonymous", [ 2, 3 ], $_[2]);
	@urv || return 0;
	if (int($urv[1]/100) == 3) {
		&ftp_command("PASS root\@".&get_system_hostname(), 2,
			     $_[2]) || return 0;
		}
	}

# Run the command
local @rv = &ftp_command($_[1], 2, $_[2]);
@rv || return 0;

# finish off..
&ftp_command("QUIT", 2, $_[2]) || return 0;
close(SOCK);

return $rv[1];
}

# ftp_listdir(host, dir, [&error], [user, pass], [port], [longmode])
# Returns a reference to a list of filenames in a directory, or if longmode
# is set returns full file details in stat format (with the 13th index being
# the filename)
sub ftp_listdir
{
local($buf, @n);

$main::download_timed_out = undef;
local $SIG{ALRM} = \&download_timeout;
alarm(60);

# connect to host and login
&open_socket($_[0], $_[5] || 21, "SOCK", $_[2]) || return 0;
alarm(0);
if ($main::download_timed_out) {
	if ($_[2]) { ${$_[2]} = $main::download_timed_out; return 0; }
	else { &error($main::download_timed_out); }
	}
&ftp_command("", 2, $_[2]) || return 0;
if ($_[3]) {
	# Login as supplied user
	local @urv = &ftp_command("USER $_[3]", [ 2, 3 ], $_[2]);
	@urv || return 0;
	if (int($urv[1]/100) == 3) {
		&ftp_command("PASS $_[4]", 2, $_[2]) || return 0;
		}
	}
else {
	# Login as anonymous
	local @urv = &ftp_command("USER anonymous", [ 2, 3 ], $_[2]);
	@urv || return 0;
	if (int($urv[1]/100) == 3) {
		&ftp_command("PASS root\@".&get_system_hostname(), 2,
			     $_[2]) || return 0;
		}
	}

# are we using IPv6?
my $v6 = !&to_ipaddress($_[0]) &&
	 &to_ip6address($_[0]);

if ($v6) {
	# request the listing over a EPSV port
	my $epsv = &ftp_command("EPSV", 2, $_[3]);
	defined($epsv) || return 0;
	$epsv =~ /\|(\d+)\|/ || return 0;
	my $epsvport = $1;
	&open_socket($_[0], $epsvport, CON, $_[3]) || return 0;
	}
else {
	# request the listing over a PASV connection
	local $pasv = &ftp_command("PASV", 2, $_[2]);
	defined($pasv) || return 0;
	$pasv =~ /\(([0-9,]+)\)/ || return 0;
	@n = split(/,/ , $1);
	&open_socket("$n[0].$n[1].$n[2].$n[3]", $n[4]*256 + $n[5], "CON", $_[2]) || return 0;
	}

local @list;
local $_;
if ($_[6]) {
	# Ask for full listing
	&ftp_command("LIST $_[1]/", 1, $_[2]) || return 0;
	while(<CON>) {
		s/\r|\n//g;
		local @st = &parse_lsl_line($_);
		push(@list, \@st) if (scalar(@st));
		}
	close(CON);
	}
else {
	# Just filenames
	&ftp_command("NLST $_[1]/", 1, $_[2]) || return 0;
	while(<CON>) {
		s/\r|\n//g;
		push(@list, $_);
		}
	close(CON);
	}

# finish off..
&ftp_command("", 2, $_[3]) || return 0;
&ftp_command("QUIT", 2, $_[3]) || return 0;
close(SOCK);

return \@list;
}

# parse_lsl_line(text)
# Given a line from ls -l output, parse it into a stat() format array. Not all
# fields are set, as not all are available. Returns an empty array if the line
# doesn't look like ls -l output.
sub parse_lsl_line
{
local @w = split(/\s+/, $_[0]);
local @now = localtime(time());
local @st;
return ( ) if ($w[0] !~ /^[rwxdlsSt\-]{10}(\+|@|\.)?$/);
$st[3] = $w[1];			# Links
$st[4] = $w[2];			# UID
$st[5] = $w[3];			# GID
$st[7] = $w[4];			# Size
if ($w[7] =~ /^(\d+):(\d+)$/) {
	# Time is month day hour:minute
	local @tm = ( 0, $2, $1, $w[6], &month_to_number($w[5]), $now[5] );
	return ( ) if ($tm[4] eq '' || $tm[3] < 1 || $tm[3] > 31);
	local $ut = timelocal(@tm);
	if ($ut > time()+(24*60*60)) {
		# Must have been last year!
		$tm[5]--;
		$ut = timelocal(@tm);
		}
	$st[8] = $st[9] = $st[10] = $ut;
	$st[13] = join(" ", @w[8..$#w]);
	}
elsif ($w[5] =~ /^(\d{4})\-(\d+)\-(\d+)$/) {
	# Time is year-month-day hour:minute
	local @tm = ( 0, 0, 0, $3, $2-1, $1-1900 );
	if ($w[6] =~ /^(\d+):(\d+)$/) {
		$tm[1] = $2;
		$tm[2] = $1;
		$st[8] = $st[9] = $st[10] = timelocal(@tm);
		}
	else {
		return ( );
		}
	$st[13] = join(" ", @w[7..$#w]);
	}
elsif ($w[7] =~ /^\d+$/ && $w[7] > 1000 && $w[7] < 10000) {
	# Time is month day year
	local @tm = ( 0, 0, 0, $w[6],
		      &month_to_number($w[5]), $w[7]-1900 );
	return ( ) if ($tm[4] eq '' || $tm[3] < 1 || $tm[3] > 31);
	$st[8] = $st[9] = $st[10] = timelocal(@tm);
	$st[13] = join(" ", @w[8..$#w]);
	}
else {
	# Unknown format??
	return ( );
	}
$st[2] = 0;			# Permissions
$w[0] =~ s/(\+|@|\.)$//;	# Remove trailing + or @ or .
local @p = reverse(split(//, $w[0]));
for(my $i=0; $i<9; $i++) {
	if ($p[$i] ne '-') {
		$st[2] += (1<<$i);
		}
	if ($i == 0 && lc($p[$i]) eq "t") {
		$st[2] += 01000;
		}
	if ($i == 3 && lc($p[$i]) eq "s") {
		$st[2] += 02000;
		}
	if ($i == 6 && lc($p[$i]) eq "s") {
		$st[2] += 04000;
		}
	}
if ($p[9] eq "d") {
	$st[2] += 040000;
	}
if ($st[13] =~ s/\s+->\s+(.*)$//) {
	# Symlink target
	$st[14] = $1;
	}
return @st;
}

# make_unix_perms(number)
# Converts a permissions number into an ls -l format string
sub make_unix_perms
{
my ($mode) = @_;
my @perms = qw(--- --x -w- -wx r-- r-x rw- rwx);
my @ftype = qw(. p c ? d ? b ? - ? l ? s ? ? ?);
$ftype[0] = '';
my $setids = ($mode & 07000)>>9;
my @permstrs = @perms[($mode&0700)>>6, ($mode&0070)>>3, $mode&0007];
my $ftype = $ftype[($mode & 0170000)>>12];

if ($setids) {
  if ($setids & 01) {         # Sticky bit
    $permstrs[2] =~ s/([-x])$/$1 eq 'x' ? 't' : 'T'/e;
    }
  if ($setids & 04) {         # Setuid bit
    $permstrs[0] =~ s/([-x])$/$1 eq 'x' ? 's' : 'S'/e;
    }
  if ($setids & 02) {         # Setgid bit
    $permstrs[1] =~ s/([-x])$/$1 eq 'x' ? 's' : 'S'/e;
    }
  }
return join('', $ftype, @permstrs);
}

# ftp_deletefile(host, file, &error, [user, pass], [port])
# Delete some file or directory from an FTP server. This is done recursively
# if needed. Returns the size of any deleted sub-directories.
sub ftp_deletefile
{
local ($host, $file, $err, $user, $pass, $port) = @_;
local $sz = 0;

# Check if we can chdir to it
local $cwderr;
local $isdir = &ftp_onecommand($host, "CWD $file", \$cwderr,
			       $user, $pass, $port);
if ($isdir) {
	# Yes .. so delete recursively first
	local $files = &ftp_listdir($host, $file, $err, $user, $pass, $port, 1);
	$files = [ grep { $_->[13] ne "." && $_->[13] ne ".." } @$files ];
	if (!$err || !$$err) {
		foreach my $f (@$files) {
			$sz += $f->[7];
			$sz += &ftp_deletefile($host, "$file/$f->[13]", $err,
					       $user, $pass, $port);
			last if ($err && $$err);
			}
		&ftp_onecommand($host, "RMD $file", $err, $user, $pass, $port);
		}
	}
else {
	# Just delete the file
	&ftp_onecommand($host, "DELE $file", $err, $user, $pass, $port);
	}
return $sz;
}

# ftp_encrypted_download(..)
# Takes the same parameters as ftp_download, but uses an encrypted control 
# connection
sub ftp_encrypted_download
{
my ($host, $file, $dest, $error, $cbfunc, $user, $pass, $port, $nocache) = @_;
if (!&has_command("curl")) {
	my $msg = "The curl command is needed for encrypted FTP downloads";
	if ($error) { $$error = $msg; return }
	else { &error($error); }
	}
my $cmd = "curl --ftp-ssl-control -k";
if ($user) {
	$cmd .= " -u ".quotemeta($user).":".quotemeta($pass);
	}
if (!ref($dest)) {
	$cmd .= " -o ".quotemeta($dest);
	}
$cmd .= " ftp://".$host.($port ? ":".$port : "").$file;
my $errtemp = &transname();
if (ref($dest)) {
	# Save to scalar reference
	$$dest = &backquote_command("$cmd 2>$errtemp </dev/null");
	}
else {
	# Save to a file
	&system_logged("$cmd >".quotemeta($dest)." 2>$errtemp </dev/null");
	}
# Handle any error
if ($? || (!ref($dest) && !-s $dest)) {
	my $errmsg = &html_escape(&read_file_contents($errtemp)) ||
		     "Unknown curl error with $cmd";
	&unlink_file($errtemp);
	if ($error) { $$error = $errmsg; return 0; }
	else { &error($errmsg); }
	}
&unlink_file($errtemp);
return 1;
}

1;

