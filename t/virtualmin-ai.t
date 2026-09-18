#!/usr/bin/perl
use strict;
use warnings;
no warnings 'once';
use Test::More;
use FindBin;
use Cwd qw(abs_path);
use File::Temp qw(tempdir);
use IO::Socket::INET;
use JSON::PP;
use POSIX qw(_exit);

my $root = abs_path("$FindBin::Bin/..");

{
	package virtual_server;
	our $virtualmin_pro;
	do "$root/commands-lib.pl";
	die $@ if ($@);
	do "$root/virtualmin-ai-lib.pl";
	die $@ if ($@);
}

subtest 'edition allowlists use audited Virtualmin commands' => sub {
	local $virtual_server::virtualmin_pro = 0;
	is_deeply(
		[ virtual_server::list_ai_api_commands() ],
		[ qw(create-domain create-user list-domains list-users) ],
		'GPL exposes only the basic domain and user commands');

	local $virtual_server::virtualmin_pro = 1;
	my @pro = virtual_server::list_ai_api_commands();
	my %pro = map { $_, 1 } @pro;
	ok($pro{'create-domain'}, 'Pro includes domain creation');
	ok($pro{'modify-dns'}, 'Pro includes an audited management command');
	ok($pro{'delete-domain'}, 'Pro includes destructive commands for explicit review');
	ok(!$pro{'get-command'} && !$pro{'list-commands'},
		'metadata commands are not offered to the planner');
	ok(!$pro{'run-api-command'}, 'the nested arbitrary-command wrapper is excluded');
	ok(grep($_ eq 'virtualmin-ai.pl', virtual_server::list_api_skip_scripts()),
		'the AI entry point is hidden from the regular API catalog');
	ok(virtual_server::is_ai_api_command('/usr/lib/virtualmin-ai.pl'),
		'the local-only command is recognized after normalization');
	open(my $run_api_fh, '<', "$root/run-api-command.pl") || die $!;
	my $run_api = do { local $/; <$run_api_fh> };
	close($run_api_fh);
	like($run_api, qr/is_ai_api_command\(\$apicmd\)/,
		'run-api-command explicitly rejects virtualmin-ai as its target');
};

subtest 'dedicated wrapper delegates to the regular API helper' => sub {
	my $tmp = tempdir(DIR => '/tmp', CLEANUP => 1);
	my $bindir = "$tmp/with quote's";
	mkdir($bindir) || die $!;
	local %virtual_server::config = (
		api_helper => "$bindir/virtualmin",
		);
	no warnings qw(once redefine);
	local *virtual_server::has_command = sub { '/bin/sh' };
	local *virtual_server::open_tempfile = sub {
		no strict 'refs';
		open(*{"virtual_server::$_[0]"}, $_[1]);
		};
	local *virtual_server::print_tempfile = sub {
		my $name = shift(@_);
		no strict 'refs';
		my $fh = *{"virtual_server::$name"}{IO};
		print $fh @_;
		};
	local *virtual_server::close_tempfile = sub {
		no strict 'refs';
		close(*{"virtual_server::$_[0]"});
		};
	local *virtual_server::set_ownership_permissions = sub {
		chmod($_[2], $_[3]);
		};
	my ($ok, $path) = virtual_server::create_virtualmin_ai_helper_command();
	ok($ok, 'wrapper is created');
	is($path, "$bindir/virtualmin-ai", 'wrapper is placed beside virtualmin');
	open(my $fh, '<', $path) || die $!;
	my $wrapper = do { local $/; <$fh> };
	close($fh);
	like($wrapper,
		qr{exec '\Q$tmp\E/with quote'"'"'s/virtualmin' virtualmin-ai "\$\@"},
		'API helper path and forwarded arguments are safely quoted');
};

subtest 'requests require strict structured output and disable storage' => sub {
	my @commands = qw(create-domain create-user);
	my $schema = virtual_server::virtualmin_ai_plan_schema(\@commands);
	my $request = virtual_server::virtualmin_ai_request(
		'gpt-test', 'instructions', 'input', 'plan', $schema);
	is($request->{'text'}->{'format'}->{'type'}, 'json_schema',
		'structured output uses JSON Schema');
	ok($request->{'text'}->{'format'}->{'strict'}, 'schema is strict');
	ok(!$request->{'store'}, 'provider storage is disabled');
	my $encoded_schema = JSON::PP->new->encode($schema);
	unlike($encoded_schema, qr/uniqueItems|maxLength/,
		'schema avoids unsupported Structured Outputs keywords');
	is_deeply(
		$request->{'text'}->{'format'}->{'schema'}->{'properties'}->{'commands'}
			->{'items'}->{'properties'}->{'command'}->{'enum'},
		\@commands,
		'only locally allowed commands are in the schema');

	# The command line hands over UTF-8 bytes, which must be encoded once
	my $utf8_request = virtual_server::virtualmin_ai_request(
		'gpt-test', 'instructions', "Caf\xc3\xa9 M\xc3\xbcller", 'plan',
		$schema);
	my $encoded_request = JSON::PP->new->utf8->canonical->encode(
		$utf8_request);
	like($encoded_request, qr/Caf\xc3\xa9 M\xc3\xbcller/,
		'non-ASCII request text is sent as UTF-8');
	unlike($encoded_request, qr/\xc3\x83/,
		'non-ASCII request text is not double-encoded');
};

