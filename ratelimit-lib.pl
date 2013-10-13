# Functions for setting up email rate limits

sub get_ratelimit_type
{
if ($gconfig{'os_type'} eq 'debian-linux') {
	# Debian or Ubuntu packages
	return 'debian';
	}
elsif ($gconfig{'os_type'} eq 'redhat-linux') {
	# Redhat / CentOS packages
	return 'redhat';
	}
return undef;	# Not supported
}

sub get_ratelimit_config_file
{
return &get_ratelimit_type() eq 'redhat' ? '/etc/mail/greylist.conf' :
       &get_ratelimit_type() eq 'debian' ? '/etc/milter-greylist/greylist.conf'
					 : undef;
}

sub get_ratelimit_init_name
{
return 'milter-greylist';
}

# check_ratelimit()
# Returns undef if all the commands needed for ratelimiting are installed
sub check_ratelimit
{
&foreign_require("init");
if (!&get_ratelimit_type()) {
	# Not supported on this OS
	return $text{'ratelimit_eos'};
	}
my $config_file = &get_ratelimit_config_file();
return &text('ratelimit_econfig', "<tt>$config_file</tt>")
	if (!-r $config_file);
my $init = &get_ratelimit_init_name();
return &text('ratelimit_einit', "<tt>$init</tt>")
	if (!&init::action_status($init));

# Check mail server
&require_mail();
if ($config{'mail_system'} > 1) {
	return $text{'ratelimit_emailsystem'};
	}
elsif ($config{'mail_system'} == 1) {
	-r $sendmail::config{'sendmail_mc'} ||
		return $text{'ratelimit_esendmailmc'};
	}
return undef;
}

# can_install_ratelimit()
# Returns 1 if milter-greylist package installation is supported on this OS
sub can_install_ratelimit
{
if ($gconfig{'os_type'} eq 'debian-linux' ||
    $gconfig{'os_type'} eq 'redhat-linux') {
	&foreign_require("software", "software-lib.pl");
	return defined(&software::update_system_install);
	}
return 0;
}

# install_ratelimit_package()
# Attempt to install milter-greylist, outputting progress messages
sub install_ratelimit_package
{
&foreign_require("software", "software-lib.pl");
my $pkg = 'milter-greylist';
my @inst = &software::update_system_install($pkg);
return scalar(@inst) || !&check_ratelimit();
}

# get_ratelimit_config()
# Returns the current rate-limiting config, parsed into an array ref
sub get_ratelimit_config
{
&require_apache();
my $cfile = &get_ratelimit_config_file();
my @rv;
my $lref = &read_file_lines($cfile, 1);
for(my $i=0; $i<@$lref; $i++) {
	my $l = $lref->[$i];
	$l =~ s/#.*$//;
	next if (!/\S/);
	my $lnum = $i;
	while($l =~ s/\/\s*$//) {
		# Ends with / .. continue on next line
		$l .= $lref->[++$i];
		}
	# Split up line like foo bar { smeg spod }
	my @toks = &apache::wsplit($l);
	next if (!@toks);
	my $dir = { 'line' => $lnum,
		    'eline' => $i,
		    'file' => $cfile,
		    'name' => shift(@toks),
		    'values' => [ ] };
	while(@toks && $toks[0] ne "{") {
		push(@{$dir->{'values'}}, shift(@toks));
		}
	$dir->{'value'} = $dir->{'values'}->[0];
	if ($toks[0] eq "{") {
		# Has sub-members
		$dir->{'members'} = [ ];
		shift(@toks);
		while(@toks && $toks[0] ne "{") {
			push(@{$dir->{'members'}}, shift(@toks));
			}
		}
	push(@rv, $dir);
	}
return \@rv;
}

# save_ratelimit_directive(&config, &old, &new)
# Create, update or delete a ratelimiting directive
sub save_ratelimit_directive
{
my ($conf, $o, $n) = @_;
my $file = $o ? $o->{'file'} : &get_ratelimit_config_file();
my @lines = $n ? &make_ratelimit_lines($n) : ();
my $idx = &indexof($o, @$conf);
my ($roffset, $rlines);
if ($o && $n) {
	# Replace existing directive
	# XXX
	}
elsif ($o && !$n) {
	# Delete existing directive
	$roffset = $o->{'line'};
	$rlines = $o->{'eline'} - $o->{'line'} + 1;
	splice(@$lref, $o->{'line'}, $rlines);
	if ($idx >= 0) {
		splice(@$conf, $idx, 1);
		}
	$rlines = -$rlines;
	}
elsif (!$o && $n) {
	# Add new directive
	push(@$conf, $n);
	$n->{'line'} = scalar(@$lref);
	$n->{'eline'} = $n->{'line'} + scalar(@lines) - 1;
	push(@$lref, @lines);
	}
if ($rlines) {
	foreach my $c (@$conf) {
		$c->{'line'} += $rlines if ($c->{'line'} > $offset);
		$c->{'eline'} += $rlines if ($c->{'eline'} > $offset);
		}
	}
}

# make_ratelimit_lines(&directive)
# Returns an array of lines for some directive
sub make_ratelimit_lines
{
my ($dir) = @_;
&require_apache();
my @w = ( $dir->{'name'}, @{$dir->{'values'}} );
if ($dir->{'members'}) {
	push(@w, "{", @{$dir->{'members'}}, "}");
	}
return &apache::wjoin(@w);
}

1;
