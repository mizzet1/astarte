use astarte_e2e::{config::Config, scenarios::certificate_revocation::Variant};

// TODO: expect success once the broker refuses superseded certificates
#[tokio::test]
async fn superseded_broker() {
    Variant::SupersededBroker
        .run(Config::from_env().unwrap())
        .await
        .unwrap();
}

// TODO: expect success once pairing checks whether a certificate was revoked
#[tokio::test]
async fn superseded_pairing() {
    Variant::SupersededPairing
        .run(Config::from_env().unwrap())
        .await
        .unwrap();
}
