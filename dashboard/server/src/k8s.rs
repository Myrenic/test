use dashboard_shared::*;
use k8s_openapi::api::core::v1::{Event as K8sEvent, Node, Pod};
use kube::{
    api::ListParams,
    Api, Client,
};
use std::sync::Arc;
use tokio::sync::RwLock;

pub async fn watch_cluster(cache: Arc<RwLock<Option<ClusterOverview>>>) {
    loop {
        match Client::try_default().await {
            Ok(client) => {
                tracing::info!("Connected to Kubernetes API");
                run_poll_loop(client, cache.clone()).await;
            }
            Err(e) => {
                tracing::error!("Failed to connect to K8s API: {}", e);
                tokio::time::sleep(std::time::Duration::from_secs(5)).await;
            }
        }
    }
}

async fn run_poll_loop(client: Client, cache: Arc<RwLock<Option<ClusterOverview>>>) {
    let nodes_api: Api<Node> = Api::all(client.clone());
    let pods_api: Api<Pod> = Api::all(client.clone());
    let events_api: Api<K8sEvent> = Api::all(client.clone());

    loop {
        let nodes = match nodes_api.list(&ListParams::default()).await {
            Ok(list) => list.items.into_iter().map(convert_node).collect::<Vec<_>>(),
            Err(e) => {
                tracing::error!("Failed to list nodes: {}", e);
                vec![]
            }
        };

        let pods = match pods_api.list(&ListParams::default()).await {
            Ok(list) => list.items.into_iter().map(convert_pod).collect::<Vec<_>>(),
            Err(e) => {
                tracing::error!("Failed to list pods: {}", e);
                vec![]
            }
        };

        let events = match events_api
            .list(&ListParams::default().limit(100))
            .await
        {
            Ok(list) => list
                .items
                .into_iter()
                .map(convert_event)
                .collect::<Vec<_>>(),
            Err(e) => {
                tracing::error!("Failed to list events: {}", e);
                vec![]
            }
        };

        let problems = build_problem_summary(&nodes, &pods, vec![]);

        let overview = ClusterOverview {
            nodes,
            pods,
            events,
            problems,
        };

        {
            let mut c = cache.write().await;
            *c = Some(overview);
        }

        tokio::time::sleep(std::time::Duration::from_secs(5)).await;
    }
}

fn convert_node(node: Node) -> NodeInfo {
    let metadata = node.metadata;
    let status = node.status.unwrap_or_default();
    let _spec = node.spec.unwrap_or_default();

    let name = metadata.name.unwrap_or_default();

    let node_status = status
        .conditions
        .as_ref()
        .and_then(|conds| {
            conds.iter().find(|c| c.type_ == "Ready").map(|c| {
                if c.status == "True" {
                    NodeStatus::Ready
                } else {
                    NodeStatus::NotReady
                }
            })
        })
        .unwrap_or(NodeStatus::Unknown);

    let roles = metadata
        .labels
        .as_ref()
        .map(|labels| {
            labels
                .keys()
                .filter(|k| k.starts_with("node-role.kubernetes.io/"))
                .map(|k| k.trim_start_matches("node-role.kubernetes.io/").to_string())
                .collect()
        })
        .unwrap_or_default();

    let version = status
        .node_info
        .as_ref()
        .map(|ni| ni.kubelet_version.clone())
        .unwrap_or_default();

    let internal_ip = status
        .addresses
        .as_ref()
        .and_then(|addrs| {
            addrs
                .iter()
                .find(|a| a.type_ == "InternalIP")
                .map(|a| a.address.clone())
        })
        .unwrap_or_default();

    let os_image = status
        .node_info
        .as_ref()
        .map(|ni| ni.os_image.clone())
        .unwrap_or_default();

    let capacity = status.capacity.unwrap_or_default();
    let cpu_capacity = capacity
        .get("cpu")
        .map(|q| q.0.clone())
        .unwrap_or_default();
    let memory_capacity = capacity
        .get("memory")
        .map(|q| q.0.clone())
        .unwrap_or_default();

    NodeInfo {
        name,
        status: node_status,
        roles,
        version,
        internal_ip,
        os_image,
        cpu_capacity,
        memory_capacity,
    }
}

fn convert_pod(pod: Pod) -> PodInfo {
    let metadata = pod.metadata;
    let status = pod.status.unwrap_or_default();
    let spec = pod.spec.unwrap_or_default();

    let name = metadata.name.unwrap_or_default();
    let namespace = metadata.namespace.unwrap_or_default();

    let phase = status.phase.clone().unwrap_or_default();

    // Check container statuses for CrashLoopBackOff / ImagePullBackOff
    let pod_status = status
        .container_statuses
        .as_ref()
        .and_then(|statuses| {
            statuses.iter().find_map(|cs| {
                cs.state.as_ref().and_then(|s| {
                    s.waiting.as_ref().and_then(|w| {
                        w.reason.as_ref().map(|r| match r.as_str() {
                            "CrashLoopBackOff" => PodStatus::CrashLoopBackOff,
                            "ImagePullBackOff" | "ErrImagePull" => PodStatus::ImagePullBackOff,
                            other => PodStatus::Unknown(other.to_string()),
                        })
                    })
                })
            })
        })
        .unwrap_or_else(|| match phase.as_str() {
            "Running" => PodStatus::Running,
            "Pending" => PodStatus::Pending,
            "Succeeded" => PodStatus::Succeeded,
            "Failed" => PodStatus::Failed,
            other => PodStatus::Unknown(other.to_string()),
        });

    let restarts: i32 = status
        .container_statuses
        .as_ref()
        .map(|statuses| statuses.iter().map(|cs| cs.restart_count).sum())
        .unwrap_or(0);

    let node = spec.node_name.unwrap_or_default();

    let age = metadata
        .creation_timestamp
        .map(|ts| format_age(ts.0))
        .unwrap_or_default();

    let total_containers = spec.containers.len();
    let ready_containers = status
        .container_statuses
        .as_ref()
        .map(|statuses| statuses.iter().filter(|cs| cs.ready).count())
        .unwrap_or(0);
    let ready = format!("{}/{}", ready_containers, total_containers);

    PodInfo {
        name,
        namespace,
        status: pod_status,
        node,
        restarts,
        age,
        ready,
    }
}

fn convert_event(event: K8sEvent) -> EventInfo {
    let metadata = event.metadata;

    let timestamp = event
        .last_timestamp
        .map(|ts| ts.0.to_rfc3339())
        .or_else(|| metadata.creation_timestamp.map(|ts| ts.0.to_rfc3339()))
        .unwrap_or_default();

    let involved = event.involved_object;
    let kind = involved.kind.unwrap_or_default();
    let namespace = involved.namespace.unwrap_or_default();
    let obj_name = involved.name.unwrap_or_default();

    let reason = event.reason.unwrap_or_default();
    let message = event.message.unwrap_or_default();

    let event_type = match event.type_.as_deref() {
        Some("Warning") => EventType::Warning,
        _ => EventType::Normal,
    };

    EventInfo {
        timestamp,
        kind,
        namespace,
        name: obj_name,
        reason,
        message,
        event_type,
    }
}

fn format_age(ts: chrono::DateTime<chrono::Utc>) -> String {
    let now = chrono::Utc::now();
    let dur = now.signed_duration_since(ts);

    if dur.num_days() > 0 {
        format!("{}d", dur.num_days())
    } else if dur.num_hours() > 0 {
        format!("{}h", dur.num_hours())
    } else if dur.num_minutes() > 0 {
        format!("{}m", dur.num_minutes())
    } else {
        format!("{}s", dur.num_seconds())
    }
}
