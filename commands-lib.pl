# Functions for use by the command-line API

our ($convert_multiline, $convert_idonly, $convert_nameonly, $convert_emailonly,
     $convert_format);

sub list_api_categories
{
return ([ "Backup and restore", "backup-domain.pl", "*-scheduled-backup*.pl",
				"restore-domain.pl", "list-backup-keys.pl" ],
	[ "Virtual servers", "*-domain.pl", "*-domains.pl",
			     "enable-feature.pl", "disable-feature.pl",
			     "modify-dns.pl", "modify-spam.pl", "modify-web.pl",
			     "modify-mail.pl", "resend-email.pl" ],
	[ "Mail and FTP users", "*-user.pl", "*-users.pl",
				"list-available-shells.pl",
				"list-mailbox.pl" ],
	[ "Mail aliases", "*-alias.pl", "*-aliases.pl" ],
	[ "Server owner limits", "*-limit.pl", "*-limits.pl",
				 "modify-resources.pl" ],
	[ "Extra administrators", "*-admin.pl", "*-admins.pl" ],
	[ "Custom fields", "*-custom.pl" ],
	[ "Databases", "*-database.pl", "*-databases.pl",
		       "modify-database-hosts.pl" ],
	[ "Reseller accounts", "*-reseller.pl", "*-resellers.pl" ],
	[ "Script installers", "install-script.pl", "delete-script.pl",
			       "list-scripts.pl", "list-available-scripts.pl" ],
	[ "Proxies and balancers", "*-proxy.pl", "*-proxies.pl" ],
	[ "PHP versions", "*-php-directory.pl", "*-php-directories.pl" ],
	[ "SSL certificates", "list-certs.pl", "*-cert.pl" ],
	[ "Virtual server templates", "*-template.pl", "*-templates.pl" ],
	[ "Account plans", "*-plan.pl", "*-plans.pl" ],
	[ "SVN repositories", "*-svn-repositor*.pl" ],
	[ "Amazon S3", "*-s3-*.pl", "*-rs-*.pl" ],
	[ "License", "*license*" ],
	[ "Repository", "*setup-repos*" ],
	[ "Other scripts", "*.pl" ],
	);
}

sub list_api_category_descs
{
return (
"Virtual servers",
"Probably the most important programs are those for creating, listing,
modifying and deleting virtual servers. Because these actions may involve
several steps, all of these programs output messages as the proceed, showing
the success or failure of each step. These programs and their options are
documented below.",

"Backup and restore",
"Virtualmin has the ability to backup and restore virtual servers either
manually or on a set schedule, using the web interface. However, you can also
use the command line programs listed below to make backups. This can be used
for doing your own migration to other systems or products, or manually setting
up custom backup schedules for different servers.",

"Mail and FTP users",
"Each Virtualmin virtual server can have users associated with it, each of
which can be a mailbox, an FTP login, or a database user. Users can be created a
ny managed from the command line, using the programs described below.",

"Mail aliases",
"Virtual servers with email enabled can have mail aliases associated with them,
to forward email either to users within the server, or to addresses at some
other domain. Aliases can also be set up to deliver mail to files, or feed
them to programs as input. The programs in this section allow you to manage
mail aliases from the command line.",

"Custom fields",
"If your Virtualmin install has been configured to allow additional custom
fields to be stored for each virtual server, the programs listed in this
section can also be used to manage those fields.",

"Databases",
"All Virtualmin virtual servers with database features enabled can have several
MySQL and PostgreSQL databases associated with them. These can be created and
deleted from the web interface, or using the following programs.",

"Extra administrators",
"All Virtualmin virtual servers can have additional administration accounts
created, which are similar to the server administrator Webmin login, but
possibly with limited capabilities. These extra admin accounts can be
created and managed using the following programs.",

"Reseller accounts",
"If your Virtualmin site uses resellers, they can also be managed using the
command-line programs documented in this section. All of the reseller options
that can be set through the web interface can also be controlled from the
Unix shell prompt.",

"Script installers",
"Virtualmin allows scripts created by other developers to be easily installed
into the virtual servers that it manages. These are typically programs like
Wikis, Blogs and web-based mail readers, often written in PHP. Normally these
are setup through the web interface, but they can be managed by the following
command-line programs as well.",

"Proxies and balancers",
"A proxy maps some URL on a virtual server to another webserver. This means
that requests for any page under that URL path will be forwarded to the
other site, which could be a separate machine or another webserver process
on the same system (such as Tomcat for Java or Mongrel for Ruby on Rails).",

"PHP versions",
"If more than one version of PHP is installed on your system and either CGI
or fCGId is used to run PHP scripts in some virtual server, it can be configured
to run a different PHP version on a per-directory basis. This is most useful
when running PHP applications that only support specific versions, like an
old script that only runs under version 4.",

"SSL certificates",
"Commands in this section can be used to list SSL certificates, generate
new certs, keys and signing requests, and install a signed cert from a CA.",

"Virtual server templates",
"These commands can be list to list, create and modify Virtualmin templates,
which in turn define the initial configuration for virtual servers.",

"Account plans",
"Plans define the quota, allowed functions and other limits on virtual server
owners. These commands can be used to list existing plans, modify their
limits, create new plans, and delete them.",

"SVN repositories",
"For virtual serves with the SVN plugin enabled, these commands can be used
to list, create and delete SVN repositories.",

"Amazon S3",
"These commands can be used to upload files to, download files from and
manage files on Amazon's S3 cloud storage service.",

"License",
"These commands are used to list Virtualmin license info, change license or
downgrade to GPL.",

"Other scripts",
"Programs in this section don't fall into any of the other categories.",
	);
}

