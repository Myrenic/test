pub mod components;

use dashboard_shared::ClusterOverview;
use gloo_net::http::Request;
use leptos::prelude::*;
use leptos::task::spawn_local;
use wasm_bindgen_futures::JsFuture;

use components::{EventsPanel, NodesPanel, PodsPanel, ProblemsPanel};

async fn sleep_ms(ms: i32) {
    let promise = js_sys::Promise::new(&mut |resolve, _| {
        web_sys::window()
            .unwrap()
            .set_timeout_with_callback_and_timeout_and_arguments_0(&resolve, ms)
            .unwrap();
    });
    let _ = JsFuture::from(promise).await;
}

pub fn fetch_overview() -> (ReadSignal<Option<ClusterOverview>>, WriteSignal<Option<ClusterOverview>>) {
    let (overview, set_overview) = signal(None::<ClusterOverview>);

    spawn_local(async move {
        loop {
            match Request::get("/api/overview").send().await {
                Ok(resp) => {
                    if let Ok(data) = resp.json::<ClusterOverview>().await {
                        set_overview.set(Some(data));
                    }
                }
                Err(e) => {
                    leptos::logging::log!("Fetch error: {}", e);
                }
            }
            sleep_ms(5000).await;
        }
    });

    (overview, set_overview)
}

#[component]
pub fn App() -> impl IntoView {
    let (overview, _) = fetch_overview();

    view! {
        <div class="container">
            <header>
                <h1>"⎈ K8s Lab Dashboard"</h1>
                {move || {
                    let badge = match overview.get() {
                        Some(ref o) if o.problems.is_healthy() => {
                            view! { <span class="status-badge status-healthy">"✓ Healthy"</span> }.into_any()
                        }
                        Some(ref o) => {
                            let count = o.problems.total_issues();
                            view! { <span class="status-badge status-unhealthy">{format!("⚠ {} issues", count)}</span> }.into_any()
                        }
                        None => {
                            view! { <span class="status-badge">"Connecting..."</span> }.into_any()
                        }
                    };
                    badge
                }}
            </header>

            {move || match overview.get() {
                None => view! { <div class="loading">"Connecting to cluster API..."</div> }.into_any(),
                Some(data) => view! {
                    <div>
                        <ProblemsPanel problems={data.problems.clone()} />
                        <div class="grid">
                            <NodesPanel nodes={data.nodes.clone()} />
                            <PodsPanel pods={data.pods.clone()} />
                        </div>
                        <EventsPanel events={data.events.clone()} />
                    </div>
                }.into_any(),
            }}
        </div>
    }
}
