# dotfiles-private scaffold

This repository skeleton is generated and validated by the sibling public
`dotfiles` repository. It intentionally contains examples only, so running the
public installer cannot apply placeholder settings.

## Configuration

1. Replace every required `.example` with a same-path file without the suffix.
   Keep the `.example` files as safe documentation.
2. Add one or more real `labpc/jobs.d/*.conf` files if `sync-labpc` is used.
3. Copy `links.conf.example` to `links.conf` only after every linked source exists.
4. Remove `.dotfiles-private-scaffold` when configuration is complete.
5. From the sibling `dotfiles`, run `make private-validate` and then `make links`.

The public contract is `dotfiles/templates/dotfiles-private.contract`. The
validator accepts either this untouched scaffold state or a fully configured
repository; it rejects partially activated repositories and runtime shell or
PowerShell scripts outside an imported `docs/dev-charter/` subtree.

## Security

Never copy real account names, email addresses, hosts, IP addresses, local paths,
or credentials into the `.example` files. Store credentials in the OS credential
store, not in this repository.
