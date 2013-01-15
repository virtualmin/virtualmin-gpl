# Functions for creating backups and managing schedules

# list_scheduled_backups()
# Returns a list of all scheduled backups
sub list_scheduled_backups
{
local @rv;

# Add old single schedule, from config file
if ($config{'backup_dest'}) {
	local %backup = ( 'id' => 1,
			  'dest' => $config{'backup_dest'},
			  'fmt' => $config{'backup_fmt'},
			  'mkdir' => $config{'backup_mkdir'},
			  'errors' => $config{'backup_errors'},
			  'increment' => $config{'backup_increment'},
			  'strftime' => $config{'backup_strftime'},
			  'onebyone' => $config{'backup_onebyone'},
			  'parent' => $config{'backup_parent'},
			  'all' => $config{'backup_all'},
			  'doms' => $config{'backup_doms'},
			  'feature_all' => $config{'backup_feature_all'},
			  'email' => $config{'backup_email'},
			  'email_err' => $config{'backup_email_err'},
			  'email_doms' => $config{'backup_email_doms'},
			  'virtualmin' => $config{'backup_virtualmin'},
			  'purge' => $config{'backup_purge'},
			  'before' => $config{'backup_before'},
			  'after' => $config{'backup_after'},
			  'exclude' => $config{'backup_exclude'},
			 );
	local @bf;
	foreach $f (&get_available_backup_features(), &list_backup_plugins()) {
		push(@bf, $f) if ($config{'backup_feature_'.$f});
		$backup{'opts_'.$f} = $config{'backup_opts_'.$f};
		}
	for(my $i=1; $config{'backup_dest'.$i}; $i++) {
		$backup{'dest'.$i} = $config{'backup_dest'.$i};
		$backup{'purge'.$i} = $config{'backup_purge'.$i};
		}
	$backup{'features'} = join(" ", @bf);
	push(@rv, \%backup);
	}

# Add others from backups dir
opendir(BACKUPS, $scheduled_backups_dir);
foreach my $b (readdir(BACKUPS)) {
	if ($b ne "." && $b ne "..") {
		local %backup;
		&read_file("$scheduled_backups_dir/$b", \%backup);
		$backup{'id'} = $b;
		$backup{'file'} = "$scheduled_backups_dir/$b";
		delete($backup{'enabled'});	# Worked out below
		push(@rv, \%backup);
		}
	}
closedir(BACKUPS);

# Merge in classic cron jobs to see which are enabled
&foreign_require("cron");
local @jobs = &cron::list_cron_jobs();
foreach my $j (@jobs) {
	if ($j->{'user'} eq 'root' &&
	    $j->{'command'} =~ /^\Q$backup_cron_cmd\E(\s+\-\-id\s+(\d+))?/) {
		local $id = $2 || 1;
		local ($backup) = grep { $_->{'id'} eq $id } @rv;
		if ($backup) {
			$backup->{'enabled'} = 1;
			&copy_cron_sched_keys($j, $backup);
			}
		}
	}

# Also merge in webmincron jobs
&foreign_require("webmincron");
local @jobs = &webmincron::list_webmin_crons();
foreach my $j (@jobs) {
	if ($j->{'module'} eq $module_name &&
	    $j->{'func'} eq 'run_cron_script' &&
	    $j->{'args'}->[0] eq 'backup.pl') {
		local $id = $j->{'args'}->[1] =~ /--id\s+(\d+)/ ? $1 : 1;
		local ($backup) = grep { $_->{'id'} eq $id } @rv;
		if ($backup) {
			$backup->{'enabled'} = 2;
			&copy_cron_sched_keys($j, $backup);
			}
		}
	}

@rv = sort { $a->{'id'} <=> $b->{'id'} } @rv;
return @rv;
}

sub copy_cron_sched_keys
{
local ($src, $dst) = @_;
foreach my $k ('mins', 'hours', 'days', 'months', 'weekdays',
	       'special', 'interval') {
	$dst->{$k} = $src->{$k};
	}
}

# save_scheduled_backup(&backup)
# Create or update a scheduled backup. Also creates any needed cron job.
sub save_scheduled_backup
{
local ($backup) = @_;
local $wasnew = !$backup->{'id'};

if ($backup->{'id'} == 1) {
	# Update schedule in Virtualmin config
	$config{'backup_dest'} = $backup->{'dest'};
	$config{'backup_fmt'} = $backup->{'fmt'};
	$config{'backup_mkdir'} = $backup->{'mkdir'};
	$config{'backup_errors'} = $backup->{'errors'};
	$config{'backup_increment'} = $backup->{'increment'};
	$config{'backup_strftime'} = $backup->{'strftime'};
	$config{'backup_onebyone'} = $backup->{'onebyone'};
	$config{'backup_parent'} = $backup->{'parent'};
	$config{'backup_all'} = $backup->{'all'};
	$config{'backup_doms'} = $backup->{'doms'};
	$config{'backup_feature_all'} = $backup->{'feature_all'};
	$config{'backup_email'} = $backup->{'email'};
	$config{'backup_email_err'} = $backup->{'email_err'};
	$config{'backup_email_doms'} = $backup->{'email_doms'};
	$config{'backup_virtualmin'} = $backup->{'virtualmin'};
	$config{'backup_purge'} = $backup->{'purge'};
	$config{'backup_before'} = $backup->{'before'};
	$config{'backup_after'} = $backup->{'after'};
	$config{'backup_exclude'} = $backup->{'exclude'};
	local @bf = split(/\s+/, $backup->{'features'});
	foreach $f (&get_available_backup_features(), &list_backup_plugins()) {
		$config{'backup_feature_'.$f} = &indexof($f, @bf) >= 0 ? 1 : 0;
		$config{'backup_opts_'.$f} = $backup->{'opts_'.$f};
		}
	foreach my $k (keys %config) {
		if ($k =~ /^backup_(dest|purge)\d+$/) {
			delete($config{$k});
			}
		}
	for(my $i=1; $backup->{'dest'.$i}; $i++) {
		$config{'backup_dest'.$i} = $backup->{'dest'.$i};
		$config{'backup_purge'.$i} = $backup->{'purge'.$i};
		}
	&lock_file($module_config_file);
	&save_module_config();
	&unlock_file($module_config_file);
	}
else {
	# Update or create separate file
	&make_dir($scheduled_backups_dir, 0700) if (!-d $scheduled_backups_dir);
	$backup->{'id'} ||= &domain_id();
	$backup->{'file'} = "$scheduled_backups_dir/$backup->{'id'}";
	&lock_file($backup->{'file'});
	&write_file($backup->{'file'}, $backup);
	&unlock_file($backup->{'file'});
	}

# Update or delete cron job
&foreign_require("cron", "cron-lib.pl");
local $cmd = $backup_cron_cmd;
$cmd .= " --id $backup->{'id'}" if ($backup->{'id'} != 1);
local $job;
if (!$wasnew) {
	local @jobs = &find_cron_script($cmd);
	if ($backup->{'id'} == 1) {
		# The find_virtualmin_cron_job function will match
		# backup.pl --id xxx when looking for backup.pl, so we have
		# to filter it out
		@jobs = grep { $_->{'command'} !~ /\-\-id/ } @jobs;
		}
	$job = $jobs[0];
	}
if ($backup->{'enabled'} && $job) {
	# Fix job schedule
	&copy_cron_sched_keys($backup, $job);
	if ($job->{'module'}) {
		# Webmin cron
		&setup_cron_script($job);
		}
	else {
		# Classic cron
		&cron::change_cron_job($job);
		}
	}
elsif ($backup->{'enabled'} && !$job) {
	# Create webmincron job
	$job = { 'user' => 'root',
		 'active' => 1,
		 'command' => $cmd };
	&copy_cron_sched_keys($backup, $job);
	&setup_cron_script($job);
	}
elsif (!$backup->{'enabled'} && $job) {
	# Delete cron job
	if ($job->{'module'}) {
		# Webmin cron
		&delete_cron_script($job);
		}
	else {
		# Classic cron
		&cron::delete_cron_job($job);
		}
	}
&cron::create_wrapper($backup_cron_cmd, $module_name, "backup.pl");
}

# delete_scheduled_backup(&backup)
# Remove one existing backup, and its cron job.
sub delete_scheduled_backup
{
local ($backup) = @_;
$backup->{'id'} == 1 && &error("The default backup cannot be deleted!");
&unlink_file($backup->{'file'});

# Delete cron too
local $cmd = $backup_cron_cmd." --id $backup->{'id'}";
local @jobs = &find_cron_script($cmd);
if ($backup->{'id'} == 1) {
	@jobs = grep { $_->{'command'} !~ /\-\-id/ } @jobs;
	}
if (@jobs) {
	&delete_cron_script($jobs[0]);
	}
}

