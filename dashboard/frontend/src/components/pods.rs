use dashboard_shared::{PodInfo, PodStatus};
use leptos::prelude::*;

#[component]
pub fn PodsPanel(pods: Vec<PodInfo>) -> impl IntoView {
    let problem_count = pods.iter().filter(|p| p.status.is_problem()).count();
    let healthy_count = pods.len() - problem_count;
    let total = pods.len();

    view! {
        <div class="card">
            <h2>{format!("Pods ({} total, {} healthy)", total, healthy_count)}</h2>
            <div class="scrollable">
                <table>
                    <thead>
                        <tr>
                            <th>"Pod"</th>
                            <th>"Namespace"</th>
                            <th>"Status"</th>
                            <th>"Ready"</th>
                            <th>"Restarts"</th>
                            <th>"Node"</th>
                            <th>"Age"</th>
                        </tr>
                    </thead>
                    <tbody>
                        {pods.into_iter().map(|pod| {
                            let status_class = match &pod.status {
                                PodStatus::Running => "tag tag-running",
                                PodStatus::CrashLoopBackOff | PodStatus::Failed => "tag tag-crash",
                                PodStatus::Pending | PodStatus::ImagePullBackOff => "tag tag-pending",
                                PodStatus::Succeeded => "tag tag-normal",
                                PodStatus::Unknown(_) => "tag tag-warning",
                            };
                            let status_str = pod.status.to_string();
                            view! {
                                <tr>
                                    <td>{pod.name}</td>
                                    <td>{pod.namespace}</td>
                                    <td><span class={status_class}>{status_str}</span></td>
                                    <td>{pod.ready}</td>
                                    <td>{pod.restarts}</td>
                                    <td>{pod.node}</td>
                                    <td>{pod.age}</td>
                                </tr>
                            }
                        }).collect_view()}
                    </tbody>
                </table>
            </div>
        </div>
    }
}
