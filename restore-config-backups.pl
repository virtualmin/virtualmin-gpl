#!/usr/local/bin/perl

=head1 restore-config-backups.pl

Restores configuration file backups from Git

By default, this program operates on the entire F</etc/> directory. However,
you can limit which files it handles by specifying a single Webmin module with
the C<--module> flag or by selecting one or more files or directories via the
C<--file> flag, which must be relative to the module directory or F</etc/>.

=head2 Restoring files

To restore files to your filesystem, use the C<--target> flag. This retrieves
all matching files from the most recent backups, as controlled by the C<--depth>
flag, and writes them into date-stamped directories. This allows you to browse
or compare multiple saved versions simultaneously, without overwriting your
current system configuration.

For example, to restore all module configuration files from the latest backup
to the F</root/backups> directory, run:

  virtualmin restore-config-backups --module virtual-server --target /root/backups

You can also restore files directly to the F</etc/> directory, overwriting the
live system configuration if needed, which can be helpful for quickly reverting
to a previous state of a module or a single configuration file.

For example, to restore both the main module config file and all domain config 
files from the latest backup directly to the live system, run:

  virtualmin restore-config-backups --module virtual-server --file config \
                                    --file domains --target /etc/

To simulate (dry run) restoring the last five versions of the main module config
file into a target directory, add the C<--dry-run> flag:

  virtualmin restore-config-backups --depth 5 --module virtual-server \
                                    --file config --target /root/backups --dry-run

When the target directory is set to F</etc/> and C<--depth> is used, only the
files from the oldest (deepest) record will be restored. For example, to restore
the main module config file from ten backups ago directly to the live system,
run:

  virtualmin restore-config-backups --depth 10 --module virtual-server \
                                    --file config --target /etc/

=head2 Restricting by module or specific files

When the C<--module> flag is used, the script looks under F</etc/webmin/<module>>
directory by default. The C<--file> flag then refers to a subdirectory or file
under that module directory.

=head2 Options

=over 4

=item B<--target <dir>>

Required flag. Directory where restored files should be written. Created if it
does not exist. If set to F</etc/>, files will be restored directly into the
live system without being placed in a date-stamped subdirectory.

=item B<--dry-run>

Simulate the restore without actually writing files. Useful for testing.

=item B<--depth <n>>

Number of recent backups to restore. By default, 1 (the latest commit). Setting
this higher, like 5, includes older backups.

=item B<--file <path>>

A file or directory path to restore. May be repeated for multiple paths.

=item B<--module <name>>

Restrict operations to a Webmin module under F</etc/webmin/> (for example,
C<virtual-server> or C<fsdump>).

=item B<--git-repo <path>>

Specifies which Git repository to use. Defaults to F</etc/.git/>.

=back

=cut

package virtual_server;

# If not loaded by Webmin, do standard Virtualmin environment prep
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*)\/[^\/]+$/) {
		chdir($pwd = $1);
		}
	else {
		chop($pwd = `pwd`);
		}
	$0 = "$pwd/restore-config-backups.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "restore-config-backups.pl must be run as root";
	}

# Get /etc from environment
my $etcdir = $ENV{'WEBMIN_CONFIG'};
$etcdir =~ s/\/[^\/]+$//;

# Disable HTML output
&set_all_text_print();

# Parse command-line args
&parse_common_cli_flags(\@ARGV);

my $target_dir;
my $dry_run;
my $depth = 1;
my @module_files;
my $module;
my $git_repo = "$etcdir/.git";