# backup_domains(file, &domains, &features, dir-format, skip-errors, &options,
#		 home-format, &virtualmin-backups, mkdir, onebyone, as-owner,
#		 &callback-func, incremental, on-schedule, &key)
# Perform a backup of one or more domains into a single tar.gz file. Returns
# an OK flag, the size of the backup file, and a list of domains for which
# something went wrong.
sub backup_domains
{
local ($desturls, $doms, $features, $dirfmt, $skip, $opts, $homefmt, $vbs,
       $mkdir, $onebyone, $asowner, $cbfunc, $increment, $onsched, $key) = @_;
$desturls = [ $desturls ] if (!ref($desturls));
local $backupdir;
local $transferred_sz;

# Check if the limit on running backups has been hit
local $err = &check_backup_limits($asowner, $onsched, $desturl);
if ($err) {
	&$first_print($err);
	return (0, 0, $doms);
	}

# Work out who the backup is running as
local $asd;
if ($asowner) {
	($asd) = grep { !$_->{'parent'} } @$doms;
	$asd ||= $doms->[0];
	}

# Find the tar command
if (!&get_tar_command()) {
	&$first_print($text{'backup_etarcmd'});
	return (0, 0, $doms);
	}

# Check for clash between encryption and backup format
if ($key && $config{'compression'} == 3) {
	&$first_print($text{'backup_ezipkey'});
	return (0, 0, $doms);
	}

# Order destinations to put local ones first
@$desturls = sort { ($a =~ /^\// ? 0 : 1) <=> ($b =~ /^\// ? 0 : 1) }
		  @$desturls;

# See if we can actually connect to the remote server
local $anyremote;
local $anylocal;
local $rsh;	# Rackspace cloud files handle
foreach my $desturl (@$desturls) {
	local ($mode, $user, $pass, $server, $path, $port) =
		&parse_backup_url($desturl);
	local $starpass = "*" x length($pass);
	$anyremote = 1 if ($mode > 0);
	$anylocal = 1 if ($mode == 0);
	if ($mode == 0 && $asd) {
		# Always create virtualmin-backup directory
		$mkdir = 1;
		}
	if ($mode == 1) {
		# Try FTP login
		local $ftperr;
		&ftp_onecommand($server, "PWD", \$ftperr, $user, $pass, $port);
		if ($ftperr) {
			$ftperr =~ s/\Q$pass\E/$starpass/g;
			&$first_print(&text('backup_eftptest', $ftperr));
			return (0, 0, $doms);
			}
		if ($dirfmt) {
			# Also create the destination directory and all parents
			# (ignoring any error, as it may already exist)
			local @makepath = split(/\//, $path);
			local $prefix;
			if ($makepath[0] eq '') {
				# Remove leading /
				$prefix = '/';
				shift(@makepath);
				}
			for(my $i=0; $i<@makepath; $i++) {
				local $makepath = $prefix.
						  join("/", @makepath[0..$i]);
				local $mkdirerr;
				&ftp_onecommand($server, "MKD $makepath",
					\$mkdirerr, $user, $pass, $port);
				$mkdirerr =~ s/\Q$pass\E/$starpass/g;
				}
			}
		}
	elsif ($mode == 2) {
		# Try a dummy SCP
		local $scperr;
		local $qserver = &check_ip6address($server) ? "[$server]"
							    : $server;
		local $testuser = $user || "root";
		local $testfile = "/tmp/virtualmin-copy-test.$testuser";
		local $r = ($user ? "$user\@" : "").$qserver.":".$testfile;
		local $temp = &transname();
		open(TEMP, ">$temp");
		close(TEMP);
		&scp_copy($temp, $r, $pass, \$scperr, $port);
		if ($scperr) {
			# Copy to /tmp failed .. try current dir instead
			$scperr = undef;
			$testfile = "virtualmin-copy-test.$testuser";
			$r = ($user ? "$user\@" : "").$qserver.":".$testfile;
			&scp_copy($temp, $r, $pass, \$scperr, $port);
			}
		if ($scperr) {
			$scperr =~ s/\Q$pass\E/$starpass/g;
			&$first_print(&text('backup_escptest', $scperr));
			return (0, 0, $doms);
			}

		# Clean up dummy file if possible
		local $sshcmd = "ssh".($port ? " -p $port" : "")." ".
				$config{'ssh_args'}." ".
				($user ? "$user\@" : "").$server;
		local $rmcmd = $sshcmd." rm -f ".quotemeta($testfile);
		local $rmerr;
		&run_ssh_command($rmcmd, $pass, \$rmerr);

		if ($dirfmt && $path ne "/") {
			# Also create the destination directory now, by running
			# mkdir via ssh or scping an empty dir
			$path =~ /^(.*)\/([^\/]+)\/?$/;
			local ($pathdir, $pathfile) = ($1, $2);

			# ssh mkdir first
			local $mkcmd = $sshcmd.
				       " 'mkdir -p ".quotemeta($path)."'";
			local $err;
			local $lsout = &run_ssh_command($mkcmd, $pass, \$err);

			if ($err) {
				# Try scping an empty dir
				local $empty = &transname($pathfile);
				local $mkdirerr;
				&make_dir($empty, 0755);
				local $r = ($user ? "$user\@" : "").
					   "$server:$pathdir";
				&scp_copy($empty, $r, $pass, \$mkdirerr, $port);
				&unlink_file($empty);
				}
			}
		}
	elsif ($mode == 3) {
		# Connect to S3 service and create bucket
		if (!$path && !$dirfmt) {
			&$first_print($text{'backup_es3nopath'});
			return (0, 0, $doms);
			}
		local $cerr = &check_s3();
		if ($cerr) {
			&$first_print($cerr);
			return (0, 0, $doms);
			}
		local $err = &init_s3_bucket($user, $pass, $server,
					     $s3_upload_tries);
		if ($err) {
			&$first_print($err);
			return (0, 0, $doms);
			}
		}
	elsif ($mode == 6) {
		# Connect to Rackspace cloud files and create container
		if (!$path && !$dirfmt) {
			&$first_print($text{'backup_ersnopath'});
			return (0, 0, $doms);
			}
		$rsh = &rs_connect($config{'rs_endpoint'}, $user, $pass);
		if (!ref($rsh)) {
			&$first_print($rsh);
			return (0, 0, $doms);
			}
		local $err = &rs_create_container($rsh, $server);
		if ($err) {
			&$first_print($err);
			return (0, 0, $doms);
			}

		}
	elsif ($mode == 0) {
		# Make sure target is / is not a directory
		if ($dirfmt && !-d $desturl) {
			# Looking for a directory
			if ($mkdir) {
				local $derr = &make_backup_dir(
						$desturl, 0755, 1, $asd)
					if (!-d $desturl);
				if ($derr) {
					&$first_print(&text('backup_emkdir',
						   "<tt>$desturl</tt>", $derr));
					return (0, 0, $doms);
					}
				}
			else {
				&$first_print(&text('backup_edirtest',
						    "<tt>$desturl</tt>"));
				return (0, 0, $doms);
				}
			}
		elsif (!$dirfmt && -d $desturl) {
			&$first_print(&text('backup_enotdirtest',
					    "<tt>$desturl</tt>"));
			return (0, 0, $doms);
			}
		if (!$dirfmt && $mkdir) {
			# Create parent directories if requested
			local $dirdest = $desturl;
			$dirdest =~ s/\/[^\/]+$//;
			if ($dirdest && !-d $dirdest) {
				local $derr = &make_backup_dir(
						$dirdest, 0755, 0, $asd);
				if ($derr) {
					&$first_print(&text('backup_emkdir',
						   "<tt>$dirdest</tt>", $derr));
					return (0, 0, $doms);
					}
				}
			}
		if (@$desturls == 1) {
			$onebyone = 0;	# Local backups are always written
					# to the destination directly
			}
		}
	}

if (!$homefmt) {
	# Create a temp dir for the backup, to be tarred up later
	$backupdir = &transname();
	if (!-d $backupdir) {
		&make_dir($backupdir, 0700);
		}
	}
else {
	# A home-format backup can only be used if the home directory is
	# included, and if we are doing one per domain, and if all domains
	# *have* a home directory
	if (!$dirfmt) {
		&$first_print($text{'backup_ehomeformat'});
		return (0, 0, $doms);
		}
	if (&indexof("dir", @$features) == -1) {
		&$first_print($text{'backup_ehomeformat2'});
		return (0, 0, $doms);
		}
	}

# Work out where to write the final tar files to
local ($dest, @destfiles, %destfiles_map);
local ($mode0, $user0, $pass0, $server0, $path0, $port0) =
	&parse_backup_url($desturls->[0]);
if (!$anylocal) {
	# Write archive to temporary file/dir first, for later upload
	$path0 =~ /^(.*)\/([^\/]+)\/?$/;
	local ($pathdir, $pathfile) = ($1, $2);
	$dest = &transname($$."-".$pathfile);
	}
else {
	# Can write direct to destination (which we might also upload from)
	$dest = $path0;
	}
if ($dirfmt && !-d $dest) {
	# If backing up to a directory that doesn't exist yet, create it
	local $derr = &make_backup_dir($dest, 0700, 1, $asd);
	if ($derr) {
		&$first_print(&text('backup_emkdir', "<tt>$dest</tt>", $derr));
		return (0, 0, $doms);
		}
	}
elsif (!$dirfmt && $anyremote && $asd) {
	# Backing up to a temp file as domain owner .. create first
	&open_tempfile(DEST, ">$dest");
	&close_tempfile(DEST);
	&set_ownership_permissions($asd->{'uid'}, $asd->{'gid'}, undef, $dest);
	}

# For a home-format backup, the home has to be last
local @backupfeatures = @$features;
local $hfsuffix;
if ($homefmt) {
	@backupfeatures = ((grep { $_ ne "dir" } @$features), "dir");
	$hfsuffix = $config{'compression'} == 0 ? "tar.gz" :
		    $config{'compression'} == 1 ? "tar.bz2" :
		    $config{'compression'} == 3 ? "zip" : "tar";
	}

# Take a lock on the backup destination, to avoid concurrent backups to
# the same dest
local @lockfiles;
foreach my $desturl (@$desturls) {
	local $lockname = $desturl;
	$lockname =~ s/\//_/g;
	$lockname =~ s/\s/_/g;
	if (!-d $backup_locks_dir) {
		&make_dir($backup_locks_dir, 0700);
		}
	local $lockfile = $backup_locks_dir."/".$lockname;
	if (&test_lock($lockfile)) {
		local $lpid = &read_file_contents($lockfile.".lock");
		chomp($lpid);
		&$second_print(&text('backup_esamelock', $lpid));
		return (0, 0, $doms);
		}
	&lock_file($lockfile);
	push(@lockfiles, $lockfile);
	}

# Go through all the domains, and for each feature call the backup function
# to add it to the backup directory
local $d;
local $ok = 1;
local @donedoms;
local ($okcount, $errcount) = (0, 0);
local @errdoms;
local %donefeatures;				# Map from domain name->features
local @cleanuphomes;				# Temporary homes
local %donedoms;				# Map from domain name->hash
DOMAIN: foreach $d (@$doms) {
	# Make sure there are no databases that don't really exist, as these
	# can cause database feature backups to fail.
	my @alldbs = &all_databases($d);
        &resync_all_databases($d, \@alldbs);
	my $dstart = time();

	# If domain has a reseller set whole doesn't exist, clear it now
	# to prevent errors on restore
	if ($d->{'reseller'} && defined(&get_reseller) &&
	    !&get_reseller($d->{'reseller'})) {
		delete($d->{'reseller'});
		&save_domain($d);
		}

	# Begin doing this domain
	&$cbfunc($d, 0, $backupdir) if ($cbfunc);
	&$first_print(&text('backup_fordomain', &show_domain_name($d)));
	local $f;
	local $dok = 1;
	local @donefeatures;

	if ($homefmt && !$d->{'dir'} && !-d $d->{'home'}) {
		# Create temporary home directory
		&make_dir($d->{'home'}, 0755);
		&set_ownership_permissions($d->{'uid'}, $d->{'gid'}, undef,
					   $d->{'home'});
		$d->{'dir'} = 1;
		push(@cleanuphomes, $d);
		}
	elsif ($homefmt && $d->{'dir'} && !-d $d->{'home'}) {
		# Missing home dir which we need, so create it
		&make_dir($d->{'home'}, 0755);
		&set_ownership_permissions($d->{'uid'}, $d->{'gid'}, undef,
					   $d->{'home'});
		}
	elsif ($homefmt && !$d->{'dir'} && -d $d->{'home'}) {
		# Home directory actually exists, so enable it on the domain
		$d->{'dir'} = 1;
		}

	local $lockdir;
	if ($homefmt) {
		# Backup goes to a sub-dir of the home
		$lockdir = $backupdir = "$d->{'home'}/.backup";
		&lock_file($lockdir);
		system("rm -rf ".quotemeta($backupdir));
		local $derr = &make_backup_dir($backupdir, 0777, 0, $asd);
		if ($derr) {
			&$second_print(&text('backup_ebackupdir',
				"<tt>$backupdir</tt>", $derr));
			$dok = 1;
			goto DOMAINFAILED;
			}
		}

	&$indent_print();
	foreach $f (@backupfeatures) {
		local $bfunc = "backup_$f";
		local $fok;
		local $ffile;
		if (&indexof($f, &list_backup_plugins()) < 0 &&
		    defined(&$bfunc) &&
		    ($d->{$f} || $f eq "virtualmin" ||
		     $f eq "mail" && &can_domain_have_users($d))) {
			# Call core feature backup function
			if ($homefmt && $f eq "dir") {
				# For a home format backup, write the home
				# itself to the backup destination
				$ffile = "$dest/$d->{'dom'}.$hfsuffix";
				}
			else {
				$ffile = "$backupdir/$d->{'dom'}_$f";
				}
			$fok = &$bfunc($d, $ffile, $opts->{$f}, $homefmt,
				       $increment, $asd, $opts, $key);
			}
		elsif (&indexof($f, &list_backup_plugins()) >= 0 &&
		       $d->{$f}) {
			# Call plugin backup function
			$ffile = "$backupdir/$d->{'dom'}_$f";
			$fok = &plugin_call($f, "feature_backup",
					  $d, $ffile, $opts->{$f}, $homefmt,
					  $increment, $asd, $opts);
			}
		if (defined($fok)) {
			# See if it worked or not
			if (!$fok) {
				# Didn't work .. remove failed file, so we
				# don't have partial data
				if ($ffile && $f ne "dir" &&
				    $f ne "mysql" && $f ne "postgres") {
					foreach my $ff ($ffile,
						glob("${ffile}_*")) {
						&unlink_file($ff);
						}
					}
				$dok = 0;
				}
			if (!$fok && (!$skip || $homefmt && $f eq "dir")) {
				# If this feature failed and errors aren't being
				# skipped, stop the backup. Also stop if this
				# was the directory step of a home-format backup
				$ok = 0;
				$errcount++;
				push(@errdoms, $d);
				last DOMAIN;
				}
			push(@donedoms, &clean_domain_passwords($d));
			}
		if ($fok) {
			push(@donefeatures, $f);
			}
		}

	DOMAINFAILED:
	if ($lockdir) {
		&unlock_file($lockdir);
		}
	$donefeatures{$d->{'dom'}} = \@donefeatures;
	$donedoms{$d->{'dom'}} = $d;
	if ($dok) {
		$okcount++;
		}
	else {
		$errcount++;
		push(@errdoms, $d);
		}

	if ($onebyone && $homefmt && $dok && $anyremote) {
		# Transfer this domain now
		local $df = "$d->{'dom'}.$hfsuffix";
		&$cbfunc($d, 1, "$dest/$df") if ($cbfunc);
		local $tstart = time();
		local $binfo = { $d->{'dom'} =>
				 $donefeatures{$d->{'dom'}} };
		local $bdom = { $d->{'dom'} => &clean_domain_passwords($d) };
		local $infotemp = &transname();
		&uncat_file($infotemp, &serialise_variable($binfo));
		local $domtemp = &transname();
		&uncat_file($domtemp, &serialise_variable($bdom));
		foreach my $desturl (@$desturls) {
			local ($mode, $user, $pass, $server, $path, $port) =
				&parse_backup_url($desturl);
			local $starpass = "*" x length($pass);
			local $err;
			if ($mode == 0) {
				# Copy to another local directory
				next if ($path eq $path0);
				&$first_print(&text('backup_copy',
						    "<tt>$path/$df</tt>"));
				local $ok;
				if ($asd) {
					($ok, $err) = 
					  &copy_source_dest_as_domain_user(
					  $asd, "$path0/$df", "$path/$df");
					($ok, $err) = 
					  &copy_source_dest_as_domain_user(
					  $asd, $infotemp, "$path/$df.info")
						if (!$err);
					($ok, $err) = 
					  &copy_source_dest_as_domain_user(
					  $asd, $domtemp, "$path/$df.dom")
						if (!$err);
					}
				else {
					($ok, $err) = &copy_source_dest(
					  "$path0/$df", "$path/$df");
					($ok, $err) = &copy_source_dest(
					  $infotemp, "$path/$df.info")
						if (!$err);
					($ok, $err) = &copy_source_dest(
					  $domtemp, "$path/$df.dom")
						if (!$err);
					}
				if (!$ok) {
					&$second_print(
					  &text('backup_copyfailed', $err));
					}
				else {
					&$second_print($text{'setup_done'});
					$err = undef;
					}
				}
			elsif ($mode == 1) {
				# Via FTP
				&$first_print(&text('backup_upload',
						    "<tt>$server</tt>"));
				&ftp_upload($server, "$path/$df", "$dest/$df",
					    \$err, undef, $user, $pass, $port,
					    $ftp_upload_tries);
				&ftp_upload($server, "$path/$df.info",
					    $infotemp, \$err, undef, $user,
					    $pass, $port, $ftp_upload_tries)
						if (!$err);
				&ftp_upload($server, "$path/$df.dom",
					    $domtemp, \$err, undef, $user,
					    $pass, $port, $ftp_upload_tries)
						if (!$err);
				$err =~ s/\Q$pass\E/$starpass/g;
				}
			elsif ($mode == 2) {
				# Via SCP
				&$first_print(&text('backup_upload2',
						    "<tt>$server</tt>"));
				local $qserver = &check_ip6address($server) ?
							"[$server]" : $server;
				local $r = ($user ? "$user\@" : "").
					   "$qserver:$path";
				&scp_copy("$dest/$df", $r, $pass, \$err, $port);
				&scp_copy($infotemp, "$r/$df.info", $pass,
					  \$err, $port) if (!$err);
				&scp_copy($domtemp, "$r/$df.dom", $pass,
					  \$err, $port) if (!$err);
				$err =~ s/\Q$pass\E/$starpass/g;
				}
			elsif ($mode == 3) {
				# Via S3 upload
				&$first_print($text{'backup_upload3'});
				$err = &s3_upload($user, $pass, $server,
						  "$dest/$df",
						  $path ? $path."/".$df : $df,
						  $binfo, $bdom,
						  $s3_upload_tries, $port);
				}
			elsif ($mode == 6) {
				# Via rackspace upload
				&$first_print($text{'backup_upload6'});
				local $dfpath = $path ? $path."/".$df : $df;
				$err = &rs_upload_object($rsh,
					$server, $dfpath, "$dest/$df");
				$err = &rs_upload_object($rsh, $server,
					$dfpath.".info", $infotemp) if (!$err);
				$err = &rs_upload_object($rsh, $server,
					$dfpath.".dom", $domtemp) if (!$err);
				}
			if ($err) {
				&$second_print(&text('backup_uploadfailed',
						     $err));
				$ok = 0;
				}
			else {
				&$second_print($text{'setup_done'});
				local @tst = stat("$dest/$df");
				if ($mode != 0) {
					$transferred_sz += $tst[7];
					}
				if ($asd && $mode != 0) {
					&record_backup_bandwidth(
					    $d, 0, $tst[7], $tstart, time());
					}
				}
			}
		&unlink_file($infotemp);
		&unlink_file($domtemp);

		# Delete .backup directory
		&execute_command("rm -rf ".quotemeta("$d->{'home'}/.backup"));
		if (!$anylocal) {
			&execute_command("rm -rf ".quotemeta("$dest/$df"));
			}
		}

	&$outdent_print();
	my $dtime = time() - $dstart;
	&$second_print(&text('backup_donedomain',
			     &nice_hour_mins_secs($dtime, 1, 1)));
	&$cbfunc($d, 2, "$dest/$df") if ($cbfunc);
	}

# Remove duplicate done domains
local %doneseen;
@donedoms = grep { !$doneseen{$_->{'id'}}++ } @donedoms;

# Add all requested Virtualmin config information
local $vcount = 0;
if (@$vbs) {
	&$first_print($text{'backup_global'});
	&$indent_print();
	if ($homefmt) {
		# Need to make a backup dir, as we cannot use one of the
		# previous domains' dirs
		$backupdir = &transname();
		&make_dir($backupdir, 0755);
		}
	foreach my $v (@$vbs) {
		local $vfile = "$backupdir/virtualmin_".$v;
		local $vfunc = "virtualmin_backup_".$v;
		local $ok = &$vfunc($vfile, $vbs);
		$vcount++;
		}
	&$outdent_print();
	&$second_print($text{'setup_done'});
	}

if ($ok) {
	# Work out command for writing to backup destination (which may use
	# su, so that permissions are correct)
	local ($out, $err);
	if ($homefmt) {
		# No final step is needed for home-format backups, because
		# we have already reached it!
		if (!$onebyone) {
			foreach $d (@donedoms) {
				push(@destfiles, "$d->{'dom'}.$hfsuffix");
				$destfiles_map{$destfiles[$#destfiles]} = $d;
				}
			}
		}
	elsif ($dirfmt) {
		# Create one tar file in the destination for each domain
		&$first_print($text{'backup_final2'});
		if (!-d $dest) {
			&make_backup_dir($dest, 0755, 0, $asd);
			}

		foreach $d (@donedoms) {
			# Work out dest file and compression command
			local $destfile = "$d->{'dom'}.tar";
			local $comp = "cat";
			if ($config{'compression'} == 0) {
				$destfile .= ".gz";
				$comp = "gzip -c $config{'zip_args'}";
				}
			elsif ($config{'compression'} == 1) {
				$destfile .= ".bz2";
				$comp = &get_bzip2_command().
					" -c $config{'zip_args'}";
				}
			elsif ($config{'compression'} == 3) {
				$destfile =~ s/\.tar$/\.zip/;
				}

			# Create command that writes to the final file
			local $qf = quotemeta("$dest/$destfile");
			local $writer = "cat >$qf";
			if ($asd) {
				$writer = &command_as_user(
					$asd->{'user'}, 0, $writer);
				}

			# If encrypting, add gpg to the pipeline
			if ($key) {
				$writer = &backup_encryption_command($key).
					  " | ".$writer;
				}

			# Create the dest file with strict permissions
			local $toucher = "touch $qf && chmod 600 $qf";
			if ($asd) {
				$toucher = &command_as_user(
					$asd->{'user'}, 0, $toucher);
				}
			&execute_command($toucher);

			# Start the tar command
			if ($config{'compression'} == 3) {
				# ZIP does both archiving and compression
				&execute_command("cd $backupdir && ".
					 "zip -r - $d->{'dom'}_* | ".
					 $writer,
					 undef, \$out, \$err);
				}
			else {
				&execute_command(
					"cd $backupdir && ".
					"(".&make_tar_command(
					    "cf", "-", "$d->{'dom'}_*")." | ".
					"$comp) 2>&1 | $writer",
					undef, \$out, \$err);
				}
			push(@destfiles, $destfile);
			$destfiles_map{$destfile} = $d;
			if ($? || !-s "$dest/$destfile") {
				$out ||= $err;
				&unlink_file("$dest/$destfile");
				&$second_print(&text('backup_finalfailed',
						     "<pre>$out</pre>"));
				$ok = 0;
				last;
				}
			}
		&$second_print($text{'setup_done'}) if ($ok);
		}
	else {
		# Tar up the directory into the final file
		local $comp = "cat";
		if ($dest =~ /\.(gz|tgz)$/i) {
			$comp = "gzip -c $config{'zip_args'}";
			}
		elsif ($dest =~ /\.(bz2|tbz2)$/i) {
			$comp = &get_bzip2_command().
				" -c $config{'zip_args'}";
			}

		# Create writer command, which may run as the domain user
		local $writer = "cat >$dest";
		if ($asd) {
			&open_tempfile_as_domain_user(
				$asd, DEST, ">$dest", 0, 1);
			&close_tempfile_as_domain_user($asd, DEST);
			$writer = &command_as_user(
					$asd->{'user'}, 0, $writer);
			&set_ownership_permissions(undef, undef, 0600, $dest);
		 	}
		else {
			&open_tempfile(DEST, ">$dest", 0, 1);
			&close_tempfile(DEST);
			}

		# If encrypting, add gpg to the pipeline
		if ($key) {
			$writer = &backup_encryption_command($key).
				  " | ".$writer;
			}

		# Start the tar command
		&$first_print($text{'backup_final'});
		if ($dest =~ /\.zip$/i) {
			# Use zip command to archive and compress
			&execute_command("cd $backupdir && ".
					 "zip -r - . | $writer",
					 undef, \$out, \$err);
			}
		else {
			&execute_command("cd $backupdir && ".
					 "(".&make_tar_command("cf", "-", ".").
					 " | $comp) 2>&1 | $writer",
					 undef, \$out, \$err);
			}
		if ($? || !-s $dest) {
			$out ||= $err;
			&$second_print(&text('backup_finalfailed',
					     "<pre>$out</pre>"));
			$ok = 0;
			}
		else {
			&$second_print($text{'setup_done'});
			}
		}

	# If encrypting, add gpg to the pipeline
	if ($key) {
		$writer = &backup_encryption_command($key).
			  " | $writer";
		}

	# Create a separate file in the destination directory for Virtualmin
	# config backups
	if (@$vbs && ($homefmt || $dirfmt)) {
		local $comp;
		local $vdestfile;
		if (&has_command("gzip")) {
			$comp = "gzip -c $config{'zip_args'}";
			$vdestfile = "virtualmin.tar.gz";
			}
		else {
			$comp = "cat";
			$vdestfile = "virtualmin.tar";
			}
		# If encrypting, add gpg to the pipeline
		if ($key) {
			$comp = $comp." | ".&backup_encryption_command($key);
			}
		&execute_command(
		    "cd $backupdir && ".
		    "(".&make_tar_command("cf", "-", "virtualmin_*").
		    " | $comp > $dest/$vdestfile) 2>&1",
		    undef, \$out, \$out);
		&set_ownership_permissions(undef, undef, 0600,
					   $dest."/".$vdestfile);
		push(@destfiles, $vdestfile);
		$destfiles_map{$vdestfile} = "virtualmin";
		}
	$donefeatures{"virtualmin"} = $vbs;
	}

# Remove any temporary home dirs
foreach my $d (@cleanuphomes) {
	&unlink_file($d->{'home'});
	$d->{'dir'} = 0;
	&save_domain($d);	# In case it was saved during the backup
	}

if (!$homefmt) {
	# Remove the global backup temp directory
	&execute_command("rm -rf ".quotemeta($backupdir));
	}
elsif (!$onebyone) {
	# For each domain, remove it's .backup directory
	foreach $d (@$doms) {
		&execute_command("rm -rf ".quotemeta("$d->{'home'}/.backup"));
		}
	}

# Work out backup size, including files already transferred and deleted
local $sz = 0;
if ($dirfmt) {
	# Multiple files
	foreach my $f (@destfiles) {
		local @st = stat("$dest/$f");
		$sz += $st[7];
		}
	}
else {
	# One file
	local @st = stat($dest);
	$sz = $st[7];
	}
$sz += $transferred_sz;

foreach my $desturl (@$desturls) {
	local ($mode, $user, $pass, $server, $path, $port) =
		&parse_backup_url($desturl);
	if ($ok && $mode == 1 && (@destfiles || !$dirfmt)) {
		# Upload file(s) to FTP server
		&$first_print(&text('backup_upload', "<tt>$server</tt>"));
		local $err;
		local $infotemp = &transname();
		local $domtemp = &transname();
		if ($dirfmt) {
			# Need to upload entire directory .. which has to be
			# created first
			foreach my $df (@destfiles) {
				local $tstart = time();
				local $d = $destfiles_map{$df};
				local $n = $d eq "virtualmin" ? "virtualmin"
							      : $d->{'dom'};
				local $binfo = { $n => $donefeatures{$n} };
				local $bdom =
					{ $n => &clean_domain_passwords($d) };
				&uncat_file($infotemp,
					    &serialise_variable($binfo));
				&uncat_file($domtemp,
					    &serialise_variable($bdom));
				&ftp_upload($server, "$path/$df", "$dest/$df",
					    \$err, undef, $user, $pass, $port,
					    $ftp_upload_tries);
				&ftp_upload($server, "$path/$df.info",
					    $infotemp, \$err,
					    undef, $user, $pass, $port,
					    $ftp_upload_tries) if (!$err);
				&ftp_upload($server, "$path/$df.dom",
					    $domtemp, \$err,
					    undef, $user, $pass, $port,
					    $ftp_upload_tries) if (!$err);
				if ($err) {
					$err =~ s/\Q$pass\E/$starpass/g;
					&$second_print(
					    &text('backup_uploadfailed', $err));
					$ok = 0;
					last;
					}
				elsif ($asd && $d) {
					# Log bandwidth used by this domain
					local @tst = stat("$dest/$df");
					&record_backup_bandwidth(
					    $d, 0, $tst[7], $tstart, time());
					}
				}
			}
		else {
			# Just a single file
			local $tstart = time();
			&uncat_file($infotemp,
				    &serialise_variable(\%donefeatures));
			&uncat_file($domtemp,
				    &serialise_variable(\%donedoms));
			&ftp_upload($server, $path, $dest, \$err, undef, $user,
				    $pass, $port, $ftp_upload_tries);
			&ftp_upload($server, $path.".info", $infotemp, \$err,
				    undef, $user, $pass, $port,
				    $ftp_upload_tries) if (!$err);
			&ftp_upload($server, $path.".dom", $domtemp, \$err,
				    undef, $user, $pass, $port,
				    $ftp_upload_tries) if (!$err);
			if ($err) {
				$err =~ s/\Q$pass\E/$starpass/g;
				&$second_print(&text('backup_uploadfailed',
						     $err));
				$ok = 0;
				}
			elsif ($asd) {
				# Log bandwidth used by whole transfer
				local @tst = stat($dest);
				&record_backup_bandwidth($asd, 0, $tst[7], 
							 $tstart, time());
				}
			}
		&unlink_file($infotemp);
		&unlink_file($domtemp);
		&$second_print($text{'setup_done'}) if ($ok);
		}
	elsif ($ok && $mode == 2 && (@destfiles || !$dirfmt)) {
		# Upload to SSH server with scp
		&$first_print(&text('backup_upload2', "<tt>$server</tt>"));
		local $err;
		local $qserver = &check_ip6address($server) ?
					"[$server]" : $server;
		local $r = ($user ? "$user\@" : "")."$qserver:$path";
		local $infotemp = &transname();
		local $domtemp = &transname();
		if ($dirfmt) {
			# Need to upload all backup files in the directory
			$err = undef;
			local $tstart = time();
			foreach my $df (@destfiles) {
				&scp_copy("$dest/$df", "$r/$df",
					  $pass, \$err, $port);
				last if ($err);
				}
			if ($err) {
				# Target dir didn't exist, so scp just the
				# directory and all files
				$err = undef;
				&scp_copy($dest, $r, $pass, \$err, $port);
				}
			# Upload each domain's .info and .dom files
			foreach my $df (@destfiles) {
				local $d = $destfiles_map{$df};
				local $n = $d eq "virtualmin" ? "virtualmin"
							      : $d->{'dom'};
				local $binfo = { $n => $donefeatures{$n} };
				local $bdom = { $n => $d };
				&uncat_file($infotemp,
					    &serialise_variable($binfo));
				&uncat_file($domtemp,
					    &serialise_variable($bdom));
				&scp_copy($infotemp, $r."/$df.info", $pass,
					  \$err, $port) if (!$err);
				&scp_copy($domtemp, $r."/$df.dom", $pass,
					  \$err, $port) if (!$err);
				}
			$err =~ s/\Q$pass\E/$starpass/g;
			if (!$err && $asd) {
				# Log bandwidth used by domain
				foreach my $df (@destfiles) {
					local $d = $destfiles_map{$df};
					if ($d) {
						local @tst = stat("$dest/$df");
						&record_backup_bandwidth(
							$d, 0, $tst[7],
							$tstart, time());
						}
					}
				}
			}
		else {
			# Just a single file
			local $tstart = time();
			&uncat_file($infotemp,
				    &serialise_variable(\%donefeatures));
			&uncat_file($domtemp,
				    &serialise_variable(\%donedoms));
			&scp_copy($dest, $r, $pass, \$err, $port);
			&scp_copy($infotemp, $r.".info", $pass, \$err, $port)
				if (!$err);
			&scp_copy($domtemp, $r.".dom", $pass, \$err, $port)
				if (!$err);
			$err =~ s/\Q$pass\E/$starpass/g;
			if ($asd && !$err) {
				# Log bandwidth used by whole transfer
				local @tst = stat($dest);
				&record_backup_bandwidth($asd, 0, $tst[7], 
							 $tstart, time());
				}
			}
		if ($err) {
			&$second_print(&text('backup_uploadfailed', $err));
			$ok = 0;
			}
		&unlink_file($infotemp);
		&unlink_file($domtemp);
		&$second_print($text{'setup_done'}) if ($ok);
		}
	elsif ($ok && $mode == 3 && (@destfiles || !$dirfmt)) {
		# Upload to S3 server
		local $err;
		&$first_print($text{'backup_upload3'});
		if ($dirfmt) {
			# Upload an entire directory of files
			foreach my $df (@destfiles) {
				local $tstart = time();
				local $d = $destfiles_map{$df};
				local $n = $d eq "virtualmin" ? "virtualmin"
							      : $d->{'dom'};
				local $binfo = { $n => $donefeatures{$n} };
				local $bdom = $d eq "virtualmin" ? undef :
					{ $n => &clean_domain_passwords($d) };
				$err = &s3_upload($user, $pass, $server,
						  "$dest/$df",
						  $path ? $path."/".$df : $df,
						  $binfo, $bdom,
						  $s3_upload_tries, $port);
				if ($err) {
					&$second_print(
					    &text('backup_uploadfailed', $err));
					$ok = 0;
					last;
					}
				elsif ($asd && $d) {
					# Log bandwidth used by this domain
					local @tst = stat("$dest/$df");
					&record_backup_bandwidth(
						$d, 0, $tst[7], $tstart,time());
					}
				}
			}
		else {
			# Upload one file to the bucket
			local %donebydname;
			local $tstart = time();
			$err = &s3_upload($user, $pass, $server, $dest,
					  $path, \%donefeatures, \%donedoms,
					  $s3_upload_tries, $port);
			if ($err) {
				&$second_print(&text('backup_uploadfailed',
						     $err));
				$ok = 0;
				}
			elsif ($asd) {
				# Log bandwidth used by whole transfer
				local @tst = stat($dest);
				&record_backup_bandwidth($asd, 0, $tst[7], 
							 $tstart, time());
				}
			}
		&$second_print($text{'setup_done'}) if ($ok);
		}
	elsif ($ok && $mode == 6 && (@destfiles || !$dirfmt)) {
		# Upload to Rackspace cloud files
		local $err;
		&$first_print($text{'backup_upload6'});
		local $infotemp = &transname();
		local $domtemp = &transname();
		if ($dirfmt) {
			# Upload an entire directory of files
			local $tstart = time();
			foreach my $df (@destfiles) {
				local $d = $destfiles_map{$df};
				local $n = $d eq "virtualmin" ? "virtualmin"
							      : $d->{'dom'};
				local $binfo = { $n => $donefeatures{$n} };
				local $bdom = { $n => $d };
				&uncat_file($infotemp,
					    &serialise_variable($binfo));
				&uncat_file($domtemp,
					    &serialise_variable($bdom));
				local $dfpath = $path ? $path."/".$df : $df;
				$err = &rs_upload_object($rsh, $server,
					$dfpath, $dest."/".$df);
				$err = &rs_upload_object($rsh, $server,
					$dfpath.".info", $infotemp) if (!$err);
				$err = &rs_upload_object($rsh, $server,
					$dfpath.".dom", $domtemp) if (!$err);
				}
			if (!$err && $asd) {
				# Log bandwidth used by domain
				foreach my $df (@destfiles) {
					local $d = $destfiles_map{$df};
					if ($d) {
						local @tst = stat("$dest/$df");
						&record_backup_bandwidth(
							$d, 0, $tst[7],
							$tstart, time());
						}
					}
				}
			}
		else {
			# Upload one file to the container
			local $tstart = time();
			&uncat_file($infotemp,
				    &serialise_variable(\%donefeatures));
			&uncat_file($domtemp,
				    &serialise_variable(\%donedoms));
			$err = &rs_upload_object($rsh, $server, $path, $dest);
			$err = &rs_upload_object($rsh, $server, $path.".info",
					  $infotemp) if (!$err);
			$err = &rs_upload_object($rsh, $server, $path.".dom",
					  $domtemp) if (!$err);
			if ($asd && !$err) {
				# Log bandwidth used by whole transfer
				local @tst = stat($dest);
				&record_backup_bandwidth($asd, 0, $tst[7], 
							 $tstart, time());
				}
			}
		if ($err) {
			&$second_print(&text('backup_uploadfailed', $err));
			$ok = 0;
			}
		&unlink_file($infotemp);
		&unlink_file($domtemp);
		&$second_print($text{'setup_done'}) if ($ok);
		}
	elsif ($ok && $mode == 0 && (@destfiles || !$dirfmt) &&
	       $path ne $path0) {
		# Copy to another local directory
		&$first_print(&text('backup_copy', "<tt>$path</tt>"));
		my ($ok, $err);
		if ($asd && $dirfmt) {
			# Copy separate files as doman owner
			foreach my $df (@destfiles) {
				($ok, $err) = &copy_source_dest_as_domain_user(
					$asd, "$path0/$df", "$path/$df");
				last if (!$ok);
				}
			}
		elsif ($asd && !$dirfmt) {
			# Copy one file as domain owner
			($ok, $err) = &copy_source_dest_as_domain_user(
				$asd, $path0, $path);
			}
		elsif (!$asd && $dirfmt) {
			# Copy separate files as root
			foreach my $df (@destfiles) {
				($ok, $err) = &copy_source_dest(
					"$path0/$df", "$path/$df");
				last if (!$ok);
				}
			}
		elsif (!$asd && !$dirfmt) {
			# Copy one file as root
			($ok, $err) = &copy_source_dest($path0, $path);
			}
		if (!$ok) {
			&$second_print(&text('backup_copyfailed', $err));
			$ok = 0;
			}
		else {
			&$second_print($text{'setup_done'});
			}
		}
	if ($ok && $mode == 0 && (@destfiles || !$dirfmt)) {
		# Write out .info and .dom files, even for initial destination
		if ($dirfmt) {
			# One .info and .dom file per domain
			foreach my $df (@destfiles) {
				local $d = $destfiles_map{$df};
				local $n = $d eq "virtualmin" ? "virtualmin"
							      : $d->{'dom'};
				local $binfo = { $n => $donefeatures{$n} };
				local $bdom = { $n => $d };
				local $wcode = sub { 
					&uncat_file("$dest/$df.info",
					    &serialise_variable($binfo));
					if ($d ne "virtualmin") {
						&uncat_file("$dest/$df.dom",
						    &serialise_variable($bdom));
						}
					};
				if ($asd) {
					&write_as_domain_user($asd, $wcode);
					}
				else {
					&$wcode();
					}
				}
			}
		else {
			# A single file
			local $wcode = sub {
				&uncat_file("$dest.info",
					&serialise_variable(\%donefeatures));
				&uncat_file("$dest.dom",
					&serialise_variable(\%donedoms));
				};
			if ($asd) {
				&write_as_domain_user($asd, $wcode);
				}
			else {
				&$wcode();
				}
			}
		}
	}

if (!$anylocal) {
	# Always delete the temporary destination
	&execute_command("rm -rf ".quotemeta($dest));
	}

# Show some status
if ($ok) {
	&$first_print(
	  ($okcount || $errcount ?
	    &text('backup_finalstatus', $okcount, $errcount) : "")."\n".
	  ($vcount ? &text('backup_finalstatus2', $vcount) : ""));
	if ($errcount) {
		&$first_print(&text('backup_errorsites',
			      join(" ", map { $_->{'dom'} } @errdoms)));
		}
	}

# Release lock on dest file
foreach my $lockfile (@lockfiles) {
	&unlock_file($lockfile);
	}

return ($ok, $sz, \@errdoms);
}

# make_backup_dir(dir, perms, recursive, &as-domain)
# Create the directory for a backup destination, perhaps as the domain owner.
# Returns undef if OK, or an error message if failed.
# If under the temp directory, this is always done as root.
sub make_backup_dir
{
local ($dir, $perms, $recur, $d) = @_;
local $cmd = "mkdir".($recur ? " -p" : "")." ".quotemeta($dir)." 2>&1";
local $out;
local $tempbase = $gconfig{'tempdir_'.$module_name} ||
		  $gconfig{'tempdir'} ||
		  "/tmp/.webmin";
if ($d && !&is_under_directory($tempbase, $dir)) {
	# As domain owner if not under temp base
	$out = &run_as_domain_user($d, $cmd, 0, 1);
	}
else {
	# As root, but make owned by user if given
	$out = &backquote_command($cmd);
	if (!$? && $d) {
		&set_ownership_permissions($d->{'uid'}, $d->{'ugid'},
					   undef, $dir);
		}
	}
# Set requested permissions
if (!$?) {
	if ($d) {
		&set_permissions_as_domain_user($d, $perms, $dir);
		}
	else {
		&set_ownership_permissions(undef, undef, $perms, $dir);
		}
	}
return $? ? $out : undef;
}

# restore_domains(file, &domains, &features, &options, &vbs,
#		  [only-backup-features], [&ip-address-info], [as-owner],
#		  [skip-warnings], [&key], [continue-on-errors])
# Restore multiple domains from the given file
sub restore_domains
{
local ($file, $doms, $features, $opts, $vbs, $onlyfeats, $ipinfo, $asowner,
       $skipwarnings, $key, $continue) = @_;

# Find owning domain
local $asd;
if ($asowner) {
	($asd) = grep { !$_->{'parent'} && !$_->{'missing'} } @$doms;
	$asd ||= $doms->[0];
	}

# Work out where the backup is located
local $ok = 1;
local $backup;
local ($mode, $user, $pass, $server, $path, $port) = &parse_backup_url($file);
local $starpass = "*" x length($pass);
if ($mode > 0) {
	# Need to download to temp file/directory first
	&$first_print($mode == 1 ? $text{'restore_download'} :
		      $mode == 3 ? $text{'restore_downloads3'} :
		      $mode == 6 ? $text{'restore_downloadrs'} :
				   $text{'restore_downloadssh'});
	if ($mode == 3) {
		local $cerr = &check_s3();
		if ($cerr) {
			&$second_print($cerr);
			return 0;
			}
		}
	$backup = &transname();
	local $tstart = time();
	local $derr = &download_backup($_[0], $backup,
		[ map { $_->{'dom'} } @$doms ], $vbs);
	if ($derr) {
		$derr =~ s/\Q$pass\E/$starpass/g;
		&$second_print(&text('restore_downloadfailed', $derr));
		$ok = 0;
		}
	else {
		# Done .. account for bandwidth
		if ($asd) {
			local $sz = &disk_usage_kb($backup)*1024;
			&record_backup_bandwidth($asd, $sz, 0, $tstart, time());
			}
		&$second_print($text{'setup_done'});
		}
	}
else {
	$backup = $file;
	}

local $restoredir;
local %homeformat;
if ($ok) {
	# Create a temp dir for the backup archive contents
	$restoredir = &transname();
	&make_dir($restoredir, 0711);

	local @files;
	if (-d $backup) {
		# Extracting a directory of backup files
		&$first_print($text{'restore_first2'});
		opendir(DIR, $backup);
		@files = map { "$backup/$_" }
			     grep { $_ ne "." && $_ ne ".." &&
				    !/\.(info|dom)$/ } readdir(DIR);
		closedir(DIR);
		}
	else {
		# Extracting one backup file
		&$first_print($text{'restore_first'});
		@files = ( $backup );
		}

	# Extract each of the files
	local $f;
	foreach $f (@files) {
		local $out;
		local $q = quotemeta($f);

		# Make sure file is for a domain we want to restore, unless
		# we are restoring templates or from a single file, in which
		# case all files need to be extracted.
		if (-r $f.".info" && !@$vbs && -d $backup) {
			local $info = &unserialise_variable(
					&read_file_contents($f.".info"));
			if ($info) {
				local @wantdoms = grep { $info->{$_->{'dom'}} }
						       @$doms;
				next if (!@wantdoms);
				}
			}

		# See if this is a home-format backup, by looking for a .backup
		# sub-directory
		local ($lout, $lerr, @lines, $reader);
		local $cf = &compression_format($f, $key);

		# Create command to read the file, as the correct user and
		# possibly with decryption
		local $catter = "cat $q";
		if ($asowner && $mode == 0) {
			$catter = &command_as_user(
				$doms[0]->{'user'}, 0, $catter);
			}
		if ($key) {
			$catter = $catter." | ".
				  &backup_decryption_command($key);
			}

		if ($cf == 4) {
			# ZIP files are extracted with a single command
			$reader = "unzip -l $q";
			if ($asowner && $mode == 0) {
				# Read as domain owner, to prevent access to
				# other files
				$reader = &command_as_user(
					$doms[0]->{'user'}, 0, $reader);
				}
			&execute_command($reader, undef, \$lout, \$lerr);
			foreach my $l (split(/\r?\n/, $lout)) {
				if ($l =~ /^\s*(\d+)\s*\d+\-\d+\-\d+\s+\d+:\d+\s+(.*)/) {
					push(@lines, $2);
					}
				}
			}
		else {
			# Other formats use uncompress | tar
			local $comp = $cf == 1 ? "gunzip -c" :
				      $cf == 2 ? "uncompress -c" :
				      $cf == 3 ? &get_bunzip2_command()." -c" :
						 "cat";
			$reader = $catter." | ".$comp;
			&execute_command("$reader | ".
					 &make_tar_command("tf", "-"), undef,
					 \$lout, \$lerr);
			@lines = split(/\n/, $lout);
			}
		local $extract;
		if (&indexof("./.backup/", @lines) >= 0 ||
		    &indexof("./.backup", @lines) >= 0) {
			# Home format! Only extract the .backup directory, as it
			# contains the feature files
			$homeformat{$f} = $f;
			$extract = "./.backup";
			}
		elsif (&indexof(".backup", @lines) >= 0) {
			# Also home format, but with slightly different
			# directory name
			$homeformat{$f} = $f;
			$extract = ".backup";
			}
		elsif (&indexof(".backup/", @lines) >= 0) {
			# Home format as in ZIP file
			$homeformat{$f} = $f;
			$extract = ".backup/*";
			}

		# If encrypted, check signature too
		if ($key) {
			if ($lerr !~ /Good\s+signature\s+from/ ||
			    $lerr !~ /Signature\s+made.*key\s+ID\s+(\S+)/ ||
			    $1 ne $key->{'key'}) {
				&$second_print(&text('restore_badkey',
					$key->{'key'},
					"<pre>".&html_escape($lerr)."</pre>"));
				$ok = 0;
				last;
				}
			}

		# Do the actual extraction
		if ($cf == 4) {
			# Using unzip command
			$reader = "unzip $q $extract";
			if ($asowner && $mode == 0) {
				$reader = &command_as_user(
					$doms[0]->{'user'}, 0, $reader);
				}
			&execute_command("cd ".quotemeta($restoredir)." && ".
				$reader, undef,
				\$out, \$out);
			}
		else {
			# Using tar pipeline
			&execute_command(
			    "cd ".quotemeta($restoredir)." && ".
			    "($reader | ".
			    &make_tar_command("xf", "-", $extract).")", undef,
			    \$out, \$out);
			}
		if ($?) {
			&$second_print(&text('restore_firstfailed',
					     "<tt>$f</tt>", "<pre>$out</pre>"));
			$ok = 0;
			last;
			}
		&set_ownership_permissions(undef, undef, 0711, $restoredir);

		if ($homeformat{$f}) {
			# Move the .backup contents to the restore dir, as
			# expected by later code
			&execute_command(
				"mv ".quotemeta("$restoredir/.backup")."/* ".
				      quotemeta($restoredir));
			}
		}
	&$second_print($text{'setup_done'}) if ($ok);
	}

# Make sure any domains we need to re-create have a Virtualmin info file
foreach $d (@{$_[1]}) {
	if ($d->{'missing'}) {
		if (!-r "$restoredir/$d->{'dom'}_virtualmin") {
			&$second_print(&text('restore_missinginfo',
					     &show_domain_name($d)));
			$ok = 0;
			last;
			}
		}
	}

# Lock user DB for UID re-allocation
if ($_[3]->{'reuid'}) {
	&obtain_lock_unix($d);
	}

# Clear left-frame links cache, as the restore may change them
&clear_links_cache();

local $vcount = 0;
local %restoreok;	# Which domain IDs were restored OK?
if ($ok) {
	# Restore any Virtualmin settings
	if (@$vbs) {
		&$first_print($text{'restore_global2'});
		&$indent_print();
		foreach my $v (@$vbs) {
			local $vfile = "$restoredir/virtualmin_".$v;
			if (-r $vfile) {
				local $vfunc = "virtualmin_restore_".$v;
				local $ok = &$vfunc($vfile, $vbs);
				$vcount++;
				}
			}
		&$outdent_print();
		&$second_print($text{'setup_done'});
		}

	# Fill in missing domain details
	foreach $d (grep { $_->{'missing'} } @$doms) {
		$d = &get_domain(undef,
			"$restoredir/$d->{'dom'}_virtualmin");
		if ($_[3]->{'fix'}) {
			# We can just use the domains file from the
			# backup and import it
			&save_domain($d, 1);
			}
		else {
			# We will be re-creating the server
			$d->{'missing'} = 1;
			}
		}

	# Now restore each of the domain/feature files
	local $d;
	local @bplugins = &list_backup_plugins();
	DOMAIN: foreach $d (sort { $a->{'parent'} <=> $b->{'parent'} ||
				   $a->{'alias'} <=> $b->{'alias'} } @$doms) {
		if ($d->{'missing'}) {
			# This domain doesn't exist yet - need to re-create it
			&$first_print(&text('restore_createdomain',
				      &show_domain_name($d)));

			# Check if licence limits are exceeded
			local ($dleft, $dreason, $dmax) = &count_domains(
				$d->{'alias'} ? "aliasdoms" :"realdoms");
			if ($dleft == 0) {
				&$second_print(&text('restore_elimit', $dmax));
				$ok = 0;
				if ($continue) { next DOMAIN; }
				else { last DOMAIN; }
				}

			# Only features in the backup are enabled
			if ($onlyfeats) {
				foreach my $f (@backup_features, @bplugins) {
					if ($d->{$f} &&
					    &indexof($f, @$features) < 0) {
						$d->{$f} = 0;
						}
					}
				}

			local ($parentdom, $parentuser);
			if ($d->{'parent'}) {
				# Does the parent exist?
				$parentdom = &get_domain($d->{'parent'});
				if (!$parentdom && $d->{'backup_parent_dom'}) {
					# Domain with same name exists, but ID
					# has changed.
					$parentdom = &get_domain_by(
					    "dom", $d->{'backup_parent_dom'});
					$d->{'parent'} = $parentdom->{'id'};
					}
				if (!$parentdom) {
					&$second_print(
					    $d->{'backup_parent_dom'} ?
						&text('restore_epardom',
						    $d->{'backup_parent_dom'}) :
						$text{'restore_epar'});
					$ok = 0;
					if ($continue) { next DOMAIN; }
					else { last DOMAIN; }
					}
				$parentuser = $parentdom->{'user'};
				}

			# Does the template exist?
			local $tmpl = &get_template($d->{'template'});
			if (!$tmpl) {
				# No .. does the backup have it?
				local $tmplfile =
				  "$restoredir/$d->{'dom'}_virtualmin_template";
				if (-r $tmplfile) {
					# Yes - create on this system and use
					&make_dir($templates_dir, 0700);
					&copy_source_dest(
					    $tmplfile,
					    "$templates_dir/$d->{'template'}");
					undef(@list_templates_cache);
					$tmpl = &get_template($d->{'template'});
					}
				}
			if (!$tmpl) {
				&$second_print($text{'restore_etemplate'});
				$ok = 0;
				if ($continue) { next DOMAIN; }
				else { last DOMAIN; }
				}

			# Does the plan exist? If not, get it from the backup
			local $plan = &get_plan($d->{'plan'});
			if (!$plan) {
				local $planfile =
				  "$restoredir/$d->{'dom'}_virtualmin_plan";
				if (-r $planfile) {
					&make_dir($plans_dir, 0700);
					&copy_source_dest(
					  $planfile, "$plans_dir/$d->{'plan'}");
					undef(@list_plans_cache);
					}
				}

			# Does the reseller exist? If not, fail
			if ($d->{'reseller'} && defined(&get_reseller)) {
				my $resel = &get_reseller($d->{'reseller'});
				if (!$resel && $skipwarnings) {
					&$second_print(&text('restore_eresel2',
							$d->{'reseller'}));
					delete($d->{'reseller'});
					}
				elsif (!$resel) {
					&$second_print(&text('restore_eresel',
							$d->{'reseller'}));
					$ok = 0;
					if ($continue) { next DOMAIN; }
					else { last DOMAIN; }
					}
				}

			if ($parentdom) {
				# UID and GID always come from parent
				$d->{'uid'} = $parentdom->{'uid'};
				$d->{'gid'} = $parentdom->{'gid'};
				$d->{'ugid'} = $parentdom->{'ugid'};
				}
			elsif ($_[3]->{'reuid'}) {
				# Re-allocate the UID and GID
				local ($samegid) = ($d->{'gid'}==$d->{'ugid'});
				local (%gtaken, %taken);
				&build_group_taken(\%gtaken);
				$d->{'gid'} = &allocate_gid(\%gtaken);
				$d->{'ugid'} = $d->{'gid'};
				&build_taken(\%taken);
				$d->{'uid'} = &allocate_uid(\%taken);
                                if (!$samegid) {
                                        # Old ugid was custom, so set from old
                                        # group name
                                        local @ginfo = getgrnam($d->{'ugroup'});
                                        if (@ginfo) {
                                                $d->{'ugid'} = $ginfo[2];
                                                }
                                        }
				}

			# Set the home directory to match this system's base
			local $oldhome = $d->{'home'};
			$d->{'home'} = &server_home_directory($d, $parentdom);
			if ($d->{'home'} ne $oldhome) {
				# Fix up setings that reference the home
				$d->{'ssl_cert'} =~s/\Q$oldhome\E/$d->{'home'}/;
				$d->{'ssl_key'} =~ s/\Q$oldhome\E/$d->{'home'}/;
				}

			# Fix up the IP address if needed
			$d->{'old_ip'} = $d->{'ip'};
			if ($d->{'alias'}) {
				# Alias domains always have same IP as parent
				local $alias = &get_domain($d->{'alias'});
				$d->{'ip'} = $alias->{'ip'};
				}
			elsif ($ipinfo && $ipinfo->{'mode'} == 5) {
				# Allocate IP if the domain had one before,
				# use shared IP otherwise
				if ($d->{'virt'}) {
					# Try to allocate, assuming template
					# defines an IP range
					local %taken =&interface_ip_addresses();
					if ($tmpl->{'ranges'} eq "none") {
						&$second_print(
						    &text('setup_evirttmpl'));
						$ok = 0;
						if ($continue) { next DOMAIN; }
						else { last DOMAIN; }
						}
					$d->{'virtalready'} = 0;
					if (&ip_within_ranges(
					      $d->{'ip'}, $tmpl->{'ranges'}) &&
					    !$taken{$d->{'ip'}} &&
					    !&ping_ip_address($d->{'ip'})) {
						# Old IP is within local range,
						# so keep it
						}
					else {
						# Actually allocate from range
						($d->{'ip'}, $d->{'netmask'}) =
							&free_ip_address($tmpl);
						if (!$d->{'ip'}) {
							&$second_print(&text('setup_evirtalloc'));
							$ok = 0;
							if ($continue) { next DOMAIN; }
							else { last DOMAIN; }
							}
						}
					}
				elsif (&indexof($d->{'ip'},
						&list_shared_ips()) >= 0) {
					# IP is on shared list, so keep it
					}
				else {
					# Use shared IP
					$d->{'ip'} = &get_default_ip(
							$d->{'reseller'});
					if (!$d->{'ip'}) {
						&$second_print(
						    $text{'restore_edefip'});
						$ok = 0;
						if ($continue) { next DOMAIN; }
						else { last DOMAIN; }
						}
					}
				}
			elsif ($ipinfo) {
				# Use IP specified on backup form
				$d->{'ip'} = $ipinfo->{'ip'};
				$d->{'virt'} = $ipinfo->{'virt'};
				$d->{'virtalready'} = $ipinfo->{'virtalready'};
				$d->{'netmask'} = $netmaskinfo->{'netmask'};
				if ($ipinfo->{'mode'} == 2) {
					# Re-allocate an IP, as we might be
					# doing several domains
					($d->{'ip'}, $d->{'netmask'}) =
						&free_ip_address($tmpl);
					}
				if (!$d->{'ip'}) {
					&$second_print(
						&text('setup_evirtalloc'));
					$ok = 0;
					if ($continue) { next DOMAIN; }
					else { last DOMAIN; }
					}
				}
			elsif (!$d->{'virt'} && !$config{'all_namevirtual'}) {
				# Use this system's default IP
				$d->{'ip'} = &get_default_ip($d->{'reseller'});
				if (!$d->{'ip'}) {
					&$second_print($text{'restore_edefip'});
					$ok = 0;
					if ($continue) { next DOMAIN; }
					else { last DOMAIN; }
					}
				}

			# DNS external IP is always reset to match this system,
			# as the old setting is unlikely to be correct.
			$d->{'old_dns_ip'} = $d->{'dns_ip'};
			$d->{'dns_ip'} = $virt || $config{'all_namevirtual'} ?
				undef : &get_dns_ip();

			# Change provisioning settings to match this system
			foreach my $f (&list_provision_features()) {
				$d->{'provision_'.$f} = 0;
				}
			&set_provision_features($d);

			# Check for clashes
			local $cerr = &virtual_server_clashes($d);
			if ($cerr) {
				&$second_print(&text('restore_eclash', $cerr));
				$ok = 0;
				if ($continue) { next DOMAIN; }
				else { last DOMAIN; }
				}

			# Check for warnings
			if (!$skipwarnings) {
				local @warns = &virtual_server_warnings($d);
				if (@warns) {
					&$second_print(
						$text{'restore_ewarnings'});
					&$indent_print();
					foreach my $w (@warns) {
						&$second_print($w);
						}
					&$outdent_print();
					$ok = 0;
					if ($continue) { next DOMAIN; }
					else { last DOMAIN; }
					}
				}

			# Finally, create it
			&$indent_print();
			delete($d->{'missing'});
			$d->{'wasmissing'} = 1;
			$d->{'nocreationmail'} = 1;
			$d->{'nocreationscripts'} = 1;
			$d->{'nocopyskel'} = 1;
			&create_virtual_server($d, $parentdom,
			       $parentdom ? $parentdom->{'user'} : undef, 1);
			&$outdent_print();
			}
		else {
			# Make sure there are no databases that don't really
			# exist, to avoid failures on restore.
			my @alldbs = &all_databases($d);
			&resync_all_databases($d, \@alldbs);
			}

		# Users need to be restored last
		local @rfeatures = @$features;
		if (&indexof("mail", @rfeatures) >= 0) {
			@rfeatures =((grep { $_ ne "mail" } @$features),"mail");
			}

		&$first_print(&text('restore_fordomain',
				    &show_domain_name($d)));

		# Run the before command
		&set_domain_envs($dom, "RESTORE_DOMAIN");
		local $merr = &making_changes();
		&reset_domain_envs($d);
		if (defined($merr)) {
			&$second_print(&text('setup_emaking',"<tt>$merr</tt>"));
			}
		else {
			# Disable quotas for this domain, so that restores work
			my $qd = $d->{'parent'} ? &get_domain($d->{'parent'})
						: $d;
			if (&has_home_quotas()) {
				&set_server_quotas($qd, 0, 0);
				}

			# Now do the actual restore, feature by feature
			&$indent_print();
			local $f;
			local %oldd;
			my $domain_failed = 0;
			foreach $f (@rfeatures) {
				# Restore features
				local $rfunc = "restore_$f";
				local $fok;
				if (&indexof($f, @bplugins) < 0 &&
				    defined(&$rfunc) &&
				    ($d->{$f} || $f eq "virtualmin" ||
				     $f eq "mail" &&
				     &can_domain_have_users($d))) {
					local $ffile;
					local $p = "$backup/$d->{'dom'}.tar";
					local $hft =
					    $homeformat{"$p.gz"} ||
					    $homeformat{"$p.bz2"}||
					    $homeformat{$p} ||
					    $homeformat{$backup};
					if ($hft && $f eq "dir") {
						# For a home-format backup, the
						# backup itself is the home
						$ffile = $hft;
						}
					else {
						$ffile = $restoredir."/".
							 $d->{'dom'}."_".$f;
						}
					if ($f eq "virtualmin") {
						# If restoring the virtualmin
						# info, keep old feature file
						&read_file($ffile, \%oldd);
						}
					if (-r $ffile) {
						# Call the restore function
						$fok = &$rfunc($d, $ffile,
						     $_[3]->{$f}, $_[3], $hft,
						     \%oldd, $asowner, $key);
						}
					}
				elsif (&indexof($f, @bplugins) >= 0 &&
				       $d->{$f}) {
					# Restoring a plugin feature
					local $ffile =
						"$restoredir/$d->{'dom'}_$f";
					if (-r $ffile) {
						$fok = &plugin_call($f,
						    "feature_restore", $d,
						    $ffile, $_[3]->{$f}, $_[3],
						    $hft, \%oldd, $asowner);
						}
					}
				if (defined($fok) && !$fok) {
					# Handle feature failure
					$ok = 0;
					&$outdent_print();
					$domain_failed = 1;
					last;
					}
				}
			&save_domain($d);

			# Re-enable quotas for this domain, or parent
			if (&has_home_quotas()) {
				&set_server_quotas($qd);
				}

			# Make site the default if it was before
			if ($d->{'web'} && $d->{'backup_web_default'}) {
				&set_default_website($d);
				}

			# Run the post-restore command
			&set_domain_envs($d, "RESTORE_DOMAIN", undef, \%oldd);
			local $merr = &made_changes();
			&$second_print(&text('setup_emade', "<tt>$merr</tt>"))
				if (defined($merr));
			&reset_domain_envs($d);

			if ($domain_failed) {
				if ($continue) { next DOMAIN; }
				else { last DOMAIN; }
				}
			else {
				$restoreok{$d->{'id'}} = 1;
				}
			}

		# Re-setup Webmin user
		&refresh_webmin_user($d);
		&$outdent_print();
		}
	}

# Find domains that were restored OK
if ($continue) {
	$doms = [ grep { $restoreok{$_->{'id'}} } @$doms ];
	}
elsif (!$ok) {
	$doms = [ ];
	}

# If any created restored domains had scripts, re-verify their dependencies
local @wasmissing = grep { $_->{'wasmissing'} } @$doms;
if (defined(&list_domain_scripts) && scalar(@wasmissing)) {
	&$first_print($text{'restore_phpmods'});
	local %scache;
	local (@phpinstalled, $phpanyfailed, @phpbad);
	foreach my $d (@wasmissing) {
		local @sinfos = &list_domain_scripts($d);
		foreach my $sinfo (@sinfos) {
			# Get the script, with caching
			local $script = $scache{$sinfo->{'name'}};
			if (!$script) {
				$script = $scache{$sinfo->{'name'}} =
					&get_script($sinfo->{'name'});
				}
			next if (!$script);
			next if (&indexof('php', @{$script->{'uses'}}) < 0);

			# Work out PHP version for this particular install. Use
			# the version recorded at script install time first,
			# then that from it's directory.
			local $phpver = $sinfo->{'opts'}->{'phpver'};
			local @dirs = &list_domain_php_directories($d);
			foreach my $dir (@dirs) {
				if ($dir->{'dir'} eq $sinfo->{'dir'}) {
					$phpver ||= $dir->{'version'};
					}
				}
			foreach my $dir (@dirs) {
				if ($dir->{'dir'} eq &public_html_dir($d)) {
					$phpver ||= $dir->{'version'};
					}
				}
			local @allvers = map { $_->[0] }
					     &list_available_php_versions($d);
			$phpver ||= $allvers[0];

			# Is this PHP version supported on the new system?
			if (&indexof($phpver, @allvers) < 0) {
				push(@phpbad, [ $d, $sinfo, $script, $phpver ]);
				next;
				}

			# Re-activate it's PHP modules
			&push_all_print();
			local $pok = &setup_php_modules($d, $script,
			   $sinfo->{'version'}, $phpver, $sinfo->{'opts'},
			   \@phpinstalled);
			&pop_all_print();
			$phpanyfailed++ if (!$pok);
			}
		}
	if ($anyfailed) {
		&$second_print($text{'restore_ephpmodserr'});
		}
	elsif (@phpinstalled) {
		&$second_print(&text('restore_phpmodsdone',
			join(" ", &unique(@phpinstalled))));
		}
	else {
		&$second_print($text{'restore_phpmodsnone'});
		}
	if (@phpbad) {
		# Some scripts needed missing PHP versions!
		my $badlist = $text{'restore_phpbad'}."<br>\n";
		foreach my $b (@phpbad) {
			$badlist .= &text('restore_phpbad2',
					  &show_domain_name($b->[0]),
					  $b->[2]->{'desc'}, $b->[3])."<br>\n";
			}
		&$second_print($badlist);
		}
	}

# Apply symlink and security restrictions on restored domains
&fix_mod_php_security($doms);
if (!$config{'allow_symlinks'}) {
	&fix_symlink_security($doms);
	}

# Clear any missing flags
foreach my $d (@$doms) {
	if ($d->{'wasmissing'}) {
		delete($d->{'wasmissing'});
		delete($d->{'old_ip'});
		delete($d->{'old_dns_ip'});
		&save_domain($d);
		}
	}

if ($_[3]->{'reuid'}) {
	&release_lock_unix($d);
	}

&execute_command("rm -rf ".quotemeta($restoredir));
if ($mode > 0) {
	# Clean up downloaded file
	&execute_command("rm -rf ".quotemeta($backup));
	}
return $ok;
}

# backup_contents(file, [want-domains], [&key])
# Returns a hash ref of domains and features in a backup file, or an error
# string if it is invalid. If the want-domains flag is given, the domain
# structures are also returned as a list of hash refs (except for S3).
sub backup_contents
{
local ($file, $wantdoms, $key) = @_;
local $backup;
local ($mode, $user, $pass, $server, $path, $port) = &parse_backup_url($file);
local $doms;
local @fst = stat($file);
local @ist = stat($file.".info");
local @dst = stat($file.".dom");

# First download the .info file(s) always
local %info;
if ($mode == 3) {
	# For S3, just download the .info backup contents files
	local $s3b = &s3_list_backups($user, $pass, $server, $path);
	return $s3b if (!ref($s3b));
	foreach my $b (keys %$s3b) {
		$info{$b} = $s3b->{$b}->{'features'};
		}
	}
elsif ($mode > 0) {
	# Download info files via SSH or FTP
	local $infotemp = &transname();
	local $infoerr = &download_backup($_[0], $infotemp, undef, undef, 1);
	if (!$infoerr) {
		if (-d $infotemp) {
			# Got a whole dir of .info files
			opendir(INFODIR, $infotemp);
			foreach my $f (readdir(INFODIR)) {
				next if ($f !~ /\.(info|dom)$/);
				local $oneinfo = &unserialise_variable(
					&read_file_contents("$infotemp/$f"));
				foreach my $dname (keys %$oneinfo) {
					$info{$dname} = $oneinfo->{$dname};
					}
				}
			closedir(INFODIR);
			&unlink_file($infotemp);
			}
		else {
			# One file
			local $oneinfo = &unserialise_variable(
					&read_file_contents($infotemp));
			&unlink_file($infotemp);
			%info = %$oneinfo if (%$oneinfo);
			}
		}
	}
elsif (@ist && $ist[9] >= $fst[9]) {
	# Local .info file exists, and is new
	local $oneinfo = &unserialise_variable(
			&read_file_contents($_[0].".info"));
	%info = %$oneinfo if (%$oneinfo);
	}

# If all we want is the .info data and we have it, can return now
if (!$wantdoms && %info) {
	return \%info;
	}

# Try to download .dom files, which contain full domain hashes
local %dom;
if ($mode == 3) {
	# For S3, just download the .dom files
	local $s3b = &s3_list_domains($user, $pass, $server, $path);
	if (ref($s3b)) {
		foreach my $b (keys %$s3b) {
			$dom{$b} = $s3b->{$b};
			}
		}
	}
elsif ($mode > 0) {
	# Download .dom files via SSH or FTP
	local $domtemp = &transname();
	local $domerr = &download_backup($_[0], $domtemp, undef, undef, 2);
	if (!$domerr) {
		if (-d $domtemp) {
			# Got a whole dir of .dom files
			opendir(INFODIR, $domtemp);
			foreach my $f (readdir(INFODIR)) {
				next if ($f !~ /\.dom$/);
				local $onedom = &unserialise_variable(
					&read_file_contents("$domtemp/$f"));
				foreach my $dname (keys %$onedom) {
					$dom{$dname} = $onedom->{$dname};
					}
				}
			closedir(INFODIR);
			&unlink_file($domtemp);
			}
		else {
			# One file
			local $onedom = &unserialise_variable(
					&read_file_contents($domtemp));
			&unlink_file($domtemp);
			%dom = %$onedom if (%$onedom);
			}
		}
	}
elsif (@dst && $dst[9] >= $fst[9]) {
	# Local .dom file exists, and is new
	local $onedom = &unserialise_variable(
			&read_file_contents($_[0].".dom"));
	%dom = %$onedom if (%$onedom);
	}

# If we got the .dom files, can return now
if (%dom && %info && keys(%dom) >= keys(%info)) {
	return $wantdoms ? (\%info, [ values %dom ]) : \%info;
	}

if ($mode > 0) {
	# Need to download the whole file
	$backup = &transname();
	local $derr = &download_backup($_[0], $backup);
	return $derr if ($derr);
	}
else {
	# Use local backup file
	$backup = $_[0];
	}

if (-d $backup) {
	# A directory of backup files, one per domain
	opendir(DIR, $backup);
	local %rv;
	foreach my $f (readdir(DIR)) {
		next if ($f eq "." || $f eq ".." || $f =~ /\.(info|dom)$/);
		local ($cont, $fdoms);
		if ($wantdoms) {
			($cont, $fdoms) = &backup_contents(
						"$backup/$f", 1, $key);
			}
		else {
			$cont = &backup_contents("$backup/$f", 0, $key);
			}
		if (ref($cont)) {
			# Merge in contents of file
			local $d;
			foreach $d (keys %$cont) {
				if ($rv{$d}) {
					return &text('restore_edup', $d);
					}
				else {
					$rv{$d} = $cont->{$d};
					}
				}
			if ($fdoms) {
				$doms ||= [ ];
				push(@$doms, @$fdoms);
				}
			}
		else {
			# Failed to read this file
			return $backup."/".$f." : ".$cont;
			}
		}
	closedir(DIR);
	return $wantdoms ? (\%rv, $doms) : \%rv;
	}
else {
	# A single file
	local $err;
	local $out;
	local $q = quotemeta($backup);
	local $cf = &compression_format($backup, $key);
	local $comp;
	if ($cf == 4) {
		# Special handling for zip
		$out = &backquote_command("unzip -l $q 2>&1");
		}
	else {
		local $catter;
		if ($key) {
			$catter = &backup_decryption_command($key)." ".$q;
			}
		else {
			$catter = "cat $q";
			}
		$comp = $cf == 1 ? "gunzip -c" :
			$cf == 2 ? "uncompress -c" :
			$cf == 3 ? &get_bunzip2_command()." -c" :
				   "cat";
		$out = &backquote_command(
			"($catter | $comp | ".
			&make_tar_command("tf", "-").") 2>&1");
		}
	if ($?) {
		return $text{'restore_etar'};
		}

	# Look for a home-format backup first
	local ($l, %rv, %done, $dotbackup, @virtfiles);
	foreach $l (split(/\n/, $out)) {
		if ($l =~ /(^|\s)(.\/)?.backup\/([^_ ]+)_([a-z0-9\-]+)$/) {
			# Found a .backup/domain_feature file
			push(@{$rv{$3}}, $4) if (!$done{$3,$4}++);
			push(@{$rv{$3}}, "dir") if (!$done{$3,"dir"}++);
			if ($4 eq 'virtualmin') {
				push(@virtfiles, $l);
				}
			$dotbackup = 1;
			}
		}
	if (!$dotbackup) {
		# Look for an old-format backup
		foreach $l (split(/\n/, $out)) {
			if ($l =~ /(^|\s)(.\/)?([^_ ]+)_([a-z0-9\-]+)$/) {
				# Found a domain_feature file
				push(@{$rv{$3}}, $4) if (!$done{$3,$4}++);
				if ($4 eq 'virtualmin') {
					push(@virtfiles, $l);
					}
				}
			}
		}

	# Extract and read domain files
	if ($wantdoms) {
		local $vftemp = &transname();
		&make_dir($vftemp, 0711);
		local $qvirtfiles = join(" ", map { quotemeta($_) } @virtfiles);
		if ($cf == 4) {
			$out = &backquote_command("cd $vftemp && ".
				"unzip $q $qvirtfiles 2>&1");
			}
		else {
			$out = &backquote_command(
			    "cd $vftemp && ".
			    "($comp $q | ".
			    &make_tar_command("xvf", "-", $qvirtfiles).
			    ") 2>&1");
			}
		if (!$?) {
			$doms = [ ];
			foreach my $f (@virtfiles) {
				local %d;
				&read_file("$vftemp/$f", \%d);
				push(@$doms, \%d);
				}
			}
		}

	return $wantdoms ? (\%rv, $doms) : \%rv;
	}
}

# missing_restore_features(&contents, [&domains])
# Returns a list of features that are in a backup, but not supported on
# this system.
sub missing_restore_features
{
local ($cont, $doms) = @_;

# Work out all features in the backup
local @allfeatures;
foreach my $dname (keys %$cont) {
	if ($dname ne "virtualmin") {
		push(@allfeatures, @{$cont->{$dname}});
		}
	}
if ($doms) {
	foreach my $d (@$doms) {
		foreach my $f (@features, @plugins) {
			# Look for known features and plugins
			push(@allfeatures, $f) if ($d->{$f});
			}
		foreach my $k (keys %$d) {
			# Look for plugins not on this system
			push(@allfeatures, $k)
				if ($d->{$k} &&
				    $k =~ /^virtualmin-([a-z0-9\-\_]+)$/ &&
				    $k !~ /limit$/);
			}
		}
	}
@allfeatures = &unique(@allfeatures);

local @rv;
foreach my $f (@allfeatures) {
	next if ($f eq 'virtualmin');
	if (&indexof($f, @features) >= 0) {
		if (!$config{$f}) {
			# Missing feature
			push(@rv, { 'feature' => $f,
				    'desc' => $text{'feature_'.$f} });
			}
		}
	elsif (&indexof($f, @plugins) < 0) {
		# Assume missing plugin
		local $desc = "Plugin $f";
		if (&foreign_check($f)) {
			# Plugin exists, but isn't enabled
			eval {
				local $main::error_must_die = 1;
				&foreign_require($f, "virtual_feature.pl");
				$desc = &plugin_call($f, "feature_name");
				};
			}
		local $critical = $f eq "virtualmin-google-analytics" ? 1 : 0;
		push(@rv, { 'feature' => $f,
			    'plugin' => 1,
			    'critical' => $critical,
			    'desc' => $desc });
		}
	}

# Check if any domains use IPv6, but this system doesn't support it
if ($doms && !&supports_ip6()) {
	foreach my $d (@$doms) {
		if ($d->{'virt6'}) {
			push(@rv, { 'feature' => 'virt6',
				    'critical' => 1,
				    'desc' => $text{'restore_evirt6'} });
			last;
			}
		}
	}

return @rv;
}

# download_backup(url, tempfile, [&domain-names], [&config-features],
#                 [info-files-only])
# Downloads a backup file or directory to a local temp file or directory.
# Returns undef on success, or an error message.
sub download_backup
{
local ($url, $temp, $domnames, $vbs, $infoonly) = @_;
local $cache = $main::download_backup_cache{$url};
if ($cache && -r $cache && !$infoonly) {
	# Already got the file .. no need to re-download
	link($cache, $temp) || symlink($cache, $temp);
	return undef;
	}
local ($mode, $user, $pass, $server, $path, $port) = &parse_backup_url($url);
local $sfx = $infoonly == 1 ? ".info" : $infoonly == 2 ? ".dom" : "";
if ($mode == 1) {
	# Download from FTP server
	local $cwderr;
	local $isdir = &ftp_onecommand($server, "CWD $path", \$cwderr,
				       $user, $pass, $port);
	local $err;
	if ($isdir) {
		# Need to download entire directory.
		# In info-only mode, skip files that don't end with .info / .dom
		&make_dir($temp, 0711);
		local $list = &ftp_listdir($server, $path, \$err, $user, $pass,
					   $port);
		return $err if (!$list);
		foreach $f (@$list) {
			$f =~ s/^$path[\\\/]//;
			next if ($f eq "." || $f eq ".." || $f eq "");
			next if ($infoonly && $f !~ /\Q$sfx\E$/);
			if (@$domnames && $f =~ /^(\S+)\.(tar.*|zip)$/i &&
			    $f !~ /^virtualmin\.(tar.*|zip)$/i) {
				# Make sure file is for a domain we want
				next if (&indexof($1, @$domnames) < 0);
				}
			&ftp_download($server, "$path/$f", "$temp/$f", \$err,
				      undef, $user, $pass, $port, 1);
			return $err if ($err);
			}
		}
	else {
		# Can just download a single file.
		# In info-only mode, just get the .info and .dom files.
		&ftp_download($server, $path.$sfx,
			      $temp, \$err, undef, $user, $pass, $port, 1);
		return $err if ($err);
		}
	}
elsif ($mode == 2) {
	# Download from SSH server
	local $qserver = &check_ip6address($server) ? "[$server]" : $server;
	if ($infoonly) {
		# First try file with .info or .dom extension
		&scp_copy(($user ? "$user\@" : "")."$qserver:$path".$sfx,
			  $temp, $pass, \$err, $port);
		if ($err) {
			# Fall back to .info or .dom files in directory
			&make_dir($temp, 0700);
			&scp_copy(($user ? "$user\@" : "").
				  $qserver.":".$path."/*".$sfx,
				  $temp, $pass, \$err, $port);
			$err = undef;
			}
		}
	else {
		# If a list of domain names was given, first try to scp down
		# only the files for those domains in the directory
		local $gotfiles = 0;
		if (@$domnames) {
			&unlink_file($temp);
			&make_dir($temp, 0711);
			local $domfiles = "{".join(",", @$domnames,
							"virtualmin")."}";
			&scp_copy(($user ? "$user\@" : "").
				  "$qserver:$path/$domfiles.*",
				  $temp, $pass, \$err, $port);
			$gotfiles = 1 if (!$err);
			$err = undef;
			}

		if (!$gotfiles) {
			# Download the whole file or directory
			&unlink_file($temp);	# Must remove so that recursive
						# scp doesn't copy into it
			&scp_copy(($user ? "$user\@" : "")."$qserver:$path",
				  $temp, $pass, \$err, $port);
			}
		}
	return $err if ($err);
	}
elsif ($mode == 3) {
	# Download from S3 server
	$infoonly && return "Info-only mode is not supported by the ".
			    "download_backup function for S3";
	local $s3b = &s3_list_backups($user, $pass, $server, $path);
	return $s3b if (!ref($s3b));
	local @wantdoms;
	push(@wantdoms, @$domnames) if (@$domnames);
	push(@wantdoms, "virtualmin") if (@$vbs);
	@wantdoms = (keys %$s3b) if (!@wantdoms);
	&make_dir($temp, 0711);
	foreach my $dname (@wantdoms) {
		local $si = $s3b->{$dname};
		if (!$si) {
			return &text('restore_es3info', $dname);
			}
		local $tempfile = $si->{'file'};
		$tempfile =~ s/^(\S+)\///;
		local $err = &s3_download($user, $pass, $server,
					  $si->{'file'}, "$temp/$tempfile");
		return $err if ($err);
		}
	}
elsif ($mode == 6) {
	# Download from Rackspace cloud files
	local $rsh = &rs_connect($config{'rs_endpoint'}, $user, $pass);
	if (!ref($rsh)) {
		return $rsh;
		}
	local $files = &rs_list_objects($rsh, $server);
	return "Failed to list $server : $files" if (!ref($files));
	local $pathslash = $path ? $path."/" : "";
	if ($infoonly) {
		# First try file with .info or .dom extension
		$err = &rs_download_object($rsh, $server, $path.$sfx, $temp);
		if ($err) {
			# Doesn't exist .. but maybe path is a sub-directory
			# full of .info and .dom files?
			&make_dir($temp, 0700);
			foreach my $f (@$files) {
				if ($f =~ /\Q$sfx\E$/ &&
				    $f =~ /^\Q$pathslash\E([^\/]*)$/) {
					my $fname = $1;
					&rs_download_object($rsh, $server, $f,
						$temp."/".$fname);
					}
				}
			}
		}
	else {
		# If a list of domain names was given, first try to download
		# only the files for those domains in the directory
		local $gotfiles = 0;
		if (@$domnames) {
                        &unlink_file($temp);
                        &make_dir($temp, 0711);
			foreach my $f (@$files) {
				my $want = 0;
				my $fname;
				if ($f =~ /^\Q$pathslash\E([^\/]*)$/) {
					$fname = $1;
					foreach my $d (@$domnames) {
						$want++ if ($fname =~
							    /^\Q$d\E\./);
						}
					}
				if ($want) {
					$err = &rs_download_object(
						$rsh, $server, $f,
						$temp."/".$fname);
					$gotfiles++ if (!$err);
					}
				else {
					$err = undef;
					}
				}
			}
		if (!$gotfiles && $path && &indexof($path, @$files) >= 0) {
			# Download the file
			&unlink_file($temp);
			$err = &rs_download_object(
				$rsh, $server, $path, $temp);
			}
		elsif (!$gotfiles) {
			# Download the directory
			&unlink_file($temp);
                        &make_dir($temp, 0711);
			foreach my $f (@$files) {
				if ($f =~ /^\Q$pathslash\E([^\/]*)$/) {
					my $fname = $1;
					$err = &rs_download_object(
						$rsh, $server, $f,
						$temp."/".$fname);
					}
				}
			}
		return $err if ($err);
		}
	}
$main::download_backup_cache{$url} = $temp if (!$infoonly);
return undef;
}

# backup_strftime(path)
# Replaces stftime-style % codes in a path with the current time
sub backup_strftime
{
local ($dest) = @_;
eval "use POSIX";
eval "use posix" if ($@);
local @tm = localtime(time());
&clear_time_locale() if (defined(&clear_time_locale));
local $rv;
if ($dest =~ /^(.*)\@([^\@]+)$/) {
	# Only modify hostname and path part
	$rv = $1."\@".strftime($2, @tm);
	}
else {
	# Fix up whole dest
	$rv = strftime($dest, @tm);
	}
&reset_time_locale() if (defined(&reset_time_locale));
return $rv;
}

# parse_backup_url(string)
# Converts a URL like ftp:// or a filename into its components. These will be
# protocol (1 for FTP, 2 for SSH, 0 for local, 3 for S3, 4 for download,
# 5 for upload, 6 for rackspace), login, password, host, path and port
sub parse_backup_url
{
local @rv;
if ($_[0] =~ /^ftp:\/\/([^:]*):(.*)\@\[([^\]]+)\](:\d+)?:?(\/.*)$/ ||
    $_[0] =~ /^ftp:\/\/([^:]*):(.*)\@\[([^\]]+)\](:\d+)?:(.+)$/ ||
    $_[0] =~ /^ftp:\/\/([^:]*):(.*)\@([^\/:\@]+)(:\d+)?:?(\/.*)$/ ||
    $_[0] =~ /^ftp:\/\/([^:]*):(.*)\@([^\/:\@]+)(:\d+)?:(.+)$/) {
	# FTP URL
	@rv = (1, $1, $2, $3, $5, $4 ? substr($4, 1) : 21);
	}
elsif ($_[0] =~ /^ssh:\/\/([^:]*):(.*)\@\[([^\]]+)\](:\d+)?:?(\/.*)$/ ||
       $_[0] =~ /^ssh:\/\/([^:]*):(.*)\@\[([^\]]+)\](:\d+)?:(.+)$/ ||
       $_[0] =~ /^ssh:\/\/([^:]*):(.*)\@([^\/:\@]+)(:\d+)?:?(\/.*)$/ ||
       $_[0] =~ /^ssh:\/\/([^:]*):(.*)\@([^\/:\@]+)(:\d+)?:(.+)$/) {
	# SSH url with no @ in password
	@rv = (2, $1, $2, $3, $5, $4 ? substr($4, 1) : 22);
	}
elsif ($_[0] =~ /^s3:\/\/([^:]*):([^\@]*)\@([^\/]+)(\/(.*))?$/) {
	# S3 with regular redundancy
	@rv = (3, $1, $2, $3, $5, 0);
	}
elsif ($_[0] =~ /^s3rrs:\/\/([^:]*):([^\@]*)\@([^\/]+)(\/(.*))?$/) {
	# S3 with less redundancy
	@rv = (3, $1, $2, $3, $5, 1);
	}
elsif ($_[0] =~ /^rs:\/\/([^:]*):([^\@]*)\@([^\/]+)(\/(.*))?$/) {
	# Rackspace cloud files
	@rv = (6, $1, $2, $3, $5, 0);
	}
elsif ($_[0] eq "download:") {
	return (4, undef, undef, undef, undef, undef);
	}
elsif ($_[0] eq "upload:") {
	return (5, undef, undef, undef, undef, undef);
	}
elsif (!$_[0] || $_[0] =~ /^\//) {
	# Absolute path
	@rv = (0, undef, undef, undef, $_[0], undef);
	$rv[4] =~ s/\/+$//;	# No need for trailing /
	}
else {
	# Relative to current dir
	local $pwd = &get_current_dir();
	@rv = (0, undef, undef, undef, $pwd."/".$_[0], undef);
	$rv[4] =~ s/\/+$//;
	}
return @rv;
}

# nice_backup_url(string, [caps-first])
# Converts a backup URL to a nice human-readable format
sub nice_backup_url
{
local ($url, $caps) = @_;
local ($proto, $user, $pass, $host, $path, $port) = &parse_backup_url($url);
local $rv;
if ($proto == 1) {
	$rv = &text('backup_niceftp', "<tt>$path</tt>", "<tt>$host</tt>");
	}
elsif ($proto == 2) {
	$rv = &text('backup_nicescp', "<tt>$path</tt>", "<tt>$host</tt>");
	}
elsif ($proto == 3) {
	$rv = $path ?
		&text('backup_nices3p', "<tt>$host</tt>", "<tt>$path</tt>") :
		&text('backup_nices3', "<tt>$host</tt>");
	}
elsif ($proto == 0) {
	$rv = &text('backup_nicefile', "<tt>$path</tt>");
	}
elsif ($proto == 4) {
	$rv = $text{'backup_nicedownload'};
	}
elsif ($proto == 5) {
	$rv = $text{'backup_niceupload'};
	}
elsif ($proto == 6) {
	$rv = $path ?
		&text('backup_nicersp', "<tt>$host</tt>", "<tt>$path</tt>") :
		&text('backup_nicers', "<tt>$host</tt>");
	}
else {
	$rv = $url;
	}
if ($caps && !$current_lang_info->{'charset'} && $rv ne $url) {
	# Make first letter upper case
	$rv = ucfirst($rv);
	}
return $rv;
}

# show_backup_destination(name, value, no-local, [&domain], [no-download],
#			  [no-upload])
# Returns HTML for fields for selecting a local or FTP file
sub show_backup_destination
{
local ($name, $value, $nolocal, $d, $nodownload, $noupload) = @_;
local ($mode, $user, $pass, $server, $path, $port) = &parse_backup_url($value);
$mode = 1 if (!$value && $nolocal);	# Default to FTP
local $defport = $mode == 1 ? 21 : $mode == 2 ? 22 : undef;
$server = "[$server]" if (&check_ip6address($server));
local $serverport = $port && $port != $defport ? "$server:$port" : $server;
local $rv;

local @opts;
if ($d && $d->{'dir'}) {
	# Limit local file to under virtualmin-backups
	push(@opts, [ 0, $text{'backup_mode0a'},
	       &ui_textbox($name."_file",
		  $mode == 0 && $path =~ /virtualmin-backup\/(.*)$/ ? $1 : "",
		  50)."<br>\n" ]);
	}
elsif (!$nolocal) {
	# Local file field (can be anywhere)
	push(@opts, [ 0, $text{'backup_mode0'},
	       &ui_textbox($name."_file", $mode == 0 ? $path : "", 50)." ".
	       &file_chooser_button($name."_file")."<br>\n" ]);
	}

# FTP file fields
local $noac = "autocomplete=off";
local $ft = "<table>\n";
$ft .= "<tr> <td>$text{'backup_ftpserver'}</td> <td>".
       &ui_textbox($name."_server", $mode == 1 ? $serverport : undef, 20).
       "</td> </tr>\n";
$ft .= "<tr> <td>$text{'backup_path'}</td> <td>".
       &ui_textbox($name."_path", $mode == 1 ? $path : undef, 50).
       "</td> </tr>\n";
$ft .= "<tr> <td>$text{'backup_login'}</td> <td>".
       &ui_textbox($name."_user", $mode == 1 ? $user : undef, 15,
		   0, undef, $noac).
       "</td> </tr>\n";
$ft .= "<tr> <td>$text{'backup_pass'}</td> <td>".
       &ui_password($name."_pass", $mode == 1 ? $pass : undef, 15,
		   0, undef, $noac).
       "</td> </tr>\n";
$ft .= "</table>\n";
push(@opts, [ 1, $text{'backup_mode1'}, $ft ]);

# SCP file fields
local $st = "<table>\n";
$st .= "<tr> <td>$text{'backup_sshserver'}</td> <td>".
       &ui_textbox($name."_sserver", $mode == 2 ? $serverport : undef, 20).
       "</td> </tr>\n";
$st .= "<tr> <td>$text{'backup_path'}</td> <td>".
       &ui_textbox($name."_spath", $mode == 2 ? $path : undef, 50).
       "</td> </tr>\n";
$st .= "<tr> <td>$text{'backup_login'}</td> <td>".
       &ui_textbox($name."_suser", $mode == 2 ? $user : undef, 15,
		   0, undef, $noac).
       "</td> </tr>\n";
$st .= "<tr> <td>$text{'backup_pass'}</td> <td>".
       &ui_password($name."_spass", $mode == 2 ? $pass : undef, 15,
		   0, undef, $noac).
       "</td> </tr>\n";
$st .= "</table>\n";
push(@opts, [ 2, $text{'backup_mode2'}, $st ]);

# S3 backup fields (bucket, access key ID, secret key and file)
local $s3user = $mode == 3 ? $user : undef;
local $s3pass = $mode == 3 ? $pass : undef;
if (&master_admin()) {
	$s3user ||= $config{'s3_akey'};
	$s3pass ||= $config{'s3_skey'};
	}
local $st = "<table>\n";
$st .= "<tr> <td>$text{'backup_akey'}</td> <td>".
       &ui_textbox($name."_akey", $s3user, 40, 0, undef, $noac).
       "</td> </tr>\n";
$st .= "<tr> <td>$text{'backup_skey'}</td> <td>".
       &ui_password($name."_skey", $s3pass, 40, 0, undef, $noac).
       "</td> </tr>\n";
$st .= "<tr> <td>$text{'backup_s3path'}</td> <td>".
       &ui_textbox($name."_s3path", $mode != 3 ? "" :
				    $server.($path ? "/".$path : ""), 50).
       "</td> </tr>\n";
$st .= "<tr> <td></td> <td>".
       &ui_checkbox($name."_rrs", 1, $text{'backup_s3rrs'}, $port == 1).
       "</td> </tr>\n";
$st .= "</table>\n";
push(@opts, [ 3, $text{'backup_mode3'}, $st ]);

# Rackspace backup fields (username, API key and bucket/file)
local $rsuser = $mode == 6 ? $user : undef;
local $rspass = $mode == 6 ? $pass : undef;
if (&master_admin()) {
	$rsuser ||= $config{'rs_user'};
	$rspass ||= $config{'rs_key'};
	}
local $st = "<table>\n";
$st .= "<tr> <td>$text{'backup_rsuser'}</td> <td>".
       &ui_textbox($name."_rsuser", $rsuser, 40, 0, undef, $noac).
       "</td> </tr>\n";
$st .= "<tr> <td>$text{'backup_rskey'}</td> <td>".
       &ui_password($name."_rskey", $rspass, 40, 0, undef, $noac).
       "</td> </tr>\n";
$st .= "<tr> <td>$text{'backup_rspath'}</td> <td>".
       &ui_textbox($name."_rspath", $mode != 6 ? undef :
				    $server.($path ? "/".$path : ""), 50).
       "</td> </tr>\n";
$st .= "</table>\n";
$st .= "<a href='http://affiliates.rackspacecloud.com/idevaffiliate.php?id=3533&url=105' target=_blank>$text{'backup_rssignup'}</a>\n";
push(@opts, [ 6, $text{'backup_mode6'}, $st ]);

if (!$nodownload) {
	# Show mode to download in browser
	push(@opts, [ 4, $text{'backup_mode4'},
		      $text{'backup_mode4desc'}."<p>" ]);
	}

if (!$noupload) {
	# Show mode to upload to server
	push(@opts, [ 5, $text{'backup_mode5'},
		      &ui_upload($name."_upload", 40) ]);
	}

return &ui_radio_selector(\@opts, $name."_mode", $mode);
return &ui_table_start(undef, 2).
       &ui_table_row(undef, 
	&ui_radio_selector(\@opts, $name."_mode", $mode), 2).
       &ui_table_end();
}

# parse_backup_destination(name, &in, no-local, [&domain])
# Returns a backup destination string, or calls error
sub parse_backup_destination
{
local ($name, $in, $nolocal, $d) = @_;
local %in = %$in;
local $mode = $in{$name."_mode"};
if ($mode == 0 && $d) {
	# Local file under virtualmin-backup directory
	$in{$name."_file"} =~ /^\S+$/ || &error($text{'backup_edest2'});
	$in{$name."_file"} =~ /\.\./ && &error($text{'backup_edest3'});
	$in{$name."_file"} =~ s/\/+$//;
	return "$d->{'home'}/virtualmin-backup/".$in{$name."_file"};
	}
elsif ($mode == 0 && !$nolocal) {
	# Any local file
	$in{$name."_file"} =~ /^\/\S/ || &error($text{'backup_edest'});
	$in{$name."_file"} =~ s/\/+$//;	# No need for trailing /
	return $in{$name."_file"};
	}
elsif ($mode == 1) {
	# FTP server
	local ($server, $port);
	if ($in{$name."_server"} =~ /^\[([^\]]+)\](:(\d+))?$/) {
		($server, $port) = ($1, $3);
		}
	elsif ($in{$name."_server"} =~ /^([A-Za-z0-9\.\-\_]+)(:(\d+))?$/) {
		($server, $port) = ($1, $3);
		}
	else {
		&error($text{'backup_eserver1'});
		}
	&to_ipaddress($server) ||
	    defined(&to_ip6address) && &to_ip6address($server) ||
		&error($text{'backup_eserver1a'});
	$port =~ /^\d*$/ || &error($text{'backup_eport'});
	$in{$name."_path"} =~ /\S/ || &error($text{'backup_epath'});
	$in{$name."_user"} =~ /^[^:\/]*$/ || &error($text{'backup_euser'});
	if ($in{$name."_path"} ne "/") {
		# Strip trailing /
		$in{$name."_path"} =~ s/\/+$//;
		}
	local $sep = $in{$name."_path"} =~ /^\// ? "" : ":";
	return "ftp://".$in{$name."_user"}.":".$in{$name."_pass"}."\@".
	       $in{$name."_server"}.$sep.$in{$name."_path"};
	}
elsif ($mode == 2) {
	# SSH server
	local ($server, $port);
	if ($in{$name."_sserver"} =~ /^\[([^\]]+)\](:(\d+))?$/) {
		($server, $port) = ($1, $3);
		}
	elsif ($in{$name."_sserver"} =~ /^([A-Za-z0-9\.\-\_]+)(:(\d+))?$/) {
		($server, $port) = ($1, $3);
		}
	else {
		&error($text{'backup_eserver2'});
		}
	&to_ipaddress($server) ||
	    defined(&to_ip6address) && &to_ip6address($server) ||
		&error($text{'backup_eserver2a'});
	$port =~ /^\d*$/ || &error($text{'backup_eport'});
	$in{$name."_spath"} =~ /\S/ || &error($text{'backup_epath'});
	$in{$name."_suser"} =~ /^[^:\/]*$/ || &error($text{'backup_euser2'});
	if ($in{$name."_spath"} ne "/") {
		# Strip trailing /
		$in{$name."_spath"} =~ s/\/+$//;
		}
	return "ssh://".$in{$name."_suser"}.":".$in{$name."_spass"}."\@".
	       $in{$name."_sserver"}.":".$in{$name."_spath"};
	}
