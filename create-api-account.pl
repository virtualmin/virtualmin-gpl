#!/usr/local/bin/perl

=head1 create-api-account.pl

Creates a dedicated API account.

This command is available only to root on the command line. It cannot be
called through the HTTP API or delegated to an API account.

Run C<virtualmin create-api-account --help> for supported options.

On Virtualmin Pro, allow a billing script to create virtual servers:

  virtualmin create-api-account --name billing-api \
      --passfile /root/billing-api.pass --command create-domain

The password must be at least 24 characters long. Use C<--passfile> to read it
from a file, or C<--pass-stdin> to read it from standard input.

New accounts use the API Access page defaults and have no command permissions.
Use C<--command> to allow individual commands. C<--command-mode exclude> allows
all API commands available in this edition except those named with C<--command>.
C<--command-mode all> allows all API commands available in this edition.
Commands added later or unlocked by an upgrade to Pro need explicit permission.

C<create-domain>, C<clone-domain>, C<disable-domain> and C<enable-domain> require
Pro when run by an API account. Plan changes with C<modify-domain> remain
available on GPL. These restrictions do not change root's terminal access.

=cut

package virtual_server;
use File::Basename ();
# Load the shared terminal-only guard before initializing Webmin.
require(File::Basename::dirname(__FILE__).'/api-account-cli.pl');
&api_account_cli('create', \@ARGV);
