# Virtualmin AI

Design of the natural-language planner in this module.

## Summary

Two entry points turn a plain-language request into ordinary Virtualmin API commands:

- `virtualmin-ai` is a root-only command line tool. It plans, shows the commands, asks for confirmation and runs them through the `virtualmin` helper as an argv array.
- `remote-ai.cgi` is a plan-only CGI for remote API clients. It returns the steps as `remote.cgi` parameters and never executes anything. The client reviews the plan and runs each step through `remote.cgi` with its own credentials.

In both, the AI provider only ever sees the request text, the catalog of command names with one-line descriptions, and the `--help` output of the commands it selected. It answers with a structured plan, which is validated locally before anything else happens.

Everything lives in `virtualmin-ai-lib.pl`. The wrappers are `virtualmin-ai.pl`, `remote-ai.cgi` and the `configure-ai` API command.

## Principles

1. **Model output is data.** A plan passes only if every command is in the edition's allowlist and every option appears in that command's own `--help`. Arguments are argv entries, never shell text. Nothing from the model reaches a shell.
2. **Execution authority never moves.** Locally, root runs the validated plan after reading it. Remotely, the caller runs it through `remote.cgi`, so miniserv authentication and the caller's ACL decide what happens. `remote-ai.cgi` has no authentication of its own and no execution path.
3. **Secrets stay on the server.** API keys live in root-only files. Passwords are generated locally or read from a root-only file, and the model sees only a placeholder unless the request itself spells a password out.
4. **No hidden state.** Each run is independent. Requests are sent with provider storage disabled (`store: false`).
5. **Human review by default.** `--plan` shows the commands and stops, the default asks for confirmation, and `--yes` is only for trusted automation and prints a warning.

## Providers

| Provider | Wire format | Default endpoint | Default model | Key variable |
| --- | --- | --- | --- | --- |
| `openai` | Responses API | `https://api.openai.com/v1/responses` | `gpt-5.4-mini` | `OPENAI_API_KEY` |
| `anthropic` | Messages API | `https://api.anthropic.com/v1/messages` | `claude-opus-5` | `ANTHROPIC_API_KEY` |
| `gemini` | Chat completions | `https://generativelanguage.googleapis.com/v1beta/openai/chat/completions` | `gemini-3.8-flash` | `GEMINI_API_KEY` |
| `xai` | Responses API | `https://api.x.ai/v1/responses` | `grok-4.6` | `XAI_API_KEY` |
| `deepseek` | Responses API | `https://api.deepseek.com/responses` | `deepseek-flash` | `DEEPSEEK_API_KEY` |
| `custom` | Chat completions | given with `--api-url` | none | `VIRTUALMIN_AI_API_KEY` |

All providers go through the same `curl` transport. Only the request shape, the headers and the response extraction differ per format. Every request asks for strict JSON Schema output; the schema lists the allowed command names as an enum.

Provider quirks handled in code:

- Anthropic and Gemini reject `maxItems`, so array limits are stripped for them. An Anthropic key that is not scoped to a workspace needs `--workspace`, sent as the `anthropic-workspace-id` header.
- DeepSeek's chat endpoint only supports JSON mode, so DeepSeek uses its Responses endpoint.
- Gemini wraps errors in a list; errors are unwrapped before they are shown.
- The request body goes to a private file and `curl` reports the HTTP status separately. 429 and 5xx responses are retried twice with backoff in Perl, so a retry can never concatenate bodies. Responses are capped at 1 MB and output at 16384 tokens.

A loopback `http://` URL is accepted for local servers such as Ollama, LM Studio or vLLM. Everything else must be `https://`.

## Settings

Accounts are stored under `$module_config_directory/ai-accounts/` (mode 0700), one file per login: `master` for root and `user-NAME` for other Webmin users (mode 0600, written through a temporary file and rename). Each file holds `provider`, `model`, `url`, `workspace` and `key`.

Values are resolved in this order: command-line flags, then environment variables (`VIRTUALMIN_AI_PROVIDER`, `VIRTUALMIN_AI_MODEL`, `VIRTUALMIN_AI_API_URL` and the provider key variable), then the saved account when its provider matches, then the provider defaults. `remote-ai.cgi` ignores the environment and uses only the caller's saved account.

`virtualmin-ai --configure` is a three-step plain-text flow:

