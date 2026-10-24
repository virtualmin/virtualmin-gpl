#!/usr/local/bin/perl

=head1 create-api-account.pl

Creates a dedicated API account.

This command is available only to root on the command line. It cannot be
called through the HTTP API or delegated to an API account.

Run C<virtualmin create-api-account --help> for supported options.

For example, allow an integration to create virtual servers:

  virtualmin create-api-account --name billing-api \
      --passfile /root/billing-api.pass --command create-domain

The password must be at least 24 characters long. Use C<--passfile> to read it
from a file, or C<--pass-stdin> to read it from standard input.

New accounts use the API Access page defaults and have no command permissions.
Use C<--command> to allow individual commands. C<--command-mode exclude> allows
all current API commands except those named with C<--command>.
C<--command-mode all> allows all current API commands. In every mode, commands
added later still need permission.

=cut

package virtual_server;
use File::Basename ();
# Load the shared terminal-only guard before initializing Webmin.
require(File::Basename::dirname(__FILE__).'/api-account-cli.pl');
&api_account_cli('create', \@ARGV);
