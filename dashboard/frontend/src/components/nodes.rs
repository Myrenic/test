use dashboard_shared::{NodeInfo, NodeStatus};
use leptos::prelude::*;

#[component]
pub fn NodesPanel(nodes: Vec<NodeInfo>) -> impl IntoView {
    let count = nodes.len();
    view! {
        <div class="card">
            <h2>{format!("Nodes ({})", count)}</h2>
            <table>
                <thead>
                    <tr>
                        <th>"Name"</th>
                        <th>"Status"</th>
                        <th>"Version"</th>
                        <th>"IP"</th>
                        <th>"CPU"</th>
                        <th>"Memory"</th>
                    </tr>
                </thead>
                <tbody>
                    {nodes.into_iter().map(|node| {
                        let status_class = match &node.status {
                            NodeStatus::Ready => "tag tag-ready",
                            _ => "tag tag-notready",
                        };
                        let status_str = node.status.to_string();
                        view! {
                            <tr>
                                <td>{node.name}</td>
                                <td><span class={status_class}>{status_str}</span></td>
                                <td>{node.version}</td>
                                <td>{node.internal_ip}</td>
                                <td>{node.cpu_capacity}</td>
                                <td>{node.memory_capacity}</td>
                            </tr>
                        }
                    }).collect_view()}
                </tbody>
            </table>
        </div>
    }
}
