#!/usr/local/bin/perl

=head1 config-backups.pl

Manages configuration file backups using a Git repository (often provided by
Etckeeper) in F</etc/.git/>. This script can either list and view backed-up
config files, or restore them to a specified directory.

By default, the script will operate on the entire F</etc/> directory. However,
you can limit which files it handles by specifying a single Webmin module with
the C<--module> flag, or by selecting one or more files or directories via the
C<--file> flag which can be relative to the module or F</etc/>.

=head2 Listing and viewing files

To view the contents of backed-up configuration files, use the C<--list> flag. If
you do not provide any additional options with C<--list>, the script defaults to
showing backups under the Virtualmin C<virtual-server> module configuration
directory.

By default, only the most recent backup is shown, but you can use the
C<--depth> flag to view more historic versions.

For example, to view the backups of the F</etc/hosts> and F</etc/fstab> files
from the last two backups, run:

  virtualmin config-backups --list --file hosts --file fstab --depth 2

To view the last backup of the main configuration file for the Virtualmin 
C<virtual-server> module, run:

  virtualmin config-backups --list --module virtual-server --file config

To see the last backup of all domain configuration files for the Virtualmin 
C<virtual-server> module, run:

  virtualmin config-backups --list --module virtual-server --file domains

After the domain configs are listed, you'll see the file name for each one. To
view the content of a specific domain config file, run:

  virtualmin config-backups --list --module virtual-server --file domains/0123456789

=head2 Restoring files

To restore files to your filesystem, use the C<--restore> flag along with
C<--target-dir>. This mode retrieves all matching files from the specified number
of recent backups, controlled by C<--depth>, and writes them to directories
organized by backup date. This lets you browse or compare multiple saved versions
at once, without overwriting your live system configuration, unless you
specifically restore them directly to F</etc/> directory.

For example, to restore the latest backup of the main configuration file to the
live system, run:

  virtualmin config-backups --restore --module virtual-server --file config \
			    --target-dir /etc/

To restore all domain config files from the latest backup to the live system, run:

  virtualmin config-backups --restore --module virtual-server --file domains \
			    --target-dir /etc/

To restore all module configuration files from the last three backups to the
directory F</root/backups>, run:

  virtualmin config-backups --restore --module virtual-server --depth 3 \
			    --target-dir /root/backups

To imitate restoring the last five versions of the main configuration file into
a specified directory use the C<--dry-run> flag:

  virtualmin config-backups --restore --module virtual-server --file config \
                            --depth 5 --target-dir /root/backups --dry-run

=head2 Restricting by module or specific files

When the C<--module> flag is used, the script looks under F</etc/webmin/<module>>
directory by default. The C<--file> flag then refers to a subdirectory or file
under that module directory. If C<--module> is omitted, any paths passed via
C<--file> should be under F</etc/>, or else they will be prefixed automatically
q(for example, C<--file hosts> becomes F</etc/hosts>).

=head2 Options

=over 4

=item B<--module <name>>

Restrict operations to a Webmin module under F</etc/webmin/>. For example,
C<virtual-server> or C<fsdump>.

=item B<--file <path>>

A file or directory path to process. May be repeated for multiple paths.

=item B<--depth <n>>

Limit how many recent backups to list or restore. By default, 1 (the latest
commit). Setting this higher, like 5, includes older backups too.

=item B<--target-dir <dir>>

Where restored files should be placed. This directory will be created if it does
not exist. This option is required for C<--restore> mode. Beware, if the target
directory is set to F</etc/>, files will be restored directly to the live system
without being placed in a date-stamped subdirectory. Additionally, when the
directory is set to F</etc/> and C<--depth> is used, only the files from the
oldest (deepest) commit will be restored.

=item B<--dry-run>

Simulate the restore without actually writing files. Useful to see what would
be changed. Ignored in C<--list> mode.

=item B<--git-repo <path>>

Specifies which Git repository to use. By default, it is F</etc/.git/>.

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
	$0 = "$pwd/list-users.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "config-backups.pl must be run as root";
	}

# Disable HTML output
&set_all_text_print();

# Parse command-line args
&parse_common_cli_flags(\@ARGV);

