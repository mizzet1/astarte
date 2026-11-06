use astarte_e2e::{device_room, scenarios::encrypted_endpoints::handshake};

#[tokio::test]
async fn key_agreement() -> eyre::Result<()> {
    let mut connection = device_room::Connection::new_random()?
        .with_interface(handshake::INTERFACE_JSON)
        .connect()
        .await?;

    handshake::check(&mut connection.channel, &connection.client).await
}
