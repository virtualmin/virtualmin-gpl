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
			 );
	local @bf;
	foreach $f (&get_available_backup_features(), @backup_plugins) {
		push(@bf, $f) if ($config{'backup_feature_'.$f});
		$backup{'opts_'.$f} = $config{'backup_opts_'.$f};
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

# Merge in cron jobs to see which are enabled
&foreign_require("cron", "cron-lib.pl");
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

return @rv;
}

sub copy_cron_sched_keys
{
local ($src, $dst) = @_;
foreach my $k ('mins', 'hours', 'days', 'months', 'weekdays', 'special') {
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
	local @bf = split(/\s+/, $backup->{'features'});
	foreach $f (&get_available_backup_features(), @backup_plugins) {
		$config{'backup_feature_'.$f} = &indexof($f, @bf) >= 0 ? 1 : 0;
		$config{'backup_opts_'.$f} = $backup->{'opts_'.$f};
		}
	}
else {
	# Update or create separate file
	&make_dir($scheduled_backups_dir, 0700) if (!-d $scheduled_backups_dir);
	$backup->{'id'} ||= &domain_id();
	$backup->{'file'} = "$scheduled_backups_dir/$backup->{'id'}";
	&write_file($backup->{'file'}, $backup);
	}

# Update or delete cron job
&foreign_require("cron", "cron-lib.pl");
local $cmd = $backup_cron_cmd;
$cmd .= " --id $backup->{'id'}" if ($backup->{'id'} != 1);
local $job;
if (!$wasnew) {
	$job = &find_virtualmin_cron_job($cmd);
	}
if ($backup->{'enabled'} && $job) {
	# Fix job schedule
	&copy_cron_sched_keys($backup, $job);
	&cron::change_cron_job($job);
	}
elsif ($backup->{'enabled'} && !$job) {
	# Create cron job
	$job = { 'user' => 'root',
		 'active' => 1,
		 'command' => $cmd };
	&copy_cron_sched_keys($backup, $job);
	&cron::create_cron_job($job);
	}
elsif (!$backup->{'enabled'} && $job) {
	# Delete cron job
	&cron::delete_cron_job($job);
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
&foreign_require("cron", "cron-lib.pl");
local $cmd = $backup_cron_cmd." --id $backup->{'id'}";
local $job = &find_virtualmin_cron_job($cmd);
if ($job) {
	&cron::delete_cron_job($job);
	}
}

# backup_domains(file, &domains, &features, dir-format, skip-errors, &options,
#		 home-format, &virtualmin-backups, mkdir, onebyone, as-owner,
#		 &callback-func, incremental)
# Perform a backup of one or more domains into a single tar.gz file. Returns
# an OK flag and the size of the backup file
sub backup_domains
{
local ($desturl, $doms, $features, $dirfmt, $skip, $opts, $homefmt, $vbs,
       $mkdir, $onebyone, $asowner, $cbfunc, $increment) = @_;
local $backupdir;
local $transferred_sz;

# See if we can actually connect to the remote server
local ($mode, $user, $pass, $server, $path, $port) =
	&parse_backup_url($desturl);
if ($mode == 1) {
	# Try FTP login
	local $ftperr;
	&ftp_onecommand($server, "CWD /", \$ftperr, $user, $pass, $port);
	if ($ftperr) {
		&$first_print(&text('backup_eftptest', $ftperr));
		return (0, 0);
		}
	if ($dirfmt) {
		# Also create the destination directory now (ignoring any error,
		# as it may already exist)
		local $mkdirerr;
		&ftp_onecommand($server, "MKD $path", \$mkdirerr, $user, $pass,
				$port);
		}
	}
elsif ($mode == 2) {
	# Try a dummy SCP
	local $scperr;
	local $r = ($user ? "$user\@" : "").
		   "$server:/tmp/virtualmin-copy-test.$user";
	local $temp = &transname();
	open(TEMP, ">$temp");
	close(TEMP);
	&scp_copy($temp, $r, $pass, \$scperr, $port);
	if ($scperr) {
		&$first_print(&text('backup_escptest', $scperr));
		return (0, 0);
		}
	if ($dirfmt && $path ne "/") {
		# Also create the destination directory now, by scping an
		# empty dir.
		$path =~ /^(.*)\/([^\/]+)\/?$/;
		local ($pathdir, $pathfile) = ($1, $2);
		local $empty = &transname($pathfile);
		local $mkdirerr;
		&make_dir($empty, 0755);
		local $r = ($user ? "$user\@" : "")."$server:$pathdir";
		&scp_copy($empty, $r, $pass, \$mkdirerr, $port);
		}
	}
elsif ($mode == 3) {
	# Connect to S3 service and create bucket
	if ($path && $dirfmt) {
		&$first_print($text{'backup_es3path'});
		return (0, 0);
		}
	elsif (!$path && !$dirfmt) {
		&$first_print($text{'backup_es3nopath'});
		return (0, 0);
		}
	local $cerr = &check_s3();
	if ($cerr) {
		&$first_print($cerr);
		return (0, 0);
		}
	local $err = &init_s3_bucket($user, $pass, $server);
	if ($err) {
		&$first_print($err);
		return (0, 0);
		}
	}
elsif ($mode == 0) {
	# Make sure target is / is not a directory
	if ($dirfmt && !-d $desturl) {
		# Looking for a directory
		if ($mkdir) {
			if (!-d $desturl) {
				&make_dir($desturl, 0755, 1);
				}
			}
		else {
			&$first_print(&text('backup_edirtest',
					    "<tt>$desturl</tt>"));
			return (0, 0);
			}
		}
	elsif (!$dirfmt && -d $desturl) {
		&$first_print(&text('backup_enotdirtest', "<tt>$desturl</tt>"));
		return (0, 0);
		}
	if (!$dirfmt && $mkdir) {
		# Create parent directories if requested
		local $dirdest = $desturl;
		$dirdest =~ s/\/[^\/]+$//;
		if ($dirdest && !-d $dirdest) {
			&make_dir($dirdest, 0755);
			}
		}
	}

if (!$homefmt) {
	# Create a temp dir for the backup, to be tarred up later
	$backupdir = &transname();
	if (!-d $backupdir) {
		&make_dir($backupdir, 0755);
		}
	}
else {
	# A home-format backup can only be used if the home directory is
	# included, and if we are doing one per domain, and if all domains
	# *have* a home directory
	if (!$dirfmt) {
		&$first_print($text{'backup_ehomeformat'});
		return (0, 0);
		}
	if (&indexof("dir", @$features) == -1) {
		&$first_print($text{'backup_ehomeformat2'});
		return (0, 0);
		}
	foreach my $d (@$doms) {
		if (!$d->{'dir'} && !$skip) {
			&$first_print(&text('backup_ehomeformat3',
					    $d->{'dom'}));
			return (0, 0);
			}
		}
	# Skip any that don't have directories
	$doms = [ grep { $_->{'dir'} } @$doms ];
	}

# Work out where to write the final tar files to
local ($dest, @destfiles, %destfiles_map);
if ($mode >= 1) {
	# Write archive to temporary file/dir first, for later upload
	$path =~ /^(.*)\/([^\/]+)\/?$/;
	local ($pathdir, $pathfile) = ($1, $2);
	$dest = &transname($pathfile);
	}
else {
	# Can write direct to destination
	$dest = $path;
	}
if ($dirfmt && !-d $dest) {
	&make_dir($dest, 0755);
	}

# For a home-format backup, the home has to be last
local @backupfeatures = @$features;
local $hfsuffix;
if ($homefmt) {
	@backupfeatures = ((grep { $_ ne "dir" } @$features), "dir");
	$hfsuffix = $config{'compression'} == 0 ? "tar.gz" :
		    $config{'compression'} == 1 ? "tar.bz2" : "tar";
	}

# Go through all the domains, and for each feature call the backup function
# to add it to the backup directory
local $d;
local $ok = 1;
local @donedoms;
local ($okcount, $errcount) = (0, 0);
local @errdoms;
local %donefeatures;				# Map from domain name->features
DOMAIN: foreach $d (@$doms) {
	if ($homefmt) {
		# Backup goes to a sub-dir of the home
		$backupdir = "$d->{'home'}/.backup";
		system("rm -rf ".quotemeta($backupdir));
		&make_dir($backupdir, 0777);
		}
	&$cbfunc($d, 0, $backupdir) if ($cbfunc);
	&$first_print(&text('backup_fordomain', $d->{'dom'}));
	&$second_print();
	&$indent_print();
	local $f;
	local $dok = 1;
	local @donefeatures;
	foreach $f (@backupfeatures) {
		local $bfunc = "backup_$f";
		local $fok;
		local $ffile;
		if (&indexof($f, @backup_plugins) < 0 &&
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
				       $increment);
			}
		elsif (&indexof($f, @backup_plugins) >= 0 &&
		       $d->{$f}) {
			# Call plugin backup function
			$ffile = "$backupdir/$d->{'dom'}_$f";
			local $fok = &plugin_call($f, "feature_backup",
					  $d, $ffile, $opts->{$f}, $homefmt,
					  $increment);
			}
		if (defined($fok)) {
			# See if it worked or not
			if (!$fok) {
				# Didn't work .. remove failed file, so we
				# don't have partial data
				if ($ffile && $f ne "dir") {
					foreach my $ff ($ffile,
						glob("${ffile}_*")) {
						&unlink_file($ff);
						}
					}
				$dok = 0;
				}
			if (!$fok && !$skip) {
				$ok = 0;
				$errcount++;
				push(@errdoms, $d->{'dom'});
				last DOMAIN;
				}
			push(@donedoms, $d);
			}
		if ($fok) {
			push(@donefeatures, $f);
			}
		}
	$donefeatures{$d->{'dom'}} = \@donefeatures;
	if ($dok) {
		$okcount++;
		}
	else {
		$errcount++;
		push(@errdoms, $d->{'dom'});
		}

	if ($onebyone && $homefmt && $dok) {
		# Transfer this domain now
		local $err;
		local $df = "$d->{'dom'}.$hfsuffix";
		&$cbfunc($d, 1, "$dest/$df") if ($cbfunc);
		if ($mode == 2) {
			# Via SCP
			&$first_print($text{'backup_upload2'});
			local $r = ($user ? "$user\@" : "")."$server:$path";
			&scp_copy("$dest/$df", $r, $pass, \$err, $port);
			}
		elsif ($mode == 1) {
			# Via FTP
			&$first_print($text{'backup_upload'});
			&ftp_upload($server, "$path/$df", "$dest/$df", \$err,
				    undef, $user, $pass, $port);
			}
		if ($mode == 3) {
			# Via S3 upload
			&$first_print($text{'backup_upload3'});
			local $binfo = { $d->{'dom'} =>
					 $donefeatures{$d->{'dom'}} };
			$err = &s3_upload($user, $pass, $server,
					  "$dest/$df", $df, $binfo);
			}
		if ($err) {
			&$second_print(&text('backup_uploadfailed', $err));
			$ok = 0;
			}
		else {
			&$second_print($text{'setup_done'});
			local @tst = stat("$dest/$df");
			$transferred_sz += $tst[7];
			}

		# Delete .backup directory
		&execute_command("rm -rf ".quotemeta("$d->{'home'}/.backup"));
		&execute_command("rm -rf ".quotemeta("$dest/$df"));
		}

	&$outdent_print();
	&$cbfunc($d, 2, "$dest/$df") if ($cbfunc);
	}

# Add all requested Virtualmin config information
local $vcount = 0;
if (@$vbs) {
	&$first_print(&text('backup_global',
		      join(", ", map { $text{'backup_v'.$_} } @$vbs)));
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
	&$second_print($text{'setup_done'});
	}

if ($ok) {
	# Work out command for writing to backup destination (which may use
	# su, so that permissions are correct)
	local $out;
	if ($homefmt) {
		# No final step is needed for home-format backups, because
		# we have already reached it!
		if (!$onebyone) {
			foreach $d (&unique(@donedoms)) {
				push(@destfiles, "$d->{'dom'}.$hfsuffix");
				$destfiles_map{$destfiles[$#destfiles]} = $d;
				}
			}
		}
	elsif ($dirfmt) {
		# Create one tar file in the destination for each domain
		&$first_print($text{'backup_final2'});
		if (!-d $dest) {
			&make_dir($dest, 0755);
			}

		foreach $d (&unique(@donedoms)) {
			# Work out dest file and compression command
			local $destfile = "$d->{'dom'}.tar";
			local $comp = "cat";
			if ($config{'compression'} == 0) {
				$destfile .= ".gz";
				$comp = "gzip -c";
				}
			elsif ($config{'compression'} == 1) {
				$destfile .= ".bz2";
				$comp = "bzip2 -c";
				}
			local $writer = "cat >$dest/$destfile";
			if ($asowner) {
				$writer = &command_as_user(
					$doms[0]->{'user'}, 0, $writer);
				}

			&execute_command("cd $backupdir && (tar cf - $d->{'dom'}_* | $comp) 2>&1 | $writer", undef, \$out);
			push(@destfiles, $destfile);
			$destfiles_map{$destfile} = $d;
			if ($?) {
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
			$comp = "gzip -c";
			}
		elsif ($dest =~ /\.(bz2|tbz2)$/i) {
			$comp = "bzip2 -c";
			}
		local $writer = "cat >$dest";
		if ($asowner) {
			$writer = &command_as_user(
					$doms[0]->{'user'}, 0, $writer);
			&open_tempfile(DEST, ">$dest", 0, 1);
			&close_tempfile(DEST);
			&set_ownership_permissions(
			  $doms[0]->{'uid'}, $doms[0]->{'ugid'}, undef, $dest);
		 	}
		&$first_print($text{'backup_final'});
		&execute_command("cd $backupdir && (tar cf - . | $comp) 2>&1 | $writer", undef, \$out);
		if ($?) {
			&$second_print(&text('backup_finalfailed', "<pre>$out</pre>"));
			$ok = 0;
			}
		else {
			&$second_print($text{'setup_done'});
			}
		}

	# Create a separate file in the destination directory for Virtualmin
	# config backups
	if (@$vbs && ($homefmt || $dirfmt)) {
		if (&has_command("gzip")) {
			&execute_command("cd $backupdir && (tar cf - virtualmin_* | gzip -c) 2>&1 >$dest/virtualmin.tar.gz", undef, \$out, \$out);
			push(@destfiles, "virtualmin.tar.gz");
			}
		else {
			&execute_command("cd $backupdir && tar cf $dest/virtualmin.tar virtualmin_* 2>&1", undef, \$out, \$out);
			push(@destfiles, "virtualmin.tar");
			}
		$destfiles_map{$destfiles[$#destfiles]} = "virtualmin";
		}
	$donefeatures{"virtualmin"} = $vbs;
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

if ($ok && $mode == 1 && (@destfiles || !$dirfmt)) {
	# Upload file(s) to FTP server
	&$first_print($text{'backup_upload'});
	local $err;
	if ($dirfmt) {
		# Need to upload entire directory .. which has to be created
		foreach my $df (@destfiles) {
			&ftp_upload($server, "$path/$df", "$dest/$df", \$err,
				    undef, $user, $pass, $port);
			if ($err) {
				&$second_print(
					&text('backup_uploadfailed', $err));
				$ok = 0;
				last;
				}
			}
		}
	else {
		# Just a single file
		&ftp_upload($server, $path, $dest, \$err, undef, $user, $pass,
			    $port);
		if ($err) {
			&$second_print(&text('backup_uploadfailed', $err));
			$ok = 0;
			}
		}
	&$second_print($text{'setup_done'}) if ($ok);
	}
elsif ($ok && $mode == 2 && (@destfiles || !$dirfmt)) {
	# Upload to SSH server with scp
	&$first_print($text{'backup_upload2'});
	local $err;
	local $r = ($user ? "$user\@" : "")."$server:$path";
	if ($dirfmt) {
		# Need to upload entire directory
		&scp_copy("$dest/*", $r, $pass, \$err, $port);
		if ($err) {
			# Target dir didn't exist, so scp just the directory
			$err = undef;
			&scp_copy($dest, $r, $pass, \$err, $port);
			}
		}
	else {
		# Just a single file
		&scp_copy($dest, $r, $pass, \$err, $port);
		}
	if ($err) {
		&$second_print(&text('backup_uploadfailed', $err));
		$ok = 0;
		}
	&$second_print($text{'setup_done'}) if ($ok);
	}
elsif ($ok && $mode == 3 && (@destfiles || !$dirfmt)) {
	# Upload to S3 server
	local $err;
	&$first_print($text{'backup_upload3'});
	if ($dirfmt) {
		# Upload an entire directory of files
		foreach my $df (@destfiles) {
			local $d = $destfiles_map{$df};
			local $n = $d eq "virtualmin" ? "virtualmin"
						      : $d->{'dom'};
			local $binfo = { $n => $donefeatures{$n} };
			$err = &s3_upload($user, $pass, $server, "$dest/$df",
					  $df, $binfo);
			if ($err) {
				&$second_print(
					&text('backup_uploadfailed', $err));
				$ok = 0;
				last;
				}
			}
		}
	else {
		# Upload one file to the bucket
		local %donebydname;
		$err = &s3_upload($user, $pass, $server, $dest,
				  $path, \%donefeatures);
		if ($err) {
			&$second_print(&text('backup_uploadfailed', $err));
			$ok = 0;
			}
		}
	&$second_print($text{'setup_done'}) if ($ok);
	}

if ($mode >= 1) {
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
		&$first_print(&text('backup_errorsites', join(" ", @errdoms)));
		}
	}

return ($ok, $sz);
}

# restore_domains(file, &domains, &features, &options, &vbs,
#		  [only-backup-features], [&ip-address-info])
# Restore multiple domains from the given file
sub restore_domains
{
local ($file, $doms, $features, $opts, $vbs, $onlyfeats, $ipinfo) = @_;

# Work out where the backup is located
local $ok = 1;
local $backup;
local ($mode, $user, $pass, $server, $path, $port) = &parse_backup_url($file);
if ($mode > 0) {
	# Need to download to temp file/directory first
	&$first_print($mode == 1 ? $text{'restore_download'} :
		      $mode == 3 ? $text{'restore_downloads3'} :
				   $text{'restore_downloadssh'});
	if ($mode == 3) {
		local $cerr = &check_s3();
		if ($cerr) {
			&$second_print($err);
			return 0;
			}
		}
	$backup = &transname();
	local $derr = &download_backup($_[0], $backup,
		[ map { $_->{'dom'} } @$doms ], $vbs);
	if ($derr) {
		&$second_print(&text('restore_downloadfailed', $derr));
		$ok = 0;
		}
	else {
		&$second_print($text{'setup_done'});
		}
	}
else {
	$backup = $file;
	}

local $restoredir;
local %homeformat;
local %missing;
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
			     grep { $_ ne "." && $_ ne ".." } readdir(DIR);
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

		# See if this is a home-format backup, by looking for a .backup
		# sub-directory
		local $lout;
		local $cf = &compression_format($f);
		local $comp = $cf == 1 ? "gunzip -c" :
			      $cf == 2 ? "uncompress -c" :
			      $cf == 3 ? "bunzip2 -c" : "cat";
		&execute_command("$comp $q | tar tf -", undef, \$lout, \$lout);
		local @lines = split(/\n/, $lout);
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

		&execute_command("cd '$restoredir' && ($comp $q | tar xf - $extract)", undef, \$out, \$out);
		if ($?) {
			&$second_print(&text('restore_firstfailed',
					     "<tt>$f</tt>", "<pre>$out</pre>"));
			$ok = 0;
			last;
			}

		if ($homeformat{$f}) {
			# Move the .backup contents to the restore dir, as
			# expected by later code
			&execute_command("mv ".quotemeta("$restoredir/.backup")."/* ".quotemeta($restoredir));
			}
		}
	&$second_print($text{'setup_done'}) if ($ok);
	}

# Make sure any domains we need to re-create have a Virtualmin info file
foreach $d (@{$_[1]}) {
	if ($d->{'missing'}) {
		if (!-r "$restoredir/$d->{'dom'}_virtualmin") {
			&$second_print(&text('restore_missinginfo', $d->{'dom'}));
			$ok = 0;
			last;
			}
		}
	}

# Lock user DB for UID re-allocation
if ($_[3]->{'reuid'}) {
	&obtain_lock_unix($d);
	}

local $vcount = 0;
if ($ok) {
	# Fill in missing domain details
	foreach $d (@{$_[1]}) {
		if ($d->{'missing'}) {
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
		}

	# Now restore each of the domain/feature files
	local $d;
	DOMAIN: foreach $d (sort { $a->{'parent'} <=> $b->{'parent'} } @{$_[1]}) {
		if ($d->{'missing'}) {
			# This domain doesn't exist yet - need to re-create it
			$missing{$d->{'id'}} = $d;
			&$first_print(&text('restore_createdomain',
				      $d->{'dom'}));

			# Only features in the backup are enabled
			if ($onlyfeats) {
				foreach my $f (@backup_features,
					       @backup_plugins) {
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
				if (!$parentdom) {
					&$second_print($text{'restore_epar'});
					$ok = 0;
					last DOMAIN;
					}
				$parentuser = $parentdom->{'user'};
				}

			# Does the template exist?
			local $tmpl = &get_template($d->{'template'});
			if (!$tmpl) {
				&$second_print($text{'restore_etemplate'});
				$ok = 0;
				last DOMAIN;
				}

			if ($parentdom) {
				# UID and GID always come from parent
				$d->{'uid'} = $parentdom->{'uid'};
				$d->{'gid'} = $parentdom->{'gid'};
				$d->{'ugid'} = $parentdom->{'ugid'};
				}
			elsif ($_[3]->{'reuid'}) {
				# Re-allocate the UID and GID
				local ($samegid) = ($d->{'gid'} == $d->{'ugid'});
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
			if ($d->{'alias'}) {
				# Alias domains always have same IP as parent
				local $alias = &get_domain($d->{'alias'});
				$d->{'ip'} = $alias->{'ip'};
				}
			elsif ($ipinfo) {
				# Use IP specified on backup form
				$d->{'ip'} = $ipinfo->{'ip'};
				$d->{'virt'} = $ipinfo->{'virt'};
				$d->{'virtalready'} = $ipinfo->{'virtalready'};
				if ($ipinfo->{'mode'} == 2) {
					# Re-allocate an IP, as we might be
					# doing several domains
					$d->{'ip'} = &free_ip_address($tmpl);
					}
				if (!$d->{'ip'}) {
					&$second_print(
						&text('setup_evirtalloc'));
					$ok = 0;
					last DOMAIN;
					}
				}
			elsif (!$d->{'virt'} && !$config{'all_namevirtual'}) {
				# Use this system's default IP
				$d->{'ip'} = &get_default_ip($d->{'reseller'});
				if (!$d->{'ip'}) {
					&$second_print($text{'restore_edefip'});
					$ok = 0;
					last DOMAIN;
					}
				}

			# DNS external IP is always reset to match this system,
			# as the old setting is unlikely to be correct.
			$d->{'dns_ip'} = $virt || $config{'all_namevirtual'} ?
				undef : $config{'dns_ip'};

			# Check for clashes
			local $cerr = &virtual_server_clashes($d);
			if ($cerr) {
				&$second_print(&text('restore_eclash', $cerr));
				$ok = 0;
				last DOMAIN;
				}

			# Finally, create it
			&$indent_print();
			delete($d->{'missing'});
			$d->{'nocreationmail'} = 1;
			$d->{'nocreationscripts'} = 1;
			$d->{'nocopyskel'} = 1;
			&create_virtual_server($d, $parentdom,
			       $parentdom ? $parentdom->{'user'} : undef, 1);
			&$outdent_print();
			}

		# Users need to be restored last
		local @rfeatures = @$features;
		if (&indexof("mail", @rfeatures) >= 0) {
			@rfeatures =((grep { $_ ne "mail" } @$features),"mail");
			}

		# Now do the actual restore
		&$first_print(&text('restore_fordomain', $d->{'dom'}));
		&$indent_print();
		local $f;
		local %oldd;
		foreach $f (@rfeatures) {
			# Restore features
			local $rfunc = "restore_$f";
			local $fok;
			if (&indexof($f, @backup_plugins) < 0 &&
			    defined(&$rfunc) &&
			    ($d->{$f} || $f eq "virtualmin" ||
			     $f eq "mail" && &can_domain_have_users($d))) {
				local $ffile;
				local $hft =
				    $homeformat{"$backup/$d->{'dom'}.tar.gz"} ||
				    $homeformat{"$backup/$d->{'dom'}.tar.bz2"}||
				    $homeformat{"$backup/$d->{'dom'}.tar"} ||
				    $homeformat{$backup};
				if ($hft && $f eq "dir") {
					# For a home-format backup, the backup
					# itself is the home
					$ffile = $hft;
					}
				else {
					$ffile = "$restoredir/$d->{'dom'}_$f";
					}
				if ($f eq "virtualmin") {
					# If restoring the virtualmin info, keep
					# the old feature file
					&read_file($ffile, \%oldd);
					}
				if (-r $ffile) {
					# Call the restore function
					$fok = &$rfunc($d, $ffile,
					     $_[3]->{$f}, $_[3], $hft, \%oldd);
					}
				}
			elsif (&indexof($f, @backup_plugins) >= 0 &&
			       $d->{$f}) {
				# Restoring a plugin feature
				local $ffile = "$restoredir/$d->{'dom'}_$f";
				if (-r $ffile) {
					$fok = &plugin_call($f,
					    "feature_restore", $d, $ffile,
					    $_[3]->{$f}, $_[3], $hft, \%oldd);
					}
				}
			if (defined($fok) && !$fok) {
				# Handle feature failure
				$ok = 0;
				&$outdent_print();
				last DOMAIN;
				}
			}
		&save_domain($d);

		# Re-setup Webmin user
		&refresh_webmin_user($d);
		&$outdent_print();
		}

	# Restore any Virtualmin settings
	if (@$vbs) {
		&$first_print(&text('restore_global',
			      join(", ", map { $text{'backup_v'.$_} } @$vbs)));
		foreach my $v (@$vbs) {
			local $vfile = "$restoredir/virtualmin_".$v;
			if (-r $vfile) {
				local $vfunc = "virtualmin_restore_".$v;
				local $ok = &$vfunc($vfile, $vbs);
				$vcount++;
				}
			}
		&$second_print($text{'setup_done'});
		}
	}

# If any created restored domains had scripts, re-verify their dependencies
if (defined(&list_domain_scripts) && $ok && scalar(keys %missing)) {
	&$first_print($text{'restore_phpmods'});
	local %scache;
	local (@phpinstalled, $phpanyfailed, @phpbad);
	foreach my $d (grep { $missing{$_->{'id'}} } @$doms) {
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
			local $ok = &setup_php_modules($d, $script,
			   $sinfo->{'version'}, $phpver, $sinfo->{'opts'},
			   \@phpinstalled);
			&pop_all_print();
			$phpanyfailed++ if (!$ok);
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
			$badlist .= &text('restore_phpbad2', $b->[0]->{'dom'},
					  $b->[2]->{'desc'}, $b->[3])."<br>\n";
			}
		&$second_print($badlist);
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

# backup_contents(file, [want-domains])
# Returns a hash ref of domains and features in a backup file, or an error
# string if it is invalid. If the want-domains flag is given, the domain
# structures are also returned as a list of hash refs (except for S3).
sub backup_contents
{
local ($file, $wantdoms) = @_;
local $backup;
local ($mode, $user, $pass, $server, $path, $port) = &parse_backup_url($file);
local $doms;
if ($mode == 3) {
	# For S3, just download the backup contents files
	local $s3b = &s3_list_backups($user, $pass, $server, $path);
	return $s3b if (!ref($s3b));
	local %rv;
	foreach my $b (keys %$s3b) {
		$rv{$b} = $s3b->{$b}->{'features'};
		}
	return $wantdoms ? (\%rv, undef) : \%rv;
	}
elsif ($mode > 0) {
	# Need to download to temp file first
	$backup = &transname();
	local $derr = &download_backup($_[0], $backup);
	return $derr if ($derr);
	}
else {
	$backup = $_[0];
	}

if (-d $backup) {
	# A directory of backup files, one per domain
	opendir(DIR, $backup);
	local $f;
	local %rv;
	foreach $f (readdir(DIR)) {
		next if ($f eq "." || $f eq "..");
		local ($cont, $fdoms);
		if ($wantdoms) {
			($cont, $fdoms) = &backup_contents("$backup/$f", 1);
			}
		else {
			$cont = &backup_contents("$backup/$f", 0);
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
	local $cf = &compression_format($backup);
	local $comp = $cf == 1 ? "gunzip -c" :
		      $cf == 2 ? "uncompress -c" :
		      $cf == 3 ? "bunzip2 -c" : "cat";
	$out = `($comp $q | tar tf -) 2>&1`;
	if ($?) {
		return $text{'restore_etar'};
		}

	# Look for a home-format backup first
	local ($l, %rv, %done, $dotbackup, @virtfiles);
	foreach $l (split(/\n/, $out)) {
		if ($l =~ /^(.\/)?.backup\/([^_]+)_([a-z0-9\-]+)$/) {
			# Found a .backup/domain_feature file
			push(@{$rv{$2}}, $3) if (!$done{$2,$3}++);
			push(@{$rv{$2}}, "dir") if (!$done{$2,"dir"}++);
			if ($3 eq 'virtualmin') {
				push(@virtfiles, $l);
				}
			$dotbackup = 1;
			}
		}
	if (!$dotbackup) {
		# Look for an old-format backup
		foreach $l (split(/\n/, $out)) {
			if ($l =~ /^(.\/)?([^_]+)_([a-z0-9\-]+)$/) {
				# Found a domain_feature file
				push(@{$rv{$2}}, $3) if (!$done{$2,$3}++);
				if ($3 eq 'virtualmin') {
					push(@virtfiles, $l);
					}
				}
			}
		}

	# Extract and read domain files
	if ($wantdoms) {
		local $vftemp = &transname();
		&make_dir($vftemp, 0700);
		local $qvirtfiles = join(" ", map { quotemeta($_) } @virtfiles);
		$out = `cd $vftemp ; ($comp $q | tar xvf - $qvirtfiles) 2>&1`;
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
		push(@rv, { 'feature' => $f,
			    'plugin' => 1,
			    'desc' => $desc });
		}
	}
return @rv;
}

# download_backup(url, tempfile, [&domain-names], [&config-features])
# Downloads a backup file or directory to a local temp file or directory.
# Returns undef on success, or an error message.
sub download_backup
{
local ($url, $temp, $domnames, $vbs) = @_;
local $cache = $main::download_backup_cache{$url};
if ($cache && -r $cache) {
	# Already got the file .. no need to re-download
	link($cache, $temp) || symlink($cache, $temp);
	return undef;
	}
local ($mode, $user, $pass, $server, $path, $port) = &parse_backup_url($url);
if ($mode == 1) {
	# Download from FTP server
	local $cwderr;
	local $isdir = &ftp_onecommand($server, "CWD $path", \$cwderr,
				       $user, $pass, $port);
	local $err;
	if ($isdir) {
		# Need to download entire directory
		&make_dir($temp, 0700);
		local $list = &ftp_listdir($server, $path, \$err, $user, $pass,
					   $port);
		return $err if (!$list);
		foreach $f (@$list) {
			$f =~ s/^$path[\\\/]//;
			next if ($f eq "." || $f eq ".." || $f eq "");
			&ftp_download($server, "$path/$f", "$temp/$f", \$err,
				      undef, $user, $pass, $port);
			return $err if ($err);
			}
		}
	else {
		# Can just download a single file
		&ftp_download($server, $path, $temp, \$err,
			      undef, $user, $pass, $port);
		return $err if ($err);
		}
	}
elsif ($mode == 2) {
	# Download from SSH server
	&scp_copy(($user ? "$user\@" : "")."$server:$path",
		  $temp, $pass, \$err, $port);
	return $err if ($err);
	}
elsif ($mode == 3) {
	# Download from S3 server
	local $s3b = &s3_list_backups($user, $pass, $server, $path);
	return $s3b if (!ref($s3b));
	local @wantdoms;
	push(@wantdoms, @$domnames) if (@$domnames);
	push(@wantdoms, "virtualmin") if (@$vbs);
	@wantdoms = (keys %$s3b) if (!@wantdoms);
	&make_dir($temp, 0700);
	foreach my $dname (@wantdoms) {
		local $si = $s3b->{$dname};
		if (!$si) {
			return &text('restore_es3info', $dname);
			}
		local $err = &s3_download($user, $pass, $server,
					  $si->{'file'}, "$temp/$si->{'file'}");
		return $err if ($err);
		}
	}
$main::download_backup_cache{$url} = $temp;
return undef;
}

# backup_strftime(path)
# Replaces stftime-style % codes in a path with the current time
sub backup_strftime
{
eval "use POSIX";
eval "use posix" if ($@);
local @tm = localtime(time());
return strftime($_[0], @tm);
}

# parse_backup_url(string)
# Converts a URL like ftp:// or a filename into its components. These will be
# protocol (1 for FTP, 2 for SSH, 0 for local, 3 for S3, 4 for download), login,
# password, host, path and port
sub parse_backup_url
{
local @rv;
if ($_[0] =~ /^ftp:\/\/([^:]*):(.*)\@([^\/:\@]+)(:\d+)?:?(\/.*)$/) {
	@rv = (1, $1, $2, $3, $5, $4 ? substr($4, 1) : 21);
	}
elsif ($_[0] =~ /^ssh:\/\/([^:]*):(.*)\@([^\/:\@]+)(:\d+)?:?(\/.*)$/ ||
       $_[0] =~ /^ssh:\/\/([^:]*):(.*)\@([^\/:\@]+)(:\d+)?:(.+)$/) {
	# SSH url with no @ in password
	@rv = (2, $1, $2, $3, $5, $4 ? substr($4, 1) : 22);
	}
elsif ($_[0] =~ /^s3:\/\/([^:]*):([^\@]*)\@([^\/]+)(\/(.*))?$/) {
	@rv = (3, $1, $2, $3, $5, undef);
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
if ($rv[0] && $rv[3] =~ /^(\S+):(\d+)$/) {
	# Convert hostname to host:port
	$rv[3] = $1;
	$rv[5] = $2;
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
	$rv = &text('backup_nices3', "<tt>$host</tt>");
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
local ($mode, $user, $pass, $server, $path, $port) = &parse_backup_url($_[1]);
local $defport = $mode == 1 ? 21 : $mode == 2 ? 22 : undef;
local $serverport = $port && $port != $defport ? "$server:$port" : $server;
local $rv;

local @opts;
if (!$nolocal) {
	# Local file field (can be anywhere)
	push(@opts, [ 0, $text{'backup_mode0'},
	       &ui_textbox($name."_file", $mode == 0 ? $path : "", 50)." ".
	       &file_chooser_button($name."_file")."<br>\n" ]);
	}
elsif ($d && $d->{'dir'}) {
	# Limit local file to under virtualmin-backups
	push(@opts, [ 0, $text{'backup_mode0a'},
	       &ui_textbox($name."_file",
		  $mode == 0 && $path =~ /virtualmin-backup\/(.*)$/ ? $1 : "",
		  50)."<br>\n" ]);
	}

# FTP file fields
local $ft = "<table>\n";
$ft .= "<tr> <td>$text{'backup_ftpserver'}</td> <td>".
       &ui_textbox($name."_server", $mode == 1 ? $serverport : undef, 20).
       "</td> </tr>\n";
$ft .= "<tr> <td>$text{'backup_path'}</td> <td>".
       &ui_textbox($name."_path", $mode == 1 ? $path : undef, 50).
       "</td> </tr>\n";
$ft .= "<tr> <td>$text{'backup_login'}</td> <td>".
       &ui_textbox($name."_user", $mode == 1 ? $user : undef, 15).
       "</td> </tr>\n";
$ft .= "<tr> <td>$text{'backup_pass'}</td> <td>".
       &ui_password($name."_pass", $mode == 1 ? $pass : undef, 15).
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
       &ui_textbox($name."_suser", $mode == 2 ? $user : undef, 15).
       "</td> </tr>\n";
$st .= "<tr> <td>$text{'backup_pass'}</td> <td>".
       &ui_password($name."_spass", $mode == 2 ? $pass : undef, 15).
       "</td> </tr>\n";
$st .= "</table>\n";
push(@opts, [ 2, $text{'backup_mode2'}, $st ]);

if (&can_use_s3()) {
	# S3 backup fields (bucket, access key ID, secret key and file)
	local $st = "<table>\n";
	$st .= "<tr> <td>$text{'backup_bucket'}</td> <td>".
	       &ui_textbox($name."_bucket", $mode == 3 ? $server : undef, 20).
	       "</td> </tr>\n";
	$st .= "<tr> <td>$text{'backup_akey'}</td> <td>".
	       &ui_textbox($name."_akey", $mode == 3 ? $user : undef, 40).
	       "</td> </tr>\n";
	$st .= "<tr> <td>$text{'backup_skey'}</td> <td>".
	       &ui_password($name."_skey", $mode == 3 ? $pass : undef, 40).
	       "</td> </tr>\n";
	$st .= "<tr> <td>$text{'backup_s3file'}</td> <td>".
	       &ui_opt_textbox($name."_s3file", $mode == 3 ? $path : undef,
			       30, $text{'backup_nos3file'}).
	       "</td> </tr>\n";
	$st .= "</table>\n";
	push(@opts, [ 3, $text{'backup_mode3'}, $st ]);
	}

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

return &ui_table_start(undef, 2).
       &ui_table_row(undef, 
	&ui_radio_selector(\@opts, $name."_mode", $mode), 2).
       &ui_table_end();
}

# parse_backup_destination(name, &in, no-local, [&domain])
# Returns a backup destination string, or calls error
sub parse_backup_destination
{
local %in = %{$_[1]};
local $mode = $in{"$_[0]_mode"};
if ($mode == 0 && !$_[2]) {
	# Any local file
	$in{"$_[0]_file"} =~ /^\/\S/ || &error($text{'backup_edest'});
	$in{"$_[0]_file"} =~ s/\/+$//;	# No need for trailing /
	return $in{"$_[0]_file"};
	}
elsif ($mode == 0 && $_[2]) {
	# Local file under virtualmin-backup directory
	$in{"$_[0]_file"} =~ /^\S+$/ || &error($text{'backup_edest2'});
	$in{"$_[0]_file"} =~ /\.\./ && &error($text{'backup_edest3'});
	$in{"$_[0]_file"} =~ s/\/+$//;
	return "$_[3]->{'home'}/virtualmin-backup/".$in{"$_[0]_file"};
	}
elsif ($mode == 1) {
	# FTP server
	local ($server, $port) = split(/:/, $in{"$_[0]_server"});
	gethostbyname($server) || &error($text{'backup_eserver1'});
	$port =~ /^\d*$/ || &error($text{'backup_eport'});
	$in{"$_[0]_path"} =~ /^\/\S/ || &error($text{'backup_epath'});
	$in{"$_[0]_user"} =~ /^[^:\/]*$/ || &error($text{'backup_euser'});
	$in{"$_[0]_path"} =~ s/\/+$//;
	return "ftp://".$in{"$_[0]_user"}.":".$in{"$_[0]_pass"}."\@".
	       $in{"$_[0]_server"}.$in{"$_[0]_path"};
	}
elsif ($mode == 2) {
	# SSH server
	local ($server, $port) = split(/:/, $in{"$_[0]_sserver"});
	gethostbyname($server) || &error($text{'backup_eserver2'});
	$port =~ /^\d*$/ || &error($text{'backup_eport'});
	$in{"$_[0]_spath"} =~ /\S/ || &error($text{'backup_epath'});
	$in{"$_[0]_suser"} =~ /^[^:\/]*$/ || &error($text{'backup_euser2'});
	$in{"$_[0]_spath"} =~ s/\/+$//;
	return "ssh://".$in{"$_[0]_suser"}.":".$in{"$_[0]_spass"}."\@".
	       $in{"$_[0]_sserver"}.":".$in{"$_[0]_spath"};
	}
elsif ($mode == 3 && &can_use_s3()) {
	# Amazon S3 service
	local $cerr = &check_s3();
	$cerr && &error($cerr);
	$in{$_[0].'_bucket'} =~ /^\S+$/ || &error($text{'backup_ebucket'});
	$in{$_[0].'_akey'} =~ /^\S+$/i || &error($text{'backup_eakey'});
	$in{$_[0].'_skey'} =~ /^\S+$/i || &error($text{'backup_eskey'});
	$in{"$_[0]_s3file_def"} ||
		$in{"$_[0]_s3file"} =~ /^[a-z0-9\-\_\.]+$/i ||
		&error($text{'backup_euser'});
	return "s3://".$in{$_[0].'_akey'}.":".$in{$_[0].'_skey'}."\@".
	       $in{$_[0].'_bucket'}.
	       ($in{"$_[0]_s3file_def"} ? "" : "/".$in{"$_[0]_s3file"});
	}
elsif ($mode == 4) {
	# Just download
	return "download:";
	}
elsif ($mode == 5) {
	# Uploaded file
	$in{$_[0]."_upload"} || &error($text{'backup_eupload'});
	return "upload:";
	}
else {
	&error($text{'backup_emode'});
	}
}

# can_backup_sched([&sched])
# Returns 1 if the current user can create scheduled backups, or edit some
# existing schedule.
sub can_backup_sched
{
local ($sched) = @_;
if (&master_admin()) {
	# Master admin can do anything
	return 1;
	}
elsif (&reseller_admin()) {
	# Resellers can do their own domains
	}
else {
	# Regular users can only edit their own schedules
	return 0 if (!$access{'edit_sched'});
	if ($sched) {
		return 0 if (!$sched->{'owner'});	# Master admin's backup
		local $myd = &get_domain_by_user($base_remote_user);
		return 0 if (!$myd || $myd->{'id'} != $sched->{'owner'});
	}
	return 1;
	}
}

# Returns 1 if tar supports incremental backups
sub has_incremental_tar
{
local $out = &backquote_command("tar --help 2>&1 </dev/null");
return $out =~ /--listed-incremental/;
}

1;

