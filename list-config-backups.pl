#!/usr/local/bin/perl

=head1 list-config-backups.pl

Lists configuration file backups from Git

By default, this program operates on the entire F</etc/> directory. However,
you can limit which files it handles by specifying a single Webmin module with
the C<--module> flag or by selecting one or more files, directories or patterns
with the C<--file> flag, which must be relative to the module directory or F</etc/>.

=head2 Listing and viewing files

If you do not provide any additional options, the script defaults to showing
backups under the Virtualmin C<virtual-server> module configuration directory.

For example, to view all configuration files from the latest backup for the
Virtualmin C<virtual-server> module, run:

  virtualmin list-config-backups

To view the content of the last backup of the main configuration file for the
Virtualmin C<virtual-server> module, run:

  virtualmin list-config-backups --module virtual-server --file config

To see the last backup of all domain configuration files for the Virtualmin 
C<virtual-server> module, run:

  virtualmin list-config-backups --module virtual-server --file "domains/*"

By default, only the most recent backup is shown, but you can use the C<--depth>
flag to view more historic versions.

For example, to view the backups of the F</etc/hosts> and F</etc/fstab> files
from the last two backups, run:

  virtualmin list-config-backups --file hosts --file fstab --depth 2

=head2 Restricting by module or specific files

When the C<--module> flag is used, the script looks under F</etc/webmin/<module>>
directory by default. The C<--file> flag then refers to a subdirectory or file
under that module directory.

=head2 Options

=over 4

=item B<--depth <n>>

Number of recent backups to list. By default, 1 (the latest commit). Setting
this higher (like 5) includes older backups.

=item B<--file <path>>

A file or directory path to list. May be repeated for multiple paths.

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
	$0 = "$pwd/list-config-backups.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "list-config-backups.pl must be run as root";
	}

# Get /etc from environment
my $etcdir = $ENV{'WEBMIN_CONFIG'};
$etcdir =~ s/\/[^\/]+$//;

# Disable HTML output
&set_all_text_print();

# Parse command-line args
&parse_common_cli_flags(\@ARGV);

my $depth = 1;
my @module_files;
my $module;
my $git_repo = "$etcdir/.git";

while(@ARGV > 0) {
	my $a = shift(@ARGV);
	if ($a eq "--depth") {
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
&do_list(\@source_paths, $depth, $git_repo);
exit(0);

# usage(msg)
# Print usage message and exit
sub usage
{
my ($msg) = @_;
print "$msg\n\n" if ($msg);
print <<"EOF";
Lists configuration file backups from a Git repository in $etcdir/ directory.

virtualmin list-config-backups [--depth <n>]
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
		# Default to module config directory in list mode
		push(@outpaths, 'webmin/virtual-server');
		}
	elsif ($p =~ m|^\Q$etcdir\E/(.*)|) {
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

my @paths = &normalize_paths(@$paths);
my $depth_str = $depth > 1 ? "last $depth backups" : "latest backup";
&$first_print("Listing the following paths in the $depth_str:");
&$indent_print();
foreach my $pp (@$paths) {
	&$first_print("— $pp");
	}
&$outdent_print();

# Indent for the overall list operation
&$indent_print();

# Common Git prefix to specify the repo and work-tree
my $git_prefix = "git --git-dir=".quotemeta($git_repo)." --work-tree=$etcdir";

# For each path we want to list
foreach my $path (@paths) {
	my $original_path = ($path eq '.') ? $etcdir : "$etcdir/$path";
	my $type = (-d $original_path) ? "directory" : "file";

	# Build a command that returns up to the given number of commits
	my $pathspec = "':(glob)$path'";
	my $log_cmd = $depth > 0
		? "$git_prefix log -n $depth --format='%H' -- $pathspec"
		: "$git_prefix log --format='%H' -- $pathspec";

	# Run git log to find commits
	my $out;
	my $rs = &execute_command($log_cmd, undef, \$out);
	if ($rs != 0 || !$out) {
		&$first_print("No backups found for \"$original_path\" $type!");
		next;
		}

	my @commits = split(/\n/, $out);
	if (!@commits) {
		&$first_print("No backups found for \"$original_path\" $type!");
		next;
		}

	# Print an overview
	my $backups_text = scalar(@commits) == 1 ? "backup" : "backups";
	my $original_path_last = $original_path;
	$original_path_last =~ s/(.*)\///;
	my $original_path_dir = $1;
	&$first_print("Found ".scalar(@commits).
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
		my $path_wildcard = $path =~ /\*/;
		my $content_text = $path_wildcard ?
			"Files matching pattern" : "Content of the";
		&$first_print("$content_text \"$original_path_last\" $type as ".
				"of $date_out (\@$commit_short) ..");
		&$indent_print();

		# Check if path contains wildcard
		if ($path_wildcard) {
			# Get the directory part before the wildcard
			my $dir_part = $path;
			$dir_part =~ s/\/[^\/]*\*[^\/]*$//;
			
			# List directory contents matching the pattern
			my $ls_cmd = "$git_prefix ls-tree -r ".quotemeta($commit).
				" --name-only ".quotemeta($dir_part);
			my $ls_out;
			&execute_command($ls_cmd, undef, \$ls_out);
			
			# Filter the output to match the pattern
			my $pattern = $path;
			$pattern =~ s/\*/.*/g;  # Convert * to .* for regex
			
			# Display content for each matching file
			my @files = grep(/$pattern/, split(/\n/, $ls_out));
			
			foreach my $file (@files) {
				# Get the file content
				my $file_cat_cmd = "$git_prefix show ".
					quotemeta($commit).":$file";
				my $file_content;
				my $file_err;
				my $file_ec = &execute_command($file_cat_cmd, 
					undef, \$file_content, \$file_err);
				
				# Display the file name and content
				&$first_print("Content of the \"$file\" file ..");
				&$indent_print();
				
				if (!$file_ec) {
					my @lines = split(/\n/, $file_content);
					foreach my $line (@lines) {
						next if ($line =~ /^\s*$/);
						next if ($line =~ /^tree\s+[0-9a-fA-F]+\S*:\S+/);
						&$first_print($line);
						}
					&$first_print("[empty]") if (!@lines);
					}
				else {
					&$first_print("Failed to get file ".
						"content : $file_err");
					}
				
				&$outdent_print();
				&$first_print(".. end of file");
				}
			&$first_print("No files match the pattern") if (!@files);
			}
		else {
			# Original approach for non-wildcard paths
			$cat_cmd = "$git_prefix show ".quotemeta($commit).":".
				quotemeta($path);
			my $catout;
			my $caterr;
			my $catec = &execute_command($cat_cmd, undef,
				\$catout, \$caterr);
		
			if (!$catec) {
				# Print the file contents with deeper indentation
				my @lines = split(/\n/, $catout);
				foreach my $line (@lines) {
					next if ($line =~ /^\s*$/);
					next if ($line =~ /^tree\s+[0-9a-fA-F]+\S*:\S+/);
					&$first_print($line);
					}
				&$first_print("[empty]") if (!@lines);
				}
			else {
				&$first_print("Error : Failed to list $type ".
					"content : $caterr");
				}
			}

		&$outdent_print();
		my $end_text = $path_wildcard ? "end of pattern" : "end of $type";
		&$first_print(".. $end_text");
		}

	&$outdent_print();
	}

&$outdent_print();
&$first_print(".. done");
}

1;
