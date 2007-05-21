#!/usr/local/bin/perl
# For each domain with spam enabled, update the links in it's spamassassin
# config directory to match the global config

package virtual_server;
$main::no_acl_check++;
require './virtual-server-lib.pl';
foreach my $d (grep { $_->{'spam'} } &list_domains()) {
	&create_spam_config_links($d);
	}

