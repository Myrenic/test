use dashboard_shared::ProblemSummary;
use leptos::prelude::*;

#[component]
pub fn ProblemsPanel(problems: ProblemSummary) -> impl IntoView {
    let is_healthy = problems.is_healthy();
    let border_style = if !is_healthy {
        "border-color: var(--red);"
    } else {
        "border-color: var(--green);"
    };
    let title = if is_healthy {
        "✓ Problem Summary — All Clear".to_string()
    } else {
        "⚠ Problem Summary".to_string()
    };

    let crash_count = problems.crash_loops.len();
    let img_count = problems.image_pull_failures.len();
    let pending_count = problems.pending_pods.len();
    let failed_count = problems.failed_pods.len();
    let node_count = problems.not_ready_nodes.len();
    let vol_count = problems.volume_issues.len();

    let crash_table = if !problems.crash_loops.is_empty() {
        let pods = problems.crash_loops.clone();
        Some(view! {
            <div class="problem-section" style="margin-top: 1rem;">
                <h3>"CrashLoopBackOff Pods:"</h3>
                <table>
                    <thead><tr><th>"Pod"</th><th>"Namespace"</th><th>"Node"</th><th>"Restarts"</th></tr></thead>
                    <tbody>
                        {pods.into_iter().map(|p| view! {
                            <tr>
                                <td>{p.name}</td>
                                <td>{p.namespace}</td>
                                <td>{p.node}</td>
                                <td>{p.restarts}</td>
                            </tr>
                        }).collect_view()}
                    </tbody>
                </table>
            </div>
        })
    } else {
        None
    };

    let vol_table = if !problems.volume_issues.is_empty() {
        let vols = problems.volume_issues.clone();
        Some(view! {
            <div class="problem-section" style="margin-top: 1rem;">
                <h3>"Volume Issues:"</h3>
                <table>
                    <thead><tr><th>"Volume"</th><th>"Namespace"</th><th>"Issue"</th><th>"Message"</th></tr></thead>
                    <tbody>
                        {vols.into_iter().map(|v| {
                            let issue_str = v.issue_type.to_string();
                            view! {
                                <tr>
                                    <td>{v.name}</td>
                                    <td>{v.namespace}</td>
                                    <td><span class="tag tag-crash">{issue_str}</span></td>
                                    <td>{v.message}</td>
                                </tr>
                            }
                        }).collect_view()}
                    </tbody>
                </table>
            </div>
        })
    } else {
        None
    };

    view! {
        <div class="card full-width" style={border_style}>
            <h2>{title}</h2>
            <div class="problems-grid">
                <ProblemCounter count={crash_count} label="CrashLoopBackOff" color="var(--red)" />
                <ProblemCounter count={img_count} label="ImagePullBackOff" color="var(--orange)" />
                <ProblemCounter count={pending_count} label="Pending Pods" color="var(--yellow)" />
                <ProblemCounter count={failed_count} label="Failed Pods" color="var(--red)" />
                <ProblemCounter count={node_count} label="NotReady Nodes" color="var(--red)" />
                <ProblemCounter count={vol_count} label="Volume Issues" color="var(--orange)" />
            </div>
            {crash_table}
            {vol_table}
        </div>
    }
}

#[component]
fn ProblemCounter(count: usize, label: &'static str, color: &'static str) -> impl IntoView {
    let c = if count == 0 { "var(--green)" } else { color };
    view! {
        <div>
            <div class="problem-count" style={format!("color: {}", c)}>{count}</div>
            <div class="problem-label">{label}</div>
        </div>
    }
}