sub list_api_skip_scripts
{
return ( "upload-api-docs.pl",
	 "functional-test.pl",
	 "generate-script-sites.pl",
	 "check-scripts.pl",
	 "fetch-script-files.pl",
	 "postinstall.pl",
	 );
}

# list_api_directories(pwd)
# Returns a list of directories to check for API scripts
sub list_api_directories
{
local ($pwd) = @_;
local $par = $pwd;
$par =~ s/\/([^\/]+)$//;
return ( $pwd, glob("$par/virtualmin-*") );
}

# get_api_helper_command()
# Returns the path to the API wrapper command
sub get_api_helper_command
{
if ($config{'api_helper'}) {
	return $config{'api_helper'};
	}
else {
	# Try some directories for writing
	foreach my $dir ("/usr/sbin", "/usr/local/sbin", "/opt/csw/bin") {
		-d $dir || next;
		open(APIWRAPPERTEST, ">$dir/.virtualmin-test") || next;
		close(APIWRAPPERTEST);
		unlink("$dir/.virtualmin-test");
		return "$dir/virtualmin";
		}
	return undef;
	}
}

# create_api_helper_command([&extra-dirs])
# Creates the API helper command. Returns either 1 and the path, or 0 and
# an error message.
sub create_api_helper_command
{
local ($extradirs) = @_;
local @dirs = ( $module_root_directory );
push(@dirs, @$extradirs) if ($extradirs);
local $dirstr = join(" ", @dirs);
local $api_helper_command = &get_api_helper_command();
if (!$api_helper_command) {
	return (0, "No writable path configured or auto-detected");
	}
local $bash = &has_command("bash") || &has_command("sh");
if ($bash) {
	&open_tempfile(HELPER, ">$api_helper_command", 1, 0) ||
		return (0, "Failed to write to $api_helper_command : $!");
	&print_tempfile(HELPER, <<EOF);
#!$bash
WEBMIN_CONFIG=$config_directory
WEBMIN_VAR=$var_directory
PERLLIB=${root_directory}:${root_directory}/vendor_perl
WRAPPER_ORIGINAL_PWD=`pwd`
unset SCRIPT_NAME
unset FOREIGN_MODULE_NAME
unset SERVER_ROOT
unset SCRIPT_FILENAME
export WEBMIN_CONFIG WEBMIN_VAR PERLLIB SCRIPT_NAME FOREIGN_MODULE_NAME SERVER_ROOT SCRIPT_FILENAME WRAPPER_ORIGINAL_PWD
cd $module_root_directory
id -a | grep -i uid=0 >/dev/null
if [ "\$?" != 0 ]; then
	echo "$api_helper_command must be run as root"
	exit 2
fi
if [ "\$1" = "" -o "\$1" = "help" -a "\$2" = "" -o "\$1" = "--help" -a "\$2" = "" -o "\$1" = "-help" -a "\$2" = "" ]; then
	echo "usage: $api_helper_command <command> [args..]"
	echo "   or: $api_helper_command help <command>"
	echo ""
	echo "Available commands :"
	echo ""
	COMMAND=list-commands
else
	COMMAND=\$1
	COMMANDINITIAL=\$COMMAND
fi
shift
if [ "\$COMMAND" = "help" ]; then
	help=1
	COMMAND=\$1
	shift
fi
echo \$COMMAND | fgrep .pl >/dev/null
if [ "\$?" != "0" ]; then
	COMMAND="\$COMMAND.pl"
fi
for dir in $dirstr; do
	if [ -x "\$dir/\$COMMAND" ]; then
		if [ "\$help" = "1" ]; then
			exec perldoc \$dir/\$COMMAND
		else
			if [[ "\$@" == "--help" ]]; then
				echo "See \\`virtualmin help \$COMMANDINITIAL\\` for more details and examples"
				echo ""
			fi
			exec \$dir/\$COMMAND "\$@"
		fi
	fi
done
echo Command \$COMMAND was not found
exit 1
EOF
	&close_tempfile(HELPER);
	&set_ownership_permissions(undef, undef, 0755, $api_helper_command);
	return (1, $api_helper_command);
	}
else {
	return (0, "bash was not found");
	}
}