subtest 'Responses API output is decoded defensively' => sub {
	my $inner = '{"commands":[],"clarification":"Need a domain"}';
	my ($direct, $direct_error) = virtual_server::virtualmin_ai_decode_response(
		JSON::PP->new->encode({ output_text => $inner }));
	is($direct_error, undef, 'top-level output text is accepted');
	is($direct->{'clarification'}, 'Need a domain', 'structured JSON is decoded');

	my ($nested, $nested_error) = virtual_server::virtualmin_ai_decode_response(
		JSON::PP->new->encode({ output => [ { content => [
			{ type => 'output_text', text => $inner },
		] } ] }));
	is($nested_error, undef, 'nested output text is accepted');
	is_deeply($nested, $direct, 'both documented response shapes match');

	my (undef, $api_error) = virtual_server::virtualmin_ai_decode_response(
		'{"error":{"message":"bad request"}}');
	like($api_error, qr/bad request/, 'provider errors are preserved');
	my (undef, $json_error) = virtual_server::virtualmin_ai_decode_response('not json');
	like($json_error, qr/invalid JSON/, 'invalid outer JSON is rejected');
	my (undef, $output_error) = virtual_server::virtualmin_ai_decode_response(
		'{"output":{}}');
	like($output_error, qr/invalid output list/, 'invalid output shape is rejected');
	my (undef, $status_error) = virtual_server::virtualmin_ai_decode_response(
		'{"status":"incomplete","output_text":"{}"}');
	like($status_error, qr/did not complete/, 'incomplete responses are rejected');
	my (undef, $budget_error) = virtual_server::virtualmin_ai_decode_response(
		'{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output_text":"{}"}');
	like($budget_error, qr/reason: max_output_tokens/,
		'an exhausted output budget is explained');

	# Providers return UTF-8, and the model may use accents or curly quotes
	my $unicode_inner = JSON::PP->new->encode({ commands => [],
		clarification => "Caf\x{e9} \x{2019}" });
	my ($unicode, $unicode_error) = virtual_server::virtualmin_ai_decode_response(
		JSON::PP->new->utf8->encode({ output_text => $unicode_inner }));
	is($unicode_error, undef, 'non-ASCII structured output is accepted');
	is($unicode->{'clarification'}, "Caf\xc3\xa9 \xe2\x80\x99",
		'non-ASCII output is returned as UTF-8 bytes');
	ok(!utf8::is_utf8($unicode->{'clarification'}),
		'decoded output is a byte string like the command line');
};

subtest 'provider transport sends a private structured request' => sub {
	my $curl = '/usr/bin/curl';
	if (!-x $curl) {
		plan skip_all => 'curl is not installed at /usr/bin/curl';
		}
	my $server = IO::Socket::INET->new(
		LocalAddr => '127.0.0.1',
		LocalPort => 0,
		Proto => 'tcp',
		Listen => 1,
		ReuseAddr => 1,
		);
	if (!$server) {
		plan skip_all => "cannot create a loopback test server: $!";
		}
	my $port = $server->sockport();
	my $pid = fork();
	die "fork failed: $!" if (!defined($pid));
	if (!$pid) {
		alarm(10);
		my $client = $server->accept();
		_exit(2) if (!$client);
		my $request_line = <$client>;
		my %headers;
		while (defined(my $line = <$client>)) {
			$line =~ s/\r?\n$//;
			last if ($line eq '');
			if ($line =~ /^([^:]+):\s*(.*)$/) {
				$headers{lc($1)} = $2;
				}
			}
		my $length = $headers{'content-length'} || 0;
		my $body = '';
		while (length($body) < $length) {
			my $bytes = read($client, my $buffer, $length - length($body));
			last if (!$bytes);
			$body .= $buffer;
			}
		my $decoded;
		eval { $decoded = JSON::PP->new->decode($body); };
		my $valid = $request_line &&
			$request_line =~ m{^POST /v1/responses HTTP/} &&
			($headers{'authorization'} || '') eq 'Bearer test-api-key' &&
			ref($decoded) eq 'HASH' && $decoded->{'model'} eq 'gpt-test' &&
			!$decoded->{'store'};
		my $response = JSON::PP->new->encode({
			output_text => '{"commands":[],"clarification":"done"}',
			});
		print $client "HTTP/1.1 200 OK\r\n";
		print $client "Content-Type: application/json\r\n";
		print $client 'Content-Length: '.length($response)."\r\n\r\n";
		print $client $response;
		close($client);
		_exit($valid ? 0 : 3);
		}
	close($server);
	my $request = virtual_server::virtualmin_ai_request(
		'gpt-test', 'instructions', 'input', 'plan',
		virtual_server::virtualmin_ai_plan_schema([ 'list-domains' ]));
	my ($raw, $error) = virtual_server::virtualmin_ai_call_provider(
		"http://127.0.0.1:$port/v1/responses", 'test-api-key',
		$request, $curl);
	is($error, undef, 'the provider request succeeds');
	my ($response, $decode_error) =
		virtual_server::virtualmin_ai_decode_response($raw || '');
	is($decode_error, undef, 'the provider response is usable');
	is($response->{'clarification'}, 'done', 'the response reaches the caller');
	waitpid($pid, 0);
	is($? >> 8, 0, 'the provider received the expected authenticated JSON');
};

