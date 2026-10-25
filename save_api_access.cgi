#!/usr/local/bin/perl
# Save API accounts through the same validation used by the root CLI.
require './virtual-server-lib.pl';
&ReadParse();
# Give validation errors the save or delete context before checking the request.
&error_setup($in{'delete'} ? $text{'apiaccess_derr'} : $text{'apiaccess_err'});
&master_admin() || &error($text{'apiaccess_ecannot'});
$ENV{'REQUEST_METHOD'} eq 'POST' || &error($text{'apiaccess_epost'});
# Form edits must supply the immutable account ID; the service checks it.
eval { &save_api_access_accounts(\%in); };
# Render service errors through the UI; only successful saves redirect.
&error($@) if ($@);
&redirect('api_access.cgi');
