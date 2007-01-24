# Functions for managing logrotate

sub init_logrotate
{
$feature_depends{'logrotate'} = [ 'web' ];
}

sub require_logrotate
{
return if ($require_logrotate++);
&foreign_require("logrotate", "logrotate-lib.pl");
}

# setup_logrotate(&domain)
# Create logrotate entries for the server's access and error logs
sub setup_logrotate
{
&$first_print($text{'setup_logrotate'});
&require_logrotate();
&require_apache();

local $alog = &get_apache_log($_[0]->{'dom'}, $_[0]->{'web_port'}, 0);
local $elog = &get_apache_log($_[0]->{'dom'}, $_[0]->{'web_port'}, 1);
local @logs = ( $alog, $elog );
if ($_[0]->{'ftp'}) {
	push(@logs, &get_proftpd_log($_[0]->{'ip'}));
	}
local @logs = &unique(grep { $_ } @logs);
local $tmpl = &get_template($_[0]->{'template'});
if (@logs) {
	local $parent = &logrotate::get_config_parent();
	local $lconf = { 'file' => &logrotate::get_add_file(),
			  'name' => \@logs };
	if ($tmpl->{'logrotate'} eq 'none') {
		# Use automatic configurtation
		local $apachectl = $apache::config{'apachectl_path'} ||
				   &has_command("apachectl") ||
				   &has_command("apache2ctl");
		local $script = $apache::config{'graceful_cmd'} ||
				"$apachectl graceful";
		$lconf->{'members'} = [
				{ 'name' => 'rotate',
				  'value' => $config{'logrotate_num'} || 5 },
				{ 'name' => 'weekly' },
				{ 'name' => 'compress' },
				{ 'name' => 'postrotate',
				  'script' => $script }
				];
		}
	else {
		# Use manually defined directives
		local $temp = &transname();
		local $txt = $tmpl->{'logrotate'};
		$txt =~ s/\t/\n/g;
		&open_tempfile(TEMP, ">$temp");
		&print_tempfile(TEMP, "/dev/null {\n");
		&print_tempfile(TEMP,
			&substitute_domain_template($txt, $_[0])."\n");
		&print_tempfile(TEMP, "}\n");
		&close_tempfile(TEMP);
		local $tconf = &logrotate::get_config($temp);
		$lconf->{'members'} = $tconf->[0]->{'members'};
		unlink($temp);
		}
	&lock_file($lconf->{'file'});
	&logrotate::save_directive($parent, undef, $lconf);
	&flush_file_lines();
	&unlock_file($lconf->{'file'});
	&$second_print($text{'setup_done'});
	}
else {
	&$second_print($text{'setup_nolog'});
	}
}

# modify_logrotate(&domain, &olddomain)
# Adjust path if home directory has changed
sub modify_logrotate
{
if ($_[0]->{'home'} ne $_[1]->{'home'}) {
	&require_logrotate();
	&$first_print($text{'save_logrotate'});

	# Work out the *old* access log, which will have already been renamed
	local $oldalog = &get_apache_log($_[0]->{'dom'}, $_[0]->{'web_port'});
	$oldalog =~ s/$_[0]->{'home'}/$_[1]->{'home'}/;
	local $lconf = &get_logrotate_section($oldalog);

	if ($lconf) {
		&lock_file($lconf->{'file'});
		local $parent = &logrotate::get_config_parent();
		local $n;
		foreach $n (@{$lconf->{'name'}}) {
			$n =~ s/(^|\s)$_[1]->{'home'}/$1$_[0]->{'home'}/g;
			}
		&logrotate::save_directive($parent, $lconf, $lconf);
		&flush_file_lines();
		&unlock_file($lconf->{'file'});
		&$second_print($text{'setup_done'});
		}
	else {
		&$second_print($text{'setup_nologrotate'});
		}
	}
}

# delete_logrotate(&domain)
# Remove logrotate section for this domain
sub delete_logrotate
{
&require_logrotate();
&$first_print($text{'delete_logrotate'});
local $lconf = &get_logrotate_section($_[0]);
if ($lconf) {
	local $parent = &logrotate::get_config_parent();
	&lock_file($lconf->{'file'});
	&logrotate::save_directive($parent, $lconf, undef);
	&flush_file_lines();
	&unlock_file($lconf->{'file'});
	&$second_print($text{'setup_done'});
	}
else {
	&$second_print($text{'setup_nologrotate'});
	}
}

# validate_logrotate(&domain)
# Returns an error message if a domain's logrotate section is not found
sub validate_logrotate
{
local ($d) = @_;
local $log = &get_apache_log($d->{'dom'}, $d->{'web_port'});
return &text('validate_elogfile', "<tt>$d->{'dom'}</tt>") if (!$log);
local $lconf = &get_logrotate_section($d);
return &text('validate_elogrotate', "<tt>$logfile</tt>") if (!$lconf);
return undef;
}