subtest 'selection is locally revalidated' => sub {
	my %allowed = ( 'create-domain' => 1, 'create-user' => 1 );
	is(virtual_server::virtualmin_ai_validate_selection({
		commands => [ 'create-domain', 'create-user' ], clarification => '',
		}, \%allowed), undef, 'known unique commands are accepted');
	my $duplicates = {
		commands => [ 'create-domain', 'create-domain' ], clarification => '',
		};
	is(virtual_server::virtualmin_ai_validate_selection(
		$duplicates, \%allowed), undef, 'duplicate known commands are accepted');
	is_deeply($duplicates->{'commands'}, [ 'create-domain' ],
		'duplicate command selections are collapsed');
	like(virtual_server::virtualmin_ai_validate_selection({
		commands => [ 'delete-domain' ], clarification => '',
		}, \%allowed), qr/unknown command/, 'unknown commands are rejected');
	like(virtual_server::virtualmin_ai_validate_selection({
		commands => [], clarification => '',
		}, \%allowed), qr/neither commands nor a clarification/,
		'empty selections need an explanation');
	like(virtual_server::virtualmin_ai_validate_selection({
		commands => [ 'create-domain' ], clarification => 'question',
		}, \%allowed), qr/commands and a clarification/,
		'ambiguous mixed selections are rejected');
	like(virtual_server::virtualmin_ai_validate_selection({
		commands => [], clarification => "question\e[31m",
	}, \%allowed), qr/clarification text/,
		'terminal control characters are rejected');
};

subtest 'plans are limited to documented argv entries' => sub {
	my $options = virtual_server::virtualmin_ai_help_options(<<'HELP');
virtualmin create-domain --domain name --passfile file
                         [--quota blocks] [--default-features]
HELP
	my %info = (
		'create-domain' => { options => $options },
		);
	my $valid = {
		summary => 'Create one domain', clarification => '',
		commands => [ {
			command => 'create-domain',
			arguments => [ '--domain', 'example.com', '--passfile',
				'__VIRTUALMIN_AI_PASSWORD_FILE__', '--quota', '524288' ],
			reason => 'Create the requested server',
		} ],
	};
	is(virtual_server::virtualmin_ai_validate_plan($valid, \%info), undef,
		'a plan using documented options is accepted');

	my $unknown_command = clone($valid);
	$unknown_command->{'commands'}->[0]->{'command'} = 'delete-domain';
	like(virtual_server::virtualmin_ai_validate_plan($unknown_command, \%info),
		qr/not available/, 'commands outside the selected catalog are rejected');
	my $unknown_option = clone($valid);
	$unknown_option->{'commands'}->[0]->{'arguments'}->[0] = '--shell-command';
	like(virtual_server::virtualmin_ai_validate_plan($unknown_option, \%info),
		qr/undocumented option/, 'undocumented options are rejected');
	my $short_option = clone($valid);
	$short_option->{'commands'}->[0]->{'arguments'}->[0] = '-x';
	like(virtual_server::virtualmin_ai_validate_plan($short_option, \%info),
		qr/short option/, 'short options are rejected');
	my $control = clone($valid);
	$control->{'commands'}->[0]->{'arguments'}->[1] = "example.com\nmalicious";
	like(virtual_server::virtualmin_ai_validate_plan($control, \%info),
		qr/control character/, 'control characters are rejected');
	my $reason_control = clone($valid);
	$reason_control->{'commands'}->[0]->{'reason'} = "safe\e[2J";
	like(virtual_server::virtualmin_ai_validate_plan($reason_control, \%info),
		qr/command reason/, 'terminal control characters in prose are rejected');

	my $shell_text = clone($valid);
	$shell_text->{'commands'}->[0]->{'arguments'}->[1] = 'example.com;rm -rf /';
	is(virtual_server::virtualmin_ai_validate_plan($shell_text, \%info), undef,
		'shell metacharacters are inert argv data rather than shell syntax');
};

