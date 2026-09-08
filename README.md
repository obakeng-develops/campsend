# Campsend

Campsend sends files to one recipient through an expiring, revocable link. A sender can add a note and see when the delivery is first opened or when any file is first downloaded.

**Campsend is meant to be self-hosted.** Run it on your own machine or your own server, and the files you send stay on infrastructure you control. It is a Rails application with SQLite and no other services to run.

<img width="2008" height="2008" alt="Delivery to Sam · Campsend (Window) 2026-08-27 09:30 AM" src="https://github.com/user-attachments/assets/a1e7daba-0760-4913-9951-69e587f78c0c" />

## Running it yourself

You need Ruby 3.3.4 and SQLite 3.

```sh
bin/setup   # installs gems and prepares the databases
bin/dev     # http://localhost:3000
```

That is a working Campsend. [Run Campsend locally](docs/tutorials/getting-started.md) walks through sending your first file, and [Deploy Campsend](docs/how-to/deploy.md) covers putting it on a server with Docker or Kamal, including S3-compatible storage if you would rather not keep files on disk.

Self-hosted Campsend has no plans and no limits. Quotas and paid tiers live in a separate distribution that extends this one through `Campsend.policy`, so nothing here is crippled to sell you an upgrade.

There is also a hosted version at [campsend.app](https://campsend.app) if you would rather not run it.

## Documentation

Choose the guide that matches what you're doing:

- **Tutorial:** [Run Campsend locally](docs/tutorials/getting-started.md)
- **How-to guide:** [Deploy Campsend](docs/how-to/deploy.md)
- **How-to guide:** [Load test Campsend locally](docs/how-to/load-test.md)
- **Reference:** [Configuration](docs/reference/configuration.md)
- **Reference:** [API stability](docs/reference/api-stability.md)
- **Explanation:** [Delivery and storage security](docs/explanation/security-model.md)

## Contributing

Start with the lode in [`docs/lode/`](docs/lode/). [Terminology](docs/lode/terminology.md), [domains](docs/lode/domains.md) and [practices](docs/lode/practices.md) cover the naming, the policy extension point, and the compromises that are deliberate.

Run the project checks before opening a pull request:

```sh
bin/rails test
bin/rubocop
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
bin/bundler-audit check
bin/importmap audit
```

Campsend is available under the [MIT License](LICENSE). See [SECURITY.md](SECURITY.md) to report a vulnerability privately.
