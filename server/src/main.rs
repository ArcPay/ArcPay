use crate::model::QueryRoot;
use crate::merkle::get_new_merkle_tree;
use crate::routes::{graphql_handler, graphql_playground, health};
use async_graphql::{EmptySubscription, Schema};
use axum::{extract::Extension, routing::get, Router, Server};
use std::sync::Arc;
use futures::lock::Mutex;
use model::MutationRoot;
mod model;
mod routes;
mod merkle;

#[tokio::main]
async fn main() {
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