subtest 'passwords come from the request, the administrator or a generator' => sub {
	no warnings qw(once redefine);
	local *virtual_server::random_password = sub { 'Generated!1' };
	my $request = "Create example.com and joe with the password s3cret";

	# Each placeholder becomes a generated password by default
	my $plan = { commands => [
		{ command => 'create-domain', arguments => [ '--domain', 'example.com',
				 '--passfile', '__VIRTUALMIN_AI_PASSWORD_FILE__' ] },
		{ command => 'create-user', arguments => [ '--domain', 'example.com', '--user', 'joe',
				 '--pass', '__VIRTUALMIN_AI_PASSWORD__' ] },
		] };
	is(virtual_server::virtualmin_ai_check_passwords($plan, $request, { }),
		undef, 'placeholders are accepted for several accounts');
	is_deeply([ map { [ @$_{qw(step position option source account value)} ] }
			@{$plan->{'passwords'}} ],
		[ [ 0, 2, '--passfile', 'generated', 'example.com', 'Generated!1' ],
		  [ 1, 4, '--pass', 'generated', 'joe@example.com', 'Generated!1' ] ],
		'either placeholder gets a generated password for the account');
	is($plan->{'commands'}->[0]->{'arguments'}->[3],
		'__VIRTUALMIN_AI_PASSWORD_FILE__',
		'the plan itself still carries only the placeholder');

	# An administrator-supplied password applies to every account
	my $supplied = clone($plan);
	is(virtual_server::virtualmin_ai_check_passwords($supplied, $request,
		{ 'password' => 'from-file' }), undef, 'a supplied password is accepted');
	is_deeply([ map { $_->{'source'}.'='.$_->{'value'} } @{$supplied->{'passwords'}} ],
		[ 'file=from-file', 'file=from-file' ],
		'the supplied password is used for every new account');

	# A remote caller can hold the password itself
	my $remote = clone($plan);
	is(virtual_server::virtualmin_ai_check_passwords($remote, $request,
		{ 'placeholder' => 1 }), undef, 'a remote placeholder is accepted');
	is_deeply([ map { $_->{'source'} } @{$remote->{'passwords'}} ],
		[ 'placeholder', 'placeholder' ],
		'the caller fills the placeholder for each account');

	# A password written in the request may be used, anything else may not
	my $inline = { commands => [ { command => 'create-user', arguments => [ '--user', 'joe', '--pass',
						      's3cret' ] } ] };
	is(virtual_server::virtualmin_ai_check_passwords($inline, $request, { }),
		undef, 'a password stated in the request is accepted');
	is($inline->{'passwords'}->[0]->{'source'}, 'request',
		'the request is recorded as its source');
	my $invented = { commands => [ { command => 'create-user', arguments => [ '--pass', 'hunter2' ] } ] };
	like(virtual_server::virtualmin_ai_check_passwords($invented, $request, { }),
		qr/does not appear in the request/, 'invented passwords are rejected');
	my $arbitrary = { commands => [ { arguments =>
		[ '--passfile', '/etc/shadow' ] } ] };
	like(virtual_server::virtualmin_ai_check_passwords($arbitrary, $request, { }),
		qr/untrusted password file/,
		'the model cannot select an arbitrary local file');
	my $random = { commands => [ { arguments => [ '--random-pass' ] } ] };
	like(virtual_server::virtualmin_ai_check_passwords($random, $request, { }),
		qr/does not reveal/, 'unrecoverable generated passwords are rejected');
	my $stray = { commands => [ { arguments => [ '--desc',
						     '__VIRTUALMIN_AI_PASSWORD__' ] } ] };
	like(virtual_server::virtualmin_ai_check_passwords($stray, $request, { }),
		qr/must follow a password option/,
		'a placeholder is only accepted where a password goes');
	my $other = { commands => [ { command => 'create-domain', arguments => [ '--mysql-pass',
						     '__VIRTUALMIN_AI_PASSWORD__' ] } ] };
	like(virtual_server::virtualmin_ai_check_passwords($other, $request, { }),
		qr/cannot take a placeholder/,
		'only account passwords can be generated');

	# Only new accounts get a password unless the request asks for a change
	my $quota = { commands => [ { command => 'modify-domain', arguments =>
		[ '--domain', 'example.com', '--quota', '4194304', '--passfile',
		  '__VIRTUALMIN_AI_PASSWORD_FILE__' ] } ] };
	like(virtual_server::virtualmin_ai_check_passwords($quota,
		'set the quota of example.com to 4 GB', { }),
		qr/does not ask for a password change/,
		'a password is not added to a command that changes something else');
	my $reset = clone($quota);
	is(virtual_server::virtualmin_ai_check_passwords($reset,
		'set the quota of example.com to 4 GB and reset its password', { }),
		undef, 'a requested password change is accepted');
	is($reset->{'passwords'}->[0]->{'source'}, 'generated',
		'the new password is generated when the request gives none');

	like(virtual_server::virtualmin_ai_password_instructions(0),
		qr/--passfile and __VIRTUALMIN_AI_PASSWORD_FILE__.*Never invent a password or use\s+--random-pass/s,
		'the local planner is told to use the file placeholder');
	like(virtual_server::virtualmin_ai_password_instructions(1),
		qr/--pass and\s+__VIRTUALMIN_AI_PASSWORD__/s,
		'the remote planner is told to use the value placeholder');
	like(virtual_server::virtualmin_ai_password_instructions(0),
		qr/A new top-level.*A sub-server or alias.*does not.*only when the request explicitly asks.*Never ask for a password/s,
		'the planner is told when a password is and is not needed');
};

