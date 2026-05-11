use axum::{
    extract::State,
    response::{
        sse::{Event, Sse},
        Json,
    },
    routing::get,
    Router,
};
use futures::stream::Stream;
use std::{convert::Infallible, sync::Arc, time::Duration};
use tokio::sync::RwLock;
use tower_http::cors::CorsLayer;
use tower_http::services::ServeDir;

mod k8s;

use dashboard_shared::{build_problem_summary, ClusterOverview, ProblemSummary};

#[derive(Clone)]
struct AppState {
    cache: Arc<RwLock<Option<ClusterOverview>>>,
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter("dashboard_server=info,tower_http=info")
        .init();

    let state = AppState {
        cache: Arc::new(RwLock::new(None)),
    };

    // Spawn background K8s watcher
    let watcher_state = state.clone();
    tokio::spawn(async move {
        k8s::watch_cluster(watcher_state.cache).await;
    });

    let app = Router::new()
        .route("/health", get(health))
        .route("/api/overview", get(get_overview))
        .route("/api/nodes", get(get_nodes))
        .route("/api/pods", get(get_pods))
        .route("/api/events", get(get_events))
        .route("/api/problems", get(get_problems))
        .route("/api/stream", get(sse_stream))
        .nest_service("/", ServeDir::new("/app/static"))
        .layer(CorsLayer::permissive())
        .with_state(state);

    let listener = tokio::net::TcpListener::bind("0.0.0.0:8080").await.unwrap();
    tracing::info!("Dashboard server listening on :8080");
    axum::serve(listener, app).await.unwrap();
}

async fn health() -> &'static str {
    "ok"
}

async fn get_overview(State(state): State<AppState>) -> Json<Option<ClusterOverview>> {
    let cache = state.cache.read().await;
    Json(cache.clone())
}

async fn get_nodes(
    State(state): State<AppState>,
) -> Json<Vec<dashboard_shared::NodeInfo>> {
    let cache = state.cache.read().await;
    Json(cache.as_ref().map(|c| c.nodes.clone()).unwrap_or_default())
}

async fn get_pods(
    State(state): State<AppState>,
) -> Json<Vec<dashboard_shared::PodInfo>> {
    let cache = state.cache.read().await;
    Json(cache.as_ref().map(|c| c.pods.clone()).unwrap_or_default())
}

async fn get_events(
    State(state): State<AppState>,
) -> Json<Vec<dashboard_shared::EventInfo>> {
    let cache = state.cache.read().await;
    Json(cache.as_ref().map(|c| c.events.clone()).unwrap_or_default())
}

async fn get_problems(State(state): State<AppState>) -> Json<ProblemSummary> {
    let cache = state.cache.read().await;
    Json(
        cache
            .as_ref()
            .map(|c| c.problems.clone())
            .unwrap_or_else(|| build_problem_summary(&[], &[], vec![])),
    )
}

async fn sse_stream(
    State(state): State<AppState>,
) -> Sse<impl Stream<Item = Result<Event, Infallible>>> {
    let stream = async_stream::stream! {
        let mut interval = tokio::time::interval(Duration::from_secs(5));
        loop {
            interval.tick().await;
            let cache = state.cache.read().await;
            if let Some(overview) = cache.as_ref() {
                if let Ok(json) = serde_json::to_string(overview) {
                    yield Ok(Event::default().data(json).event("cluster-update"));
                }
            }
        }
    };
    Sse::new(stream).keep_alive(
        axum::response::sse::KeepAlive::new()
            .interval(Duration::from_secs(15))
            .text("ping"),
    )
}
