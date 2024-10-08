#!/usr/bin/env perl

# This is intermediate code to extract and store specific usage for each
# sub-command in data structures and remove the usage function.

use strict;
use warnings;
use File::Slurp;
use File::Copy;
use Data::Dumper;

# Paths
my $virtualmin_dir = '/usr/share/webmin/virtual-server';
my $pro_dir        = "$virtualmin_dir/pro";


# List of sub-commands (modify as needed)
my @sub_commands = qw(
    backup-domain
    change-license
    change-password
    check-config
    check-connectivity
    clone-domain
    copy-mailbox
    create-admin
    create-alias
    create-database
    create-domain
    create-login-link
    create-plan
    create-protected-directory
    create-protected-user
    create-proxy
    create-redirect
    create-reseller
    create-rs-container
    create-s3-bucket
    create-scheduled-backup
    create-shared-address
    create-simple-alias
    create-template
    create-user
    delete-admin
    delete-alias
    delete-backup
    delete-database
    delete-domain
    delete-php-directory
    delete-plan
    delete-protected-directory
    delete-protected-user
    delete-proxy
    delete-redirect
    delete-reseller
    delete-rs-container
    delete-rs-file
    delete-s3-bucket
    delete-s3-file
    delete-scheduled-backup
    delete-script
    delete-shared-address
    delete-template
    delete-user
    disable-domain
    disable-feature
    disable-limit
    disable-writelogs
    disconnect-database
    downgrade-license
    download-dropbox-file
    download-rs-file
    download-s3-file
    enable-domain
    enable-feature
    enable-limit
    enable-writelogs
    fix-domain-permissions
    fix-domain-quota
    generate-acme-cert
    generate-cert
    generate-letsencrypt-cert
    get-command
    get-dns
    get-logs
    get-ssl
    get-template
    import-database
    info
    install-cert
    install-script
    install-service-cert
    license-info
    list-acme-providers
    list-admins
    list-aliases
    list-available-scripts
    list-available-shells
    list-backup-keys
    list-backup-logs
    list-bandwidth
    list-certs
    list-certs-expiry
    list-commands
    list-custom
    list-databases
    list-domains
    list-dropbox-files
    list-features
    list-gcs-buckets
    list-gcs-files
    list-mailbox
    list-mysql-servers
    list-php-directories
    list-php-ini
    list-php-versions
    list-plans
    list-ports
    list-protected-directories
    list-protected-users
    list-proxies
    list-redirects
    list-resellers
    list-rs-containers
    list-rs-files
    list-s3-accounts
    list-s3-buckets
    list-s3-files
    list-scheduled-backups
    list-scripts
    list-server-statuses
    list-service-certs
    list-shared-addresses
    list-simple-aliases
    list-templates
    list-users
    lookup-domain-daemon
    migrate-domain
    modify-admin
    modify-all-ips
    modify-custom
    modify-database-hosts
    modify-database-pass
    modify-database-user
    modify-dns
    modify-domain
    modify-limits
    modify-mail
    modify-php-ini
    modify-plan
    modify-proxy
    modify-reseller
    modify-resources
    modify-scheduled-backup
    modify-spam
    modify-template
    modify-user
    modify-users
    modify-web
    move-domain
    notify-domains
    rename-domain
    resend-email
    reset-feature
    reset-pass
    restart-server
    restore-domain
    run-all-webalizer
    run-api-command
    search-maillogs
    set-dkim
    set-global-feature
    set-mysql-pass
    set-php-directory
    set-spam
    setup-repos
    start-stop-script
    syncmx-domain
    test-imap
    test-pop3
    test-smtp
    transfer-domain
    unalias-domain
    unsub-domain
    upgrade-license
    upload-dropbox-file
    upload-rs-file
    upload-s3-file
    validate-domains
);

