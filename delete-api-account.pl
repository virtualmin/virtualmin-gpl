#!/usr/local/bin/perl

=head1 delete-api-account.pl

Deletes a dedicated API account without deleting its virtual servers.

This command is available only to root on the command line. It cannot be
called through the HTTP API or delegated to an API account.

Run C<virtualmin delete-api-account --help> for supported options.

=cut

package virtual_server;
use File::Basename ();
# Load the shared terminal-only guard before initializing Webmin.
require(File::Basename::dirname(__FILE__).'/api-account-cli.pl');
&api_account_cli('delete', \@ARGV);
