use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct NodeInfo {
    pub name: String,
    pub status: NodeStatus,
    pub roles: Vec<String>,
    pub version: String,
    pub internal_ip: String,
    pub os_image: String,
    pub cpu_capacity: String,
    pub memory_capacity: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum NodeStatus {
    Ready,
    NotReady,
    Unknown,
}

impl std::fmt::Display for NodeStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            NodeStatus::Ready => write!(f, "Ready"),
            NodeStatus::NotReady => write!(f, "NotReady"),
            NodeStatus::Unknown => write!(f, "Unknown"),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct PodInfo {
    pub name: String,
    pub namespace: String,
    pub status: PodStatus,
    pub node: String,
    pub restarts: i32,
    pub age: String,
    pub ready: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum PodStatus {
    Running,
    Pending,
    Succeeded,
    Failed,
    CrashLoopBackOff,
    ImagePullBackOff,
    Unknown(String),
}

impl std::fmt::Display for PodStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            PodStatus::Running => write!(f, "Running"),
            PodStatus::Pending => write!(f, "Pending"),
            PodStatus::Succeeded => write!(f, "Succeeded"),
            PodStatus::Failed => write!(f, "Failed"),
            PodStatus::CrashLoopBackOff => write!(f, "CrashLoopBackOff"),
            PodStatus::ImagePullBackOff => write!(f, "ImagePullBackOff"),
            PodStatus::Unknown(s) => write!(f, "{}", s),
        }
    }
}