1. **Provider**, chosen by number. A custom server is also asked for its endpoint URL.
2. **API key**, typed with echo off. Enter keeps the saved key. The key is checked with the provider's model listing, and an Anthropic key that needs a workspace is asked for one.
3. **Model**, chosen by number or name from the provider's list. Recommended models come first with a short note, non-chat models (dated snapshots, audio, embeddings and similar) are hidden with a count, and typing part of a name filters, `all` lists everything and `more` pages. A single tiny structured request is sent to the chosen model before saving.

A summary shows what changed, then `Save to <file>? [Y/n]`. Scripts pass `--provider`, `--model`, `--api-url`, `--workspace` and the key through `--api-key-file` or `--api-key-stdin`. `--user NAME` configures another Webmin user. `--show` masks the key, `--remove` deletes the file.

The `configure-ai` API command shares the same logic for scripts and remote API users. Only the master administrator may use `--user`, `--api-key-file`, `--list` or `--api-url`, and only the master may assign the `custom` provider. Other users keep a built-in provider or a custom endpoint already assigned to them. `--api-key` is accepted only in a remote API POST request, so a key never appears on a command line or in a URL.

Saved accounts are removed with their Webmin user (domain owners, extra administrators) and renamed with a renamed login.

## Planning

1. **Selection** (Pro only, when more than eight commands are allowed). The provider receives the catalog of command names and descriptions and picks the few it needs, or asks one clarifying question. GPL has four commands and plans directly.
2. **Help.** The current `--help` output of each selected command is loaded. It is the model's only source of option names, so the help text must be accurate. `create-domain` usage now states that quotas are 1 kB blocks and need both `--quota` and `--uquota`, that a feature choice is required, and that a password is only needed for a top-level server.
3. **Plan.** The provider returns `summary`, `commands` (each `command`, `arguments` and `reason`) and `clarification`. The planner instructions cover: argv only, no shell syntax; 1 kB block conversion; unbracketed help arguments are required; `--default-features` unless features are named, and named features need `--dir`; sensible defaults for details the request leaves open, such as `--shell /bin/bash` for SSH access; and the password rules below. The request is declared to be data, never instructions.
4. **Validation.** Command in the selected catalog, every option present in its help, no short options, no control characters, no positional arguments in remote plans. A rejected plan is sent back once with the reason before anything runs; small models usually slip on a single option name.
5. **Clarification.** An empty plan with a question is returned to the caller. `virtualmin-ai` prints it and exits with status 2.

## Passwords

A password is never asked for.

- A new top-level virtual server or a new user gets a password slot. The model emits a placeholder for it: `--passfile __VIRTUALMIN_AI_PASSWORD_FILE__` locally, `--pass __VIRTUALMIN_AI_PASSWORD__` remotely. Either placeholder is accepted with either option.
- Locally the value comes from `--password-file`, which applies to every new account in the plan, and otherwise a password is generated per account with Virtualmin's own `random_password()`. Just before a command runs, its password is written to a private 0600 file and handed over with `--passfile`; the file is removed when the command finishes, so no password appears on a command line. Generated passwords are printed once after the run, also after a failure for the commands that did run.
- A password written in the request is used as given, since it already went to the provider with the request. The validator accepts a literal password only when it appears verbatim in the request text.
- Remotely, `have-password=1` keeps the placeholder in the plan and the client substitutes its own value when it posts the step. Without it, passwords are generated on the server, put into the plan and listed under `generated`. `--passfile` never appears in a remote plan, because it would name a server-side file.
- No other command may carry a password option unless the request asks for a password change. A quota change, for example, is rejected and corrected if the model adds `--pass`. `--random-pass` is rejected because `create-user` does not reveal the generated password. Other secret options such as `--mysql-pass` are only accepted with a value taken from the request.

In the confirmation view a slot shows as `--pass <generated>` or `--passfile /path/given`.

## remote-ai.cgi

Parameters: `request` (required) and `have-password` (optional). No API key, password or command name is accepted as a parameter.

The CGI must be listed in miniserv's `sessiononly` like `remote.cgi`, or a basic-auth call gets the login page. `postinstall.pl` adds it. The caller must be the master administrator or a user allowed to use the remote API (`can_use_virtualmin_ai`). For a non-master caller the catalog is filtered through `can_remote()`, so a plan can never name a command the caller could not run by hand. One planning request per account runs at a time; a second call gets the `busy` error while the first is still waiting for the provider.

