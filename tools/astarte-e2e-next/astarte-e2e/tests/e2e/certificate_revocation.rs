use astarte_e2e::{config::Config, scenarios::certificate_revocation::Variant};

#[tokio::test]
async fn superseded_broker() {
    Variant::SupersededBroker
        .run(Config::from_env().unwrap())
        .await
        .unwrap();
}

#[tokio::test]
async fn superseded_pairing() {
    Variant::SupersededPairing
        .run(Config::from_env().unwrap())
        .await
        .unwrap();
}