impl PodStatus {
    pub fn is_problem(&self) -> bool {
        matches!(
            self,
            PodStatus::CrashLoopBackOff
                | PodStatus::ImagePullBackOff
                | PodStatus::Failed
                | PodStatus::Pending
        )
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct EventInfo {
    pub timestamp: String,
    pub kind: String,
    pub namespace: String,
    pub name: String,
    pub reason: String,
    pub message: String,
    pub event_type: EventType,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum EventType {
    Normal,
    Warning,
}

impl std::fmt::Display for EventType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            EventType::Normal => write!(f, "Normal"),
            EventType::Warning => write!(f, "Warning"),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ProblemSummary {
    pub crash_loops: Vec<PodInfo>,
    pub image_pull_failures: Vec<PodInfo>,
    pub pending_pods: Vec<PodInfo>,
    pub failed_pods: Vec<PodInfo>,
    pub not_ready_nodes: Vec<NodeInfo>,
    pub volume_issues: Vec<VolumeIssue>,
}

impl ProblemSummary {
    pub fn total_issues(&self) -> usize {
        self.crash_loops.len()
            + self.image_pull_failures.len()
            + self.pending_pods.len()
            + self.failed_pods.len()
            + self.not_ready_nodes.len()
            + self.volume_issues.len()
    }

    pub fn is_healthy(&self) -> bool {
        self.total_issues() == 0
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct VolumeIssue {
    pub name: String,
    pub namespace: String,
    pub issue_type: VolumeIssueType,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum VolumeIssueType {
    Detached,
    Degraded,
    Faulted,
}

impl std::fmt::Display for VolumeIssueType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            VolumeIssueType::Detached => write!(f, "Detached"),
            VolumeIssueType::Degraded => write!(f, "Degraded"),
            VolumeIssueType::Faulted => write!(f, "Faulted"),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClusterOverview {
    pub nodes: Vec<NodeInfo>,
    pub pods: Vec<PodInfo>,
    pub events: Vec<EventInfo>,
    pub problems: ProblemSummary,
}

/// Build a ProblemSummary from lists of nodes and pods
pub fn build_problem_summary(
    nodes: &[NodeInfo],
    pods: &[PodInfo],
    volume_issues: Vec<VolumeIssue>,
) -> ProblemSummary {
    ProblemSummary {
        crash_loops: pods
            .iter()
            .filter(|p| p.status == PodStatus::CrashLoopBackOff)
            .cloned()
            .collect(),
        image_pull_failures: pods
            .iter()
            .filter(|p| p.status == PodStatus::ImagePullBackOff)
            .cloned()
            .collect(),
        pending_pods: pods
            .iter()
            .filter(|p| p.status == PodStatus::Pending)
            .cloned()
            .collect(),
        failed_pods: pods
            .iter()
            .filter(|p| p.status == PodStatus::Failed)
            .cloned()
            .collect(),
        not_ready_nodes: nodes
            .iter()
            .filter(|n| n.status != NodeStatus::Ready)
            .cloned()
            .collect(),
        volume_issues,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_pod(name: &str, status: PodStatus) -> PodInfo {
        PodInfo {
            name: name.to_string(),
            namespace: "default".to_string(),
            status,
            node: "node1".to_string(),
            restarts: 0,
            age: "1h".to_string(),
            ready: "1/1".to_string(),
        }
    }

    fn make_node(name: &str, status: NodeStatus) -> NodeInfo {
        NodeInfo {
            name: name.to_string(),
            status,
            roles: vec!["control-plane".to_string()],
            version: "v1.33.1".to_string(),
            internal_ip: "10.0.3.60".to_string(),
            os_image: "Talos".to_string(),
            cpu_capacity: "2".to_string(),
            memory_capacity: "2Gi".to_string(),
        }
    }

    #[test]
    fn test_pod_status_is_problem() {
        assert!(PodStatus::CrashLoopBackOff.is_problem());
        assert!(PodStatus::ImagePullBackOff.is_problem());
        assert!(PodStatus::Failed.is_problem());
        assert!(PodStatus::Pending.is_problem());
        assert!(!PodStatus::Running.is_problem());
        assert!(!PodStatus::Succeeded.is_problem());
    }

    #[test]
    fn test_build_problem_summary_healthy() {
        let nodes = vec![make_node("node1", NodeStatus::Ready)];
        let pods = vec![
            make_pod("pod1", PodStatus::Running),
            make_pod("pod2", PodStatus::Succeeded),
        ];
        let summary = build_problem_summary(&nodes, &pods, vec![]);
        assert!(summary.is_healthy());
        assert_eq!(summary.total_issues(), 0);
    }

    #[test]
    fn test_build_problem_summary_with_issues() {
        let nodes = vec![
            make_node("node1", NodeStatus::Ready),
            make_node("node2", NodeStatus::NotReady),
        ];
        let pods = vec![
            make_pod("pod1", PodStatus::Running),
            make_pod("pod2", PodStatus::CrashLoopBackOff),
            make_pod("pod3", PodStatus::ImagePullBackOff),
            make_pod("pod4", PodStatus::Pending),
        ];
        let volumes = vec![VolumeIssue {
            name: "vol1".to_string(),
            namespace: "storage".to_string(),
            issue_type: VolumeIssueType::Detached,
            message: "Volume detached".to_string(),
        }];
        let summary = build_problem_summary(&nodes, &pods, volumes);

        assert!(!summary.is_healthy());
        assert_eq!(summary.total_issues(), 5);
        assert_eq!(summary.crash_loops.len(), 1);
        assert_eq!(summary.image_pull_failures.len(), 1);
        assert_eq!(summary.pending_pods.len(), 1);
        assert_eq!(summary.not_ready_nodes.len(), 1);
        assert_eq!(summary.volume_issues.len(), 1);
    }

    #[test]
    fn test_node_status_display() {
        assert_eq!(NodeStatus::Ready.to_string(), "Ready");
        assert_eq!(NodeStatus::NotReady.to_string(), "NotReady");
        assert_eq!(NodeStatus::Unknown.to_string(), "Unknown");
    }

    #[test]
    fn test_pod_status_display() {
        assert_eq!(PodStatus::Running.to_string(), "Running");
        assert_eq!(PodStatus::CrashLoopBackOff.to_string(), "CrashLoopBackOff");
        assert_eq!(
            PodStatus::Unknown("Custom".to_string()).to_string(),
            "Custom"
        );
    }

    #[test]
    fn test_volume_issue_type_display() {
        assert_eq!(VolumeIssueType::Detached.to_string(), "Detached");
        assert_eq!(VolumeIssueType::Degraded.to_string(), "Degraded");
        assert_eq!(VolumeIssueType::Faulted.to_string(), "Faulted");
    }
}
