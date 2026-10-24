#!/usr/local/bin/perl

=head1 modify-api-account.pl

Updates a dedicated API account.

This command is available only to root on the command line. It cannot be
called through the HTTP API or delegated to an API account.

Run C<virtualmin modify-api-account --help> for supported options.

Settings you leave out stay unchanged. A list you supply replaces the saved
list. For example, allow only these two commands:

  virtualmin modify-api-account --name billing-api \
      --command list-domains --command list-users

To disable the account:

  virtualmin modify-api-account --name billing-api --disable

Use C<--passfile> or C<--pass-stdin> to change the password.
Use C<--desc ""> to clear the description.

C<--command-mode include> without any C<--command> options removes all command
permissions.

=cut

package virtual_server;
use File::Basename ();
# Load the shared terminal-only guard before initializing Webmin.
require(File::Basename::dirname(__FILE__).'/api-account-cli.pl');
&api_account_cli('modify', \@ARGV);