# get_logrotate_section(&domain|log-file)
sub get_logrotate_section
{
&require_logrotate();
&require_apache();
local $alog = ref($_[0]) ? &get_apache_log($_[0]->{'dom'}, $_[0]->{'web_port'})
			 : $_[0];
if (!$alog && ref($_[0])) {
	# Website may have been already deleted, so we don't know the log
	# file path! Try the template default.
	$alog = &get_apache_template_log($_[0]);
	}
local $conf = &logrotate::get_config();
local ($c, $n);
foreach $c (@$conf) {
	foreach $n (@{$c->{'name'}}) {
		return $c if ($n eq $alog);
		}
	}
return undef;
}

# check_logrotate_clash()
# No need to check for clashes ..
sub check_logrotate_clash
{
return 0;
}

# backup_logrotate(&domain, file)
# Saves the log rotation section for this domain to a file
sub backup_logrotate
{
&$first_print($text{'backup_logrotatecp'});
local $lconf = &get_logrotate_section($_[0]);
if ($lconf) {
	local $lref = &read_file_lines($lconf->{'file'});
	local $l;
	&open_tempfile(FILE, ">$_[1]");
	foreach $l (@$lref[$lconf->{'line'} .. $lconf->{'eline'}]) {
		&print_tempfile(FILE, "$l\n");
		}
	&close_tempfile(FILE);
	&$second_print($text{'setup_done'});
	return 1;
	}
else {
	&$second_print($text{'setup_nologrotate'});
	return 0;
	}
}

# restore_logrotate(&domain, file, &options, &all-options, home-format,
#		    &olddomain)
sub restore_logrotate
{
&$first_print($text{'restore_logrotatecp'});
local $lconf = &get_logrotate_section($_[0]);
if ($lconf) {
	local $srclref = &read_file_lines($_[1]);
	local $dstlref = &read_file_lines($lconf->{'file'});
	&lock_file($lconf->{'file'});
	splice(@$dstlref, $lconf->{'line'}+1,
	       $lconf->{'eline'}-$lconf->{'line'}-1,
	       @$srclref[1 .. @$srclref-2]);
	if ($_[5]->{'home'} && $_[5]->{'home'} ne $_[0]->{'home'}) {
		# Fix up any references to old home dir
		local $i;
		foreach $i ($lconf->{'line'} .. $lconf->{'line'}+scalar(@$srclref)-1) {
			$dstlref->[$i] =~ s/(^|\s)$_[5]->{'home'}/$1$_[0]->{'home'}/g;
			}
		}
	&flush_file_lines();
	&unlock_file($lconf->{'file'});
	&$second_print($text{'setup_done'});
	return 1;
	}
else {
	&$second_print($text{'setup_nologrotate'});
	return 0;
	}
}

# sysinfo_logrotate()
# Returns the Logrotate version
sub sysinfo_logrotate
{
&require_logrotate();
$logrotate::logrotate_version ||= &logrotate::get_logrotate_version();
return ( [ $text{'sysinfo_logrotate'}, $logrotate::logrotate_version ] );
}

# check_logrotate_template([directives])
# Returns an error message if the default Logrotate directives don't look valid
sub check_logrotate_template
{
local ($d, $gotpostrotate);
local @dirs = split(/\t+/, $_[0]);
foreach $d (@dirs) {
	if ($d =~ /\s*postrotate/) {
		$gotpostrotate = 1;
		}
	}
$gotpostrotate || return $text{'lcheck_epost'};
return undef;
}

# show_template_logrotate(&tmpl)
# Outputs HTML for editing Logrotate related template options
sub show_template_logrotate
{
local ($tmpl) = @_;

# Logrotate directives
print &ui_table_row(
	&hlink($text{'tmpl_logrotate'}, "template_logrotate"),
	&none_def_input("logrotate", $tmpl->{'logrotate'},
			$text{'tmpl_ftpbelow'}, 0, 0,
			$text{'tmpl_logrotatenone'})."<br>\n".
	&ui_textarea("logrotate",
		$tmpl->{'logrotate'} eq "none" ? undef :
		  join("\n", split(/\t/, $tmpl->{'logrotate'})),
		5, 60));
}

# parse_template_logrotate(&tmpl)
# Updates Logrotate related template options from %in
sub parse_template_logrotate
{
local ($tmpl) = @_;

# Save logrotate settings
$tmpl->{'logrotate'} = &parse_none_def("logrotate");
if ($in{"logrotate_mode"} == 2) {
	local $err = &check_logrotate_template($in{'logrotate'});
	&error($err) if ($err);
	}
}

# chained_logrotate(&domain)
# Logrotate is automatically enabled when a website is
sub chained_logrotate
{
local ($d) = @_;
return $d->{'web'} && !$d->{'alias'} && !$d->{'subdom'};
}

$done_feature_script{'logrotate'} = 1;

1;