# Extracts an ordered list of command-line parameters
# (flags) from the output of usage
sub extract_params_from_usage {
    my ($lines) = @_;

    # Parse the usage output and extract parameters
    my @params;
    my $required_flag = 1; # By default, assume parameters are required
    my $in_alt_group = 0;  # Flag to indicate if we are inside an alt group
    my @current_group;     # To collect parameters in the current group
    my $prev_param;        # Reference to the previous parameter hash

    # Concatenate all lines into one string for easier parsing
    my $usage_text = $lines;
    $usage_text =~ s/\n/ /g;  # Replace newlines with spaces to simplify parsing

    # Loop through each part of the usage text and extract parameters
    while ($usage_text =~ /((?:\-\-)[^\[\]\s+|]+(?:\s+[^\[\]\s]+)?|\[.*?\])\s*(\*?)(\||\s*)/g) {
        my $param_def = $1;
        my $multi = $2 ? 1 : 0;
        my $separator = $3;
        $separator = '|' if ($param_def =~ /\|\\n$/); # Post required group element

        # Check if the parameter is enclosed in brackets (optional)
        if ($param_def =~ /^\[.*\]$/) {
            $required_flag = 0;
            $param_def =~ s/^\[|\]$//g;  # Remove brackets around optional params
        }
        $param_def =~ s/\\n$//;  # Remove new lines

        # Handle parameter and its value (including handling '|' inside value names correctly)
        while ($param_def =~ /--([^\s]+)(?:\s+("?)([^\s"|<]+(?:\|[^\s"]+)?|<[^<>]+>)(\2))?(?:\s*(\*))?/g) {
            my $param_name  = $1;
            my $value_name  = $3;
            $multi = $5 ? 1 : 0 if (!$multi);

            # Clean up value name by removing trailing
            # characters like '\n' and quotes
            $value_name =~ s/\\n//g if defined($value_name);
            $value_name =~ s/^\s+|\s+$//g if defined($value_name); # Trim spaces

            # Store the parameter with its required/optional status
            my $param_hash = {
                param  => $param_name,
            };
            # Optional params if defined or set
            $param_hash->{'value'} = $value_name if (defined($value_name));
            $param_hash->{'reuse'} = 1 if ($multi);
            $param_hash->{'req'} = 1 if ($required_flag);

            if ($in_alt_group) {
                my $param_hash_gr = $param_hash;
                delete($param_hash_gr->{'req'});
                delete($param_hash_gr->{'reuse'});
                push @current_group, $param_hash_gr;
            } else {
                push @params, $param_hash;
                $prev_param = $param_hash; # Keep reference to the last parameter
            }
        }

        # Handle grouping logic
        if ($separator eq "|") {
            $in_alt_group = 1;  # Start or continue an alternative group
            $required_flag = 0; # Alternative group is optional
        } else {
            if ($in_alt_group) {
                # End of alternative group
                # Attach the group to the previous parameter under 'group' key
                if ($prev_param) {
                    $prev_param->{'values'} = [@current_group];
                }
                @current_group = ();
                $in_alt_group = 0;
            }
            $required_flag = 1;  # Reset to required for non-alternative params
        }
    }

    return @params;
}

# Function to format the @params array as Perl code
sub format_perl_array {
    my ($array_ref) = @_;
    $Data::Dumper::Terse     = 1;  # Do not output the variable name
    $Data::Dumper::Indent    = 2;  # Mild indentation, keeps output compact
    $Data::Dumper::Sortkeys  = 1;  # Sort hash keys
    $Data::Dumper::Quotekeys = 0;  # Do not quote hash keys
    $Data::Dumper::Useqq     = 1;  # Use double quotes where possible
    my $formatted =
      Data::Dumper->new([$array_ref])->Terse(1)->Indent(1)->Sortkeys(1)->Dump();
    return $formatted;
}

# Function to format a string as a Perl string literal
sub format_perl_string {
    my ($string) = @_;
    $string =~ s/([\\\'])/\\$1/g;    # Escape backslashes and single quotes
    return "'$string'";
}

# Function to extract a subroutine's content, start and end positions
sub extract_subroutine {
    my ($content, $sub_name) = @_;
    my $pattern = qr/sub\s+$sub_name\s*(?:\s|\n)*\{/;
    if ($content =~ /$pattern/gc) {
        my $start_pos = pos($content) - length($&);
        my $rest      = substr($content, pos($content));
        my $level     = 1;
        my $i         = 0;
        while ($i < length($rest) && $level > 0) {
            my $char = substr($rest, $i, 1);
            if ($char eq '{') {
                $level++;
            } elsif ($char eq '}') {
                $level--;
            }
            $i++;
        }
        my $end_pos    = pos($content) + $i;
        my $sub_content = substr($content, $start_pos, $end_pos - $start_pos);
        return ($sub_content, $start_pos, $end_pos);
    } else {
        return undef;
    }
}

# Main processing loop
foreach my $sub_command (@sub_commands) {
    print "Processing sub-command: $sub_command\n";

    # Determine the .pl file path
    my $pl_file;
    if (-e "$pro_dir/$sub_command.pl") {
        $pl_file = "$pro_dir/$sub_command.pl";
    } elsif (-e "$virtualmin_dir/$sub_command.pl") {
        $pl_file = "$virtualmin_dir/$sub_command.pl";
    } else {
        warn "Cannot find ${sub_command}.pl file, skipping...\n";
        next;
    }

    # Read the content of the .pl file
    my $pl_content = read_file($pl_file);

    # Extract the 'sub usage { ... }' content
    my ($usage_content, $start_pos, $end_pos) =
            extract_subroutine($pl_content, 'usage');

    if (defined $usage_content) {
        # Remove 'sub usage' from $pl_content
        substr($pl_content, $start_pos, $end_pos - $start_pos) = '';
        print "Removed 'sub usage' from $pl_file\n";
    } else {
        warn "Could not find 'sub usage' in $pl_file\n";
        next;
    }

    # Replace variable references in $usage_content with empty strings
    $usage_content =~ s/\$_\[\d+\]/''/g;

    # Now, extract the usage output from $usage_content
    # Look for print statements inside $usage_content
    my $usage_output = '';

    # Capture text within <<END_USAGE blocks
    if ($usage_content =~ /<<['"]?END_USAGE['"]?;?(.*?)^END_USAGE\s*$/ms) {
        $usage_output = $1;
    } else {
        # Collect all strings passed to print statements
        while ($usage_content =~ /\s*print\s*(.+?);/sg) {
            my $print_arg = $1;
            # Remove any parentheses
            $print_arg =~ s/^\s*\(?(.*?)\)?\s*$/$1/;
            # Remove any variables or code, keep strings
            my @strings = ();
            while ($print_arg =~ /(['"])((?:\\.|[^\1])*)(?<!\\)\1/g) {
                my $quote_content = $2;
                $quote_content =~ s/\\"/'/g;
                push @strings, $quote_content;
            }
            $usage_output .= join('', @strings);
        }
    }

    # Clean up $usage_output
    $usage_output =~ s/^\s+|\s+$//g; # Trim leading/trailing whitespace

    # Extract the description from the usage output
    # Initialize params_desc
    my @lines = split(/\n/, $usage_output);
    my $params_desc = '';

    # Iterate through each line to find the first meaningful description
    foreach my $line (@lines) {
        # Remove leading single quotes and any leading/trailing whitespace
        $line =~ s/^''//;
        $line =~ s/^\s+|\s+$//g;
        
        # Assign the first non-empty line to params_desc
        if ($line ne '') {
            $params_desc = $line;
            # Clean up
            if ($params_desc =~ /\\n\\n(.*?)\\n\\n/) {
                $params_desc = $1;
            }
            last;
        }
    }

    if ($params_desc eq '') {
        warn "Could not extract description for sub-command '$sub_command'\n";
    }

    # Use $usage_output to extract parameters
    my @params = extract_params_from_usage($usage_output);

    # Prepare the code to insert
    my $params_code =
        "\n\n\# Params factory\nmy \@usage = ".format_perl_array(\@params);
    # Remove the trailing newline
    chomp($params_code);
    $params_code .= ";";
    $params_code .= "\n\n\# Program simple description\nmy \$usagedesc = ".
        format_perl_string($params_desc).";\n";

    # Insert the code after 'package virtual_server;' line
    if ($pl_content =~ s/(package\s+virtual_server\s*;)/$1$params_code/) {
        print "Inserted \@params and \$params_desc into $pl_file\n";
    } else {
        warn "Could not find 'package virtual_server;' in $pl_file\n";
        next;
    }

    # Write the modified content back to the file
    write_file($pl_file, $pl_content);

    print "Finished processing $pl_file\n";
}