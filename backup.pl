#!/usr/local/bin/perl
# Do a scheduled virtual server backup

package virtual_server;
$main::no_acl_check++;
require './virtual-server-lib.pl';

# Work out what will be backed up
if ($config{'backup_all'} == 1) {
	@doms = &list_domains();
	}
elsif ($config{'backup_all'} == 2) {
	%exc = map { $_, 1 } split(/\0/, $config{'backup_doms'});
	@doms = grep { !$exc{$_->{'id'}} } &list_domains();
	}
else {
	foreach $d (split(/\s+/, $config{'backup_doms'})) {
		local $dinfo = &get_domain($d);
		push(@doms, $dinfo) if ($dinfo);
		}
	}
foreach $f (@backup_features, @backup_plugins) {
	push(@do_features, $f) if ($config{'backup_feature_'.$f});
	$options{$f} = { map { split(/=/, $_) }
			  split(/,/, $config{'backup_opts_'.$f}) };
	}
@vbs = split(/\s+/, $config{'backup_virtualmin'});

# Do the backup, capturing any output
$first_print = \&first_save_print;
$second_print = \&second_save_print;
$indent_print = \&indent_save_print;
$outdent_print = \&outdent_save_print;
if ($config{'backup_strftime'}) {
	$dest = &backup_strftime($config{'backup_dest'});
	}
else {
	$dest = $config{'backup_dest'};
	}
($ok, $size) = &backup_domains($dest, \@doms, \@do_features,
			       $config{'backup_fmt'},
			       $config{'backup_errors'}, \%options,
			       $config{'backup_fmt'} == 2,
			       \@vbs,
			       $config{'backup_mkdir'},
			       $config{'backup_onebyone'});

# Send an email to the recipient
if ($config{'backup_email'} && &foreign_check("mailboxes")) {
	if ($ok) {
		$output .= &text('backup_done', &nice_size($size))."\n";
		}
	else {
		$output .= $text{'backup_failed'}."\n";
		}
	&foreign_require("mailboxes", "mailboxes-lib.pl");
	$host = &get_system_hostname();
	$mail = { 'headers' => [ [ 'From', $config{'from_addr'} ||
					   &mailboxes::get_from_address() ],
				 [ 'Subject', "Backup of Virtualmin on $host" ],
				 [ 'To', $config{'backup_email'} ] ],
		  'attach'  => [ { 'headers' => [ [ 'Content-type',
						    'text/plain' ] ],
				   'data' => &entities_to_ascii($output) } ]
		};
	&mailboxes::send_mail($mail);
	}

sub first_save_print { $output .= $indent_text.join("", @_)."\n"; }
sub second_save_print { $output .= $indent_text.join("", @_)."\n\n"; }
sub indent_save_print { $indent_text .= "    "; }
sub outdent_save_print { $indent_text = substr($indent_text, 4); }