subtest 'execution never invokes a shell and stops on failure' => sub {
	my $plan = { commands => [
		{ command => 'create-domain', arguments =>
			[ '--domain', 'example.com;touch /tmp/bad', '--passfile',
			  '__VIRTUALMIN_AI_PASSWORD_FILE__' ] },
		{ command => 'create-user', arguments => [ '--user', 'amanda' ] },
		{ command => 'create-user', arguments => [ '--user', 'linda' ] },
	], passwords => [ { step => 0, position => 2, option => '--passfile',
			    source => 'generated', value => 'Generated!1' } ] };
	my (@calls, $seen, $file);
	my ($status, $index, $step, $error) =
		virtual_server::virtualmin_ai_execute_plan(
		$plan, '/usr/sbin/virtualmin', sub {
			my ($argv) = @_;
			push(@calls, [ @$argv ]);
			if (@calls == 1) {
				# The password is in a private file while the command runs
				$file = $argv->[5];
				open(my $fh, '<', $file) || die $!;
				$seen = <$fh>;
				close($fh);
				}
			return @calls == 2 ? 7 : 0;
		});
	is($status, 7, 'runner failure is returned');
	is($index, 2, 'failure identifies the second command');
	is($step->{'command'}, 'create-user', 'failed step is returned');
	is($error, undef, 'a command failure carries no execution error');
	is(scalar(@calls), 2, 'later commands are not run');
	is_deeply([ @{$calls[0]}[0 .. 4] ], [ '/usr/sbin/virtualmin', 'create-domain',
		'--domain', 'example.com;touch /tmp/bad', '--passfile' ],
		'execution receives an exact argv array');
	is($seen, 'Generated!1', 'the generated password reached the command');
	ok(!-e $file, 'the private password file is removed afterwards');
};

subtest 'display quoting and provider URL validation are conservative' => sub {
	is(virtual_server::virtualmin_ai_format_command('create-domain',
		[ '--domain', 'example.com', '--desc', "Artist's site" ]),
		q{virtualmin create-domain --domain example.com --desc 'Artist'"'"'s site'},
		'display output is safely shell quoted');
	my $plan = { commands => [ { command => 'create-user', arguments =>
			[ '--user', 'joe', '--pass', '__VIRTUALMIN_AI_PASSWORD__' ] } ],
		     passwords => [ { step => 0, position => 2, option => '--pass',
				      source => 'generated', value => 'x' } ] };
	is(virtual_server::virtualmin_ai_display_step($plan, 0),
		'virtualmin create-user --user joe --pass <generated>',
		'a generated password is shown as such rather than by value');
	$plan->{'passwords'}->[0]->{'source'} = 'file';
	is(virtual_server::virtualmin_ai_display_step($plan, 0, '/root/p.txt'),
		'virtualmin create-user --user joe --passfile /root/p.txt',
		'a supplied password file is shown by its path');
	is(virtual_server::virtualmin_ai_validate_api_url(
		'https://api.openai.com/v1/responses'), undef, 'HTTPS is accepted');
	is(virtual_server::virtualmin_ai_validate_api_url(
		'http://127.0.0.1:8000/v1/responses'), undef, 'loopback HTTP is accepted');
	like(virtual_server::virtualmin_ai_validate_api_url(
		'http://example.com/v1/responses'), qr/must use HTTPS/,
		'remote plaintext HTTP is rejected');
	my (undef, $key_error) = virtual_server::virtualmin_ai_call_provider(
		'https://api.example/v1/responses', "bad\nheader", {}, '/bin/false');
	like($key_error, qr/API key is invalid/,
		'control characters cannot inject curl configuration');
	my (undef, $timeout_error) = virtual_server::virtualmin_ai_call_provider(
		'https://api.example/v1/responses', 'key', {}, '/bin/false',
		{ deadline => time() - 1 });
	like($timeout_error, qr/Remote AI planning timed out/,
		'an expired shared deadline stops a remote provider call');
	like(virtual_server::virtualmin_ai_unattended_warning(),
		qr/skips human review.*as root.*any file path/s,
		'unattended mode clearly warns about root-level file access');
};

subtest 'the provider table covers every supported wire format' => sub {
	my @providers = virtual_server::list_ai_providers();
	is_deeply(\@providers, [ qw(openai anthropic gemini xai deepseek custom) ],
		'providers are listed in display order');
	my %formats;
	foreach my $id (@providers) {
		my $info = virtual_server::get_ai_provider($id);
		ok($info->{'desc'} && $info->{'format'} && $info->{'env'},
			"$id has a description, format and key variable");
		$formats{$info->{'format'}}++;
		next if ($id eq 'custom');
		is(virtual_server::virtualmin_ai_validate_api_url($info->{'url'}),
			undef, "$id has a valid default URL");
		ok($info->{'model'}, "$id has a default model");
		ok(virtual_server::virtualmin_ai_models_url($info->{'url'}),
			"$id has a derivable model listing URL");
		}
	is_deeply([ sort keys %formats ], [ qw(anthropic chat responses) ],
		'three wire formats are used');
	is(virtual_server::get_ai_provider('nope'), undef,
		'unknown providers are rejected');
	is(virtual_server::virtualmin_ai_models_url(
		'http://127.0.0.1:11434/v1/chat/completions'),
		'http://127.0.0.1:11434/v1/models',
		'local chat endpoints map to their model list');
	{
		local %ENV = ( 'DEEPSEEK_API_KEY' => 'x' );
		is(virtual_server::virtualmin_ai_provider_from_env(), 'deepseek',
			'the provider can be inferred from a key variable');
	}
};