my $restore_mode;
my $list_mode;
my $module;
my @module_files;
my $depth = 1;
my $target_dir;
my $dry_run;
my $git_repo = "/etc/.git";

while(@ARGV > 0) {
	my $a = shift(@ARGV);
	if ($a eq "--list") {
		$list_mode = 1;
		}
	elsif ($a eq "--restore") {
		$restore_mode = 1;
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
	elsif ($a eq "--depth") {
		$depth = shift(@ARGV) ||
			&usage("Missing numeric value after --depth");
		$depth =~ /^\d+$/ || &usage("--depth must be numeric");
		}
	elsif ($a eq "--target-dir") {
		$target_dir = shift(@ARGV) ||
			&usage("Missing directory after --target-dir");
		$target_dir =~ s|/+$||;
		}
	elsif ($a eq "--dry-run") {
		$dry_run = 1;
		}
	elsif ($a eq "--git-repo") {
		$git_repo = shift(@ARGV) || &usage("Missing path after --git-repo");
		}
	else {
		&usage("Unknown parameter $a");
		}
	}

# If restoring, require --target-dir
&usage("For restore, you must specify --target-dir <dir>")
	if ($restore_mode && !$target_dir);

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
			$mf = "/etc/$mf" if ($mf !~ m|^/|);
			push(@source_paths, $mf);
			}
		}
	else {
		@source_paths = ("/etc");
		}
	}

# Main logic
&do_list(\@source_paths, $depth, $git_repo) if ($list_mode);
&do_restore(\@source_paths, $depth, $git_repo, $target_dir, $dry_run)
	if ($restore_mode);
exit(0);

# usage(msg)
# Print usage message and exit
sub usage
{
my ($msg) = @_;
print "$msg\n\n" if ($msg);
print <<'EOF';
Manage configuration file backups from a Git repository in /etc. Supports
viewing file contents in list mode or restoring them in restore mode.

virtualmin config-backups --list | --restore [--dry-run]
                          [--file file]*
                          [--module module]*
                          [--depth <n>] [--target-dir <dir>]
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
	if ($p eq '/etc') {
		if ($list_mode) {
			# Default to module config directory in list mode
			push(@outpaths, 'webmin/virtual-server');
			}
		else {
			# Restore everything under /etc/
			push(@outpaths, '.');
			}
		}
	elsif ($p =~ m|^/etc/(.*)|) {
		# e.g. /etc/webmin/virtual-server => webmin/virtual-server
		push(@outpaths, $1);
		}
	}
return @outpaths;
}

# do_list(\@paths, depth, git_repo)
# Shows file contents from Git for the given paths, for one or more backups.
sub do_list
{
my ($paths, $depth, $git_repo) = @_;

my @rel_paths = &normalize_paths(@$paths);
my $depth_str = $depth > 1 ? "last $depth backups" : "latest backup";
&$first_print("Preview mode for the following paths in the $depth_str:");
&$indent_print();
foreach my $pp (@$paths) {
	&$first_print("— $pp");
	}
&$first_print();
&$outdent_print();

# Indent for the overall list operation
&$indent_print();

# Common Git prefix to specify the repo and work-tree
my $git_prefix = "git --git-dir=".quotemeta($git_repo)." --work-tree=/etc";

# For each path we want to list
foreach my $relp (@rel_paths) {
	my $original_path = ($relp eq '.') ? '/etc' : "/etc/$relp";
	my $type = (-d $original_path) ? "directory" : "file";

	# Build a command that returns up to number of commits
	my $log_cmd = $depth > 0
		? "$git_prefix log -n $depth --format='%H' -- ".quotemeta($relp)
		: "$git_prefix log --format='%H' -- ".quotemeta($relp);


	# Run git log to find commits
	my $out;
	my $rs = &execute_command($log_cmd, undef, \$out);
	if ($rs != 0 || !$out) {
		&$second_print("No commits found for $original_path $type!");
		next;
		}

	my @commits = split(/\n/, $out);
	if (!@commits) {
		&$second_print("No commits found for $original_path $type!");
		next;
		}

	# Print an overview
	my $backups_text = scalar(@commits) == 1 ? "backup" : "backups";
	my $original_path_last = $original_path;
	$original_path_last =~ s/(.*)\///;
	my $original_path_dir = $1;
	&$second_print("Found ".scalar(@commits).
		" $backups_text in \"$original_path_dir\" directory ..");

	# Increase indentation for commits
	&$indent_print();

	# Iterate over each commit (newest first as returned by git log)
	foreach my $commit (@commits) {
		my $commit_short = substr($commit, 0, 7);
		my $date_cmd = "$git_prefix show -s --format='%cd' --date=format:".
			       "'%Y-%m-%d %H:%M:%S' ".quotemeta($commit);
		my $date_out;
		&execute_command($date_cmd, undef, \$date_out);
		chomp($date_out);
		&$first_print("Content of the \"$original_path_last\" $type as ".
			      "of $date_out (\@$commit_short) ..");
		&$indent_print();

		# Construct command to show the file contents
		my $cat_cmd = "$git_prefix show ".quotemeta($commit).":".
			quotemeta($relp);
		my $catout;
		my $caterr;
		my $catec = &execute_command($cat_cmd, undef, \$catout, \$caterr);
		
		if (!$catec) {
			# Print the file contents with deeper indentation
			my @lines = split(/\n/, $catout);
			if (@lines) {
				foreach my $line (@lines) {
					next if ($line =~ /^\s*$/);
					next if ($line =~ /^tree\s+[0-9a-fA-F]+\S*:\S+/);
					&$first_print($line);
					}
				}
			else {
				&$first_print("[empty]");
				}
			}
		else {
			&$first_print("Error : Failed to cat $type content : $caterr");
			}

		&$outdent_print();
		&$second_print(".. end of $type content");
		}

	&$outdent_print();
	}

&$outdent_print();
&$first_print(".. done");
}