Response:

```json
{
  "status": "plan",
  "summary": "Create example.com and a mailbox for joe",
  "steps": [
    {
      "program": "create-domain",
      "params": { "domain": "example.com", "pass": "Xk9...", "default-features": "" },
      "reason": "The request names a new top-level server",
      "destructive": false
    }
  ],
  "generated": [ { "step": 1, "account": "example.com", "password": "Xk9..." } ]
}
```

`status` is `plan`, `clarification` with a `question`, or `error` with a `code` such as `not-allowed`, `no-api-key`, `busy` or `provider`. Parameter values are strings, or lists of strings for repeated options; an empty string is a flag. `placeholder` names the value to substitute when `have-password=1` was sent. `destructive` is set for `delete-*`, `disable-*`, `unsub-*` and similar programs, and for options such as `--delete` or `--reset`, so a client can highlight the step.

A client shows the summary and the steps, substitutes the placeholder or shows the generated passwords, asks for confirmation, then posts each step to `remote.cgi` with the same credentials, for example `program=create-domain&domain=example.com&...&json=1`, and stops at the first failure.

## Secrets

| Sent to the provider | Never sent |
| --- | --- |
| The request text, including a password typed into it | API keys |
| Catalog descriptions and `--help` text of the selected commands | Passwords from `--password-file` and generated passwords |
| | System data such as domain lists or earlier command output |

Key files must be regular files owned by root and not readable by group or others; they are opened and checked on the handle so a swap between check and use cannot help. Provider errors have the key redacted before they are shown. Provider environment variables are removed from the environment before any Virtualmin command runs.

## Threat model

| Threat | Handling |
| --- | --- |
| Injected instructions in the request | The request is data to the planner; the validator, not the model, decides what runs; a human reads the plan. |
| Invented commands or options | Rejected against the allowlist and the help-derived option list; one correction round. |
| Documented options that touch root-accessible paths | Human review before execution; `--yes` warns and is documented as trusted-automation only. |
| Password leakage | Never on a command line, never in a prompt unless the user typed it there, never accepted as a remote parameter. |
| Remote privilege escalation | The CGI plans only; `remote.cgi` and the caller's ACL execute; the catalog is limited to what the caller may run. |
| Provider abuse or hangs | One request per account at a time, timeouts, bounded retries, 1 MB response cap. |
| Planner reconfiguring itself | `configure-ai` and the metadata commands are excluded from the catalog; `run-api-command` refuses `virtualmin-ai`. |

## Editions and commands

| Edition | Commands offered to the planner |
| --- | --- |
| GPL | `create-domain`, `create-user`, `list-domains`, `list-users` |
| Pro | Every command already audited for the remote API, except `get-command`, `list-commands` and `configure-ai` |

The final catalog is also limited to commands installed on the system. `virtualmin-ai` itself is hidden from the regular API catalog.

## Verified live

On Rocky 9 Pro, Alma 10 GPL and Ubuntu 24.04 Pro debug systems:

- Plans through OpenAI, Anthropic, xAI and DeepSeek; Gemini 2.5 and 3.5 (3.8 was overloaded at the time).
- Domain and user creation end to end with `gpt-5.4-mini` and `gpt-5.5`, including generated passwords handed over through private files and printed once.
- A quota change plans without a password after the password policy fix; a user with a password written in the request keeps it.
- The remote path as a domain owner: plan JSON, a step executed through `remote.cgi`, provider switched with `configure-ai` over `remote.cgi`, `--user` refused for a non-master caller.
- The configure flow on a pseudo-terminal: keeping values with Enter, the model list with filter, `all` and `more`, the test request, the summary and declining to save.
- Deleting a Webmin user removes its account file.

## Known limitations

- Feature dependencies are enforced by Virtualmin at run time, not by the planner. A sub-server whose parent lacks a feature, or named features without `--dir`, fail with Virtualmin's own message and the plan stops there.
- Small models sometimes miscount units or omit an option. The review step catches it; `--yes` accepts the risk.
- Help output is loaded on every run; there is no cache.
- The reseller deletion hook lives in the Pro repository.
- Anthropic server-side fallbacks are deliberately not used.