# parse_common_cli_flags(&argv)
# Parses and updates the provided argv, and sets global variables $multiline,
# $idonly, $nameonly. May also start capturing output for XML and JSON.
sub parse_common_cli_flags
{
my ($argv) = @_;
my $i = 0;
while($i < @$argv) {
	if ($argv->[$i] eq "--multiline") {
		$convert_multiline = $multiline = 1;
		splice(@$argv, $i, 1);
		}
	elsif ($argv->[$i] eq "--simple-multiline") {
		$convert_multiline = $multiline = 2;
		splice(@$argv, $i, 1);
		}
	elsif ($argv->[$i] eq "--id-only") {
		$convert_idonly = $idonly = 1;
		splice(@$argv, $i, 1);
		}
	elsif ($argv->[$i] eq "--name-only") {
		$convert_nameonly = $nameonly = 1;
		splice(@$argv, $i, 1);
		}
	elsif ($argv->[$i] eq "--email-only") {
		$convert_emailonly = $emailonly = 1;
		splice(@$argv, $i, 1);
		}
	elsif ($argv->[$i] =~ /^--(xml|json)$/) {
		&cli_convert_remote_format($1);
		$convert_format = $1;
		splice(@$argv, $i, 1);
		if (!$multiline && !$idonly && !$nameonly && !$emailonly) {
			$convert_multiline = $multiline = 1;
			}
		}
	elsif ($argv->[$i] eq "--help") {
		&usage();
		}
	else {
		$i++;
		}
	}
}

# extract_params_from_usage()
# Extracts a hash of command-line parameters (flags) from the output of the
# usage() function of the current sub-program. This function captures the output
# of usage(), scans for parameters prefixed with '--', and determines whether
# each parameter requires a value and whether it can be specified multiple times
# (indicated by '*'). The function returns a hash where each key is a parameter
# name (without '--'), and the value indicates:
#
# - 0: Parameter does not require a value.
# - 1: Parameter requires a value.
# - 2: Parameter requires a value and can be specified multiple times (indicated
#   by '*').
#
# The function handles the capturing of usage output through a forked process
# and pipes, allowing it to process the output of the usage() function that
# prints to STDOUT.
sub extract_params_from_usage
{
my ($usage) = @_;
my $lines = q{};
# Capture the output of the usage subroutine
pipe(my $reader, my $writer) || die("Cannot extract parameters from usage: $!");
my $pid = fork();
die "Fork failed: $!" unless defined($pid);
if ($pid == 0) {
	# Child process
	close($reader);
	open(STDOUT, '>&', $writer) || die("Can't redirect STDOUT: $!");
	close($writer);
	$usage->();
	# Ensure child process exits
	exit(0);
	}
# Parent process
close($writer);
while (my $line = <$reader>) {
	$lines .= $line;
	}
close($reader);
waitpid($pid, 0);
# Parse the usage output and extract parameters
my %params;
my @lines = split(/\n/, $lines);
foreach my $line (@lines) {
	# Remove leading and trailing whitespace
	$line =~ s/^\s+|\s+$//g;
	# Skip empty lines
	next unless $line;
	# Process lines containing parameters
	next unless $line =~ /--/;
	# Remove surrounding brackets for easier processing
	$line =~ s/^\[//;
	$line =~ s/\]$//;
	# Handle multiple parameters separated by '|'
	my @parts = split(/\|/, $line);
	foreach my $part (@parts) {
		# Trim whitespace
		$part =~ s/^\s+|\s+$//g;
		# Match parameter patterns
		if ($part =~ /--([^\s\[\]|]+)/) {
			my $param_name = $1;
			my $takes_value = 0;
			my $reusable = 0;
			# Check if parameter is followed by a value
			if ($part =~ /--\Q$param_name\E\s+([^\s\[\]|]+)/) {
				$takes_value = 1;
				}
			# Check if parameter or its value is followed by '*'
			if ($part =~ /\*\s*$/ ||
			    $part =~ /[^\s\[\]|]+\s*\*\s*$/) {
				$reusable = 1;
				}
			# Determine the value to store in %params
			my $param_value =
				$takes_value ? ($reusable ? 2 : 1) : 0;
			# Store the parameter and its value, unless already
			# stored
			$params{$param_name} =
				$param_value unless exists($params{$param_name});
			}
		}
	}
return %params;
}