subtest 'each wire format gets its own request shape' => sub {
	my $schema = virtual_server::virtualmin_ai_plan_schema([ 'create-domain' ]);
	my $chat = virtual_server::virtualmin_ai_request(
		'm', 'sys', 'in', 'plan', $schema, 'chat');
	is($chat->{'messages'}->[0]->{'role'}, 'system',
		'chat requests carry a system message');
	is($chat->{'response_format'}->{'type'}, 'json_schema',
		'chat requests use response_format');
	ok($chat->{'response_format'}->{'json_schema'}->{'strict'},
		'the chat schema is strict');
	ok($chat->{'max_tokens'}, 'chat requests cap output with max_tokens');

	my $anthropic = virtual_server::virtualmin_ai_request(
		'm', 'sys', 'in', 'plan', $schema, 'anthropic');
	is($anthropic->{'system'}, 'sys', 'Messages requests carry the system prompt');
	is($anthropic->{'output_config'}->{'format'}->{'type'}, 'json_schema',
		'Messages requests use output_config');
	my $encoded = JSON::PP->new->encode(
		$anthropic->{'output_config'}->{'format'}->{'schema'});
	unlike($encoded, qr/maxItems|minItems/,
		'array size limits Claude rejects are stripped');
	like($encoded, qr/"additionalProperties":false/,
		'additionalProperties false survives the rewrite');
	like(JSON::PP->new->encode($schema), qr/maxItems/,
		'the original schema is left untouched');

	my $quirky = virtual_server::virtualmin_ai_request(
		'm', 'sys', 'in', 'plan', $schema, 'responses', { 'no_store' => 1 });
	ok(!exists($quirky->{'store'}), 'providers that reject store do not receive it');
	my $gemini = virtual_server::virtualmin_ai_request(
		'm', 'sys', 'in', 'plan', $schema, 'chat',
		virtual_server::get_ai_provider('gemini')->{'request_options'});
	unlike(JSON::PP->new->encode($gemini->{'response_format'}), qr/maxItems/,
		'Gemini requests carry no array size limits');
	ok($gemini->{'response_format'}->{'json_schema'}->{'strict'},
		'Gemini requests stay strict');
	is_deeply([ virtual_server::virtualmin_ai_auth_headers('anthropic', 'k', 'wrkspc_1') ],
		[ 'x-api-key: k', 'anthropic-version: 2023-06-01',
		  'anthropic-workspace-id: wrkspc_1' ],
		'Anthropic uses its own headers plus an optional workspace');
	is_deeply([ virtual_server::virtualmin_ai_auth_headers('chat', 'k') ],
		[ 'Authorization: Bearer k' ], 'other formats use a bearer token');
	is_deeply([ virtual_server::virtualmin_ai_auth_headers('chat', '') ], [],
		'local servers without a key send no authorization header');
};

subtest 'chat and Messages responses are decoded defensively' => sub {
	my $inner = '{"commands":[],"clarification":"Need a domain"}';
	my ($chat, $chat_error) = virtual_server::virtualmin_ai_decode_response(
		JSON::PP->new->encode({ choices => [ { finish_reason => 'stop',
			message => { role => 'assistant', content => $inner } } ] }),
		'chat');
	is($chat_error, undef, 'chat completions content is accepted');
	is($chat->{'clarification'}, 'Need a domain', 'chat content is decoded');
	my (undef, $parts_error) = virtual_server::virtualmin_ai_decode_response(
		JSON::PP->new->encode({ choices => [ { message => { content => [
			{ type => 'text', text => $inner } ] } } ] }), 'chat');
	is($parts_error, undef, 'chat content parts are joined');
	my (undef, $length_error) = virtual_server::virtualmin_ai_decode_response(
		JSON::PP->new->encode({ choices => [ { finish_reason => 'length',
			message => { content => '{' } } ] }), 'chat');
	like($length_error, qr/finish_reason: length/,
		'truncated chat output is rejected');
	my (undef, $refusal_error) = virtual_server::virtualmin_ai_decode_response(
		JSON::PP->new->encode({ choices => [ { message => {
			refusal => 'no', content => undef } } ] }), 'chat');
	like($refusal_error, qr/refused/, 'chat refusals are reported');

	my ($claude, $claude_error) = virtual_server::virtualmin_ai_decode_response(
		JSON::PP->new->encode({ stop_reason => 'end_turn', content => [
			{ type => 'thinking', thinking => 'hmm' },
			{ type => 'text', text => $inner } ] }), 'anthropic');
	is($claude_error, undef, 'Messages text blocks are accepted');
	is($claude->{'clarification'}, 'Need a domain', 'thinking blocks are skipped');
	my (undef, $max_error) = virtual_server::virtualmin_ai_decode_response(
		JSON::PP->new->encode({ stop_reason => 'max_tokens', content => [
			{ type => 'text', text => '{' } ] }), 'anthropic');
	like($max_error, qr/stop_reason: max_tokens/,
		'truncated Messages output is rejected');
	my (undef, $claude_refusal) = virtual_server::virtualmin_ai_decode_response(
		JSON::PP->new->encode({ stop_reason => 'refusal',
			stop_details => { explanation => 'policy' }, content => [] }),
		'anthropic');
	like($claude_refusal, qr/refused.*policy/, 'Messages refusals are reported');
	my (undef, $claude_api_error) = virtual_server::virtualmin_ai_decode_response(
		'{"type":"error","error":{"type":"authentication_error","message":"bad key"}}',
		'anthropic');
	like($claude_api_error, qr/bad key/, 'Messages API errors are preserved');
};

