//! The SDK runs the key agreement handshake on connection, so a value sent on an encrypted
//! endpoint that reaches Astarte in plaintext proves both sides derived the same key.

use astarte_device_sdk::{AstarteData, Client};
use chrono::Utc;
use eyre::Context;

use crate::interfaces::{AstarteClient, retry};
use crate::room::Room;
use crate::scenarios::interfaces::device::individual_datastream::expect_individual;

/// Interface to pass to [`crate::device_room::ConnectionBuilder::with_interface`].
pub const INTERFACE_JSON: &str = include_str!(
    "../../../interfaces/encrypted/org.astarte-platform.e2e.EncryptedDeviceDatastream.json"
);
const INTERFACE: &str = "org.astarte-platform.e2e.EncryptedDeviceDatastream";
const PATH: &str = "/integer_endpoint";

pub async fn check(channel: &mut Room, client: &AstarteClient) -> eyre::Result<()> {
    let data = AstarteData::Integer(42);

    // Sending fails with a missing shared secret until the ExchangeResp is received
    retry(20, || async {
        client
            .send_individual_with_timestamp(INTERFACE, PATH, data.clone(), Utc::now())
            .await
            .map_err(Into::into)
    })
    .await
    .wrap_err("the key agreement handshake never completed")?;

    expect_individual(channel, INTERFACE, PATH, &data).await
}