while(@ARGV > 0) {
	my $a = shift(@ARGV);
	if ($a eq "--target") {
		$target_dir = shift(@ARGV) ||
			&usage("Missing directory after --target");
		$target_dir =~ s|/+$||;
		}
	elsif ($a eq "--dry-run") {
		$dry_run = 1;
		}
	elsif ($a eq "--depth") {
		$depth = shift(@ARGV) ||
			&usage("Missing numeric value after --depth");
		$depth =~ /^\d+$/ ||
			&usage("--depth must be numeric value greater than zero");
		}
	elsif ($a eq "--file") {
		my $f = shift(@ARGV) ||
			&usage("Missing file/directory name after --file");
		push(@module_files, $f);
		}
	elsif ($a eq "--module") {
		$module = shift(@ARGV) ||
			&usage("Missing module name after --module");
		}
	elsif ($a eq "--git-repo") {
		$git_repo = shift(@ARGV) || &usage("Missing path after --git-repo");
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# Require --target
if (!$target_dir) {
	&usage("For restore to work --target <dir> must be specified");
}

# Check that Git repo directory exists
&usage("Git repository not found in $git_repo") if (!-d $git_repo);

# Figure out which source paths we are looking at
my @source_paths;
if ($module) {
	my $base = "$ENV{'WEBMIN_CONFIG'}/$module";
	if (@module_files) {
		# Combine /etc/webmin/<module> + each file/dir
		foreach my $mf (@module_files) {
			push(@source_paths, "$base/$mf");
			}
		}
	else {
		# Just the base module directory
		push(@source_paths, $base);
		}
	}
else {
	# If no module, but we de have --file, treat them as absolute
	if (@module_files) {
		foreach my $mf (@module_files) {
			$mf = "$etcdir/$mf" if ($mf !~ m|^/|);
			push(@source_paths, $mf);
			}
		}
	else {
		@source_paths = ($etcdir);
		}
	}

# Main logic
&do_restore(\@source_paths, $depth, $git_repo, $target_dir, $dry_run);
exit(0);

# usage(msg)
# Print usage message and exit
sub usage
{
my ($msg) = @_;
print "$msg\n\n" if ($msg);
print <<"EOF";
Restores configuration file backups from a Git repository in $etcdir/ directory.

virtualmin restore-config-backups --target <dir> [--dry-run]
                                  [--depth <n>]
                                  [--file file]*
                                  [--module module]
                                  [--git-repo </path/to/.git>]
EOF
exit(1);
}

# normalize_paths(@paths)
# Converts paths to the format used by Git repository.
sub normalize_paths
{
my (@inpaths) = @_;
my @outpaths;
foreach my $p (@inpaths) {
	if ($p eq $etcdir) {
		# Restore everything under /etc/
		push(@outpaths, '.');
		}
	elsif ($p =~ m|^\Q$etcdir\E/(.*)|) {
		# e.g. /etc/webmin/virtual-server => webmin/virtual-server
		push(@outpaths, $1);
		}
	}
return @outpaths;
}

# do_restore(\@paths, depth, git_repo, target_dir, dry_run)
# Restores the specified paths
sub do_restore
{
my ($paths, $depth, $git_repo, $target_dir, $dry_run) = @_;

# Print the restore operation header
my $restore_text = $dry_run ? "Imitating restore to the directory:" :
			      "Restoring to the directory:";
my $dry_run_txt = $dry_run ? " (dry-run)" : "";
&$first_print($restore_text);
&$indent_print();
&$first_print("— $target_dir");

# Create the target directory
&make_dir($target_dir, 0755, 1) if (!$dry_run && !-d $target_dir);

# Normalize paths
my @rel_paths = &normalize_paths(@$paths);

# Prepare the Git command prefix
my $git_prefix = "git --git-dir=".quotemeta($git_repo)." --work-tree=$etcdir";

# For each path to restore
foreach my $relp (@rel_paths) {
	my $display_path = ($relp eq '.') ? $etcdir : "$etcdir/$relp";
	my $display_path_last = $display_path;
	$display_path_last =~ s/.*\///;

	# Attempt to match do_list style printing
	my $type = (-d $display_path) ? "directory" : "file";

	# Get up to $depth commits for this path
	my $log_cmd = $depth > 0
		? "$git_prefix log -n $depth --format='%H' -- ".quotemeta($relp)
		: "$git_prefix log --format='%H' -- ".quotemeta($relp);

	my $out;
	my $rs = &execute_command($log_cmd, undef, \$out);
	if ($rs != 0 || !$out) {
		&$first_print("No backups found for \"$display_path_last\" $type!");
		next;
		}

	my @commits = split(/\n/, $out);
	if (!@commits) {
		&$first_print("No backups found for \"$display_path_last\" $type!");
		next;
		}

	# If --target is /etc, restore only the oldest commit
	my @use_commits = @commits;
	my $latest_commit = "";
	if ($target_dir eq $etcdir && @commits > 1) {
		# The commits array is newest first. The oldest is at the end.
		@use_commits = ( $commits[-1] );
		$latest_commit = ", yet only the oldest one at depth $depth is used";
		}
	
	# Print an overview (like do_list)
	my $backups_text = scalar(@commits) == 1 ? "backup" : "backups";
	&$first_print("Found ".scalar(@commits)." $backups_text$latest_commit ..");

	&$indent_print();

	# Iterate over the chosen commits
	foreach my $commit (@use_commits) {
		# Get the commit date
		my $date_cmd = "$git_prefix show -s --format='%cd' --date=format:".
			       "'%Y-%m-%d %H:%M:%S' ".quotemeta($commit);
		my $date_out;
		&execute_command($date_cmd, undef, \$date_out);
		chomp($date_out);
		my $date_out_path = $date_out;
		$date_out_path =~ s/ /-/g;
		$date_out_path =~ s/:/-/g;
		my $commit_short = substr($commit, 0, 7);

		# If target_dir is /etc, do not create date subdir
		my $dest_dir = $target_dir;
		if ($target_dir ne $etcdir) {
			$dest_dir .= "/$date_out_path";
			if (!$dry_run && !-d $dest_dir) {
				mkdir($dest_dir, 0755) ||
					die "Could not create $dest_dir: $!";
				}
			}

		# List all files in this commit that match $relp
		my $list_cmd = "$git_prefix ls-tree -r ".quotemeta($commit).
			       " --name-only ".quotemeta($relp);
		my $list_out;
		my $list_err;
		my $rs = &execute_command($list_cmd, undef, \$list_out, \$list_err, 0, 1);
		if ($rs != 0) {
			&$first_print("Failed to list files for commit ".
				      "$commit_short: $list_err");
			next;
			}

		my @files = split(/\n/, $list_out);
		if (!@files) {
			&$first_print("No tracked files in commit $commit_short ".
				      "for $display_path");
			next;
			}

		my $file_text = scalar(@files) == 1 ? "file" : "files";
		&$first_print("Found ".scalar(@files)." $file_text to restore ".
			"from backup \@$commit_short dated $date_out to ..");
		&$indent_print();

		# Extract or imitate each file
		foreach my $f (@files) {
			my $target_full = "$dest_dir/$f";
			if ($dry_run) {
				&$first_print("=> $target_full");
				}
			else {
				# Recursively create subdirectories
				my ($subdir) = $f =~ m|^(.*)/[^/]+$|;
				if ($subdir) {
					my @parts = split('/', $subdir);
					my $path_accum = $dest_dir;
					foreach my $p (@parts) {
						$path_accum .= "/$p";
						&make_dir($path_accum, 0755, 1)
							if (!-d $path_accum);
						}
					}

				# Retrieve file content from Git
				my $show_cmd = "$git_prefix show ".
					quotemeta($commit).":".quotemeta($f);
				my $content;
				my $show_err;
				my $rs = &execute_command($show_cmd, undef,
					\$content, \$show_err, 0, 1);
				if ($rs == 0) {
					&write_file_contents($target_full, $content);
					&$first_print("=> $target_full");
					}
				else {
					&$first_print("Failed to extract $f ".
						"from commit \@$commit_short : $show_err");
					}
				}
			}
		&$outdent_print();
		&$first_print(".. restored$dry_run_txt");
		}

	&$outdent_print();
	}

&$outdent_print();
&$first_print(".. done");
}

1;
