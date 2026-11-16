#!/usr/local/bin/perl

=head1 list-api-accounts.pl

Lists dedicated API accounts without exposing passwords.

This command is available only to root on the command line. It cannot be
called through the HTTP API or delegated to an API account.

Run C<virtualmin list-api-accounts --help> for supported options.

=cut

package virtual_server;
use File::Basename ();
# Load the shared terminal-only guard before initializing Webmin.
require(File::Basename::dirname(__FILE__).'/api-account-cli.pl');
&api_account_cli('list', \@ARGV);
