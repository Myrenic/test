use dashboard_shared::{EventInfo, EventType};
use leptos::prelude::*;

#[component]
pub fn EventsPanel(events: Vec<EventInfo>) -> impl IntoView {
    let warning_count = events.iter().filter(|e| e.event_type == EventType::Warning).count();
    let recent_events: Vec<_> = events.into_iter().take(50).collect();

    view! {
        <div class="card full-width">
            <h2>{format!("Events ({} warnings)", warning_count)}</h2>
            <div class="scrollable">
                <table>
                    <thead>
                        <tr>
                            <th>"Time"</th>
                            <th>"Type"</th>
                            <th>"Kind"</th>
                            <th>"Namespace"</th>
                            <th>"Name"</th>
                            <th>"Reason"</th>
                            <th>"Message"</th>
                        </tr>
                    </thead>
                    <tbody>
                        {recent_events.into_iter().map(|event| {
                            let type_class = match &event.event_type {
                                EventType::Warning => "tag tag-warning",
                                EventType::Normal => "tag tag-normal",
                            };
                            let short_time = if event.timestamp.len() > 19 {
                                event.timestamp[11..19].to_string()
                            } else {
                                event.timestamp.clone()
                            };
                            let type_str = event.event_type.to_string();
                            view! {
                                <tr class="event-row">
                                    <td class="event-time">{short_time}</td>
                                    <td><span class={type_class}>{type_str}</span></td>
                                    <td>{event.kind}</td>
                                    <td>{event.namespace}</td>
                                    <td>{event.name}</td>
                                    <td>{event.reason}</td>
                                    <td>{event.message}</td>
                                </tr>
                            }
                        }).collect_view()}
                    </tbody>
                </table>
            </div>
        </div>
    }
}