# parse_cli_args(&argv, &params_ref)
# Parses command-line arguments based on predefined parameter definitions. It
# processes an array of arguments, identifies known parameters, handles their
# values (if required), and detects unknown or improperly formatted parameters.
#
# The function returns a hash reference containing the parsed parameters and
# their associated values or flags, without changing the original argument
# array.
sub parse_cli_args
{
my ($argv, $params_ref) = @_;
my %params = %$params_ref;
my %flags;
# Create a copy of the argument array to avoid modifying the original
my @args = @{$argv};
# Initialize index to iterate through @args
for (my $i = 0; $i < @args;) {
	my $arg = $args[$i];  # Current argument
	# Handle the '--help' flag separately to display usage information
	if ($arg eq '--help' || $arg eq '-h') {
		&usage();  # Display usage and exit
		}
	# Check if the argument starts with '--', indicating a parameter
	elsif ($arg =~ /^--(.+)/) {
		my $param = $1; # Extract parameter name without '--'
		# Verify if the parameter is recognized based on predefined
		# definitions
		if (exists($params{$param})) {
			my $param_type = $params{$param};  # Get parameter type
			# Parameter requires a value (type 1 or 2) or may have
			# an optional value (type 3)
			if (grep { $_ == $param_type } (1, 2, 3)) {
				# Check if a value exists for the parameter and
				# does not start with '--'
				if ($i + 1 < @args && $args[$i + 1] !~ /^--/) {
					# Retrieve the parameter's value
					my $value = $args[$i + 1];
					if ($param_type == 2) {
						# Parameter can be specified
						# multiple times
						push(@{$flags{$param}}, $value);
						}
					else {
						# Parameter requires a single
						# value or has an optional value
						$flags{$param} = $value;
						}
					# Remove the parameter and its value
					# from @args
					splice(@args, $i, 2);
					# Do not increment $i since the array
					# has shifted
					next;
					}
				elsif ($param_type == 1 || $param_type == 2) {
					# Parameter requires a value but none
					# was provided
					&usage("Error: Parameter '--$param' ".
					       "requires a value");
					}
				elsif ($param_type == 3) {
					# Parameter may optionally take a value
					if ($i + 1 < @args &&
					    $args[$i + 1] !~ /^--/) {
						# Optional value is provided
						my $value = $args[$i + 1];
						$flags{$param} = $value;
						# Remove parameter and its value
						splice(@args, $i, 2);
						}
					else {
						# No value provided; set
						# parameter as present without a
						# value
						$flags{$param} = undef;
						# Remove only the parameter
						splice(@args, $i, 1);
						}
					# Do not increment $i since the array
					# has shifted
					next;
					}
				}
			# No value required (i.e. $param_type == 0)
			else {
				# Set the flag as present
				$flags{$param} = 1;
				# Remove the parameter from @args
				splice(@args, $i, 1);
				# Do not increment $i since the array has
				# shifted
				next;
				}
			}
		else {
			# Parameter is not recognized; display an error
			&usage("Unknown parameter '--$param'");
			}
		}
	else {
		# Argument does not start with '--' and is not a value for a
		# parameter This is an unknown or misplaced parameter
		&usage("Unknown parameter '$arg'");
		}
	# Move to the next argument
	$i++;
	}
return \%flags;
}

# cli_convert_remote_format(format)
# Catches and displays Virtualmin CLI standard listing
# commands in JSON or XML format. Returns 1 if the output
# should be multiline, 0 if not.
sub cli_convert_remote_format
{
my ($format) = @_;
return 0 if ($convert_remote_format_pid);

my ($lines, $fh, $ofh);
# Redirect STDOUT to a variable
open ($fh, '>', \$lines) || return;
# Save the original STDOUT
$ofh = select($fh);
$convert_remote_format_pid = $$;

# Setup end handler to convert saved output
END {
	return if ($$ != $convert_remote_format_pid);
	no warnings 'closure';
	# Restore the original STDOUT
	select($ofh);

	# Convert output to XML or JSON
	my $program = $0;
	$program =~ s/^.*\///;
	my %fakein = ( 'multiline' => $convert_multiline,
		       'id-only' => $convert_idonly,
		       'name-only' => $convert_nameonly,
		       'email-only' => $convert_emailonly );
	print &convert_remote_format($lines, $?, $program,
				     \%fakein, $convert_format);
	}
return 1;
}

1;