subtest 'provider accounts are stored in root-only files' => sub {
	my $dir = tempdir(DIR => '/tmp', CLEANUP => 1);
	local $virtual_server::virtualmin_ai_accounts_dir = "$dir/ai-accounts";
	like(virtual_server::save_ai_account('', { provider => 'nope', key => 'k' }),
		qr/Unknown AI provider/, 'unknown providers are refused');
	like(virtual_server::save_ai_account('', { provider => 'openai' }),
		qr/API key is required/, 'a missing key is refused');
	like(virtual_server::save_ai_account('', { provider => 'custom', key => '' }),
		qr/API URL is required/, 'custom servers need a URL');
	like(virtual_server::save_ai_account('', { provider => 'openai', key => "bad\nkey" }),
		qr/API key is invalid/, 'control characters in keys are refused');
	like(virtual_server::save_ai_account('../x', { provider => 'openai', key => 'k' }),
		qr/Invalid user name/, 'user names cannot escape the directory');
	is(virtual_server::save_ai_account('', { provider => 'openai',
		model => 'gpt-test', key => 'sk-master-key-0000' }), undef,
		'the master account is saved');
	is(virtual_server::save_ai_account('artists', { provider => 'anthropic',
		key => 'sk-ant-user-key-000', workspace => 'wrkspc_1' }), undef,
		'a user account is saved');
	is((stat("$dir/ai-accounts"))[2] & 0777, 0700, 'the directory is private');
	is((stat("$dir/ai-accounts/master"))[2] & 0777, 0600, 'the account file is private');
	my $master = virtual_server::get_ai_account('');
	is($master->{'model'}, 'gpt-test', 'saved values are read back');
	is($master->{'key'}, 'sk-master-key-0000', 'the key is read back');
	my $user = virtual_server::get_ai_account('artists');
	is($user->{'workspace'}, 'wrkspc_1', 'the workspace is read back');
	is(virtual_server::get_ai_account('nobody'), undef, 'missing accounts are undef');
	is_deeply([ map { $_->{'user'} } virtual_server::list_ai_accounts() ],
		[ '', 'artists' ], 'accounts are listed');
	is(virtual_server::mask_ai_key('sk-master-key-0000'), 'sk-m...0000',
		'keys are masked for display');

	my ($settings, $error) = virtual_server::resolve_ai_settings('artists', {}, 0);
	is($error, undef, 'settings resolve for a user');
	is($settings->{'format'}, 'anthropic', 'the saved provider decides the format');
	is($settings->{'model'}, 'claude-opus-5', 'the provider default model applies');
	is($settings->{'workspace'}, 'wrkspc_1', 'the saved workspace applies');
	like(virtual_server::virtualmin_ai_nonmaster_provider_error(
		'openai', 1, $user), qr/only available to the master/,
		'non-master users cannot override a provider endpoint');
	like(virtual_server::virtualmin_ai_nonmaster_provider_error(
		'custom', 0, undef), qr/must be assigned by the master/,
		'non-master users cannot select a new custom endpoint');
	is(virtual_server::virtualmin_ai_nonmaster_provider_error(
		'custom', 0, { provider => 'custom', url => 'https://ai.example/v1' }),
		undef, 'a user can keep a custom endpoint assigned by master');
	($settings, $error) = virtual_server::resolve_ai_settings('', { provider => 'xai' }, 0);
	is($settings->{'key'}, undef, 'a different provider does not reuse the saved key');
	{
		local %ENV = ( 'VIRTUALMIN_AI_MODEL' => 'gpt-env', 'OPENAI_API_KEY' => 'sk-env' );
		($settings, $error) = virtual_server::resolve_ai_settings('', {}, 1);
		is($settings->{'model'}, 'gpt-env', 'environment overrides the saved model');
		is($settings->{'key'}, 'sk-env', 'environment overrides the saved key');
		($settings, $error) = virtual_server::resolve_ai_settings('', { model => 'gpt-flag' }, 1);
		is($settings->{'model'}, 'gpt-flag', 'flags override the environment');
		($settings, $error) = virtual_server::resolve_ai_settings('', {}, 0);
		is($settings->{'model'}, 'gpt-test', 'the CGI path ignores the environment');
	}
	my ($lock, $lock_error) = virtual_server::virtualmin_ai_request_lock('artists');
	is($lock_error, undef, 'the first remote request takes the account lock');
	my (undef, $busy_error) = virtual_server::virtualmin_ai_request_lock('artists');
	like($busy_error, qr/already running/, 'a concurrent request is refused');
	close($lock);
	my ($next_lock, $next_error) = virtual_server::virtualmin_ai_request_lock('artists');
	is($next_error, undef, 'the account lock is released with its handle');
	close($next_lock);

	ok(virtual_server::rename_ai_account('artists', 'painters'),
		'accounts move with renamed Webmin users');
	is(virtual_server::get_ai_account('artists'), undef,
		'the old login no longer has the account');
	is(virtual_server::get_ai_account('painters')->{'key'}, 'sk-ant-user-key-000',
		'the renamed login keeps its key');
	ok(virtual_server::delete_ai_account('painters'), 'accounts can be removed');
	is(virtual_server::get_ai_account('painters'), undef, 'removed accounts are gone');
	ok(!virtual_server::delete_ai_account('painters'), 'removing again reports nothing');
	is(virtual_server::save_ai_account('painters', { provider => 'openai',
		key => 'stale-user-key' }), undef, 'a stale target account is saved');
	ok(virtual_server::rename_ai_account('missing-user', 'painters'),
		'a rename without source settings still succeeds');
	is(virtual_server::get_ai_account('painters'), undef,
		'a renamed user cannot inherit stale target settings');
};

