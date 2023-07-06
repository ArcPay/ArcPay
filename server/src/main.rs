use crate::model::QueryRoot;
use crate::merkle::get_new_merkle_tree;
use crate::routes::{graphql_handler, graphql_playground, health};
use async_graphql::{EmptySubscription, Schema};
use axum::{extract::Extension, routing::get, Router, Server};
use std::sync::Arc;
use futures::lock::Mutex;
use model::MutationRoot;
use tokio_postgres::{NoTls, Error};
mod model;
mod routes;
mod merkle;

#[tokio::main]
async fn main() {
    // experimental postgresql integration
    // Connect to the database.
    let (client, connection) = tokio_postgres::connect("host=localhost user=dev dbname=arcpay", NoTls).await.unwrap();

    // The connection object performs the actual communication with the database,
    // so spawn it off to run on its own.
    tokio::spawn(async move {
        if let Err(e) = connection.await {
            eprintln!("connection error: {}", e);
        }
    });

    // Now we can execute a simple statement that just returns its parameter.
    let rows = client
        .query("SELECT * FROM state_tree", &[])
        .await.unwrap();

    dbg!(rows);

    // And then check that we got back the same string we sent over.
    // let value: &str = rows[0].get(0);
    // assert_eq!(value, "hello world");

    let mt = get_new_merkle_tree(2);
    let schema = Schema::build(QueryRoot, MutationRoot, EmptySubscription)
        .data(Arc::new(Mutex::new(mt)))
        .finish();
    let app = Router::new()
        .route("/", get(graphql_playground).post(graphql_handler))
        .route("/health", get(health))
        .layer(Extension(schema));
    Server::bind(&"0.0.0.0:8000".parse().unwrap())
        .serve(app.into_make_service())
        .await
        .unwrap();
}