elsif ($mode == 3) {
	# Amazon S3 service
	local $cerr = &check_s3();
	$cerr && &error($cerr);
	$in{$name.'_s3path'} =~ /^\S+$/ || &error($text{'backup_es3path'});
	$in{$name.'_s3path'} =~ /\\/ && &error($text{'backup_es3pathslash'});
	($in{$name.'_s3path'} =~ /^\// || $in{$name.'_s3path'} =~ /\/$/) &&
		&error($text{'backup_es3path2'});
	$in{$name.'_akey'} =~ /^\S+$/i || &error($text{'backup_eakey'});
	$in{$name.'_skey'} =~ /^\S+$/i || &error($text{'backup_eskey'});
	local $proto = $in{$name.'_rrs'} ? 's3rrs' : 's3';
	return $proto."://".$in{$name.'_akey'}.":".$in{$name.'_skey'}."\@".
	       $in{$name.'_s3path'};
	}
elsif ($mode == 4) {
	# Just download
	return "download:";
	}
elsif ($mode == 5) {
	# Uploaded file
	$in{$name."_upload"} || &error($text{'backup_eupload'});
	return "upload:";
	}
elsif ($mode == 6) {
	# Rackspace cloud files
	$in{$name.'_rsuser'} =~ /^\S+$/i || &error($text{'backup_ersuser'});
	$in{$name.'_rskey'} =~ /^\S+$/i || &error($text{'backup_erskey'});
	$in{$name.'_rspath'} =~ /^\S+$/i || &error($text{'backup_erspath'});
	($in{$name.'_rspath'} =~ /^\// || $in{$name.'_rspath'} =~ /\/$/) &&
		&error($text{'backup_erspath2'});
	return "rs://".$in{$name.'_rsuser'}.":".$in{$name.'_rskey'}."\@".
	       $in{$name.'_rspath'};
	}
else {
	&error($text{'backup_emode'});
	}
}

# can_backup_sched([&sched])
# Returns 1 if the current user can create scheduled backups, or edit some
# existing schedule. If sched is set, checks if the user is allowed to create
# schedules at all.
sub can_backup_sched
{
local ($sched) = @_;
if (&master_admin()) {
	# Master admin can do anything
	return 1;
	}
elsif (&reseller_admin()) {
	# Resellers can edit schedules for their domains' users
	return 0 if ($access{'backups'} != 2);
	if ($sched) {
		return 0 if (!$sched->{'owner'});       # Master admin's backup
		return 1 if ($sched->{'owner'} eq $base_remote_user);
		foreach my $d (&get_domain_by("reseller", $base_remote_user)) {
			return 1 if ($d->{'id'} eq $sched->{'owner'});
			}
		return 0;
		}
	return 1;
	}
else {
	# Regular users can only edit their own schedules
	return 0 if (!$access{'edit_sched'});
	if ($sched) {
		return 0 if (!$sched->{'owner'});	# Master admin's backup
		local $myd = &get_domain_by_user($base_remote_user);
		return 0 if (!$myd || $myd->{'id'} ne $sched->{'owner'});
		}
	return 1;
	}
}

# Returns 1 if the current user can define pre and post-backup commands
sub can_backup_commands
{
return &master_admin();
}

# Returns 1 if the configured backup format supports incremental backups
sub has_incremental_format
{
return $config{'compression'} != 3;
}

# Returns 1 if tar supports incremental backups
sub has_incremental_tar
{
return 0 if ($config{'tar_args'} =~ /--acls/);
my $tar = &get_tar_command();
my $out = &backquote_command("$tar --help 2>&1 </dev/null");
return $out =~ /--listed-incremental/;
}

# get_tar_command()
# Returns the full path to the tar command, which may be 'gtar' on BSD
sub get_tar_command
{
my @cmds;
if ($config{'tar_cmd'}) {
	@cmds = ( $config{'tar_cmd'} );
	}
else {
	@cmds = ( "tar" );
	if ($gconfig{'os_type'} eq 'freebsd' ||
	    $gconfig{'os_type'} eq 'netbsd' ||
	    $gconfig{'os_type'} eq 'openbsd' ||
	    $gconfig{'os_type'} eq 'solaris') {
		unshift(@cmds, "gtar");
		}
	else {
		push(@cmds, "gtar");
		}
	}
foreach my $c (@cmds) {
	my ($bin, @args) = split(/\s+/, $c);
	my $p = &has_command($bin);
	return join(" ", $p, @args) if ($p);
	}
return undef;
}

# make_tar_command(flags, output, file, ...)
# Returns a tar command using the given flags writing to the given output
sub make_tar_command
{
my ($flags, $output, @files) = @_;
my $cmd = &get_tar_command();
if ($config{'tar_args'}) {
	$cmd .= " ".$config{'tar_args'};
	$flags = "-".$flags;
	if ($flags =~ s/X//) {
		# In -flag mode, need to move -X after the output name and
		# before the exclude filename.
		unshift(@files, "-X");
		}
	}
$cmd .= " ".$flags;
$cmd .= " ".$output;
$cmd .= " ".join(" ", @files) if (@files);
return $cmd;
}

# get_bzip2_command()
# Returns the full path to the bzip2-compatible command
sub get_bzip2_command
{
return &has_command($config{'pbzip2'} ? 'pbzip2' : 'bzip2');
}

# get_bunzip2_command()
# Returns the full path to the bunzip2-compatible command
sub get_bunzip2_command
{
if (!$config{'pbzip2'}) {
	return &has_command('bunzip2');
	}
elsif (&has_command('pbunzip2')) {
	return &has_command('pbunzip2');
	}
else {
	# Fall back to using -d option
	return &has_command('pbzip2').' -d';
	}
}

# get_backup_actions()
# Returns a list of arrays for backup / restore actions that the current
# user is allowed to do. The first is links, the second titles, the third
# long descriptions, the fourth is codes.
sub get_backup_actions
{
local (@links, @titles, @descs, @codes);
if (&can_backup_domain()) {
	if (&can_backup_sched()) {
		# Can do scheduled backups, so show list
		push(@links, "list_sched.cgi");
		push(@titles, $text{'index_scheds'});
		push(@descs, $text{'index_schedsdesc'});
		push(@codes, 'sched');
		}
	# Can do immediate
	push(@links, "backup_form.cgi");
	push(@titles, $text{'index_backup'});
	push(@descs, $text{'index_backupdesc'});
	push(@codes, 'backup');
	}
if (&can_backup_log()) {
	# Show logged backups
	push(@links, "backuplog.cgi");
	push(@titles, $text{'index_backuplog'});
	push(@descs, $text{'index_backuplogdesc'});
	push(@codes, 'backuplog');
	}
if (&can_restore_domain()) {
	# Show restore form
	push(@links, "restore_form.cgi");
	push(@titles, $text{'index_restore'});
	push(@descs, $text{'index_restoredesc'});
	push(@codes, 'restore');
	}
if (&can_backup_keys()) {
	# Show list of backup keys
	push(@links, "list_bkeys.cgi");
	push(@titles, $text{'index_bkeys'});
	push(@descs, $text{'index_bkeysdesc'});
	push(@codes, 'bkeys');
	}
return (\@links, \@titles, \@descs, \@codes);
}

# Returns 1 if the user can backup and restore all domains
# Deprecated, but kept for old theme users
sub can_backup_domains
{
return &master_admin();
}

# Returns 1 if the user can backup and restore core Virtualmin settings, like
# the config, resellers and so on
sub can_backup_virtualmin
{
return &master_admin();
}

# can_backup_domain([&domain])
# Returns 0 if no backups are allowed, 1 if they are, 2 if only backups to
# remote or a file under the domain are allowed, 3 if only remote is allowed.
# If a domain is given, checks if backups of that domain are allowed.
sub can_backup_domain
{
local ($d) = @_;
if (&master_admin()) {
	# Master admin can do anything
	return 1;
	}
elsif (&reseller_admin()) {
	# Resellers can only backup their domains, to remote
	return 0 if (!$access{'backups'});
	if ($d) {
		return 0 if (!&can_edit_domain($d));
		}
	return 3;
	}
else {
	# Domain owners can only backup to their dir, or remote
	return 0 if (!$access{'edit_backup'});
	if ($d) {
		return 0 if (!&can_edit_domain($d));
		}
	return 2;
	}
}

# can_restore_domain([&domain])
# Returns 1 if the user is allowed to perform full restores, 2 if only
# dir/mysql restores are allowed, 0 if nothing
sub can_restore_domain
{
local ($d) = @_;
if (&master_admin()) {
	# Master admin always can
	return 1;
	}
else {
	if (&reseller_admin()) {
		# Resellers can do limited restores
		return 2;
		}
	else {
		# Domain owners can only restore if allowed
		return 0 if (!$access{'edit_restore'});
		}
	if ($d) {
		return &can_edit_domain($d) ? 2 : 0;
		}
	return 2;
	}
}

# can_backup_log([&log])
# Returns 1 if the current user can view backup logs, and if given a specific
# log entry
sub can_backup_log
{
local ($log) = @_;
return 1 if (&master_admin());
return 0 if (!&can_backup_domain());
if ($log) {
	# Only allow non-admins to view their own logs
	local @dnames = &backup_log_own_domains($log);
	return @dnames ? 1 : 0;
	}
return 1;
}

# can_backup_keys()
# Returns 1 if the current user can access all backup keys, 2 if only his own,
# 0 if neither
sub can_backup_keys
{
return 0 if (!$virtualmin_pro);		# Pro only feature
return 0 if ($access{'admin'});		# Not for extra admins
return 1 if (&master_admin());		# Master admin can access all keys
return 2;			# Domain owner / reseller can access his own
}

# backup_log_own_domains(&log, [error-domains-only])
# Given a backup log object, return the domain names that the current user
# can restore
sub backup_log_own_domains
{
local ($log, $errormode) = @_;
local @dnames = split(/\s+/, $errormode ? $log->{'errdoms'} : $log->{'doms'});
return @dnames if (&master_admin() || $log->{'user'} eq $remote_user);
if ($config{'own_restore'}) {
	local @rv;
	foreach my $d (&get_domains_by_names(@dnames)) {
		push(@rv, $d->{'dom'}) if (&can_edit_domain($d));
		}
	return @rv;
	}
return ( );
}

# extract_purge_path(dest)
# Given a backup URL with a path like /backup/%d-%m-%Y, return the base
# directory (like /backup) and the regexp matching the date-based filename
# (like .*-.*-.*)
sub extract_purge_path
{
local ($dest) = @_;
local ($mode, undef, undef, $host, $path) = &parse_backup_url($dest);
if (($mode == 0 || $mode == 1 || $mode == 2) &&
    $path =~ /^(\S+)\/([^%]*%.*)$/) {
	# Local, FTP or SSH file like /backup/%d-%m-%Y
	local ($base, $date) = ($1, $2);
	$date =~ s/%[_\-0\^\#]*\d*[A-Za-z]/\.\*/g;
	return ($base, $date);
	}
elsif (($mode == 1 || $mode == 2) &&
       $path =~ /^([^%\/]+%.*)$/) {
	# FTP or SSH file like backup-%d-%m-%Y
	local ($base, $date) = ("", $1);
	$date =~ s/%[_\-0\^\#]*\d*[A-Za-z]/\.\*/g;
	return ($base, $date);
	}
elsif (($mode == 3 || $mode == 6) && $host =~ /%/) {
	# S3 / Rackspace bucket which is date-based
	$host =~ s/%[_\-0\^\#]*\d*[A-Za-z]/\.\*/g;
	return (undef, $host);
	}
elsif (($mode == 3 || $mode == 6) && $path =~ /%/) {
	# S3 / Rackspace filename which is date-based
	$path =~ s/%[_\-0\^\#]*\d*[A-Za-z]/\.\*/g;
	return ($host, $path);
	}
return ( );
}

# purge_domain_backups(dest, days, [time-now])
# Searches a backup destination for backup files or directories older than
# same number of days, and deletes them. May print stuff using first_print.
sub purge_domain_backups
{
local ($dest, $days, $start) = @_;
&$first_print(&text('backup_purging2', $days, &nice_backup_url($dest)));
local ($mode, $user, $pass, $host, $path, $port) = &parse_backup_url($dest);
local ($base, $re) = &extract_purge_path($dest);
if (!$base && !$re) {
	&$second_print($text{'backup_purgenobase'});
	return 0;
	}

&$indent_print();
$start ||= time();
local $cutoff = $start - $days*24*60*60;
local $pcount = 0;
local $ok = 1;

if ($mode == 0) {
	# Just search a local directory for matching files, and remove them
	opendir(PURGEDIR, $base);
	foreach my $f (readdir(PURGEDIR)) {
		local $path = "$base/$f";
		local @st = stat($path);
		if ($f ne "." && $f ne ".." && $f =~ /^$re$/ &&
		    $st[9] < $cutoff && $f !~ /\.(dom|info)$/) {
			# Found one to delete
			local $old = int((time() - $st[9]) / (24*60*60));
			&$first_print(&text(-d $path ? 'backup_deletingdir'
					             : 'backup_deletingfile',
				            "<tt>$path</tt>", $old));
			local $sz = &nice_size(&disk_usage_kb($path)*1024);
			&unlink_file($path.".info") if (!-d $path);
			&unlink_file($path.".dom") if (!-d $path);
			&unlink_file($path);
			&$second_print(&text('backup_deleted', $sz));
			$pcount++;
			}
		}
	closedir(PURGEDIR);
	}

elsif ($mode == 1) {
	# List parent directory via FTP
	local $err;
	local $dir = &ftp_listdir($host, $base, \$err, $user, $pass, $port, 1);
	if ($err) {
		&$second_print(&text('backup_purgeelistdir', $err));
		return 0;
		}
	$dir = [ grep { $_->[13] ne "." && $_->[13] ne ".." } @$dir ];
	if (@$dir && !$dir->[0]->[9]) {
		# No times in output
		&$second_print(&text('backup_purgeelisttimes', $base));
		return 0;
		}
	foreach my $f (@$dir) {
		if ($f->[13] =~ /^$re$/ && $f->[9] && $f->[9] < $cutoff &&
		    $f->[13] !~ /\.(dom|info)$/) {
			local $old = int((time() - $f->[9]) / (24*60*60));
			&$first_print(&text('backup_deletingftp',
					    "<tt>$base/$f->[13]</tt>", $old));
			local $err;
			local $sz = $f->[7];
			$sz += &ftp_deletefile($host, "$base/$f->[13]",
					       \$err, $user, $pass, $port);
			local $infoerr;
			&ftp_deletefile($host, "$base/$f->[13].info",
					\$infoerr, $user, $pass, $port);
			local $domerr;
			&ftp_deletefile($host, "$base/$f->[13].dom",
					\$domerr, $user, $pass, $port);
			if ($err) {
				&$second_print(&text('backup_edelftp', $err));
				$ok = 0;
				}
			else {
				&$second_print(&text('backup_deleted',
						     &nice_size($sz)));
				$pcount++;
				}
			}
		}
	}

elsif ($mode == 2) {
	# Use ls -l via SSH to list the directory
	local $sshcmd = "ssh".($port ? " -p $port" : "")." ".
			$config{'ssh_args'}." ".
			$user."\@".$host;
	local $lscmd = $sshcmd." ls -l ".quotemeta($base);
	local $err;
	local $lsout = &run_ssh_command($lscmd, $pass, \$err);
	if ($err) {
		&$second_print(&text('backup_purgeesshls', $err));
		return 0;
		}
	foreach my $l (split(/\r?\n/, $lsout)) {
		local @st = &parse_lsl_line($l);
		next if (!scalar(@st));
		if ($st[13] =~ /^$re$/ && $st[9] && $st[9] < $cutoff &&
		    $st[13] !~ /\.(dom|info)$/) {
			local $old = int((time() - $st[9]) / (24*60*60));
			&$first_print(&text('backup_deletingssh',
					    "<tt>$base/$st[13]</tt>", $old));
			local $rmcmd = $sshcmd." rm -rf".
				       " ".quotemeta("$base/$st[13]").
				       " ".quotemeta("$base/$st[13].info").
				       " ".quotemeta("$base/$st[13].dom");
			local $rmerr;
			&run_ssh_command($rmcmd, $pass, \$rmerr);
			if ($rmerr) {
				&$second_print(&text('backup_edelssh', $rmerr));
				$ok = 0;
				}
			else {
				&$second_print(&text('backup_deleted',
						     &nice_size($st[7])));
				$pcount++;
				}
			}
		}
	}

elsif ($mode == 3 && $host =~ /\%/) {
	# Search S3 for S3 buckets matching the regexp
	local $buckets = &s3_list_buckets($user, $pass);
	if (!ref($buckets)) {
		&$second_print(&text('backup_purgeebuckets', $buckets));
		return 0;
		}
	foreach my $b (@$buckets) {
		local $ctime = &s3_parse_date($b->{'CreationDate'});
		if ($b->{'Name'} =~ /^$re$/ && $ctime && $ctime < $cutoff) {
			# Found one to delete
			local $old = int((time() - $ctime) / (24*60*60));
			&$first_print(&text('backup_deletingbucket',
					    "<tt>$b->{'Name'}</tt>", $old));

			# Sum up size of files
			local $files = &s3_list_files($user, $pass,
						      $b->{'Name'});
			local $sz = 0;
			if (ref($files)) {
				foreach my $f (@$files) {
					$sz += $f->{'Size'};
					}
				}
			local $err = &s3_delete_bucket($user, $pass,
						       $b->{'Name'});
			if ($err) {
				&$second_print(&text('backup_edelbucket',$err));
				$ok = 0;
				}
			else {
				&$second_print(&text('backup_deleted',
						     &nice_size($sz)));
				$pcount++;
				}
			}
		}
	}

elsif ($mode == 3 && $path =~ /\%/) {
	# Search for S3 files under the bucket
	local $files = &s3_list_files($user, $pass, $host);
	if (!ref($files)) {
		&$second_print(&text('backup_purgeefiles', $files));
		return 0;
		}
	foreach my $f (@$files) {
		local $ctime = &s3_parse_date($f->{'LastModified'});
		if ($f->{'Key'} =~ /^$re$/ && $ctime && $ctime < $cutoff &&
		    $f->{'Key'} !~ /\.(dom|info)$/) {
			# Found one to delete
			local $old = int((time() - $ctime) / (24*60*60));
			&$first_print(&text('backup_deletingfile',
					    "<tt>$f->{'Key'}</tt>", $old));
			local $err = &s3_delete_file($user, $pass, $host,
						     $f->{'Key'});
			if ($err) {
				&$second_print(&text('backup_edelbucket',$err));
				$ok = 0;
				}
			else {
				&s3_delete_file($user, $pass, $host,
						$f->{'Key'}.".info");
				&s3_delete_file($user, $pass, $host,
						$f->{'Key'}.".dom");
				&$second_print(&text('backup_deleted',
						     &nice_size($f->{'Size'})));
				$pcount++;
				}
			}
		}
	}

elsif ($mode == 6 && $host =~ /\%/) {
	# Search Rackspace for containers matching the regexp
	local $rsh = &rs_connect($config{'rs_endpoint'}, $user, $pass);
	if (!ref($rsh)) {
		return &text('backup_purgeersh', $rsh);
		}
	local $containers = &rs_list_containers($rsh);
	if (!ref($containers)) {
		&$second_print(&text('backup_purgeecontainers', $containers));
		return 0;
		}
	foreach my $c (@$containers) {
		local $st = &rs_stat_container($rsh, $c);
		next if (!ref($st));
		local $ctime = int($st->{'X-Timestamp'});
		if ($c =~ /^$re$/ && $ctime && $ctime < $cutoff) {
			# Found one to delete
			local $old = int((time() - $ctime) / (24*60*60));
			&$first_print(&text('backup_deletingcontainer',
					    "<tt>$c</tt>", $old));

			local $err = &rs_delete_container($rsh, $c, 1);
			if ($err) {
				&$second_print(
					&text('backup_edelcontainer',$err));
				$ok = 0;
				}
			else {
				&$second_print(&text('backup_deleted',
			          &nice_size($st->{'X-Container-Bytes-Used'})));
				$pcount++;
				}
			}
		}
	}

elsif ($mode == 6 && $path =~ /\%/) {
	# Search for Rackspace files under the container
	local $rsh = &rs_connect($config{'rs_endpoint'}, $user, $pass);
	if (!ref($rsh)) {
		return &text('backup_purgeersh', $rsh);
		}
	local $files = &rs_list_objects($rsh, $host);
	if (!ref($files)) {
		&$second_print(&text('backup_purgeefiles2', $files));
		return 0;
		}
	foreach my $f (@$files) {
		local $st = &rs_stat_object($rsh, $host, $f);
		next if (!ref($st));
		local $ctime = int($st->{'X-Timestamp'});
		if ($f =~ /^$re($|\/)/ && $ctime && $ctime < $cutoff &&
		    $f !~ /\.(dom|info)$/) {
			# Found one to delete
			local $old = int((time() - $ctime) / (24*60*60));
			&$first_print(&text('backup_deletingfile',
					    "<tt>$f</tt>", $old));
			local $err = &rs_delete_object($rsh, $host, $f);
			if ($err) {
				&$second_print(&text('backup_edelbucket',$err));
				$ok = 0;
				}
			else {
				&rs_delete_object($rsh, $host, $f.".dom");
				&rs_delete_object($rsh, $host, $f.".info");
				&$second_print(&text('backup_deleted',
				     &nice_size($st->{'Content-Length'})));
				$pcount++;
				}
			}
		}
	}




&$outdent_print();

&$second_print($pcount ? &text('backup_purged', $pcount)
		       : $text{'backup_purgednone'});
return $ok;
}

# write_backup_log(&domains, dest, incremental?, start, size, ok?,
# 		   "cgi"|"sched"|"api", output, &errordoms, [user], [&key])
# Record that some backup was made and succeeded or failed
sub write_backup_log
{
local ($doms, $dest, $increment, $start, $size, $ok, $mode,
       $output, $errdoms, $user, $key) = @_;
if (!-d $backups_log_dir) {
	&make_dir($backups_log_dir, 0700);
	}
local %log = ( 'doms' => join(' ', map { $_->{'dom'} } @$doms),
	       'errdoms' => join(' ', map { $_->{'dom'} } @$errdoms),
	       'dest' => $dest,
	       'increment' => $increment,
	       'start' => $start,
	       'end' => time(),
	       'size' => $size,
	       'ok' => $ok,
	       'user' => $user || $remote_user,
	       'mode' => $mode,
	       'key' => $key->{'id'},
	     );
$main::backup_log_id_count++;
$log{'id'} = $log{'end'}."-".$$."-".$main::backup_log_id_count;
&write_file("$backups_log_dir/$log{'id'}", \%log);
if ($output) {
	&open_tempfile(OUTPUT, ">$backups_log_dir/$log{'id'}.out");
	&print_tempfile(OUTPUT, $output);
	&close_tempfile(OUTPUT);
	}
}

# list_backup_logs([start-time])
# Returns a list of all backup logs, optionally limited to after some time
sub list_backup_logs
{
local ($start) = @_;
local @rv;
opendir(LOGS, $backups_log_dir);
while(my $id = readdir(LOGS)) {
	next if ($id eq "." || $id eq "..");
	next if ($id =~ /\.out$/);
	my ($time, $pid, $count) = split(/\-/, $id);
	next if (!$time || !$pid);
	next if ($start && $time < $start);
	local %log;
	&read_file("$backups_log_dir/$id", \%log) || next;
	$log{'output'} = &read_file_contents("$backups_log_dir/$id.out");
	push(@rv, \%log);
	}
close(LOGS);
return @rv;
}

# get_backup_log(id)
# Read and return a single logged backup
sub get_backup_log
{
local ($id) = @_;
local %log;
&read_file("$backups_log_dir/$id", \%log) || return undef;
$log{'output'} = &read_file_contents("$backups_log_dir/$id.out");
return \%log;
}

# record_backup_bandwidth(&domain, bytes-in, bytes-out, start, end)
# Add to the bandwidth files for some domain data transfer used by a backup
sub record_backup_bandwidth
{
local ($d, $inb, $outb, $start, $end) = @_;
if ($config{'bw_backup'}) {
	local $bwinfo = &get_bandwidth($d);
	local $startday = int($start / (24*60*60));
	local $endday = int($end / (24*60*60));
	for(my $day=$startday; $day<=$endday; $day++) {
		$bwinfo->{"backup_".$day} += $outb / ($endday - $startday + 1);
		$bwinfo->{"restore_".$day} += $inb / ($endday - $startday + 1);
		}
	&save_bandwidth($d, $bwinfo);
	}
}

# check_backup_limits(as-owner, on-schedule, dest)
# Check if the limit on the number of running backups has been exceeded, and
# if so either waits or returns an error. Returns undef if OK to proceed. May
# print a message if waiting.
sub check_backup_limits
{
local ($asowner, $sched, $dest) = @_;
local %maxes;
local $start = time();
local $printed;

while(1) {
	# Lock the file listing current backups, clean it up and read it
	&lock_file($backup_maxes_file);
	&cleanup_backup_limits(1);
	%maxes = ( );
	&read_file($backup_maxes_file, \%maxes);

	# Check if we are under the limit, or it doesn't apply
	local @pids = keys %maxes;
	local $waiting = time() - $start;
	if (!$config{'max_backups'} ||
	    @pids < $config{'max_backups'} ||
	    !$asowner && $config{'max_all'} == 0 ||
	    !$sched && $config{'max_manual'} == 0) {
		# Under the limit, or no limit applies in this case
		if ($printed) {
			&$second_print($text{'backup_waited'});
			}
		last;
		}
	elsif (!$config{'max_timeout'}) {
		# Too many, and no timeout is set .. give up now
		&unlock_file($backup_maxes_file);
		return &text('backup_maxhit', scalar(@pids),
					      $config{'max_backups'});
		}
	elsif ($waiting < $config{'max_timeout'}) {
		# Too many, but still under timeout .. wait for a while
		&unlock_file($backup_maxes_file);
		if (!$printed) {
			&$first_print(&text('backup_waiting',
					    $config{'max_backups'}));
			$printed++;
			}
		sleep(10);
		}
	else {
		# Over the timeout .. give up
		&unlock_file($backup_maxes_file);
		return &text('backup_waitfailed', $config{'max_timeout'});
		}
	}

# Add this job to the file
$maxes{$$} = $dest;
&write_file($backup_maxes_file, \%maxes);
&unlock_file($backup_maxes_file);

return undef;
}

# cleanup_backup_limits([no-lock], [include-this])
# Delete from the backup limits file any entries for PIDs that are not running
sub cleanup_backup_limits
{
local ($nolock, $includethis) = @_;
local (%maxes, $changed);
&lock_file($backup_maxes_file) if (!$nolock);
&read_file($backup_maxes_file, \%maxes);
foreach my $pid (keys %maxes) {
	if (!kill(0, $pid) || ($includethis && $pid == $$)) {
		delete($maxes{$pid});
		$changed++;
		}
	}
if ($changed) {
	&write_file($backup_maxes_file, \%maxes);
	}
&unlock_file($backup_maxes_file) if (!$nolock);
}

# get_scheduled_backup_dests(&sched)
# Returns a list of destinations for some scheduled backup
sub get_scheduled_backup_dests
{
local ($sched) = @_;
local @dests = ( $sched->{'dest0'} || $sched->{'dest'} );
for(my $i=1; $sched->{'dest'.$i}; $i++) {
	push(@dests, $sched->{'dest'.$i});
	}
return @dests;
}

# get_scheduled_backup_purges(&sched)
# Returns a list of purge times for some scheduled backup
sub get_scheduled_backup_purges
{
local ($sched) = @_;
local @purges = ( $sched->{'purge0'} || $sched->{'purge'} );
for(my $i=1; exists($sched->{'purge'.$i}); $i++) {
	push(@purges, $sched->{'purge'.$i});
	}
return @purges;
}

# get_scheduled_backup_keys(&sched)
# Returns a list of encryption key IDs for some scheduled backup
sub get_scheduled_backup_keys
{
local ($sched) = @_;
local @keys = ( $sched->{'key0'} || $sched->{'key'} );
for(my $i=1; exists($sched->{'key'.$i}); $i++) {
	push(@keys, $sched->{'key'.$i});
	}
return @keys;
}

# clean_domain_passwords(&domain)
# Removes any passwords or other secure information from a domain hash
sub clean_domain_passwords
{
local ($d) = @_;
local $rv = { %$d };
foreach my $f ("pass", "enc_pass", "mysql_pass", "postgres_pass") {
	delete($rv->{$f});
	}
return $rv;
}

# rename_backup_owner(&domain, &old-domain)
# Updates all scheduled backups and backup keys to reflect a username change
sub rename_backup_owner
{
local ($d, $oldd) = @_;
local $owner = $d->{'parent'} ? &get_domain($d->{'parent'})->{'user'}
			      : $d->{'user'};
local $oldowner = $oldd->{'parent'} ? &get_domain($oldd->{'parent'})->{'user'}
			            : $oldd->{'user'};
if ($owner ne $oldowner) {
	foreach my $sched (&list_scheduled_backups()) {
		if ($sched->{'owner'} eq $oldowner) {
			$sched->{'owner'} = $owner;
			&save_scheduled_backup($sched);
			}
		}
	if (defined(&list_backup_keys)) {
		foreach my $key (&list_backup_keys()) {
			if ($key->{'owner'} eq $oldowner) {
				$key->{'owner'} = $owner;
				&save_backup_key($key);
				}
			}
		}
	}
}

1;