subtest 'models are grouped into recommended, other and hidden' => sub {
	my ($entries, $note) = virtual_server::virtualmin_ai_model_groups('openai',
		[ 'gpt-5.5', 'gpt-5.5-2026-03-01', 'gpt-6-astra', 'tts-1',
		  'text-embedding-4', 'o9-mini', 'gpt-realtime' ]);
	is_deeply([ map { $_->{'id'} } grep { $_->{'group'} eq 'Recommended' } @$entries ],
		[ 'gpt-6-astra', 'gpt-5.5' ],
		'recommended models listed by the provider come first in order');
	is_deeply([ map { $_->{'id'} } grep { $_->{'group'} eq 'Other chat models' } @$entries ],
		[ 'o9-mini' ], 'other chat models follow');
	is_deeply([ sort map { $_->{'id'} } grep { $_->{'hidden'} } @$entries ],
		[ 'gpt-5.5-2026-03-01', 'gpt-realtime', 'text-embedding-4', 'tts-1' ],
		'dated, audio, realtime and embedding models are hidden');
	like($note, qr/dated snapshots/, 'the hidden note names what is hidden');
	ok((grep { $_->{'id'} eq 'gpt-6-astra' && $_->{'note'} } @$entries),
		'recommended models carry a short description');
	my ($custom) = virtual_server::virtualmin_ai_model_groups('custom',
		[ 'llama4:latest' ]);
	is_deeply([ map { $_->{'group'} } @$custom ], [ 'Other chat models' ],
		'providers without recommendations list everything as other');

	# Pages of the numbered menu
	my $page = virtual_server::virtualmin_ai_model_page($entries,
		{ 'limit' => 2 });
	is_deeply([ map { $_->{'id'} } @{$page->{'shown'}} ], [ 'gpt-6-astra', 'gpt-5.5' ],
		'the first page lists the first chat models');
	is($page->{'total'}, 3, 'the total counts only chat models by default');
	is($page->{'hidden'}, 4, 'the hidden count is reported');
	is($page->{'remaining'}, 1, 'the remaining count is reported');
	$page = virtual_server::virtualmin_ai_model_page($entries,
		{ 'limit' => 2, 'offset' => 2 });
	is_deeply([ map { $_->{'id'} } @{$page->{'shown'}} ], [ 'o9-mini' ],
		'the next page continues where the first stopped');
	is($page->{'remaining'}, 0, 'the last page has nothing remaining');
	$page = virtual_server::virtualmin_ai_model_page($entries,
		{ 'all' => 1, 'filter' => 'GPT-5.5' });
	is_deeply([ map { $_->{'id'} } @{$page->{'shown'}} ],
		[ 'gpt-5.5', 'gpt-5.5-2026-03-01' ],
		'a filter is case-insensitive and "all" includes hidden models');
	is($page->{'hidden'}, 0, 'nothing is hidden once all are shown');
	$page = virtual_server::virtualmin_ai_model_page($entries,
		{ 'filter' => 'nothing-like-this' });
	is($page->{'total'}, 0, 'an unmatched filter lists nothing');
};

subtest 'remote plans carry parameters and a placeholder instead of secrets' => sub {
	my ($params, $error) = virtual_server::virtualmin_ai_step_params(
		[ '--domain', 'example.com', '--mysql', 'db1', '--mysql', 'db2',
		  '--ftp', '--quota', '1024' ]);
	is($error, undef, 'documented argv converts');
	is_deeply($params, { domain => 'example.com', mysql => [ 'db1', 'db2' ],
		ftp => '', quota => '1024' },
		'values, repeats and flags map to remote.cgi parameters');
	(undef, $error) = virtual_server::virtualmin_ai_step_params([ 'example.com' ]);
	like($error, qr/not a command option/,
		'positional values cannot be expressed remotely');
	ok(virtual_server::virtualmin_ai_destructive_command('delete-domain'),
		'deletions are destructive');
	ok(virtual_server::virtualmin_ai_destructive_command(
		'modify-user', [ '--user', 'joe', '--disable' ]),
		'destructive options on modify commands are highlighted');
	ok(!virtual_server::virtualmin_ai_destructive_command('list-domains'),
		'listings are not');

	# The CGI turns every password slot into a --pass parameter
	open(my $fh, '<', "$root/remote-ai.cgi") || die $!;
	my $cgi = do { local $/; <$fh> };
	close($fh);
	like($cgi, qr/'placeholder' => \$have_password/,
		'have-password lets the caller fill the placeholder itself');
	like($cgi, qr/\{'generated'\} = \\\@generated/,
		'generated passwords are returned to the caller');
	like($cgi, qr/= '--pass' if \(\$slot->\{'option'\} eq '--passfile'\)/,
		'server-side password files never reach a remote plan');
};

done_testing();

sub clone
{
return JSON::PP->new->decode(JSON::PP->new->encode($_[0]));
}