# do_restore(\@paths, depth, git_repo, target_dir, dry_run)
# Restores the specified paths
sub do_restore
{
my ($paths, $depth, $git_repo, $target_dir, $dry_run) = @_;

# Print the restore operation header
my $dry_run_text = $dry_run ? "dry-run" : "direct write";
&$first_print("Restore process is running in $dry_run_text mode to the directory:");
&$indent_print();
&$first_print("— $target_dir");

# Create the target directory
&make_dir($target_dir, 0755, 1) if (!$dry_run && !-d $target_dir);

# Normalize paths
my @rel_paths = &normalize_paths(@$paths);

# Prepare the Git command prefix
my $git_prefix = "git --git-dir=".quotemeta($git_repo)." --work-tree=/etc";

# For each path to restore
foreach my $relp (@rel_paths) {
	my $display_path = ($relp eq '.') ? '/etc' : "/etc/$relp";
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
		&$first_print();
		&$first_print("No commits found for \"$display_path_last\" $type!");
		&$outdent_print();
		next;
		}

	my @commits = split(/\n/, $out);
	if (!@commits) {
		&$first_print();
		&$first_print("No commits found for \"$display_path_last\" $type!");
		&$outdent_print();
		next;
		}

	# If --target-dir is /etc, restore only the oldest commit
	my @use_commits = @commits;
	my $latest_commit = "";
	if ($target_dir eq '/etc' && @commits > 1) {
		# The commits array is newest first. The oldest is at the end.
		@use_commits = ( $commits[-1] );
		$latest_commit = ", however using only oldest backup in the given depth";
		}
	
	# Print an overview (like do_list)
	&$first_print();
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
		if ($target_dir ne '/etc') {
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
		&$first_print("Found ".scalar(@files)." $file_text to be restored ".
			"from this backup dated $date_out (\@$commit_short) ..");
		&$indent_print();

		# Extract or imitate each file
		foreach my $f (@files) {
			my $target_full = "$dest_dir/$f";
			if ($dry_run) {
				&$first_print("Restored $target_full (dry-run)");
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
					&$first_print($target_full);
					}
				else {
					&$second_print("Failed to extract $f ".
						"from commit \@$commit_short : $show_err");
					}
				}
			}

		&$outdent_print();
		}

	&$outdent_print();
	}

&$outdent_print();
&$first_print();
if (!$dry_run) {
	&$first_print(".. restored") unless ();
	}
else {
	&$first_print(".. imitated (dry-run)");
	}
}

1;
