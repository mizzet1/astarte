<!--
Copyright 2026 SECO Mind Srl
SPDX-License-Identifier: CC0-1.0
-->

# Astarte E2E

End to end tests and synthetic monitoring for Astarte, built on the
[Astarte Device SDK for Rust](https://github.com/astarte-platform/astarte-device-sdk-rust).

- `astarte-e2e`: library with the shared code (device, AppEngine room channel,
  AMQP trigger consumer, REST client) and the scenarios. The e2e tests live in
  `astarte-e2e/tests/e2e` and run with `cargo e2e`.
- `astarte-synthetic-monitoring`: binary running the same scenarios in a loop
  against a live cluster.

Each test registers a fresh device, connects it over MQTT, sends data and
checks that the same data is delivered back through a volatile trigger on an
AppEngine room.

## Running locally

### Prerequisites

- Docker with the compose plugin
- [`astartectl`](https://github.com/astarte-platform/astartectl)
- Rust (see `rust-version` in `Cargo.toml`)
- The compose keys and certificates. If `compose/astarte-keys` is empty, run
  from the repository root:

  ```sh
  docker run -v $(pwd)/compose:/compose astarte/docker-compose-initializer
  ```

### 1. Start Astarte

From the repository root:

```sh
docker compose -p astarte-e2e \
  -f docker-compose.yml \
  -f tools/astarte-e2e-next/compose.local.yaml \
  up -d
```

`compose.local.yaml` publishes RabbitMQ on `127.0.0.1:5672`, which the tests
need to consume trigger events. The dedicated `astarte-e2e` project keeps its
own volumes, so the tests don't depend on (or break) the database of your
usual development stack. To test local changes instead of the `snapshot`
images, build them first with `docker compose build`.

### 2. Prepare the realm

From this directory:

```sh
./scripts/setup-local.sh
```

The script mirrors the CI setup: it creates the realm keypair and the realm
(`test`, or `$E2E_REALM`), installs the interfaces in
`astarte-e2e/interfaces`, registers a device and generates a JWT. Everything
is stored in the git-ignored `.local` directory, and the configuration is
written to `.local/e2e.env`.

It can be run again at any time, for example when the JWT expires after 8
hours: the realm and its keypair are reused.

### 3. Run the tests

```sh
source .local/e2e.env
cargo e2e
```

### Known limitations

- Test names and libtest flags can't be passed: `cargo e2e some_test` and
  `cargo e2e -- --nocapture` fail with `unexpected argument`, because each test
  parses its configuration from the command line. Run the whole suite.
- `E2E_DEVICE_ID` must be set even though every test registers a new device,
  otherwise the tests fail with `missing device id`. The setup script sets it.
- Every test run leaves a `device-connected-*` trigger in the realm and an
  exchange and queue in RabbitMQ.

### Cleaning up

```sh
docker compose -p astarte-e2e -f docker-compose.yml down -v
rm -rf .local
```

## Development

```sh
task ci                                         # fmt, clippy, generated code and unit tests
cargo nextest run --workspace -E 'not binary(e2e)'  # unit tests only, no cluster needed
cargo insta review                              # review changed snapshots
cargo regen-proto                               # regenerate src/simple_events.rs
```

In CI the tests run in the `end-to-end` Docker image, inside the compose
network, through the `end-to-end-next-test` job of
`.github/workflows/astarte-end-to-end-test-workflow.yaml`.
